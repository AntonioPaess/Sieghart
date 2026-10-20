#!/usr/bin/env python3
"""Join Xcode's enumerated Swift Testing leaves to source traits and contracts.

This is a deliberately small Swift declaration reader, not a Swift compiler. It
handles the declarations used in Tests/SwiftTesting and fails closed when an
enumerated leaf cannot be mapped. Parameter matrices remain function leaves:
their runtime argument instances are not invented from source expressions.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import sys
import tempfile


GROUP_TAGS = {
    "mouse-buttons": "mouseButtons",
    "desktop": "desktop",
    "input": "input",
    "timer": "timer",
    "callbacks": "callbacks",
    "voice-integration": "voiceIntegration",
    "interactions": "interactions",
    "companions": "companions",
    "usage": "usage",
    "spending": "spending",
    "activity": "activity",
    "pricing": "pricing",
    "audio": "audio",
    "imports": "imports",
    "clipboard": "clipboard",
    "middle-click": "middleClick",
    "utilities": "utilities",
    "calendar": "calendar",
    "files-capture": "filesCapture",
    "agent-room": "agentRoom",
    "local-chat": "localChat",
    "new-codex-chat": "newCodexChat",
}
FAST_PROFILES = {"logic", "isolated"}
FULL_ONLY_PROFILES = {"localIntegration", "nativeView"}
ROOTS = {"LogicTests", "MacContractsTests"}
CONTRACT = re.compile(r"\b(?:G\d{2}\.\d{2}|A\d{2})\b")
MODIFIERS = {
    "private", "fileprivate", "internal", "public", "open", "package",
    "final", "static", "mutating", "nonmutating", "nonisolated", "override",
    "required", "convenience", "indirect", "distributed", "consuming", "borrowing",
}


class IndexError(ValueError):
    """An input or declaration is not safe to select automatically."""


@dataclass(frozen=True)
class Token:
    value: str
    kind: str
    offset: int
    line: int


def string_end(source: str, start: int) -> int:
    """Skip Swift quoted/raw/multiline strings, including interpolation."""
    cursor = start
    while cursor < len(source) and source[cursor] == "#":
        cursor += 1
    hashes = source[start:cursor]
    quote = '"""' if source.startswith('"""', cursor) else '"'
    if not source.startswith(quote, cursor):
        raise IndexError("Unsupported string delimiter")
    cursor += len(quote)
    closing = quote + hashes
    escape = "\\" + hashes
    while cursor < len(source):
        if source.startswith(closing, cursor):
            return cursor + len(closing)
        if source.startswith(escape, cursor):
            cursor += len(escape)
            if cursor < len(source) and source[cursor] == "(":
                cursor = interpolation_end(source, cursor + 1)
            else:
                cursor += 1
        else:
            cursor += 1
    raise IndexError(f"Unterminated Swift string at offset {start}")


def comment_end(source: str, start: int) -> int:
    if source.startswith("//", start):
        end = source.find("\n", start)
        return len(source) if end < 0 else end
    cursor, depth = start + 2, 1
    while cursor < len(source) and depth:
        if source.startswith("/*", cursor):
            cursor += 2
            depth += 1
        elif source.startswith("*/", cursor):
            cursor += 2
            depth -= 1
        else:
            cursor += 1
    if depth:
        raise IndexError(f"Unterminated Swift comment at offset {start}")
    return cursor


def begins_string(source: str, cursor: int) -> bool:
    return source[cursor] == '"' or (
        source[cursor] == "#" and re.match(r'#+"', source[cursor:]) is not None
    )


def interpolation_end(source: str, cursor: int) -> int:
    depth = 1
    while cursor < len(source):
        if source.startswith(("//", "/*"), cursor):
            cursor = comment_end(source, cursor)
        elif begins_string(source, cursor):
            cursor = string_end(source, cursor)
        elif source[cursor] == "(":
            depth += 1
            cursor += 1
        elif source[cursor] == ")":
            depth -= 1
            cursor += 1
            if depth == 0:
                return cursor
        else:
            cursor += 1
    raise IndexError("Unterminated Swift string interpolation")


def lex(source: str) -> list[Token]:
    tokens: list[Token] = []
    cursor, line = 0, 1
    while cursor < len(source):
        start = cursor
        char = source[cursor]
        if source.startswith(("//", "/*"), cursor):
            cursor = comment_end(source, cursor)
        elif begins_string(source, cursor):
            cursor = string_end(source, cursor)
            tokens.append(Token(source[start:cursor], "string", start, line))
        elif char.isspace():
            cursor += 1
        elif char.isalpha() or char in "_$`":
            cursor += 1
            while cursor < len(source) and (
                source[cursor].isalnum() or source[cursor] in "_$`"
            ):
                cursor += 1
            tokens.append(Token(source[start:cursor].strip("`"), "word", start, line))
        else:
            cursor += 1
            tokens.append(Token(char, "symbol", start, line))
        line += source[start:cursor].count("\n")
    return tokens


def paired(tokens: list[Token], start: int) -> int:
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = [pairs[tokens[start].value]]
    for cursor in range(start + 1, len(tokens)):
        token = tokens[cursor]
        if token.kind == "string":
            continue
        if token.value in pairs:
            stack.append(pairs[token.value])
        elif token.value in pairs.values():
            if token.value != stack.pop():
                raise IndexError(f"Unbalanced Swift delimiters at line {token.line}")
            if not stack:
                return cursor
    raise IndexError(f"Unterminated Swift delimiter at line {tokens[start].line}")


@dataclass(frozen=True)
class Attribute:
    name: str
    arguments: tuple[Token, ...]
    line: int


def attribute(tokens: list[Token], cursor: int) -> tuple[Attribute, int]:
    start = cursor
    cursor += 1
    if cursor >= len(tokens) or tokens[cursor].kind != "word":
        raise IndexError(f"Unsupported Swift attribute at line {tokens[start].line}")
    name = tokens[cursor].value
    cursor += 1
    while cursor + 1 < len(tokens) and tokens[cursor].value == ".":
        name = tokens[cursor + 1].value
        cursor += 2
    arguments: tuple[Token, ...] = ()
    if cursor < len(tokens) and tokens[cursor].value == "(":
        end = paired(tokens, cursor)
        arguments = tuple(tokens[cursor + 1:end])
        cursor = end + 1
    return Attribute(name, arguments, tokens[start].line), cursor


def tags(attributes: list[Attribute]) -> set[str]:
    result: set[str] = set()
    for attr in attributes:
        tokens = list(attr.arguments)
        cursor = 0
        while cursor + 1 < len(tokens):
            if tokens[cursor].value == "tags" and tokens[cursor + 1].value == "(":
                end = paired(tokens, cursor + 1)
                for index in range(cursor + 2, end - 1):
                    if tokens[index].value == "." and tokens[index + 1].kind == "word":
                        result.add(tokens[index + 1].value)
                cursor = end + 1
            else:
                cursor += 1
    return result


def literal(token: Token) -> str:
    text = token.value
    count = len(text) - len(text.lstrip("#"))
    quotes = 3 if text[count:].startswith('"""') else 1
    result = text[count + quotes:len(text) - count - quotes]
    escape = "\\" + "#" * count
    result = re.sub(
        re.escape(escape) + r"u\{([0-9a-fA-F]+)\}",
        lambda match: chr(int(match.group(1), 16)), result,
    )
    for old, new in [('"', '"'), ("n", "\n"), ("r", "\r"), ("t", "\t"), ("\\", "\\")]:
        result = result.replace(escape + old, new)
    return result


def method_name(name: str, parameters: list[Token]) -> str:
    if not parameters:
        return name + "()"
    segments: list[list[Token]] = [[]]
    stack: list[str] = []
    opening = {"(": ")", "[": "]", "<": ">"}
    for token in parameters:
        value = token.value
        if value == "," and not stack:
            segments.append([])
            continue
        segments[-1].append(token)
        if value in opening:
            stack.append(opening[value])
        elif stack and value == stack[-1]:
            stack.pop()
    labels = []
    for segment in segments:
        colon = next((index for index, token in enumerate(segment) if token.value == ":"), None)
        if colon is None:
            raise IndexError(f"Unsupported parameters for test {name}")
        words = [token.value for token in segment[:colon] if token.kind == "word"]
        if not words:
            raise IndexError(f"Missing argument label for test {name}")
        labels.append(words[0] + ":")
    return name + "(" + "".join(labels) + ")"


def profile_for(all_tags: set[str], location: str) -> str:
    fast = all_tags & FAST_PROFILES
    full_only = all_tags & FULL_ONLY_PROFILES
    if not fast and not full_only:
        raise IndexError(f"Test without a profile: {location}")
    if fast and full_only:
        raise IndexError(f"Contradictory profiles {sorted(fast | full_only)}: {location}")
    # Isolated and nativeView are the conservative choices if traits overlap
    # inside their own boundary. All original tags remain in the record.
    for profile in ("nativeView", "localIntegration", "isolated", "logic"):
        if profile in all_tags:
            return profile
    raise AssertionError("Unreachable profile")


class SourceReader:
    def __init__(self, path: Path, project: Path, roots: dict[str, set[str]]):
        self.path = path
        self.project = project
        self.tokens = lex(path.read_text(encoding="utf-8"))
        self.roots = roots
        self.root_declarations: dict[str, set[str]] = {}
        self.records: list[dict] = []

    def read(self) -> list[dict]:
        self.block(0, len(self.tokens), (), set())
        return self.records

    def block(self, start: int, end: int, context: tuple[str, ...], inherited: set[str]) -> None:
        tokens = self.tokens
        cursor = start
        pending: list[Attribute] = []
        while cursor < end:
            token = tokens[cursor]
            value = token.value
            if value == "@":
                attr, cursor = attribute(tokens, cursor)
                pending.append(attr)
                continue
            if value in MODIFIERS:
                cursor += 1
                continue
            if value == "extension":
                names: list[str] = []
                header = cursor + 1
                while header < end and tokens[header].value != "{":
                    if tokens[header].kind == "word":
                        names.append(tokens[header].value)
                    elif tokens[header].value != ".":
                        raise IndexError(f"Unsupported extension in {self.path}:{token.line}")
                    header += 1
                if header == end or not names:
                    raise IndexError(f"Malformed extension in {self.path}:{token.line}")
                close = paired(tokens, header)
                root_tags = self.roots.get(names[0], set())
                self.block(header + 1, close, tuple(names), root_tags | tags(pending))
                cursor, pending = close + 1, []
                continue
            if value in {"struct", "class", "enum", "actor"} and cursor + 1 < end:
                if tokens[cursor + 1].value == "func":
                    cursor += 1
                    continue
                name = tokens[cursor + 1].value
                header = cursor + 2
                while header < end and tokens[header].value != "{":
                    header += 1
                if header == end:
                    raise IndexError(f"Malformed type in {self.path}:{token.line}")
                close = paired(tokens, header)
                own_tags = tags([attr for attr in pending if attr.name == "Suite"])
                if not context and name in ROOTS:
                    self.root_declarations[name] = own_tags
                self.block(header + 1, close, context + (name,), inherited | own_tags)
                cursor, pending = close + 1, []
                continue
            if value == "func" and cursor + 1 < end:
                test_attributes = [attr for attr in pending if attr.name == "Test"]
                name = tokens[cursor + 1].value
                params = cursor + 2
                while params < end and tokens[params].value != "(":
                    params += 1
                if params == end:
                    raise IndexError(f"Malformed function in {self.path}:{token.line}")
                close_params = paired(tokens, params)
                if test_attributes:
                    if len(test_attributes) != 1 or not context or context[0] not in ROOTS:
                        raise IndexError(f"Unsupported @Test context in {self.path}:{token.line}")
                    attr = test_attributes[0]
                    if not attr.arguments or attr.arguments[0].kind != "string":
                        raise IndexError(f"@Test needs a literal contract description: {self.path}:{attr.line}")
                    description = literal(attr.arguments[0])
                    contracts = sorted(set(CONTRACT.findall(description)))
                    if not contracts:
                        raise IndexError(f"@Test without Gxx.yy/A01 contract: {self.path}:{attr.line}")
                    signature = method_name(name, tokens[params + 1:close_params])
                    selector = "/".join(context + (signature,))
                    all_tags = inherited | tags(test_attributes)
                    profile = profile_for(all_tags, f"{self.path}:{attr.line} {selector}")
                    groups = sorted(group for group, tag in GROUP_TAGS.items() if tag in all_tags)
                    if not groups:
                        raise IndexError(f"@Test without a legacy group tag: {self.path}:{attr.line}")
                    self.records.append({
                        "selector": selector,
                        "root": context[0],
                        "suite": "/".join(context),
                        "method": signature,
                        "description": description,
                        "contractIDs": contracts,
                        "tags": sorted(all_tags),
                        "groups": groups,
                        "profile": profile,
                        "fastEligible": profile in FAST_PROFILES,
                        "sourceFile": self.path.relative_to(self.project).as_posix(),
                        "sourceLine": attr.line,
                        "functionLine": token.line,
                    })
                # Function-local helpers and braces are intentionally not suites.
                header = close_params + 1
                while header < end and tokens[header].value not in {"{", ";"}:
                    header += 1
                cursor = paired(tokens, header) + 1 if header < end and tokens[header].value == "{" else header + 1
                pending = []
                continue
            if value in {"{", "(", "["}:
                cursor = paired(tokens, cursor) + 1
            else:
                cursor += 1
            pending = []


def source_index(project: Path) -> dict[str, dict]:
    support = project / "Tests/Support/TestSupport.swift"
    if not support.is_file():
        raise IndexError(f"Missing root suite declarations: {support}")
    reader = SourceReader(support, project, {})
    reader.read()
    roots = reader.root_declarations
    if set(roots) != ROOTS or "logic" not in roots["LogicTests"]:
        raise IndexError("Expected LogicTests(.logic) and MacContractsTests roots in TestSupport.swift")
    result: dict[str, dict] = {}
    paths = sorted((project / "Tests/SwiftTesting").rglob("*.swift"))
    if not paths:
        raise IndexError("No Swift Testing sources were found")
    for path in paths:
        for record in SourceReader(path, project, roots).read():
            selector = record["selector"]
            if selector in result:
                raise IndexError(f"Ambiguous source test identifier: {selector}")
            result[selector] = record
    if not result:
        raise IndexError("No @Test declarations were indexed")
    return result


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise IndexError(f"Cannot read JSON {path}: {error}") from error


def enumerated_records(data: object, sources: dict[str, dict]) -> list[dict]:
    if not isinstance(data, dict) or not isinstance(data.get("values"), list):
        raise IndexError("Enumeration must contain a values array")
    if data.get("errors"):
        raise IndexError(f"Xcode enumeration reported errors: {data['errors']}")
    records: dict[str, dict] = {}

    def walk(node: object, path: tuple[str, ...], plan: str | None) -> None:
        if not isinstance(node, dict):
            raise IndexError("Enumeration contains a node that is not an object")
        kind, name = node.get("kind"), node.get("name")
        if kind not in {"plan", "target", "class", "suite", "test"} or not isinstance(name, str) or not name:
            raise IndexError(f"Unsupported enumeration node: kind={kind!r}, name={name!r}")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise IndexError(f"Invalid children for enumerated {name}")
        if kind == "plan":
            path, plan = (), name
        elif kind == "target":
            if name != "SieghartTests":
                raise IndexError(f"Unknown enumerated test target: {name}")
            path = (name,)
        else:
            if not path:
                raise IndexError(f"Enumeration node outside a target: {name}")
            path = path + (name,)
        if kind == "test":
            if children:
                raise IndexError(f"Unexpected argument-instance enumeration for {'/'.join(path)}")
            identifier, selector = "/".join(path), "/".join(path[1:])
            if selector not in sources:
                raise IndexError(f"Unknown enumerated test (no matching @Test source): {identifier}")
            if identifier not in records:
                records[identifier] = {"identifier": identifier, **sources[selector], "plans": []}
            if plan is not None and plan not in records[identifier]["plans"]:
                records[identifier]["plans"].append(plan)
        for child in children:
            walk(child, path, plan)

    for node in data["values"]:
        walk(node, (), None)
    if not records:
        raise IndexError("Enumeration contains no executable test leaves")
    return [records[key] for key in sorted(records)]


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            temporary = stream.name
            stream.write(text)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def json_text(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def swift_testing_selection(selectors: list[str]) -> dict:
    # Xcode writes Swift Testing selections as a suite tree. A string array is
    # the XCTest format and silently selects zero Swift Testing functions.
    selection: dict = {}
    for selector in sorted(selectors):
        *suites, method = selector.split("/")
        parent = selection
        for name in suites:
            children = parent.setdefault("suites", [])
            child = next((item for item in children if item["name"] == name), None)
            if child is None:
                child = {"name": name}
                children.append(child)
            parent = child
        parent.setdefault("testFunctions", []).append(method)
    return selection


def run(arguments: argparse.Namespace) -> dict:
    project = Path(__file__).resolve().parent.parent
    outputs = [arguments.output, arguments.selectors, arguments.fast_plan]
    destinations = [path.resolve() for path in outputs if path is not None]
    if len(set(destinations)) != len(destinations) or arguments.enumeration.resolve() in destinations:
        raise IndexError("Output, selectors, fast plan and enumeration must use distinct paths")
    sources = source_index(project)
    records = enumerated_records(read_json(arguments.enumeration), sources)
    matched_groups = set(GROUP_TAGS)
    if arguments.filter is not None:
        try:
            pattern = re.compile(arguments.filter)
        except re.error as error:
            raise IndexError(f"Invalid group filter regex: {error}") from error
        matched_groups = {group for group in GROUP_TAGS if pattern.search(group)}
        if not matched_groups:
            raise IndexError(f"Group filter matches none of the registered groups: {arguments.filter!r}")
    only_identifier = None
    if arguments.only is not None:
        matches = [record["identifier"] for record in records if arguments.only in {record["identifier"], record["selector"]}]
        if len(matches) != 1:
            raise IndexError(f"Unknown or ambiguous exact --only identifier: {arguments.only}")
        only_identifier = matches[0]
    for record in records:
        record["selected"] = (
            bool(set(record["groups"]) & matched_groups)
            and (arguments.plan == "complete" or record["fastEligible"])
            and (only_identifier is None or record["identifier"] == only_identifier)
        )
    selected = [record["identifier"] for record in records if record["selected"]]
    if not selected:
        raise IndexError(f"Final selection is empty (plan={arguments.plan}, filter={arguments.filter!r}, only={arguments.only!r})")
    fast_selectors = [record["selector"] for record in records if record["fastEligible"]]
    fast_plan = None
    if arguments.fast_plan is not None:
        fast_plan = read_json(arguments.fast_plan)
        if not isinstance(fast_plan, dict) or not isinstance(fast_plan.get("testTargets"), list) or not fast_plan["testTargets"] or not isinstance(fast_plan["testTargets"][0], dict):
            raise IndexError("Fast plan must contain testTargets[0]")
        target = fast_plan["testTargets"][0].get("target", {})
        if not isinstance(target, dict) or target.get("name") != "SieghartTests":
            raise IndexError("Fast plan testTargets[0] must refer to SieghartTests")
        if not fast_selectors:
            raise IndexError("No eligible logic/isolated test leaves are available for the fast plan")
        fast_plan["testTargets"][0]["selectedTests"] = swift_testing_selection(fast_selectors)
    summary = {
        "sourceTests": len(sources),
        "runtimeTests": len(records),
        "sourceOnlyTests": len(set(sources) - {record["selector"] for record in records}),
        "selectedTests": len(selected),
        "fastEligibleTests": len(fast_selectors),
        "contractIDs": sorted({contract for record in records for contract in record["contractIDs"]}),
        "profiles": dict(sorted(Counter(record["profile"] for record in records).items())),
        "selectedProfiles": dict(sorted(Counter(record["profile"] for record in records if record["selected"]).items())),
        "groups": dict(sorted(Counter(group for record in records for group in record["groups"]).items())),
        "selectedGroups": dict(sorted(Counter(group for record in records if record["selected"] for group in record["groups"]).items())),
    }
    result = {
        "version": 1,
        "enumeration": str(arguments.enumeration.resolve()),
        "sourceRoot": str(project),
        "selection": {"plan": arguments.plan, "filter": arguments.filter, "only": only_identifier, "matchedGroups": sorted(matched_groups)},
        "records": records,
        "selected": selected,
        "summary": summary,
    }
    # Validate every input and the final selection before any output is changed.
    if fast_plan is not None:
        atomic_write(arguments.fast_plan, json_text(fast_plan))
    if arguments.selectors is not None:
        atomic_write(arguments.selectors, "\n".join(selected) + "\n")
    atomic_write(arguments.output, json_text(result))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--enumeration", type=Path, required=True, help="Xcode -enumerate-tests JSON")
    parser.add_argument("--output", type=Path, required=True, help="Write complete metadata and the selected identifiers")
    parser.add_argument("--fast-plan", type=Path, help="Update only this copied .xctestplan with all eligible function leaves")
    parser.add_argument("--filter", help="Regex over the registered group names")
    parser.add_argument("--plan", choices=("complete", "fast"), default="complete")
    parser.add_argument("--only", help="Exact runtime identifier, optionally omitting SieghartTests/")
    parser.add_argument("--selectors", type=Path, help="Write full selected identifiers, one per line")
    arguments = parser.parse_args()
    try:
        result = run(arguments)
    except (IndexError, OSError) as error:
        print(f"swift-test-index: error: {error}", file=sys.stderr)
        return 2
    print(json.dumps({"output": str(arguments.output), "summary": result["summary"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
