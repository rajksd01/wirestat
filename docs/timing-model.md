# curl's timing model

`curl` exposes seven timing variables through `-w`. They are easy to subtract
incorrectly, and every naive snippet does. This is what wirestat's renderer
encodes, verified against a controlled local server rather than assumed.

## They are offsets, not durations

Every `time_*` value is an offset from the start of the operation, so phases
come from differences:

```
dns = time_namelookup
tcp = time_connect      - time_namelookup
tls = time_appconnect   - time_connect
srv = time_starttransfer - time_appconnect
dl  = time_total        - time_starttransfer
```

That is correct **only when there were no redirects**.

## time_appconnect can be zero, or stale

On plain HTTP it is `0`, so `tls` would come out as a large negative number.

Worse, after a cross-scheme redirect it can *predate* `time_connect`. Real
capture from `curl -sL http://github.com`:

```
time_connect=0.077  time_appconnect=0.063
```

which subtracts to `tls = -14ms`. wirestat falls back to `time_connect`
whenever `time_appconnect` is not strictly later than it.

## The connection timers describe the FIRST connection

This is the surprising one. With a redirect that forces a new connection:

```
$ curl -sL -o /dev/null -w '...' http://127.0.0.1:8941/r
num_connects=2  time_connect=0.000619  time_redirect=0.313259
                time_starttransfer=0.523992  time_total=0.527667
```

curl opened two connections, but `time_connect` is 0.6ms — it never moved off
hop 1. The second connection's setup is not reported separately anywhere.

## time_starttransfer includes redirect time

Same server, with and without the redirect:

```
direct:        starttransfer=0.212  total=0.215  redirect=0.000
via redirect:  starttransfer=0.522  total=0.524  redirect=0.311
```

`0.522 ≈ 0.311 + 0.212`. So subtracting `time_redirect` from the *download*
(a common fix attempt) double-counts and produces a negative `dl`.

## What wirestat computes

```
base  = time_appconnect > time_connect ? time_appconnect : time_connect

dns   = time_namelookup
tcp   = time_connect - time_namelookup
tls   = base - time_connect
redir = redirects ? max(0, time_redirect - base) : 0
srv   = time_starttransfer - (redirects ? time_redirect : base)
dl    = time_total - time_starttransfer
```

The segments sum to exactly `time_total` in every case.

One known imprecision: when a redirect forces a *new* connection, that second
connection's DNS/TCP/TLS is invisible to curl's write-out, so it lands inside
`srv`. wirestat does not pretend otherwise — a redirect line's `srv` is an
upper bound on real server time.
