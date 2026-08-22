#!/bin/sh
# Integration tests: the curl wrapper itself, exercised in bash and zsh
# against a throwaway local HTTP server. No network access required.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pass=0
fail=0

assert_eq() {
  _name=$1 _want=$2 _got=$3
  if [ "$_want" = "$_got" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$_name"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n' "$_name"
    printf '       want: [%s]\n' "$_want"; printf '       got:  [%s]\n' "$_got"
  fi
}

assert_match() {
  _name=$1 _pat=$2 _got=$3
  case "$_got" in
    *$_pat*) pass=$((pass + 1)); printf '  ok   %s\n' "$_name" ;;
    *) fail=$((fail + 1)); printf '  FAIL %s\n' "$_name"
       printf '       want match: [%s]\n' "$_pat"; printf '       got:       [%s]\n' "$_got" ;;
  esac
}

TMP=$(mktemp -d)
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT

printf 'hello wirestat\n' > "$TMP/body.txt"
( cd "$TMP" && exec python3 -u -m http.server 0 --bind 127.0.0.1 ) > "$TMP/srv.log" 2>&1 &
SRV=$!
set +m 2>/dev/null || true

PORT=""
i=0
while [ "$i" -lt 100 ]; do
  PORT=$(sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' "$TMP/srv.log" | head -1)
  [ -n "$PORT" ] && break
  i=$((i + 1)); sleep 0.1
done
[ -n "$PORT" ] || { echo "could not start test server"; exit 1; }
URL="http://127.0.0.1:$PORT/body.txt"

# run <shell> <script> -> runs script with wirestat.sh sourced
run() {
  _sh=$1; _script=$2
  "$_sh" -c ". '$ROOT/wirestat.sh'
$_script"
}

for SHELL_UNDER_TEST in bash zsh; do
  command -v "$SHELL_UNDER_TEST" >/dev/null 2>&1 || continue
  echo "$SHELL_UNDER_TEST:"

  assert_eq "$SHELL_UNDER_TEST: piped body is byte-identical to bare curl" \
    "$(command curl -s "$URL")" \
    "$(run "$SHELL_UNDER_TEST" "curl -s '$URL'" 2>/dev/null)"

  assert_eq "$SHELL_UNDER_TEST: no stats line leaks when stdout is not a tty" \
    "" \
    "$(run "$SHELL_UNDER_TEST" "curl -s '$URL'" 2>&1 >/dev/null)"

  assert_match "$SHELL_UNDER_TEST: forced render emits a stats line on stderr" \
    "srv " \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "$SHELL_UNDER_TEST: stats output is exactly one line, no blank padding" \
    "1" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 curl -s '$URL'" 2>&1 >/dev/null | wc -l | tr -d ' ')"

  assert_eq "$SHELL_UNDER_TEST: WIRESTAT_DISABLE suppresses the stats line" \
    "" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 WIRESTAT_DISABLE=1 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "$SHELL_UNDER_TEST: one stats line per transfer for a multi-URL call" \
    "2" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 curl -s -o /dev/null -o /dev/null '$URL' '$URL'" 2>&1 >/dev/null | wc -l | tr -d ' ')"

  assert_eq "$SHELL_UNDER_TEST: an unsupported curl disables the wrapper" \
    "" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 WIRESTAT_CURL_OK=0 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "$SHELL_UNDER_TEST: curl exit code is preserved on failure" \
    "6" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 curl -s http://wirestat.invalid/ >/dev/null 2>&1; echo \$?")"

  assert_eq "$SHELL_UNDER_TEST: curl's own stderr still reaches stderr" \
    "found" \
    "$(run "$SHELL_UNDER_TEST" "WIRESTAT_FORCE=1 curl -sS http://wirestat.invalid/ 2>&1 >/dev/null | grep -qi 'resolve' && echo found")"
done

if command -v fish >/dev/null 2>&1; then
  echo "fish:"
  fishrun() {
    fish -c "set -gx WIRESTAT_HOME '$ROOT'
source '$ROOT/conf.d/wirestat.fish'
source '$ROOT/functions/curl.fish'
$1"
  }

  assert_eq "fish: piped body is byte-identical to bare curl" \
    "$(command curl -s "$URL")" \
    "$(fishrun "curl -s '$URL'" 2>/dev/null)"

  assert_eq "fish: no stats line leaks when stdout is not a tty" \
    "" \
    "$(fishrun "curl -s '$URL'" 2>&1 >/dev/null)"

  assert_match "fish: forced render emits a stats line on stderr" \
    "srv " \
    "$(fishrun "WIRESTAT_FORCE=1 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "fish: stats output is exactly one line, no blank padding" \
    "1" \
    "$(fishrun "WIRESTAT_FORCE=1 curl -s '$URL'" 2>&1 >/dev/null | wc -l | tr -d ' ')"

  assert_eq "fish: WIRESTAT_DISABLE suppresses the stats line" \
    "" \
    "$(fishrun "WIRESTAT_FORCE=1 WIRESTAT_DISABLE=1 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "fish: one stats line per transfer for a multi-URL call" \
    "2" \
    "$(fishrun "WIRESTAT_FORCE=1 curl -s -o /dev/null -o /dev/null '$URL' '$URL'" 2>&1 >/dev/null | wc -l | tr -d ' ')"

  assert_eq "fish: an unsupported curl disables the wrapper" \
    "" \
    "$(fishrun "WIRESTAT_FORCE=1 WIRESTAT_CURL_OK=0 curl -s '$URL'" 2>&1 >/dev/null)"

  assert_eq "fish: curl exit code is preserved on failure" \
    "6" \
    "$(fishrun "WIRESTAT_FORCE=1 curl -s http://wirestat.invalid/ >/dev/null 2>/dev/null; echo \$status")"

  assert_eq "fish: curl's own stderr still reaches stderr" \
    "found" \
    "$(fishrun "WIRESTAT_FORCE=1 curl -sS http://wirestat.invalid/ 2>&1 >/dev/null | grep -qi resolve; and echo found")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
