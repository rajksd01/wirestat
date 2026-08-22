#!/usr/bin/env python3
"""Regenerate the SVG terminal captures used in README.md.

    python3 docs/render-demo.py

Text is positioned per-character on a fixed grid so the output looks identical
in every SVG renderer, and the palette is the real xterm-256 values wirestat
emits, so the images match what a terminal actually shows.
"""
import pathlib

CW, LH, PAD = 8.4, 22.0, 22.0          # char width, line height, padding
FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"
FS = 14

BG, CHROME = "#121214", "#0e0e10"
FG, PROMPT, COMMENT = "#c9c5be", "#e8834a", "#6b6b73"
OK, WARN, BAD, DIM = "#5f875f", "#ff875f", "#d75f5f", "#767680"

# (text, color) runs. A bare string is FG.
DEMO = [
    [("$ ", PROMPT), ("curl -s -o /dev/null https://example.com", FG)],
    [("200", OK), ("  h2   new   dns 13  tcp 9  tls 13  srv 14  dl 0", DIM),
     ("   49ms", WARN), ("  559B", DIM)],
    [],
    [("$ ", PROMPT), ("curl -s -o /dev/null -o /dev/null https://example.com https://example.com", FG)],
    [("200", OK), ("  h2   new   dns 2  tcp 8  tls 13  srv 18  dl 0", DIM),
     ("   41ms", WARN), ("  559B", DIM)],
    [("200", OK), ("  h2   reuse dns 0  tcp 0  tls 0  srv 10  dl 3", DIM),
     ("   13ms", WARN), ("  559B", DIM)],
    [("", FG), ("# same connection reused: no dns, no tcp, no tls", COMMENT)],
    [],
    [("$ ", PROMPT), ("curl -sL -o /dev/null http://github.com", FG)],
    [("200", OK), ("  h2   new   dns 16  tcp 67  tls 0  srv 130  dl 171  redir 6", DIM),
     ("   390ms", WARN), ("  561.1KB", DIM)],
    [],
    [("$ ", PROMPT), ("curl -s -o /dev/null https://httpbin.org/status/503", FG)],
    [("503", BAD), ("  h2   new   dns 30  tcp 286  tls 534  srv 796  dl 0", DIM),
     ("   1646ms", WARN), ("  0B", DIM)],
    [("", FG), ("# 1.6s, and 820ms of it never reached the app", COMMENT)],
    [],
    [("$ ", PROMPT), ("curl -s -o /dev/null https://nope.invalid", FG)],
    [("err", BAD), ("  curl: (6) Could not resolve host: nope.invalid", DIM)],
]

ANATOMY_LINE = [
    ("200", OK), ("  ", DIM), ("h2", DIM), ("   ", DIM), ("new", DIM),
    ("   dns 16  tcp 67  tls 0  srv 130  dl 171  redir 6", DIM),
    ("   390ms", WARN), ("  561.1KB", DIM),
]

# (start column, length, label, colour)
ANATOMY_MARKS = [
    (0, 3, "status", OK),
    (5, 2, "protocol", DIM),
    (10, 3, "fresh connection?", DIM),
    (16, 6, "resolve", DIM),
    (24, 6, "handshake", DIM),
    (32, 5, "tls", DIM),
    (39, 7, "your backend", WARN),
    (48, 6, "transfer", DIM),
    (56, 7, "redirect hops", DIM),
    (66, 5, "wall clock", WARN),
    (73, 7, "bytes", DIM),
]


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def runs_to_svg(runs, y):
    out, col = [], 0
    for text, color in runs:
        if text:
            out.append(
                '<tspan x="%.1f" y="%.1f" fill="%s" xml:space="preserve">%s</tspan>'
                % (PAD + col * CW, y, color, esc(text))
            )
        col += len(text)
    return "".join(out)


def card(lines, width_cols, extra="", extra_h=0.0):
    w = PAD * 2 + width_cols * CW
    h = PAD * 2 + len(lines) * LH + 34 + extra_h
    body = []
    for i, runs in enumerate(lines):
        if runs:
            body.append(runs_to_svg(runs, PAD + 34 + (i + 0.75) * LH))
    dots = "".join(
        '<circle cx="%d" cy="17" r="5.5" fill="%s"/>' % (x, c)
        for x, c in ((22, "#d75f5f"), (42, "#c8a45c"), (62, "#5f875f"))
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" '
        'viewBox="0 0 %.0f %.0f" font-family="%s" font-size="%d">'
        '<rect width="%.0f" height="%.0f" rx="10" fill="%s"/>'
        '<rect width="%.0f" height="34" rx="10" fill="%s"/>'
        '<rect y="24" width="%.0f" height="10" fill="%s"/>'
        "%s<text>%s</text>%s</svg>"
    ) % (w, h, w, h, FONT, FS, w, h, BG, w, CHROME, w, CHROME, dots, "".join(body), extra)


def main():
    here = pathlib.Path(__file__).parent

    cols = max(sum(len(t) for t, _ in r) for r in DEMO if r)
    (here / "demo.svg").write_text(card(DEMO, cols))

    marks, top = [], PAD + 34 + 1.75 * LH - 4
    card_w = PAD * 2 + 84 * CW
    for i, (col, length, label, color) in enumerate(ANATOMY_MARKS):
        x, w = PAD + col * CW, length * CW
        depth = top + 30 + (i % 3) * 24
        mid = x + w / 2
        # keep the label inside the card even when its column hugs an edge
        half = len(label) * 3.3
        tx = min(max(mid, PAD + half), card_w - PAD - half)
        marks.append(
            '<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f" '
            'fill="none" stroke="%s" stroke-width="1" opacity="0.5"/>'
            % (x, top, x, top + 7, x + w, top + 7, x + w, top, color)
        )
        marks.append(
            '<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f" fill="none" stroke="%s" '
            'stroke-width="1" opacity="0.5"/>'
            % (mid, top + 7, mid, depth - 16, tx, depth - 11, color)
        )
        marks.append(
            '<text x="%.1f" y="%.1f" fill="%s" font-size="11.5" text-anchor="middle" '
            'opacity="0.95">%s</text>' % (tx, depth, color, esc(label))
        )
    (here / "anatomy.svg").write_text(
        card([ANATOMY_LINE], 84, extra="".join(marks), extra_h=112)
    )
    print("wrote docs/demo.svg and docs/anatomy.svg")


if __name__ == "__main__":
    main()
