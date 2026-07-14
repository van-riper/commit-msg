#!/usr/bin/env python3
"""Validate commit messages against the house style."""

import re
import sys
from pathlib import Path

__version__ = "0.1.1"

SCISSORS_RE = re.compile(r"-{2,} >8 -{2,}")


def strip_message(raw: str) -> str:
    """Drop comment lines and the scissors block; return clean message."""
    kept: list[str] = []
    for line in raw.splitlines():
        if line.startswith("#") and SCISSORS_RE.search(line):
            break
        if line.startswith("#"):
            continue
        kept.append(line)
    return "\n".join(kept).strip("\n")


def should_skip(first_line: str) -> bool:
    """True for machine-generated messages that bypass validation."""
    return (
        first_line.startswith("Merge ")
        or first_line.startswith("fixup!")
        or first_line.startswith("squash!")
    )


TYPES = {
    "feat",
    "fix",
    "refactor",
    "perf",
    "style",
    "docs",
    "build",
    "test",
    "ci",
    "chore",
    "revert",
}

HEADER_RE = re.compile(
    r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?"
    r"(?P<bang>!)?: (?P<desc>.+)$"
)


def check_header_format(header: str) -> list[str]:
    """Return errors for header format, type, case, trailing period."""
    match = HEADER_RE.match(header)
    if match is None:
        return [
            "header must match 'type(scope)!: subject' with a "
            "lowercase type and a ': ' separator"
        ]

    errors: list[str] = []
    if match["type"] not in TYPES:
        errors.append(
            f"unknown type '{match['type']}'; expected one of "
            + ", ".join(sorted(TYPES))
        )
    desc = match["desc"]
    if desc[:1].isupper():
        errors.append("description must not start with a capital letter")
    if desc.endswith("."):
        errors.append("description must not end with a period")
    return errors


def check_header_length(header: str) -> tuple[list[str], list[str]]:
    """Warn above 50 chars; reject above 72. Prefix is included."""
    length_chars = len(header)
    if length_chars > 72:
        return ([f"header is {length_chars} chars; hard limit is 72"], [])
    if length_chars > 50:
        return ([], [f"header is {length_chars} chars; aim for 50 or fewer"])
    return ([], [])


URL_RE = re.compile(r"https?://")

TRAILER_LINE_RE = re.compile(
    r"^([A-Za-z]+(?:-[A-Za-z]+)*|BREAKING[- ]CHANGES?): ", re.MULTILINE
)

# Mined from the non-merge commit trailers of git/git, torvalds/linux,
# kubernetes/kubernetes, rust-lang/rust, and llvm/llvm-project (1000 most
# recent commits each); Reviewed-by, Acked-by, and Refs from the
# Conventional Commits spec's own footer examples; and Bug, Test,
# Depends-on, Reviewed-on from Chromium/Gerrit/OpenStack conventions.
# Change-Id, base-commit, "Differential Revision", and "Test Plan" are
# real but skipped: the first two have tooling-mandated casing that
# Sentence-case would corrupt, the last two use a space instead of a
# hyphen and don't fit this shape.
KNOWN_TRAILERS = frozenset({
    "signed-off-by",
    "co-authored-by",
    "co-developed-by",
    "reviewed-by",
    "acked-by",
    "tested-by",
    "reported-by",
    "suggested-by",
    "helped-by",
    "mentored-by",
    "assisted-by",
    "cc",
    "fixes",
    "closes",
    "link",
    "ref",
    "refs",
    "bug",
    "test",
    "depends-on",
    "reviewed-on",
})


def _trailer_key(token: str) -> str:
    """Canonical lookup key: lowercase, spaces folded to hyphens."""
    return re.sub(r"[\s-]+", "-", token.strip().lower())


def _is_breaking_change(token: str) -> bool:
    return _trailer_key(token).rstrip("s") == "breaking-change"


def _is_known_trailer(token: str) -> bool:
    return _trailer_key(token) in KNOWN_TRAILERS or _is_breaking_change(token)


def _sentence_case(token: str) -> str:
    """First hyphenated word capitalized, the rest lowercase."""
    words = token.split("-")
    return "-".join([words[0].capitalize(), *(w.lower() for w in words[1:])])


def fix_trailer_casing(raw: str) -> str:
    """Normalize known body trailers to git's Sentence-case convention.

    The header is left alone: 'type: subject' has the same shape as a
    trailer but isn't one. BREAKING CHANGE / BREAKING-CHANGE (and their
    plural typo) also keep whatever casing they already have, since
    Conventional Commits requires them all-caps rather than sentence-cased.
    Unrecognized "Token: value" lines are left untouched.
    """

    def repl(match: re.Match[str]) -> str:
        token = match.group(1)
        if not _is_known_trailer(token) or _is_breaking_change(token):
            return match.group(0)
        return f"{_sentence_case(token)}: "

    header, sep, body = raw.partition("\n")
    return header + sep + TRAILER_LINE_RE.sub(repl, body)


def _is_wrap_exempt(line: str) -> bool:
    """Known trailers and URL-bearing lines are not wrapped."""
    match = TRAILER_LINE_RE.match(line)
    if match and _is_known_trailer(match.group(1)):
        return True
    return bool(URL_RE.search(line))


FORBIDDEN_CHARS = {
    "—": "em dash",
    "–": "en dash",
    "―": "horizontal bar",
    "“": "curly left double quote",
    "”": "curly right double quote",
    "‘": "curly left single quote",
    "’": "curly right single quote",
    "…": "ellipsis",
    "•": "bullet",
    "→": "right arrow",
    "←": "left arrow",
    " ": "non-breaking space",
}

EMOJI_RE = re.compile(
    r"[\U0001f1e6-\U0001faff\U00002600-\U000027bf\U00002b00-\U00002bff]"
)

DOUBLE_HYPHEN_DASH_RE = re.compile(r"(?<=\S)--|--(?=\s|$)")


def check_forbidden_chars(lines: list[str]) -> list[str]:
    """Reject smart-typography and emoji glyphs common in AI output."""
    errors: list[str] = []
    for number, line in enumerate(lines, start=1):
        for char, name in FORBIDDEN_CHARS.items():
            if char in line:
                article = "an" if name[0] in "aeiou" else "a"
                errors.append(
                    f"line {number} contains {article} {name} "
                    f"('{char}'); use plain ASCII instead"
                )
        if DOUBLE_HYPHEN_DASH_RE.search(line):
            errors.append(
                f"line {number} contains '--' used as an em dash; "
                "use plain ASCII instead"
            )
        if EMOJI_RE.search(line):
            errors.append(f"line {number} contains an emoji; remove it")
    return errors


def check_body(lines: list[str]) -> list[str]:
    """Require a blank separator and wrap non-exempt body lines at 72."""
    if len(lines) < 2:
        return []

    errors: list[str] = []
    if lines[1]:
        errors.append("body must be separated from the subject by a blank line")
    for number, line in enumerate(lines[1:], start=2):
        if len(line) > 72 and not _is_wrap_exempt(line):
            errors.append(f"line {number} is {len(line)} chars; wrap at 72")
    return errors


def validate(message: str) -> tuple[list[str], list[str]]:
    """Run every check against a stripped, non-skipped message."""
    lines = message.split("\n")
    header = lines[0]
    errors = list(check_header_format(header))
    length_errors, warnings = check_header_length(header)
    errors += length_errors
    errors += check_body(lines)
    errors += check_forbidden_chars(lines)
    return errors, warnings


def _report(errors: list[str], warnings: list[str]) -> None:
    if errors:
        print("commit-msg: rejected\n", file=sys.stderr)
        for error in errors:
            print(f"  error: {error}", file=sys.stderr)
    if warnings:
        print("\ncommit-msg: warnings", file=sys.stderr)
        for warning in warnings:
            print(f"  warn: {warning}", file=sys.stderr)
    if errors:
        print(
            "\nfix the errors above, or bypass with 'git commit --no-verify'",
            file=sys.stderr,
        )


def main(argv: list[str]) -> int:
    """Validate the commit message file; return the hook exit code."""
    if argv[1:2] == ["--version"]:
        print(__version__)
        return 0

    path = Path(argv[1])
    raw = path.read_text(encoding="utf-8")
    fixed = fix_trailer_casing(raw)
    if fixed != raw:
        path.write_text(fixed, encoding="utf-8")
    message = strip_message(fixed)

    if not message.strip():
        return 0
    if should_skip(message.split("\n")[0]):
        return 0

    errors, warnings = validate(message)
    _report(errors, warnings)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
