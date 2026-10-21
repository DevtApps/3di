#!/usr/bin/env python3
"""Servidor estático sem cache para desenvolver o 3DI. Uso: python3 scripts/serve.py [porta]"""
import functools, http.server, os, sys

class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8327
handler = functools.partial(NoCache, directory=root)
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
