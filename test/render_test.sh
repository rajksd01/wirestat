# Test cases for libexec/wirestat-render.awk
#
# Field order (pipe-delimited, matches WIRESTAT_FORMAT):
#   code|version|num_connects|namelookup|connect|appconnect|pretransfer|
#   starttransfer|total|redirect|size_download|num_redirects|exitcode|errormsg
#
# Redirect fixtures are real captures, not invented numbers -- curl's timer
# semantics under -L are counter-intuitive enough that guessed values encode
# the wrong model. See docs/timing-model.md.

echo 'render:'

assert_eq 'https 200, new connection, phases sum to total' \
  '200  h2   new   dns 4  tcp 20  tls 17  srv 101  dl 81   223ms  13.9KB' \
  "$(render '200|2|1|0.004000|0.024000|0.041000|0.041500|0.142000|0.223000|0.000000|14200|0|0|')"

assert_eq 'curl transport failure reports exit code and message, no phases' \
  'err  curl: (6) Could not resolve host: nope.invalid' \
  "$(render '000|0|0|0.000000|0.000000|0.000000|0.000000|0.000000|0.005000|0.000000|0|0|6|Could not resolve host: nope.invalid')"

assert_eq 'error message containing a pipe is not truncated' \
  "err  curl: (60) SSL: no alternative certificate subject name matches 'a|b'" \
  "$(render "000|0|0|0|0|0|0|0|0.005000|0.000000|0|0|60|SSL: no alternative certificate subject name matches 'a|b'")"

assert_eq 'http/1.1 reused connection aligns with h2 lines' \
  '200  1.1  reuse dns 0  tcp 0  tls 0  srv 118  dl 9   127ms  13.9KB' \
  "$(render '200|1.1|0|0.000000|0.000000|0.000000|0.000100|0.118000|0.127000|0.000000|14200|0|0|')"

assert_eq 'multi-megabyte download reports MB, not four-digit KB' \
  '200  h2   new   dns 1  tcp 10  tls 20  srv 50  dl 1919   2000ms  5.0MB' \
  "$(render '200|2|1|0.001000|0.011000|0.031000|0.031000|0.081000|2.000000|0.000000|5242880|0|0|')"

# Captured from a controlled local server: /r sleeps 300ms then 302s to a
# second port (forcing a new connection), /big sleeps 200ms then sends 8MB.
# curl reports num_connects=2 but time_connect=0.6ms -- the connection timers
# describe the FIRST connection, so the redirect hop must be measured from
# time_redirect, not by subtracting it from the download.
assert_eq 'cross-origin redirect: hop cost is attributed to redir, not dl' \
  '200  1.1  new   dns 0  tcp 1  tls 0  srv 211  dl 4  redir 312   528ms  8.0MB' \
  "$(render '200|1.1|2|0.000181|0.000619|0.000000|0.000686|0.523992|0.527667|0.313259|8388608|1|0|')"

# Captured from `curl -sL http://github.com`: time_appconnect (63ms) predates
# time_connect (77ms), which naively subtracts to a negative TLS phase.
assert_eq 'stale appconnect after a redirect never yields a negative tls phase' \
  '200  h2   new   dns 14  tcp 63  tls 0  srv 95  dl 57  redir 5   234ms  561.1KB' \
  "$(render '200|2|1|0.014000|0.077000|0.063000|0.063000|0.177000|0.234000|0.082000|574566|1|0|')"

assert_eq 'color mode tints status green, phases dim, total orange' \
  "${E}[38;5;65m200${E}[0m  ${E}[38;5;240mh2   new   dns 4  tcp 20  tls 17  srv 101  dl 81${E}[0m   ${E}[38;5;209m223ms${E}[0m  ${E}[38;5;240m13.9KB${E}[0m" \
  "$(render_color '200|2|1|0.004000|0.024000|0.041000|0.041500|0.142000|0.223000|0.000000|14200|0|0|')"

assert_eq 'color mode tints a 404 status red' \
  "${E}[38;5;167m404${E}[0m  ${E}[38;5;240mh2   new   dns 4  tcp 20  tls 17  srv 101  dl 81${E}[0m   ${E}[38;5;209m223ms${E}[0m  ${E}[38;5;240m13.9KB${E}[0m" \
  "$(render_color '404|2|1|0.004000|0.024000|0.041000|0.041500|0.142000|0.223000|0.000000|14200|0|0|')"
