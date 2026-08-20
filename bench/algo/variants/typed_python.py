"""Python with the type safety AgentS provides. The fair comparison."""
from typing import Dict, List


def histogram(text: str) -> Dict[str, int]:
    words: List[str] = [w for w in text.strip().split(" ") if w]
    counts: Dict[str, int] = {}
    for w in words:
        counts[w] = counts.get(w, 0) + 1
    if not counts:
        return {}
    top: int = max(counts.values())
    return {k: v for k, v in counts.items() if v == top}
