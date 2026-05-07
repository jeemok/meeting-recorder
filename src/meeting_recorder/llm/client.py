"""LLM provider abstraction. Default impl uses the Anthropic Python SDK."""

from __future__ import annotations

import os
from typing import Protocol


class LLMClient(Protocol):
    model: str

    def complete(self, system: str, user: str, max_tokens: int = 1024) -> str: ...


class AnthropicClient:
    def __init__(self, model: str, api_key: str | None = None):
        self.model = model
        self._api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not self._api_key:
            raise RuntimeError(
                "ANTHROPIC_API_KEY is not set. Add it to .env or set llm.enabled: false."
            )
        self._client = None

    def _ensure_client(self):
        if self._client is None:
            from anthropic import Anthropic

            self._client = Anthropic(api_key=self._api_key)
        return self._client

    def complete(self, system: str, user: str, max_tokens: int = 1024) -> str:
        client = self._ensure_client()
        msg = client.messages.create(
            model=self.model,
            max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
        )
        # Concatenate all text blocks.
        chunks: list[str] = []
        for block in msg.content:
            if getattr(block, "type", None) == "text":
                chunks.append(block.text)
        return "".join(chunks).strip()


def build_client(cfg: dict) -> LLMClient | None:
    """Returns None if LLM features are disabled in config."""
    if not cfg.get("enabled"):
        return None
    provider = cfg.get("provider", "anthropic")
    model = cfg.get("model", "claude-opus-4-7")
    if provider == "anthropic":
        return AnthropicClient(model=model)
    raise ValueError(f"Unsupported llm.provider: {provider}")
