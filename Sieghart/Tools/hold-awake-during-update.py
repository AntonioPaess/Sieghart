#!/usr/bin/env python3
"""Transfer only an already-held Keep Awake assertion across an app update.
Run prepare BEFORE quitting, check BEFORE installing, finish AFTER LaunchServices.
The independent guard never exceeds a finite session's original deadline.
An indefinite session receives a bounded 180-second update bridge.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time

STATE = Path(tempfile.gettempdir()) / f"sieghart-update-awake-{os.getuid()}.json"
PREFERENCES = Path.home() / "Library/Preferences/com.sieghart.app.plist"
APP_EXECUTABLE = "/Applications/Sieghart.app/Contents/MacOS/Sieghart"
APPLE_EPOCH = 978307200


def snapshot():
    data = plistlib.loads(PREFERENCES.read_bytes()) if PREFERENCES.exists() else {}
    request = json.loads(data.get("awake.request", b"{}"))
    return {"active": bool(data.get("awake.active")), "request": request}


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def valid_session(value, now):
    end = value["request"].get("end")
    return value["active"] and (end is None or end + APPLE_EPOCH > now)


def plan(value, now, held_display):
    if not valid_session(value, now) or held_display is None:
        return None
    end = value["request"].get("end")
    seconds = 180 if end is None else math.floor(end + APPLE_EPOCH - now)
    return {"seconds": seconds, "display": held_display} if seconds > 0 else None


def app_pid():
    result = subprocess.run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True, errors="replace", check=True)
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == APP_EXECUTABLE:
            return int(parts[0])
    return None


def held_assertion(pid):
    if pid is None:
        return None
    result = subprocess.run(["/usr/bin/pmset", "-g", "assertions"], capture_output=True, text=True, errors="replace", check=True)
    owned = [line for line in result.stdout.splitlines() if f"pid {pid}(" in line]
    if any("PreventUserIdleDisplaySleep" in line for line in owned):
        return True
    if any("PreventUserIdleSystemSleep" in line for line in owned):
        return False
    return None


def identity(pid):
    result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "uid=,lstart=,command="], capture_output=True, text=True, errors="replace")
    return result.stdout.strip() if result.returncode == 0 else None


def read_state():
    if not STATE.exists():
        return None
    if STATE.is_symlink() or STATE.stat().st_uid != os.getuid():
        raise RuntimeError("Update guard state is not owned by this user")
    return json.loads(STATE.read_text())


def running(record):
    return bool(record and record.get("pid") and record.get("identity") and identity(record["pid"]) == record["identity"])


def write_state(record):
    fd, name = tempfile.mkstemp(prefix="sieg-update-awake-", dir=STATE.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(record, output)
        os.replace(name, STATE)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def prepare():
    value, now = snapshot(), time.time()
    previous = read_state()
    if running(previous) and previous["fingerprint"] == fingerprint(value) and previous["until"] > now + 15:
        display = held_assertion(previous["pid"])
        if display is True or (display is False and not previous["display"]):
            print("Keep Awake update guard already armed")
            return
    requested = plan(value, now, held_assertion(app_pid()))
    record = {"fingerprint": fingerprint(value), "prepared": now, "until": now, "pid": None}
    if requested:
        args = ["/usr/bin/caffeinate", "-i"]
        if requested["display"]:
            args.append("-d")
        args += ["-t", str(requested["seconds"])]
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        marker = identity(process.pid)
        if not marker or process.poll() is not None:
            raise RuntimeError("Could not start the temporary update guard; leave Sieghart running")
        for _ in range(20):
            guard_display = held_assertion(process.pid)
            if guard_display is True or (guard_display is False and not requested["display"]):
                break
            time.sleep(0.05)
        else:
            process.terminate()
            raise RuntimeError("Temporary protection was not confirmed by macOS; leave Sieghart running")
        record.update(pid=process.pid, identity=marker, display=requested["display"], until=now + requested["seconds"])
    elif valid_session(value, now) and not any(value["request"].get(k) for k in ("onlyOnAC", "externalDisplayOnly", "applications")):
        raise RuntimeError("Active session has no confirmed assertion. Keep Sieghart open and resolve its state before updating")
    write_state(record)
    if running(previous):
        os.kill(previous["pid"], signal.SIGTERM)
    print("Keep Awake update guard armed" if record["pid"] else "No active held session to bridge")


def check():
    value, now = snapshot(), time.time()
    if not valid_session(value, now):
        return
    record = read_state()
    if not record or record["fingerprint"] != fingerprint(value):
        raise RuntimeError("Run hold-awake-during-update.py prepare BEFORE quitting Sieghart; update stopped before replacing files")
    if record["pid"] and (record["until"] <= now or not running(record)):
        raise RuntimeError("The temporary update guard ended; resume the app before updating")
    if record["pid"]:
        display = held_assertion(record["pid"])
        if display is None or (record["display"] and not display):
            raise RuntimeError("macOS no longer confirms the temporary protection; resume the app before updating")


def finish():
    record = read_state()
    if not record:
        return
    if not record["pid"]:
        STATE.unlink(missing_ok=True)
        return
    for _ in range(15):
        if not running(record):
            STATE.unlink(missing_ok=True)
            return
        value = snapshot()
        current = held_assertion(app_pid())
        # A user stop or the original deadline also ends the temporary bridge.
        if fingerprint(value) != record["fingerprint"] or not valid_session(value, time.time()) or current is True or (current is False and not record["display"]):
            os.kill(record["pid"], signal.SIGTERM)
            STATE.unlink(missing_ok=True)
            print("Keep Awake handoff verified; temporary guard released")
            return
        time.sleep(1)
    raise RuntimeError("New app protection is not yet confirmed. Temporary guard stays until its bounded deadline")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "check", "finish"])
    args = parser.parse_args()
    try:
        {"prepare": prepare, "check": check, "finish": finish}[args.action]()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
