import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

SPEC = importlib.util.spec_from_file_location('awake_guard', Path(__file__).resolve().parents[2] / 'Tools/hold-awake-during-update.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class UpdateAwakeGuardTests(unittest.TestCase):
    def value(self, seconds=7200, **options):
        return {'active': True, 'request': {'end': 1000 + seconds - guard.APPLE_EPOCH, **options}}

    def test_deadline_and_opt_out(self):
        self.assertIsNone(guard.plan({'active': False, 'request': {}}, 1000, True))
        self.assertIsNone(guard.plan(self.value(-1), 1000, True))
        self.assertIsNone(guard.plan(self.value(), 1000, None))
        self.assertEqual(guard.plan(self.value(12.8), 1000, True), {'seconds': 12, 'display': True})
        self.assertEqual(guard.plan(self.value(), 1000, False), {'seconds': 7200, 'display': False})
        self.assertEqual(guard.plan({'active': True, 'request': {}}, 1000, True)['seconds'], 180)

    def test_prepare_verifies_the_bridge_before_allowing_quit(self):
        process = MagicMock(pid=123); process.poll.return_value = None
        with patch.object(guard, 'snapshot', return_value=self.value(90)), patch.object(guard.time, 'time', return_value=1000), patch.object(guard, 'read_state', return_value=None), patch.object(guard, 'app_pid', return_value=999), patch.object(guard, 'held_assertion', return_value=True) as held, patch.object(guard, 'identity', return_value='owned marker'), patch.object(guard.subprocess, 'Popen', return_value=process) as start, patch.object(guard, 'write_state') as save:
            guard.prepare()
            self.assertEqual(start.call_args.args[0], ['/usr/bin/caffeinate', '-i', '-d', '-t', '90'])
            self.assertEqual(held.call_args.args, (123,))
            self.assertEqual(save.call_args.args[0]['until'], 1090)

    def test_no_held_assertion_does_not_override_waiting_conditions(self):
        with patch.object(guard, 'snapshot', return_value=self.value(7200, onlyOnAC=True)), patch.object(guard.time, 'time', return_value=1000), patch.object(guard, 'read_state', return_value=None), patch.object(guard, 'app_pid', return_value=999), patch.object(guard, 'held_assertion', return_value=None), patch.object(guard.subprocess, 'Popen') as start, patch.object(guard, 'write_state') as save:
            guard.prepare()
            start.assert_not_called()
            self.assertIsNone(save.call_args.args[0]['pid'])

    def test_check_rejects_an_unprotected_active_update(self):
        with patch.object(guard, 'snapshot', return_value=self.value()), patch.object(guard.time, 'time', return_value=1000), patch.object(guard, 'read_state', return_value=None):
            with self.assertRaises(RuntimeError): guard.check()

    def test_delayed_finite_update_remains_protected_until_original_deadline(self):
        value = self.value()
        record = {'pid': 123, 'identity': 'owned marker', 'display': True,
                  'fingerprint': guard.fingerprint(value), 'prepared': 1000, 'until': 8200}
        with patch.object(guard, 'snapshot', return_value=value), patch.object(guard.time, 'time', return_value=1600), patch.object(guard, 'read_state', return_value=record), patch.object(guard, 'identity', return_value='owned marker'), patch.object(guard, 'held_assertion', return_value=True):
            guard.check()

    def test_check_rejects_a_live_process_without_its_display_assertion(self):
        value = self.value()
        record = {'pid': 123, 'identity': 'owned marker', 'display': True,
                  'fingerprint': guard.fingerprint(value), 'prepared': 1000, 'until': 8200}
        with patch.object(guard, 'snapshot', return_value=value), patch.object(guard.time, 'time', return_value=1600), patch.object(guard, 'read_state', return_value=record), patch.object(guard, 'identity', return_value='owned marker'), patch.object(guard, 'held_assertion', return_value=False):
            with self.assertRaises(RuntimeError): guard.check()

    def test_failed_native_assertion_cancels_bridge_and_blocks_update(self):
        process = MagicMock(pid=123); process.poll.return_value = None
        with patch.object(guard, 'snapshot', return_value=self.value()), patch.object(guard.time, 'time', return_value=1000), patch.object(guard.time, 'sleep'), patch.object(guard, 'read_state', return_value=None), patch.object(guard, 'app_pid', return_value=999), patch.object(guard, 'held_assertion', side_effect=[True]+[None]*20), patch.object(guard, 'identity', return_value='owned marker'), patch.object(guard.subprocess, 'Popen', return_value=process), patch.object(guard, 'write_state') as save:
            with self.assertRaises(RuntimeError): guard.prepare()
            process.terminate.assert_called_once(); save.assert_not_called()

    def test_release_requires_matching_identity_and_new_app_protection(self):
        value=self.value(); record={'pid':123,'identity':'owned marker','display':True,'fingerprint':guard.fingerprint(value)}
        with tempfile.TemporaryDirectory() as folder, patch.object(guard, 'STATE', Path(folder)/'state.json'), patch.object(guard, 'read_state', return_value=record), patch.object(guard, 'snapshot', return_value=value), patch.object(guard.time, 'time', return_value=1000), patch.object(guard, 'app_pid', return_value=999), patch.object(guard, 'identity', return_value='owned marker'), patch.object(guard, 'held_assertion', return_value=True), patch.object(guard.os, 'kill') as kill:
            guard.finish(); kill.assert_called_once_with(123, guard.signal.SIGTERM)
        with tempfile.TemporaryDirectory() as folder, patch.object(guard, 'STATE', Path(folder)/'state.json'), patch.object(guard, 'read_state', return_value=record), patch.object(guard, 'identity', return_value='unrelated process'), patch.object(guard.os, 'kill') as kill:
            guard.finish(); kill.assert_not_called()


if __name__ == '__main__': unittest.main()
