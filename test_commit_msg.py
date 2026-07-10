import commit_msg
import pytest


def test_strip_removes_comment_lines() -> None:
    raw = "feat: add thing\n# a comment\n\nbody line\n"
    assert commit_msg.strip_message(raw) == "feat: add thing\n\nbody line"


def test_strip_drops_scissors_block() -> None:
    raw = (
        "feat: add thing\n"
        "# ------------------------ >8 ------------------------\n"
        "diff --git a/x b/x\n"
    )
    assert commit_msg.strip_message(raw) == "feat: add thing"


def test_skip_merge_and_autosquash() -> None:
    assert commit_msg.should_skip("Merge branch 'main'")
    assert commit_msg.should_skip("fixup! feat: add x")
    assert commit_msg.should_skip("squash! feat: add x")


def test_no_skip_for_revert_or_normal() -> None:
    assert not commit_msg.should_skip('Revert "feat: add x"')
    assert not commit_msg.should_skip("feat: add x")


def test_header_format_accepts_valid() -> None:
    assert commit_msg.check_header_format("feat(api)!: add x") == []


@pytest.mark.parametrize(
    ("header", "snippet"),
    [
        ("feat add x", "type(scope)"),
        ("frobnicate: add x", "unknown type"),
        ("feat: Add x", "capital"),
        ("feat: add x.", "period"),
    ],
)
def test_header_format_rejects(header: str, snippet: str) -> None:
    errs = commit_msg.check_header_format(header)
    assert any(snippet in e for e in errs)


@pytest.mark.parametrize(
    ("length_chars", "expect_error", "expect_warning"),
    [
        (11, False, False),
        (50, False, False),
        (56, False, True),
        (72, False, True),
        (73, True, False),
        (76, True, False),
    ],
)
def test_header_length(
    length_chars: int, expect_error: bool, expect_warning: bool
) -> None:
    header = "feat: " + "a" * (length_chars - len("feat: "))
    assert len(header) == length_chars
    errs, warns = commit_msg.check_header_length(header)
    assert bool(errs) == expect_error
    assert bool(warns) == expect_warning


def test_body_requires_blank_line() -> None:
    lines = ["feat: add x", "body with no blank"]
    errs = commit_msg.check_body(lines)
    assert any("blank line" in e for e in errs)


def test_body_wrap_rejects_long_line() -> None:
    lines = ["feat: add x", "", "x" * 73]
    errs = commit_msg.check_body(lines)
    assert any("72" in e for e in errs)


def test_body_wrap_exempts_trailer_and_url() -> None:
    long_trailer = "Co-Authored-By: " + "n" * 70
    long_url = "Ref: https://example.com/" + "p" * 70
    lines = ["feat: add x", "", long_trailer, long_url]
    assert commit_msg.check_body(lines) == []


def test_body_header_only_is_fine() -> None:
    assert commit_msg.check_body(["feat: add x"]) == []


def test_validate_clean_message() -> None:
    msg = "feat(api): add x\n\nExplain the why here.\n"
    errs, warns = commit_msg.validate(commit_msg.strip_message(msg))
    assert errs == [] and warns == []


def test_validate_collects_multiple_errors() -> None:
    errs, _ = commit_msg.validate("Frob: Add x.")
    assert len(errs) >= 2


def test_main_passes_valid_file(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text("feat: add x\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_rejects_bad_file(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text("nope no colon here\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 1


def test_main_skips_merge(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text("Merge branch 'main'\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_allows_empty(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text("\n# only a comment\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_strip_keeps_body_after_hash_mentioning_8() -> None:
    raw = (
        "feat: add x\n\nfirst body line\n"
        "# note about >8 retries\nsecond body line\n"
    )
    result = commit_msg.strip_message(raw)
    assert "second body line" in result
    assert "# note about >8 retries" not in result


def test_main_warning_only_passes(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text("feat: " + "a" * 50 + "\n")  # 56-char header
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_validates_revert_not_skipped(tmp_path) -> None:
    f = tmp_path / "MSG"
    f.write_text('Revert "feat: add x"\n')
    assert commit_msg.main(["commit-msg", str(f)]) == 1


def test_forbidden_chars_rejects_em_dash_and_emoji() -> None:
    errs = commit_msg.check_forbidden_chars([
        "feat: do it — now",
        "body \U0001f600",
    ])
    assert any("em dash" in e for e in errs)
    assert any("emoji" in e for e in errs)


def test_forbidden_chars_allows_plain_ascii() -> None:
    assert commit_msg.check_forbidden_chars(["feat: plain ascii"]) == []
