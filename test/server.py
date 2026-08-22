#!/usr/bin/env python3
"""Throwaway HTTP server for wirestat's integration tests.

Binds an ephemeral port, prints `PORT=<n>` on stdout and flushes immediately,
then serves:

    /body.txt   a small fixed body
    /r          302 -> /body.txt, after a short delay

Prints the port itself rather than relying on http.server's banner, whose
wording and stream have varied across Python versions and runners.
"""
import http.server
import socket
import sys
import time

BODY = b"hello wirestat\n"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/r":
            time.sleep(0.05)
            self.send_response(302)
            self.send_header("Location", "/body.txt")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.listen(64)

    print("PORT=%d" % port, flush=True)

    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", port), Handler, bind_and_activate=False
    )
    server.socket = sock
    server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # surfaced by the runner on failure
        print("server failed: %r" % (exc,), file=sys.stderr, flush=True)
        raise
