#!/bin/sh
set -eu

hooks_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks"
src="$(cd "$(dirname "$0")" && pwd)/commit_msg.py"

mkdir -p "$hooks_dir"
chmod +x "$src"
rm -f "$hooks_dir/commit-msg"
cp "$src" "$hooks_dir/commit-msg"
chmod +x "$hooks_dir/commit-msg"
git config --global core.hooksPath "$hooks_dir"

echo "installed: $hooks_dir/commit-msg ($("$hooks_dir/commit-msg" --version))"
echo "core.hooksPath = $(git config --global core.hooksPath)"
echo "warning: global core.hooksPath shadows each repo's local .git/hooks"
