"""Tiny HTTP helper with sane TLS.

Uses certifi's CA bundle when available (python.org builds on macOS ship without
a system trust store); otherwise falls back to the default context. GitHub Actions
runners have a working trust store, so this is transparent there.
"""
from __future__ import annotations

import ssl
import urllib.request

UA = "hu-boxoffice/1.0 (+https://github.com/)"


def _context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


_CTX = _context()


def get(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout, context=_CTX) as r:
        return r.read()
