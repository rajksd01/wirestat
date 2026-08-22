#!/bin/sh
# wirestat test runner. POSIX sh, no deps beyond awk.
# Usage: sh test/run.sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RENDER="$ROOT/libexec/wirestat-render.awk"

pass=0
fail=0

# render <stats-line> [env assignments...] -> prints rendered output
render() {
  printf '%s\n' "$1" | awk -f "$RENDER"
}

assert_eq() {
  _name=$1 _want=$2 _got=$3
  if [ "$_want" = "$_got" ]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$_name"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n' "$_name"
    printf '       want: [%s]\n' "$_want"
    printf '       got:  [%s]\n' "$_got"
  fi
}

render_color() {
  printf '%s\n' "$1" | awk -v color=1 -f "$RENDER"
}

E=$(printf '\033')

. "$ROOT/test/render_test.sh"
echo
. "$ROOT/test/version_test.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
