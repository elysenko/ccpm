"""
Trigger Decision Client for Meeting Bot

Calls local Ollama LLM to decide if the bot should respond to the conversation.
Designed for low-latency (<500ms) decisions on ARM64.
"""

import os
import time
import httpx
from dataclasses import dataclass
from typing import Optional

# Ollama service URL (K8s internal)
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
TRIGGER_MODEL = os.getenv("TRIGGER_MODEL", "qwen2:1.5b")
TRIGGER_THRESHOLD = float(os.getenv("TRIGGER_THRESHOLD", "0.7"))


@dataclass
class TriggerDecision:
    """Result of trigger evaluation."""
    should_respond: bool
    confidence: float
    reason: str
    latency_ms: float


# System prompt for trigger decisions - uses few-shot examples for small models
TRIGGER_SYSTEM_PROMPT = """Decide if AI should speak. Answer YES or NO.

Example 1:
"Alice: The report looks good. Bob: Revenue is up."
Answer: NO (normal conversation)

Example 2:
"Alice: Hey AI, what do you think about this?"
Answer: YES (directly asked)

Example 3:
"Bob: I'm confused about the timeline. Alice: Me too."
Answer: NO (not asked for AI input)

Example 4:
"Alice: Let's ask the bot for help."
Answer: YES (mentioned bot)"""


class TriggerClient:
    """Client for making trigger decisions via Ollama."""

    def __init__(
        self,
        ollama_url: str = OLLAMA_URL,
        model: str = TRIGGER_MODEL,
        threshold: float = TRIGGER_THRESHOLD,
        timeout: float = 30.0,  # 30 second timeout for ARM64 with phi3:mini
    ):
        self.ollama_url = ollama_url.rstrip("/")
        self.model = model
        self.threshold = threshold
        self.timeout = timeout
        self._client = httpx.Client(timeout=timeout)

    def should_respond(self, transcript_buffer: str) -> TriggerDecision:
        """
        Evaluate if the bot should respond based on recent transcript.

        Args:
            transcript_buffer: Last 30-60 seconds of transcript text

        Returns:
            TriggerDecision with confidence score and recommendation
        """
        start = time.perf_counter()

        # Truncate very long transcripts (focus on recent context)
        if len(transcript_buffer) > 2000:
            transcript_buffer = transcript_buffer[-2000:]

        try:
            response = self._client.post(
                f"{self.ollama_url}/api/generate",
                json={
                    "model": self.model,
                    "prompt": f"Meeting transcript:\n{transcript_buffer}\n\nShould the AI speak? YES or NO:",
                    "system": TRIGGER_SYSTEM_PROMPT,
                    "stream": False,
                    "options": {
                        "num_predict": 5,  # Only need YES or NO
                        "temperature": 0.1,  # Deterministic
                    },
                },
            )
            response.raise_for_status()
            result = response.json()

            latency_ms = (time.perf_counter() - start) * 1000

            # Parse YES/NO from response
            raw_output = result.get("response", "").strip().upper()

            if "YES" in raw_output:
                confidence = 1.0
                should_respond = True
            elif "NO" in raw_output:
                confidence = 0.0
                should_respond = False
            else:
                # Fallback: try to parse as number
                try:
                    confidence = float(raw_output.split()[0])
                    confidence = max(0.0, min(1.0, confidence))
                    should_respond = confidence >= self.threshold
                except (ValueError, IndexError):
                    confidence = 0.0
                    should_respond = False

            return TriggerDecision(
                should_respond=should_respond,
                confidence=confidence,
                reason=f"LLM confidence: {confidence:.2f} (threshold: {self.threshold})",
                latency_ms=latency_ms,
            )

        except httpx.TimeoutException:
            latency_ms = (time.perf_counter() - start) * 1000
            return TriggerDecision(
                should_respond=False,
                confidence=0.0,
                reason=f"Timeout after {latency_ms:.0f}ms",
                latency_ms=latency_ms,
            )
        except Exception as e:
            latency_ms = (time.perf_counter() - start) * 1000
            return TriggerDecision(
                should_respond=False,
                confidence=0.0,
                reason=f"Error: {str(e)}",
                latency_ms=latency_ms,
            )

    def health_check(self) -> bool:
        """Check if Ollama is available and model is loaded."""
        try:
            response = self._client.get(f"{self.ollama_url}/api/tags")
            if response.status_code != 200:
                return False
            tags = response.json()
            models = [m["name"] for m in tags.get("models", [])]
            # Check if our model (or base name) is loaded
            return any(self.model.split(":")[0] in m for m in models)
        except Exception:
            return False

    def warm_up(self) -> float:
        """
        Send a dummy request to warm up the model.
        Returns latency in ms.
        """
        decision = self.should_respond("Hello, this is a test.")
        return decision.latency_ms

    def close(self):
        """Close the HTTP client."""
        self._client.close()


# Singleton for reuse across calls
_trigger_client: Optional[TriggerClient] = None


def get_trigger_client() -> TriggerClient:
    """Get or create the global trigger client."""
    global _trigger_client
    if _trigger_client is None:
        _trigger_client = TriggerClient()
    return _trigger_client


# --- Convenience functions ---

def should_respond(transcript_buffer: str) -> TriggerDecision:
    """Quick check if bot should respond to transcript."""
    return get_trigger_client().should_respond(transcript_buffer)


def warm_up() -> float:
    """Warm up the trigger model. Call at startup."""
    return get_trigger_client().warm_up()


# --- CLI for testing ---

if __name__ == "__main__":
    import sys

    print(f"Trigger Client - Model: {TRIGGER_MODEL}")
    print(f"Ollama URL: {OLLAMA_URL}")
    print(f"Threshold: {TRIGGER_THRESHOLD}")
    print()

    client = TriggerClient()

    # Health check
    print("Health check...", end=" ")
    if client.health_check():
        print("OK")
    else:
        print("FAILED - Is Ollama running with model loaded?")
        sys.exit(1)

    # Warm up
    print("Warming up model...", end=" ")
    warmup_ms = client.warm_up()
    print(f"{warmup_ms:.0f}ms")

    # Test cases
    test_cases = [
        ("Normal conversation - should NOT trigger",
         "Alice: So the quarterly report looks good.\nBob: Yeah, revenue is up 15%.\nAlice: Let's discuss marketing next."),

        ("Direct question - should trigger",
         "Alice: What about the API integration?\nBob: I'm not sure about the best approach.\nAlice: Hey AI, what do you think we should do here?"),

        ("Confusion detected - might trigger",
         "Alice: Wait, I thought we decided on microservices?\nBob: No, I think we said monolith first.\nAlice: I'm confused about what we agreed on."),

        ("Bot mentioned - should trigger",
         "Alice: Let's ask the meeting bot.\nBob: Good idea, it might have context from previous meetings."),
    ]

    print("\n" + "=" * 60)
    print("TEST CASES")
    print("=" * 60)

    for name, transcript in test_cases:
        decision = client.should_respond(transcript)
        status = "RESPOND" if decision.should_respond else "SILENT"
        print(f"\n{name}")
        print(f"  Result: {status} (confidence: {decision.confidence:.2f})")
        print(f"  Latency: {decision.latency_ms:.0f}ms")

    client.close()
