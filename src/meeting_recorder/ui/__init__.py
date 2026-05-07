"""Tiny FastAPI app for browsing and editing meeting markdown files."""

from .server import build_app

__all__ = ["build_app"]
