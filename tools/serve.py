#!/usr/bin/env python3
"""Preview the showcase site locally, auto-incrementing the port if it's taken.

`make serve` calls this. Starts at $PORT (or argv[1], default 8000) and binds
the first free port at or above it, so a second `make serve` — or a stray
earlier server — just lands on the next port instead of erroring out.
"""
import functools
import http.server
import os
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "site"


def main() -> int:
    start = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT", 8000))
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(SITE))

    port = start
    httpd = None
    while port < start + 100:
        try:
            httpd = http.server.ThreadingHTTPServer(("", port), handler)
            break
        except OSError:
            port += 1
    if httpd is None:
        print(f"no free port in {start}..{start + 99}", file=sys.stderr)
        return 1

    if port != start:
        print(f"port {start} busy — using {port}")
    print(f"Serving site/ at http://localhost:{port}/  (Ctrl-C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
