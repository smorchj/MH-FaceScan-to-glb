"""Dev static server for docs/ that sends no-store headers.

`python -m http.server` sends no cache directives, so browsers heuristically
cache index.html + viewer.js and serve stale modules across edits (which made
the viewer appear "stuck" on old settings during tuning). This handler forces
revalidation so every reload picks up the current files.

Usage:  python tools/serve_nocache.py [port]   (defaults to 8000, serves docs/)
"""
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
os.chdir(ROOT)


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


print(f"[serve_nocache] serving {ROOT} at http://localhost:{PORT} (no-store)")
Server(("", PORT), NoCacheHandler).serve_forever()
