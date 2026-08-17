#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/commit-msg.sh"
  # shellcheck source=commit-msg.sh
  source "$SCRIPT"
}

@test "strip_message removes comment lines" {
  raw=$'feat: add thing\n# a comment\n\nbody line\n'
  result="$(strip_message "$raw")"
  [ "$result" = $'feat: add thing\n\nbody line' ]
}

@test "strip_message drops scissors block" {
  raw=$'feat: add thing\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n'
  result="$(strip_message "$raw")"
  [ "$result" = "feat: add thing" ]
}

@test "strip_message keeps body after hash mentioning >8" {
  raw=$'feat: add x\n\nfirst body line\n# note about >8 retries\nsecond body line\n'
  result="$(strip_message "$raw")"
  [[ "$result" == *"second body line"* ]]
  [[ "$result" != *"# note about >8 retries"* ]]
}

@test "should_skip matches merge and autosquash" {
  should_skip "Merge branch 'main'"
  should_skip "fixup! feat: add x"
  should_skip "squash! feat: add x"
  should_skip "release: v1.2.3"
}

@test "should_skip does not match revert or normal headers" {
  run ! should_skip 'Revert "feat: add x"'
  run ! should_skip "feat: add x"
}

@test "check_header_format accepts a valid header" {
  local -a errs=()
  check_header_format "feat(api)!: add x" errs
  [ "${#errs[@]}" -eq 0 ]
}

@test "check_header_format rejects a header with no colon separator" {
  local -a errs=()
  check_header_format "feat add x" errs
  [[ "${errs[*]}" == *"type(scope)"* ]]
}

@test "check_header_format accepts a multi-part scope with a slash" {
  local -a errs=()
  check_header_format "feat(etl/web): add x" errs
  [ "${#errs[@]}" -eq 0 ]
}

@test "check_header_format rejects a scope containing whitespace" {
  local -a errs=()
  check_header_format "feat(etl web): add x" errs
  [[ "${errs[*]}" == *"type(scope)"* ]]
}

@test "check_header_format rejects an unknown type" {
  local -a errs=()
  check_header_format "frobnicate: add x" errs
  [[ "${errs[*]}" == *"unknown type"* ]]
}

@test "check_header_format rejects a capitalized description" {
  local -a errs=()
  check_header_format "feat: Add x" errs
  [[ "${errs[*]}" == *"capital"* ]]
}

@test "check_header_format rejects a description ending in a period" {
  local -a errs=()
  check_header_format "feat: add x." errs
  [[ "${errs[*]}" == *"period"* ]]
}

@test "header length 11 chars: no error, no warning" {
  local header
  header="feat: $(printf 'a%.0s' {1..5})"
  [ "${#header}" -eq 11 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 0 ]
  [ "${#warns[@]}" -eq 0 ]
}

@test "header length 50 chars: no error, no warning" {
  local header
  header="feat: $(printf 'a%.0s' {1..44})"
  [ "${#header}" -eq 50 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 0 ]
  [ "${#warns[@]}" -eq 0 ]
}

@test "header length 56 chars: warning only" {
  local header
  header="feat: $(printf 'a%.0s' {1..50})"
  [ "${#header}" -eq 56 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 0 ]
  [ "${#warns[@]}" -eq 1 ]
}

@test "header length 72 chars: warning only" {
  local header
  header="feat: $(printf 'a%.0s' {1..66})"
  [ "${#header}" -eq 72 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 0 ]
  [ "${#warns[@]}" -eq 1 ]
}

@test "header length 73 chars: error, no warning" {
  local header
  header="feat: $(printf 'a%.0s' {1..67})"
  [ "${#header}" -eq 73 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 1 ]
  [ "${#warns[@]}" -eq 0 ]
}

@test "header length 76 chars: error, no warning" {
  local header
  header="feat: $(printf 'a%.0s' {1..70})"
  [ "${#header}" -eq 76 ]
  local -a errs=() warns=()
  check_header_length "$header" errs warns
  [ "${#errs[@]}" -eq 1 ]
  [ "${#warns[@]}" -eq 0 ]
}

@test "check_body rejects a body flush against the subject" {
  local -a lines=("feat: add x" "body with no blank")
  local -a errs=()
  check_body lines errs
  [[ "${errs[*]}" == *"blank line"* ]]
}

@test "check_body rejects a body line over 72 chars" {
  local long_line
  long_line="$(printf 'x%.0s' {1..73})"
  local -a lines=("feat: add x" "" "$long_line")
  local -a errs=()
  check_body lines errs
  [[ "${errs[*]}" == *"72"* ]]
}

@test "check_body exempts trailer and url lines from wrap" {
  local long_trailer long_url
  long_trailer="Co-authored-by: $(printf 'n%.0s' {1..70})"
  long_url="Ref: https://example.com/$(printf 'p%.0s' {1..70})"
  local -a lines=("feat: add x" "" "$long_trailer" "$long_url")
  local -a errs=()
  check_body lines errs
  [ "${#errs[@]}" -eq 0 ]
}

@test "check_body rejects an unknown-trailer-shaped long line" {
  local long_line
  long_line="Whatever: $(printf 'n%.0s' {1..70})"
  local -a lines=("feat: add x" "" "$long_line")
  local -a errs=()
  check_body lines errs
  [[ "${errs[*]}" == *"72"* ]]
}

@test "check_body passes a header with no body" {
  local -a lines=("feat: add x")
  local -a errs=()
  check_body lines errs
  [ "${#errs[@]}" -eq 0 ]
}

@test "validate passes a clean message" {
  msg="$(strip_message $'feat(api): add x\n\nExplain the why here.\n')"
  local -a errs=() warns=()
  validate "$msg" errs warns
  [ "${#errs[@]}" -eq 0 ]
  [ "${#warns[@]}" -eq 0 ]
}

@test "validate collects multiple errors" {
  local -a errs=() warns=()
  validate "Frob: Add x." errs warns
  [ "${#errs[@]}" -ge 2 ]
}

@test "main passes a valid message file" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'feat: add x\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

@test "main --version prints the version and exits 0" {
  run --separate-stderr "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$VERSION" ]
}

@test "main rejects an invalid message file" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'nope no colon here\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
}

@test "main skips a merge message file" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf "Merge branch 'main'\n" >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

@test "main skips a release message file" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'release: v1.2.3\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

@test "main allows an empty (comments-only) message" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf '\n# only a comment\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

@test "main passes a warning-only message" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'feat: %s\n' "$(printf 'a%.0s' {1..50})" >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

@test "main validates revert messages instead of skipping them" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'Revert "feat: add x"\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
}

@test "fix_trailer_casing normalizes known trailers regardless of casing" {
  local -a cases=(
    "Co-Authored-By:Co-authored-by" "CO-AUTHORED-BY:Co-authored-by"
    "co-authored-by:Co-authored-by" "REVIEWED-BY:Reviewed-by"
    "SIGNED-OFF-BY:Signed-off-by" "ref:Ref" "CC:Cc"
    "assisted-BY:Assisted-by" "BUG:Bug" "DEPENDS-ON:Depends-on"
  )
  local pair token expected raw want got
  for pair in "${cases[@]}"; do
    token="${pair%%:*}"
    expected="${pair#*:}"
    raw="feat: add x"$'\n\n'"${token}: value"$'\n'
    want="feat: add x"$'\n\n'"${expected}: value"$'\n'
    fix_trailer_casing "$raw" got
    if [[ "$got" != "$want" ]]; then
      echo "FAILED for token='$token': want='$want' got='$got'" >&2
      return 1
    fi
  done
}

@test "fix_trailer_casing leaves an unknown token alone" {
  raw="feat: add x"$'\n\n'"Whatever: value"$'\n'
  fix_trailer_casing "$raw" got
  [ "$got" = "$raw" ]
}

@test "fix_trailer_casing exempts BREAKING CHANGE" {
  raw="feat: add x"$'\n\n'"BREAKING CHANGE: value"$'\n'
  fix_trailer_casing "$raw" got
  [ "$got" = "$raw" ]
}

@test "fix_trailer_casing exempts BREAKING-CHANGE" {
  raw="feat: add x"$'\n\n'"BREAKING-CHANGE: value"$'\n'
  fix_trailer_casing "$raw" got
  [ "$got" = "$raw" ]
}

@test "fix_trailer_casing exempts lowercase breaking change" {
  raw="feat: add x"$'\n\n'"breaking change: value"$'\n'
  fix_trailer_casing "$raw" got
  [ "$got" = "$raw" ]
}

@test "main rewrites trailer casing in the message file itself" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'feat: add x\n\nCO-AUTHORED-BY: Bot <bot@example.com>\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  grep -qF "Co-authored-by: Bot <bot@example.com>" "$f"
}

@test "strip_claude_context_suffix removes the context size" {
  raw="feat: add x"$'\n\n'"Co-authored-by: Claude Opus 5 (1M context) <noreply@anthropic.com>"$'\n'
  want="feat: add x"$'\n\n'"Co-authored-by: Claude Opus 5 <noreply@anthropic.com>"$'\n'
  strip_claude_context_suffix "$raw" got
  [ "$got" = "$want" ]
}

@test "strip_claude_context_suffix ignores other co-authors" {
  raw="feat: add x"$'\n\n'"Co-authored-by: Jane Doe (1M context) <jane@example.com>"$'\n'
  strip_claude_context_suffix "$raw" got
  [ "$got" = "$raw" ]
}

@test "strip_claude_context_suffix leaves a plain claude trailer alone" {
  raw="feat: add x"$'\n\n'"Co-authored-by: Claude Opus 5 <noreply@anthropic.com>"$'\n'
  strip_claude_context_suffix "$raw" got
  [ "$got" = "$raw" ]
}

@test "main strips the context size from the message file itself" {
  f="$BATS_TEST_TMPDIR/MSG"
  printf 'feat: add x\n\nCo-authored-by: Claude Opus 5 (1M context) <noreply@anthropic.com>\n' >"$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  grep -qF "Co-authored-by: Claude Opus 5 <noreply@anthropic.com>" "$f"
  ! grep -qF "1M context" "$f"
}

@test "check_forbidden_chars rejects em dash and emoji" {
  local -a lines=("feat: do it — now" "body 😀")
  local -a errs=()
  check_forbidden_chars lines errs
  [[ "${errs[*]}" == *"em dash"* ]]
  [[ "${errs[*]}" == *"emoji"* ]]
}

@test "check_forbidden_chars allows plain ascii" {
  local -a lines=("feat: plain ascii")
  local -a errs=()
  check_forbidden_chars lines errs
  [ "${#errs[@]}" -eq 0 ]
}

@test "double hyphen: rejects sneaky em-dash-shaped and glued patterns" {
  local -a cases=(
    "this is a -- sneaky em-dash"
    "trailing double hyphen --"
    "word--word glued both sides"
    "sentence ends with text--"
  )
  local -a lines errs line
  for line in "${cases[@]}"; do
    lines=("$line")
    errs=()
    check_forbidden_chars lines errs
    if [ "${#errs[@]}" -eq 0 ]; then
      echo "expected rejection for: $line" >&2
      return 1
    fi
  done
}

@test "double hyphen: allows CLI flag usage" {
  local -a cases=(
    "here's a CLI --flag"
    "run with --flag=value"
  )
  local -a lines errs line
  for line in "${cases[@]}"; do
    lines=("$line")
    errs=()
    check_forbidden_chars lines errs
    if [ "${#errs[@]}" -ne 0 ]; then
      echo "expected no rejection for: $line, got: ${errs[*]}" >&2
      return 1
    fi
  done
}
