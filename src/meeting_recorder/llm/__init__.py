"""LLM integration. Provider-agnostic interface, default implementation: Claude.

* ``client.py``    -- thin Anthropic SDK wrapper, single point of network IO
* ``summarize.py`` -- post-call summary + action items from a Meeting
* ``realtime.py``  -- rolling-window question suggestions while recording
"""

from .client import LLMClient, AnthropicClient, build_client
from .summarize import summarize_meeting
from .realtime import RealtimeSuggester

__all__ = [
    "LLMClient",
    "AnthropicClient",
    "build_client",
    "summarize_meeting",
    "RealtimeSuggester",
]
