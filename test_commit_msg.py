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
