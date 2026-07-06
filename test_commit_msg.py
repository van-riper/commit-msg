import importlib.machinery
import importlib.util
from pathlib import Path

_path = Path(__file__).parent / "commit-msg"
_loader = importlib.machinery.SourceFileLoader("commit_msg", str(_path))
_spec = importlib.util.spec_from_file_location(
    "commit_msg", _path, loader=_loader
)
commit_msg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(commit_msg)


def test_strip_removes_comment_lines():
    raw = "feat: add thing\n# a comment\n\nbody line\n"
    assert commit_msg.strip_message(raw) == "feat: add thing\n\nbody line"


def test_strip_drops_scissors_block():
    raw = (
        "feat: add thing\n"
        "# ------------------------ >8 ------------------------\n"
        "diff --git a/x b/x\n"
    )
    assert commit_msg.strip_message(raw) == "feat: add thing"


def test_skip_merge_and_autosquash():
    assert commit_msg.should_skip("Merge branch 'main'")
    assert commit_msg.should_skip("fixup! feat: add x")
    assert commit_msg.should_skip("squash! feat: add x")


def test_no_skip_for_revert_or_normal():
    assert not commit_msg.should_skip('Revert "feat: add x"')
    assert not commit_msg.should_skip("feat: add x")


def test_header_format_accepts_valid():
    assert commit_msg.check_header_format("feat(api)!: add x") == []


def test_header_format_rejects_missing_colon():
    errs = commit_msg.check_header_format("feat add x")
    assert any("type(scope)" in e for e in errs)


def test_header_format_rejects_unknown_type():
    errs = commit_msg.check_header_format("frobnicate: add x")
    assert any("unknown type" in e for e in errs)


def test_header_format_rejects_capitalized_desc():
    errs = commit_msg.check_header_format("feat: Add x")
    assert any("capital" in e for e in errs)


def test_header_format_rejects_trailing_period():
    errs = commit_msg.check_header_format("feat: add x.")
    assert any("period" in e for e in errs)


def test_header_length_ok_under_50():
    errs, warns = commit_msg.check_header_length("feat: add x")
    assert errs == [] and warns == []


def test_header_length_warns_over_50():
    header = "feat: " + "a" * 50  # 56 chars
    errs, warns = commit_msg.check_header_length(header)
    assert errs == [] and any("50" in w for w in warns)


def test_header_length_rejects_over_72():
    header = "feat: " + "a" * 70  # 76 chars
    errs, warns = commit_msg.check_header_length(header)
    assert any("72" in e for e in errs)


def test_body_requires_blank_line():
    lines = ["feat: add x", "body with no blank"]
    errs = commit_msg.check_body(lines)
    assert any("blank line" in e for e in errs)


def test_body_wrap_rejects_long_line():
    lines = ["feat: add x", "", "x" * 73]
    errs = commit_msg.check_body(lines)
    assert any("72" in e for e in errs)


def test_body_wrap_exempts_trailer_and_url():
    long_trailer = "Co-Authored-By: " + "n" * 70
    long_url = "Ref: https://example.com/" + "p" * 70
    lines = ["feat: add x", "", long_trailer, long_url]
    assert commit_msg.check_body(lines) == []


def test_body_header_only_is_fine():
    assert commit_msg.check_body(["feat: add x"]) == []


def test_validate_clean_message():
    msg = "feat(api): add x\n\nExplain the why here.\n"
    errs, warns = commit_msg.validate(commit_msg.strip_message(msg))
    assert errs == [] and warns == []


def test_validate_collects_multiple_errors():
    errs, _ = commit_msg.validate("Frob: Add x.")
    assert len(errs) >= 2


def test_main_passes_valid_file(tmp_path):
    f = tmp_path / "MSG"
    f.write_text("feat: add x\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_rejects_bad_file(tmp_path):
    f = tmp_path / "MSG"
    f.write_text("nope no colon here\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 1


def test_main_skips_merge(tmp_path):
    f = tmp_path / "MSG"
    f.write_text("Merge branch 'main'\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_allows_empty(tmp_path):
    f = tmp_path / "MSG"
    f.write_text("\n# only a comment\n")
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_strip_keeps_body_after_hash_mentioning_8():
    raw = (
        "feat: add x\n\nfirst body line\n"
        "# note about >8 retries\nsecond body line\n"
    )
    result = commit_msg.strip_message(raw)
    assert "second body line" in result
    assert "# note about >8 retries" not in result


def test_header_length_boundary_50_ok():
    header = "feat: " + "a" * 44  # 50 chars
    assert len(header) == 50
    errs, warns = commit_msg.check_header_length(header)
    assert errs == [] and warns == []


def test_header_length_boundary_72_warns_not_rejects():
    header = "feat: " + "a" * 66  # 72 chars
    assert len(header) == 72
    errs, warns = commit_msg.check_header_length(header)
    assert errs == [] and warns != []


def test_header_length_boundary_73_rejects():
    header = "feat: " + "a" * 67  # 73 chars
    assert len(header) == 73
    errs, _ = commit_msg.check_header_length(header)
    assert errs != []


def test_main_warning_only_passes(tmp_path):
    f = tmp_path / "MSG"
    f.write_text("feat: " + "a" * 50 + "\n")  # 56-char header
    assert commit_msg.main(["commit-msg", str(f)]) == 0


def test_main_validates_revert_not_skipped(tmp_path):
    f = tmp_path / "MSG"
    f.write_text('Revert "feat: add x"\n')
    assert commit_msg.main(["commit-msg", str(f)]) == 1
