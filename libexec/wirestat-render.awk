# wirestat renderer: turns one pipe-delimited `curl -w` record into a status line.
#
# Input fields (see WIRESTAT_FORMAT in wirestat.sh):
#   1 http_code        6 time_appconnect     11 size_download
#   2 http_version     7 time_pretransfer    12 num_redirects
#   3 num_connects     8 time_starttransfer  13 exitcode
#   4 time_namelookup  9 time_total          14+ errormsg (may contain "|")
#   5 time_connect    10 time_redirect
#
# awk -v color=1 enables 256-colour output.

BEGIN {
  FS = "|"
  OK = 65; WARN = 209; BAD = 167; DIM = 240   # metalterm palette
}

function ms(sec) { return int(sec * 1000 + 0.5) }

function human(bytes) {
  if (bytes < 1024) return bytes "B"
  if (bytes < 1048576) return sprintf("%.1fKB", bytes / 1024)
  return sprintf("%.1fMB", bytes / 1048576)
}

function tint(text, code) {
  if (!color) return text
  return sprintf("\033[38;5;%dm%s\033[0m", code, text)
}

function status_color(code) {
  if (code + 0 >= 400) return BAD
  if (code + 0 >= 300) return WARN
  return OK
}

{
  code = $1; ver = $2; conns = $3
  namelookup = $4; connect = $5; appconnect = $6
  starttransfer = $8; total = $9; redirect = $10
  size = $11; redirects = $12; exitcode = $13

  errormsg = $14
  for (i = 15; i <= NF; i++) errormsg = errormsg "|" $i

  if (exitcode + 0 != 0) {
    printf "%s  %s\n", tint("err", BAD), tint(sprintf("curl: (%d) %s", exitcode, errormsg), DIM)
    next
  }

  # All of curl's time_* values are offsets from the start of the whole
  # operation, but they do not all describe the same request:
  #
  #   namelookup/connect/appconnect  the FIRST connection curl opened
  #   redirect                       everything before the final transaction
  #   starttransfer, total           cumulative across the entire operation
  #
  # Verified against a controlled server: a redirect to a second port reports
  # num_connects=2 with time_connect=0.6ms, i.e. the connection timers stayed
  # on hop 1. So the redirect hop is (redirect - end of first connection), and
  # server time is measured from time_redirect. Any connection setup on the
  # final leg lands inside srv -- imprecise, but honest, and the segments then
  # sum to exactly time_total.
  #
  # time_appconnect is 0 for plain HTTP, and after a cross-scheme redirect it
  # can predate time_connect entirely. Either way it carries no usable TLS
  # timing, so fall back to time_connect rather than going negative.
  base = (appconnect > connect) ? appconnect : connect
  redirecting = (redirects + 0 > 0)

  dns = ms(namelookup)
  tcp = ms(connect) - dns
  tls = ms(base) - ms(connect)
  redir = redirecting ? ms(redirect) - ms(base) : 0
  if (redir < 0) redir = 0
  srv = ms(starttransfer) - (redirecting ? ms(redirect) : ms(base))
  dl  = ms(total) - ms(starttransfer)

  redirseg = redirecting ? sprintf("  redir %d", redir) : ""

  verlabel = (ver == "2") ? "h2" : (ver == "3") ? "h3" : ver
  connlabel = (conns + 0 > 0) ? "new" : "reuse"

  phases = sprintf("%-3s  %-5s dns %d  tcp %d  tls %d  srv %d  dl %d%s",
                   verlabel, connlabel, dns, tcp, tls, srv, dl, redirseg)

  printf "%s  %s   %s  %s\n",
    tint(sprintf("%-3s", code), status_color(code)),
    tint(phases, DIM),
    tint(sprintf("%dms", ms(total)), WARN),
    tint(human(size), DIM)
}
