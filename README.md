# commit-msg

A global Git `commit-msg` hook that checks every commit message against my
curated style: [Conventional Commits][cc] headers plus the [seven rules][seven]
of a good commit message.

It's particularly useful for checking commits written by LLMs and coding agents,
which tend to slip in em-dashes, smart quotes, and overlong subjects that the
checks reject.

**NOTE:** this will override any repo-level commit-msg hooks you have set, so
don't use if your project uses a git hook manager like pre-commit or lefthook.

## Rules

| Rule                                                      | Result |
| --------------------------------------------------------- | ------ |
| Header over 50 chars                                      | warn   |
| Header over 72 chars                                      | reject |
| Header shaped `type(scope)!: subject`, type from the enum | reject |
| Description starts uppercase, or ends with a period       | reject |
| Body not separated from the subject by a blank line       | reject |
| Body line over 72 chars (trailers and URLs exempt)        | reject |
| Em dashes, smart quotes, ellipses, arrows, emoji          | reject |

Merge, `fixup!`, `squash!`, and empty messages pass without checks. Revert
messages are checked.

Known body trailers (`Co-Authored-By:`, `REVIEWED-BY:`, `SIGNED-OFF-BY:`,
and the like) are rewritten to git's standard `Sentence-case:` casing in
place, before the checks above run. `BREAKING CHANGE:` / `BREAKING-CHANGE:`
are exempt, since Conventional Commits requires those all-caps.
Unrecognized `Token: value` lines are left alone.

The trailer list was mined from the non-merge commit histories of
git/git, torvalds/linux, kubernetes/kubernetes, rust-lang/rust, and
llvm/llvm-project, plus the footer tokens from the Conventional Commits
spec and Chromium/Gerrit/OpenStack conventions.

## Install

```sh
./install.sh
```

This copies `commit_msg.py` to `~/.config/git/hooks/commit-msg` and points
`core.hooksPath` there, so the hook runs in every repo. A global
`core.hooksPath` shadows any repo's local `.git/hooks`.

## Bypass and uninstall

Skip the check for one commit:

```sh
git commit --no-verify
```

Turn the hook off everywhere:

```sh
git config --global --unset core.hooksPath
```

## Tests

```sh
pytest
```

[cc]: https://www.conventionalcommits.org
[seven]: https://cbea.ms/git-commit/#seven-rules
