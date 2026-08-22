# wirestat -- per-request HTTP timing breakdown for curl, in bash and zsh.
# https://github.com/rajksd01/wirestat
#
#   source /path/to/wirestat.sh
#
# Every interactive curl then prints one dim line after the response:
#   200  h2   new   dns 4  tcp 20  tls 17  srv 101  dl 81   223ms  13.9KB
#
# Environment:
#   WIRESTAT_DISABLE=1   turn the wrapper off (or: wirestat off)
#   WIRESTAT_FORCE=1     render even when stdout is not a terminal
#   NO_COLOR=1           plain output
#
# Escape hatch: `command curl ...` always runs curl untouched.

WIRESTAT_VERSION=0.1.0

# Field order must match libexec/wirestat-render.awk.
WIRESTAT_FORMAT='%{http_code}|%{http_version}|%{num_connects}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_pretransfer}|%{time_starttransfer}|%{time_total}|%{time_redirect}|%{size_download}|%{num_redirects}|%{exitcode}|%{errormsg}'

_wirestat_self() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval 'printf "%s\n" "${(%):-%x}"'
  else
    printf '%s\n' "${BASH_SOURCE[0]}"
  fi
}

WIRESTAT_HOME=${WIRESTAT_HOME:-$(CDPATH= cd -- "$(dirname -- "$(_wirestat_self)")" && pwd)}
WIRESTAT_RENDER=$WIRESTAT_HOME/libexec/wirestat-render.awk

# curl owns stderr while it runs (-v, --trace, progress bar). Rather than fight
# it for the stream, hand those invocations straight through untouched.
_wirestat_passthrough_arg() {
  case $1 in
    -v|--verbose|--trace|--trace-ascii|--trace-config|--trace-ids|--trace-time|-#|--progress-bar)
      return 0 ;;
  esac
  return 1
}

# The write-out fields we rely on landed in curl 7.75 (%{exitcode},
# %{errormsg}); older curl prints those tokens literally rather than erroring,
# so probe once and stay out of the way if they are unavailable.
_wirestat_curl_ok() {
  _wsv=${1:-}
  case $_wsv in '' | *[!0-9.]*) return 1 ;; esac
  _wsmaj=${_wsv%%.*}
  _wsrest=${_wsv#*.}
  if [ "$_wsrest" = "$_wsv" ]; then _wsmin=0; else _wsmin=${_wsrest%%.*}; fi
  [ "$_wsmaj" -gt 7 ] && return 0
  [ "$_wsmaj" -eq 7 ] && [ "$_wsmin" -ge 75 ] && return 0
  return 1
}

_wirestat_should_wrap() {
  [ -z "${WIRESTAT_DISABLE:-}" ] || return 1

  if [ -z "${WIRESTAT_CURL_OK:-}" ]; then
    if _wirestat_curl_ok "$(command curl --version 2>/dev/null | awk 'NR==1 {print $2}')"; then
      WIRESTAT_CURL_OK=1
    else
      WIRESTAT_CURL_OK=0
    fi
  fi
  [ "$WIRESTAT_CURL_OK" = 1 ] || return 1

  [ -n "${WIRESTAT_FORCE:-}" ] || [ -t 1 ] || return 1
  [ -r "$WIRESTAT_RENDER" ] || return 1
  for _arg in "$@"; do
    if _wirestat_passthrough_arg "$_arg"; then return 1; fi
  done
  return 0
}

curl() {
  if ! _wirestat_should_wrap "$@"; then
    command curl "$@"
    return $?
  fi

  _ws_err=$(mktemp "${TMPDIR:-/tmp}/wirestat.XXXXXX") || { command curl "$@"; return $?; }

  # %{stderr} sends the write-out to fd 2; the leading newline keeps it off the
  # tail of whatever curl printed there, and the sentinel lets us pull it back
  # out without swallowing curl's own diagnostics.
  command curl -w "%{stderr}
__wirestat__|$WIRESTAT_FORMAT" "$@" 2>"$_ws_err"
  _ws_rc=$?

  # Replay curl's own stderr, minus the sentinel record and minus the blank
  # line the sentinel's leading newline leaves as the final line.
  awk '
    /^__wirestat__\|/ { next }
    { if (seen) print prev; prev = $0; seen = 1 }
    END { if (seen && prev != "") print prev }
  ' "$_ws_err" >&2
  # One record per transfer: `curl a b` reports both, not just the last.
  _ws_color=0
  if [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then _ws_color=1; fi
  sed -n 's/^__wirestat__|//p' "$_ws_err" \
    | awk -v color="$_ws_color" -f "$WIRESTAT_RENDER" >&2
  rm -f "$_ws_err"

  return $_ws_rc
}

wirestat() {
  case ${1:-} in
    on)  unset WIRESTAT_DISABLE; printf 'wirestat on\n' ;;
    off) WIRESTAT_DISABLE=1; export WIRESTAT_DISABLE; printf 'wirestat off\n' ;;
    version|--version|-V) printf 'wirestat %s\n' "$WIRESTAT_VERSION" ;;
    *) printf 'usage: wirestat on|off|version\n' >&2; return 2 ;;
  esac
}
