#!/usr/bin/env bash
# Validate commit messages against the house style.
#
# Accumulator functions take an output array's *name* as a string and bind
# it with `local -n` internally, so shellcheck can't trace the assignment
# through to callers and flags it as SC2178 throughout this file.
# shellcheck disable=SC2178
set -uo pipefail

VERSION="0.3.1"

SCISSORS_RE='-{2,} >8 -{2,}'

TYPES_SORTED=(build chore ci docs feat fix perf refactor revert style test)
declare -gA TYPES=()
for _type in "${TYPES_SORTED[@]}"; do TYPES[$_type]=1; done
TYPES_LIST="build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test"

HEADER_RE='^([A-Za-z]+)(\(([^)]+)\))?(!)?: (.+)$'

TRAILER_LINE_RE='^([A-Za-z]+(-[A-Za-z]+)*|BREAKING[- ]CHANGES?): '

# Mined from the non-merge commit trailers of git/git, torvalds/linux,
# kubernetes/kubernetes, rust-lang/rust, and llvm/llvm-project (1000 most
# recent commits each); Reviewed-by, Acked-by, and Refs from the
# Conventional Commits spec's own footer examples; and Bug, Test,
# Depends-on, Reviewed-on from Chromium/Gerrit/OpenStack conventions.
# Change-Id, base-commit, "Differential Revision", and "Test Plan" are
# real but skipped: the first two have tooling-mandated casing that
# Sentence-case would corrupt, the last two use a space instead of a
# hyphen and don't fit this shape.
declare -gA KNOWN_TRAILERS=(
  [signed-off-by]=1 [co-authored-by]=1 [co-developed-by]=1 [reviewed-by]=1
  [acked-by]=1 [tested-by]=1 [reported-by]=1 [suggested-by]=1 [helped-by]=1
  [mentored-by]=1 [assisted-by]=1 [cc]=1 [fixes]=1 [closes]=1 [link]=1
  [ref]=1 [refs]=1 [bug]=1 [test]=1 [depends-on]=1 [reviewed-on]=1
)

# shellcheck disable=SC1112 # these are the literal glyphs being checked for
FORBIDDEN_CHARS=('—' '–' '―' '“' '”' '‘' '’' '…' '•' '→' '←' $' ')
FORBIDDEN_NAMES=(
  "em dash" "en dash" "horizontal bar"
  "curly left double quote" "curly right double quote"
  "curly left single quote" "curly right single quote"
  "ellipsis" "bullet" "right arrow" "left arrow" "non-breaking space"
)

EMOJI_RANGE_LO=(0x1f1e6 0x2600 0x2b00)
EMOJI_RANGE_HI=(0x1faff 0x27bf 0x2bff)

# str.split("\n"): unlike splitlines(), always keeps a trailing "" element.
split_lines_exact() {
  local __str="$1" __out_name="$2"
  local -n __out="$__out_name"
  __out=()
  local rest="$__str" piece
  while [[ "$rest" == *$'\n'* ]]; do
    piece="${rest%%$'\n'*}"
    __out+=("$piece")
    rest="${rest#*$'\n'}"
  done
  __out+=("$rest")
}

strip_message() {
  local raw="$1"
  local -a lines=()
  mapfile -t lines < <(printf '%s' "$raw")
  local -a kept=()
  local line
  for line in "${lines[@]}"; do
    if [[ "$line" == "#"* ]] && [[ "$line" =~ $SCISSORS_RE ]]; then
      break
    fi
    [[ "$line" == "#"* ]] && continue
    kept+=("$line")
  done
  local IFS=$'\n'
  local joined="${kept[*]}"
  unset IFS
  while [[ "$joined" == $'\n'* ]]; do joined="${joined#$'\n'}"; done
  while [[ "$joined" == *$'\n' ]]; do joined="${joined%$'\n'}"; done
  printf '%s' "$joined"
}

should_skip() {
  local first_line="$1"
  [[ "$first_line" == "Merge "* ]] ||
    [[ "$first_line" == "fixup!"* ]] ||
    [[ "$first_line" == "squash!"* ]] ||
    [[ "$first_line" == "release:"* ]]
}

check_header_format() {
  local header="$1" __errors_name="$2"
  local -n __errors="$__errors_name"
  if [[ ! "$header" =~ $HEADER_RE ]]; then
    __errors+=(
      "header must match 'type(scope)!: subject' with a lowercase type and a ': ' separator"
    )
    return
  fi
  local type="${BASH_REMATCH[1]}"
  local desc="${BASH_REMATCH[5]}"
  if [[ -z "${TYPES[$type]:-}" ]]; then
    __errors+=("unknown type '$type'; expected one of $TYPES_LIST")
  fi
  if [[ "${desc:0:1}" =~ [A-Z] ]]; then
    __errors+=("description must not start with a capital letter")
  fi
  if [[ "$desc" == *. ]]; then
    __errors+=("description must not end with a period")
  fi
}

check_header_length() {
  local header="$1" __errors_name="$2" __warnings_name="$3"
  local -n __errors="$__errors_name"
  local -n __warnings="$__warnings_name"
  local length_chars=${#header}
  if ((length_chars > 72)); then
    __errors+=("header is $length_chars chars; hard limit is 72")
    return
  fi
  if ((length_chars > 50)); then
    __warnings+=("header is $length_chars chars; aim for 50 or fewer")
  fi
}

trailer_key() {
  local token="${1,,}"
  token="${token#"${token%%[^[:space:]]*}"}"
  token="${token%"${token##*[^[:space:]]}"}"
  printf '%s' "$token" | sed -E 's/[[:space:]-]+/-/g'
}

is_breaking_change() {
  local key stripped
  key="$(trailer_key "$1")"
  stripped="$key"
  while [[ "$stripped" == *s ]]; do stripped="${stripped%s}"; done
  [[ "$stripped" == "breaking-change" ]]
}

is_known_trailer() {
  local key
  key="$(trailer_key "$1")"
  [[ -n "${KNOWN_TRAILERS[$key]:-}" ]] || is_breaking_change "$1"
}

sentence_case() {
  local -a words
  IFS='-' read -ra words <<<"$1"
  local first="${words[0],,}"
  first="${first^}"
  local out="$first" i
  for ((i = 1; i < ${#words[@]}; i++)); do
    out+="-${words[i],,}"
  done
  printf '%s' "$out"
}

match_trailer_prefix() {
  local line="$1"
  if [[ "$line" =~ $TRAILER_LINE_RE ]]; then
    TRAILER_TOKEN="${BASH_REMATCH[1]}"
    TRAILER_MATCH_LEN="${#BASH_REMATCH[0]}"
    return 0
  fi
  return 1
}

is_wrap_exempt() {
  local line="$1"
  if match_trailer_prefix "$line" && is_known_trailer "$TRAILER_TOKEN"; then
    return 0
  fi
  [[ "$line" =~ https?:// ]]
}

fix_trailer_casing() {
  local raw="$1" __out_name="$2"
  local header body sep
  if [[ "$raw" == *$'\n'* ]]; then
    header="${raw%%$'\n'*}"
    body="${raw#*$'\n'}"
    sep=$'\n'
  else
    header="$raw"
    body=""
    sep=""
  fi

  local had_trailing_nl=0
  [[ "$body" == *$'\n' ]] && had_trailing_nl=1

  local -a body_lines=()
  mapfile -t body_lines < <(printf '%s' "$body")

  local -a rewritten=()
  local line cased
  for line in "${body_lines[@]}"; do
    if match_trailer_prefix "$line" && is_known_trailer "$TRAILER_TOKEN" &&
      ! is_breaking_change "$TRAILER_TOKEN"; then
      cased="$(sentence_case "$TRAILER_TOKEN")"
      rewritten+=("${cased}: ${line:$TRAILER_MATCH_LEN}")
    else
      rewritten+=("$line")
    fi
  done

  local IFS=$'\n'
  local new_body="${rewritten[*]}"
  unset IFS
  ((had_trailing_nl)) && new_body+=$'\n'

  local -n __out="$__out_name"
  __out="${header}${sep}${new_body}"
}

strip_claude_context_suffix() {
  local raw="$1" __out_name="$2"
  local header body sep
  if [[ "$raw" == *$'\n'* ]]; then
    header="${raw%%$'\n'*}"
    body="${raw#*$'\n'}"
    sep=$'\n'
  else
    header="$raw"
    body=""
    sep=""
  fi

  local had_trailing_nl=0
  [[ "$body" == *$'\n' ]] && had_trailing_nl=1

  local -a body_lines=()
  mapfile -t body_lines < <(printf '%s' "$body")

  local -a rewritten=()
  local line
  for line in "${body_lines[@]}"; do
    if match_trailer_prefix "$line" &&
      [[ "$(trailer_key "$TRAILER_TOKEN")" == "co-authored-by" ]] &&
      [[ "$line" == *"<noreply@anthropic.com>"* ]]; then
      line="${line/ (1M context)/}"
    fi
    rewritten+=("$line")
  done

  local IFS=$'\n'
  local new_body="${rewritten[*]}"
  unset IFS
  ((had_trailing_nl)) && new_body+=$'\n'

  local -n __out="$__out_name"
  __out="${header}${sep}${new_body}"
}

is_emoji_codepoint() {
  local cp=$1 i
  for i in "${!EMOJI_RANGE_LO[@]}"; do
    if ((cp >= EMOJI_RANGE_LO[i] && cp <= EMOJI_RANGE_HI[i])); then
      return 0
    fi
  done
  return 1
}

line_has_emoji() {
  local ch cp
  while IFS= read -r ch; do
    [[ -z "$ch" ]] && continue
    cp=$(printf '%d' "'$ch")
    is_emoji_codepoint "$cp" && return 0
  done < <(grep -o . <<<"$1")
  return 1
}

# Advances one char past the *start* of each "--" so overlapping matches in
# runs of 3+ hyphens (e.g. "---") aren't skipped the way jumping past the
# whole match would skip them.
has_bad_double_hyphen() {
  local line="$1"
  local scan="$line" consumed=0 prefix pos before after
  while [[ "$scan" == *--* ]]; do
    prefix="${scan%%--*}"
    pos=$((consumed + ${#prefix}))
    before="${line:pos-1:1}"
    after="${line:pos+2:1}"
    if [[ -n "$before" && ! "$before" =~ [[:space:]] ]]; then
      return 0
    fi
    if [[ -z "$after" || "$after" =~ [[:space:]] ]]; then
      return 0
    fi
    consumed=$((pos + 1))
    scan="${line:consumed}"
  done
  return 1
}

check_forbidden_chars() {
  local __lines_name="$1" __errors_name="$2"
  local -n __lines="$__lines_name"
  local -n __errors="$__errors_name"
  local number=0 line i char name article
  for line in "${__lines[@]}"; do
    number=$((number + 1))
    for i in "${!FORBIDDEN_CHARS[@]}"; do
      char="${FORBIDDEN_CHARS[i]}"
      if [[ "$line" == *"$char"* ]]; then
        name="${FORBIDDEN_NAMES[i]}"
        case "${name:0:1}" in
        [aeiou]) article="an" ;;
        *) article="a" ;;
        esac
        __errors+=(
          "line $number contains $article $name ('$char'); use plain ASCII instead"
        )
      fi
    done
    if has_bad_double_hyphen "$line"; then
      __errors+=(
        "line $number contains '--' used as an em dash; use plain ASCII instead"
      )
    fi
    if line_has_emoji "$line"; then
      __errors+=("line $number contains an emoji; remove it")
    fi
  done
}

check_body() {
  local __lines_name="$1" __errors_name="$2"
  local -n __lines="$__lines_name"
  local -n __errors="$__errors_name"
  local count=${#__lines[@]}
  ((count < 2)) && return
  if [[ -n "${__lines[1]}" ]]; then
    __errors+=("body must be separated from the subject by a blank line")
  fi
  local idx number line
  for ((idx = 1; idx < count; idx++)); do
    number=$((idx + 1))
    line="${__lines[idx]}"
    if ((${#line} > 72)) && ! is_wrap_exempt "$line"; then
      __errors+=("line $number is ${#line} chars; wrap at 72")
    fi
  done
}

validate() {
  local message="$1" __errors_name="$2" __warnings_name="$3"
  local -a lines=()
  split_lines_exact "$message" lines
  local header="${lines[0]}"
  check_header_format "$header" "$__errors_name"
  local -a length_errors=() length_warnings=()
  check_header_length "$header" length_errors length_warnings
  local -n __errors="$__errors_name"
  local -n __warnings="$__warnings_name"
  __errors+=("${length_errors[@]}")
  __warnings+=("${length_warnings[@]}")
  check_body lines "$__errors_name"
  check_forbidden_chars lines "$__errors_name"
}

report() {
  local __errors_name="$1" __warnings_name="$2"
  local -n __errors="$__errors_name"
  local -n __warnings="$__warnings_name"
  local e w
  if ((${#__errors[@]} > 0)); then
    printf 'commit-msg: rejected\n\n' >&2
    for e in "${__errors[@]}"; do
      printf '  error: %s\n' "$e" >&2
    done
  fi
  if ((${#__warnings[@]} > 0)); then
    printf '\ncommit-msg: warnings\n' >&2
    for w in "${__warnings[@]}"; do
      printf '  warn: %s\n' "$w" >&2
    done
  fi
  if ((${#__errors[@]} > 0)); then
    printf "\nfix the errors above, or bypass with 'git commit --no-verify'\n" >&2
  fi
}

main() {
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  local path="$1"
  local raw
  # read -d '' reads to EOF without stripping trailing newlines the way
  # raw=$(cat "$path") would.
  IFS= read -r -d '' raw <"$path" || true

  local fixed
  fix_trailer_casing "$raw" fixed
  strip_claude_context_suffix "$fixed" fixed
  if [[ "$fixed" != "$raw" ]]; then
    printf '%s' "$fixed" >"$path"
  fi

  local message
  message="$(strip_message "$fixed")"

  [[ -z "${message//[[:space:]]/}" ]] && return 0
  should_skip "${message%%$'\n'*}" && return 0

  local -a errors=()
  # shellcheck disable=SC2034 # used by name via validate/report
  local -a warnings=()
  validate "$message" errors warnings
  report errors warnings

  ((${#errors[@]} > 0)) && return 1
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
