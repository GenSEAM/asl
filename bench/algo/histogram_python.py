"""Idiomatic hand-written Python. The comparison baseline."""


def histogram(text):
    words = [w for w in text.strip().split(" ") if w]
    counts = {}
    for w in words:
        counts[w] = counts.get(w, 0) + 1
    if not counts:
        return {}
    top = max(counts.values())
    return {k: v for k, v in counts.items() if v == top}
