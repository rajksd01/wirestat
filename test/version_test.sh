# _wirestat_curl_ok gates the wrapper on curl features we depend on:
#   %{stderr}   7.63    %{http_version} 7.50
#   %{exitcode} 7.75    %{errormsg}     7.75
# Older curl prints those tokens literally, which would render as garbage.

echo 'version gate:'

vcheck() {
  ( . "$ROOT/wirestat.sh" >/dev/null 2>&1
    if _wirestat_curl_ok "$1"; then echo ok; else echo no; fi )
}

assert_eq 'curl 8.7.1 is supported'          'ok' "$(vcheck 8.7.1)"
assert_eq 'curl 7.75.0 is the floor'         'ok' "$(vcheck 7.75.0)"
assert_eq 'curl 7.74.0 is rejected'          'no' "$(vcheck 7.74.0)"
assert_eq 'curl 7.68.0 (Ubuntu 20.04) is rejected' 'no' "$(vcheck 7.68.0)"
assert_eq 'curl 6.5 is rejected'             'no' "$(vcheck 6.5)"
assert_eq 'unparseable version is rejected'  'no' "$(vcheck '')"
