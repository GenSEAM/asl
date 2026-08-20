# One algorithm, three ways — HumanEval/111 `histogram`

Return each most-frequent letter of a space-separated string, with its count. Ties all included.

**All three pass the same 17 assertions** (`.venv/bin/python -m pytest bench/algo -q`).

---

## 1. AgentS source — hand-written

```lisp
(defun tally [(m (Map String Int64)) (w String)] -> (Map String Int64)
  :doc "Increment the count for one letter."
  (match (map-get m w)
    ((some n) (map-set m w (+ n 1)))
    ((none)   (map-set m w 1))))

(defun histogram [(text String)] -> (Map String Int64)
  :doc "Letters occurring most often, with their counts. Empty input yields an empty map."
  (let [(words (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split (string-trim text) " ")))
        (counts (fold tally (map-empty) words))]
    (match (list-max (map-values counts))
      ((none) (map-empty))
      ((some top)
       (map-from-pairs
         (filter (fn [(p (Pair String Int64))] -> Bool (= (.-second p) top))
                 (map-pairs counts)))))))
```

## 2. Python, generated from the above

```python
def tally(m, w):
    _t1 = _as.m_get(m, w)
    if _t1[0] == "some":
        n = _t1[1]
        _t2 = _as.m_set(m, w, (n + 1))
    elif _t1[0] == "none":
        _t2 = _as.m_set(m, w, 1)
    return _t2

def histogram(text):
    words = [_x for _x in text.strip().split(" ") if (lambda w: (not (len(w) == 0)))(_x)]
    counts = _as.fold(tally, {}, words)
    _t3 = _as.greatest([counts[_k] for _k in sorted(counts)])
    if _t3[0] == "none":
        _t4 = {}
    elif _t3[0] == "some":
        top = _t3[1]
        _t4 = _as.m_from([_x for _x in _as.m_pairs(counts) if (lambda p: _as.eq(p[2], top))(_x)])
    return _t4
```

## 3. Python, hand-written and idiomatic

```python
def histogram(text):
    words = [w for w in text.strip().split(" ") if w]
    counts = {}
    for w in words:
        counts[w] = counts.get(w, 0) + 1
    if not counts:
        return {}
    top = max(counts.values())
    return {k: v for k, v in counts.items() if v == top}
```

---

## Size

| Artifact | Bytes | ~Tokens | Code lines |
|---|---:|---:|---:|
| AgentS source | 894 | 223 | 19 |
| Generated Python | 643 | 160 | 19 |
| Idiomatic Python | 341 | 85 | 9 |

**AgentS costs 2.6× the tokens and 2.1× the lines of idiomatic Python for this task.**

That number matters more than it looks. The project's stated goal is more work per agent pass, and
tokens spent on syntax are tokens not spent on problem-solving. On this evidence the language is
currently moving that metric the wrong way. One task is not a measurement — but it is the first
real data point, and it points down.

Roughly half the excess is mandatory `:doc` strings and explicit parameter types. Those are
deliberate: they exist so an agent reading a module needs nothing but its surface. The trade is
real and should be judged, not assumed away.

## Critique of the generated Python

Reported qualitatively, never folded into a score (PCP `c-9af5`) — the language's designer cannot
be its scoring judge.

**Wrong, none found.** Output agrees with the hand-written version on every case.

**Bad, three:**

1. **Immediately-applied lambdas in comprehensions.** `[_x for _x in xs if (lambda w: ...)(_x)]`
   builds and calls a closure per element where the predicate could be inlined. Wasteful and ugly;
   the fix is to substitute the lambda body when the argument is used linearly.
2. **`map-values` evaluates its argument twice.** The lowering is
   `[{0}[_k] for _k in sorted({0})]`, so a non-trivial expression in that position would be
   recomputed. Correct only because the language is pure; still a latent performance trap, and it
   would be a correctness bug the moment effects exist.
3. **Temporaries are never reused.** `_t1`…`_t4` grow monotonically per function. Harmless, but it
   reads as machine output, which matters if a human ever has to debug the generated file.

**Notable, one:** every `match` becomes a flat `if`/`elif` chain with no fallback branch. If the
checker ever fails to prove exhaustiveness, the result is an `UnboundLocalError` far from the
cause — which is exactly the bug the smoke test caught earlier. The generated code should end with
an explicit unreachable-case raise, so a checker gap surfaces as a clear error rather than a
mystery.

## What this run establishes, and what it does not

**Establishes:** the pipeline is real end to end — an algorithm can be written in AgentS, lowered
to Python, and pass the original benchmark's assertions unmodified.

**Does not establish:** anything about whether an *agent* can write AgentS. This file was written
by hand. The premise under test in `EXPERIMENT.md` is untouched by it.
