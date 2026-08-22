function curl --description 'curl with a per-request timing line (wirestat)'
    if not _wirestat_should_wrap $argv
        command curl $argv
        return $status
    end

    set -l err (mktemp "$TMPDIR/wirestat.XXXXXX"; or mktemp /tmp/wirestat.XXXXXX)
    if test -z "$err"
        command curl $argv
        return $status
    end

    # %{stderr} sends the write-out to fd 2; the leading newline keeps it off
    # the tail of whatever curl printed there, and the sentinel lets us pull it
    # back out without swallowing curl's own diagnostics.
    command curl -w "%{stderr}
__wirestat__|$WIRESTAT_FORMAT" $argv 2>$err
    set -l rc $status

    # Replay curl's own stderr, minus the sentinel record and minus the blank
    # line the sentinel's leading newline leaves as the final line.
    awk '
        /^__wirestat__\|/ { next }
        { if (seen) print prev; prev = $0; seen = 1 }
        END { if (seen && prev != "") print prev }
  ' $err >&2
    # One record per transfer: `curl a b` reports both, not just the last.
    set -l color 0
    if test -z "$NO_COLOR"; and test -t 2
        set color 1
    end
    sed -n 's/^__wirestat__|//p' $err | awk -v color=$color -f $WIRESTAT_RENDER >&2
    rm -f $err

    return $rc
end

# The write-out fields we rely on landed in curl 7.75 (%{exitcode},
# %{errormsg}); older curl prints those tokens literally rather than erroring,
# so probe once and stay out of the way if they are unavailable.
function _wirestat_curl_ok
    set -l v $argv[1]
    string match -qr '^[0-9]+(\.[0-9]+)*$' -- "$v"; or return 1
    set -l parts (string split . -- $v)
    set -l maj $parts[1]
    set -l min 0
    test (count $parts) -ge 2; and set min $parts[2]
    test $maj -gt 7; and return 0
    test $maj -eq 7 -a $min -ge 75; and return 0
    return 1
end

function _wirestat_should_wrap
    test -z "$WIRESTAT_DISABLE"; or return 1

    if not set -q WIRESTAT_CURL_OK
        if _wirestat_curl_ok (command curl --version 2>/dev/null | head -1 | string split ' ')[2]
            set -g WIRESTAT_CURL_OK 1
        else
            set -g WIRESTAT_CURL_OK 0
        end
    end
    test "$WIRESTAT_CURL_OK" = 1; or return 1

    if test -z "$WIRESTAT_FORCE"; and not test -t 1
        return 1
    end
    test -r "$WIRESTAT_RENDER"; or return 1
    for arg in $argv
        switch $arg
            case -v --verbose --trace --trace-ascii --trace-config --trace-ids --trace-time -# --progress-bar
                return 1
        end
    end
    return 0
end
