# wirestat -- per-request HTTP timing breakdown for curl, in fish.
# Loaded automatically by fisher/oh-my-fish; sets the shared configuration
# that functions/curl.fish reads.

set -q WIRESTAT_VERSION; or set -g WIRESTAT_VERSION 0.1.0

# Field order must match libexec/wirestat-render.awk.
set -g WIRESTAT_FORMAT '%{http_code}|%{http_version}|%{num_connects}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_pretransfer}|%{time_starttransfer}|%{time_total}|%{time_redirect}|%{size_download}|%{num_redirects}|%{exitcode}|%{errormsg}'

if not set -q WIRESTAT_HOME
    set -g WIRESTAT_HOME (path dirname (path dirname (status filename)))
end
set -g WIRESTAT_RENDER $WIRESTAT_HOME/libexec/wirestat-render.awk

function wirestat --description 'control wirestat curl timing output'
    switch "$argv[1]"
        case on
            set -e WIRESTAT_DISABLE
            echo 'wirestat on'
        case off
            set -gx WIRESTAT_DISABLE 1
            echo 'wirestat off'
        case version --version -V
            echo "wirestat $WIRESTAT_VERSION"
        case '*'
            echo 'usage: wirestat on|off|version' >&2
            return 2
    end
end
