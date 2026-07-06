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
