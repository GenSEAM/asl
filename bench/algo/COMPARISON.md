# One algorithm, three ways — HumanEval/111 `histogram`

Return each most-frequent letter of a space-separated string, with its count. Ties all included.

> **Historical record, not a current measurement.** The comparison below (sections 1 to 3 and
> everything after them) was made against an earlier AgentScript syntax — top-level `(df ...)`,
> `:d` docstrings, kebab-case builtins such as `map-get` — and a Python lowering and pytest
> harness (`.venv/bin/python -m pytest bench/algo -q`, 17 assertions) that are not in this
> repository. The section 1 source no longer loads: the stage-0 host rejects a top-level
> `(df ...)` with `ERR_UNSUPPORTED_TOPLEVEL`. Its sizes and ratios describe that version and
> cannot be reproduced from this tree.

## Current source and its status (2026-10-14)

The current versions are `asl/bench/algo/histogram.asl` and `asl/bench/algo/variants/tight.asl`
(the one `asl/bench/tasks/histogram.asn` names, with 7 cases).

- `asl/host/out/asl-host check` passes on both files.
- Run against the 7 cases of `histogram.asn`, both stop on the first case with
  `ERR_TYPE: .-second expects a record, got Variant`: they read a pair's second element as
  `p.second`. With `(pairSecond p)` in its place, all 7 cases pass. No runner in the tree
  executes those cases; this was checked with a scratch test outside the repository.
- Size: `histogram.asl` is 556 bytes in 7 lines, `tight.asl` 515 bytes in 4 lines. Their token
  counts have not been measured, so no token ratio against Python is claimed for current syntax.

---

## The original comparison (earlier syntax)


## 1. AgentScript source — hand-written, earlier syntax

<!-- not-agentscript: retired (df ...) syntax, kept as the historical input -->
```text
(df tally [(m (Map Str I64)) (w Str)] -> (Map Str I64)
  :d "Increment the count for one letter."
  (mt (map-get m w)
    ((some n) (map-set m w (+ n 1)))
    ((none)   (map-set m w 1))))

(df histogram [(text Str)] -> (Map Str I64)
  :d "Letters occurring most often, with their counts. Empty input yields an empty map."
  (let [(words (filter (fn [(w Str)] -> Bool (not (string-empty? w)))
                       (string-split (string-trim text) " ")))
        (counts (fold tally (map-empty) words))]
    (mt (list-max (map-values counts))
      ((none) (map-empty))
      ((some top)
       (map-from-pairs
         (filter (fn [(p (Pair Str I64))] -> Bool (= (.-second p) top))
                 (map-pairs counts)))))))
```

## 2. Python, generated from the above

```python
def tally(m, w):
    _t1 = _agentscript.m_get(m, w)
    if _t1[0] == "some":
        n = _t1[1]
        _t2 = _agentscript.m_set(m, w, (n + 1))
    elif _t1[0] == "none":
        _t2 = _agentscript.m_set(m, w, 1)
    return _t2

def histogram(text):
    words = [_x for _x in text.strip().split(" ") if (lambda w: (not (len(w) == 0)))(_x)]
    counts = _agentscript.fold(tally, {}, words)
    _t3 = _agentscript.greatest([counts[_k] for _k in sorted(counts)])
    if _t3[0] == "none":
        _t4 = {}
    elif _t3[0] == "some":
        top = _t3[1]
        _t4 = _agentscript.m_from([_x for _x in _agentscript.m_pairs(counts) if (lambda p: _agentscript.eq(p[2], top))(_x)])
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

## Size (earlier syntax, as recorded then)

| Artifact | Bytes | ~Tokens | Code lines |
|---|---:|---:|---:|
| AgentScript source | 894 | 223 | 19 |
| Generated Python | 643 | 160 | 19 |
| Idiomatic Python | 341 | 85 | 9 |

**In that version, AgentScript cost 2.6× the tokens and 2.1× the lines of idiomatic Python for this task.** The tokenizer and date of those counts were not recorded.

That number matters more than it looks. The project's stated goal is more work per agent pass, and
tokens spent on syntax are tokens not spent on problem-solving. On that evidence the language was
then moving that metric the wrong way. One task is not a measurement — but it was the first
real data point, and it pointed down. Whether the current syntax changes the ratio is unmeasured.

Roughly half the excess was mandatory `:d` docstrings and explicit parameter types. The current
syntax has no docstrings in source (the reader rejects `:d`; docs live as rows in a package
`doc.asn`) and keeps explicit parameter types; the trade should be judged, not assumed away.

## Critique of the generated Python (as it was then)

Reported qualitatively, never folded into a score — the language's designer cannot
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

## What that run established, and what it did not

**Established then:** an algorithm could be written in AgentScript, lowered to Python, and pass the
original benchmark's assertions unmodified. The lowering and harness used are not in this
repository, so this tree does not re-establish it.

**Did not establish:** anything about whether an *agent* can write AgentScript. The source was written
by hand. The premise under test in `asl/EXPERIMENT.md` is untouched by it.
