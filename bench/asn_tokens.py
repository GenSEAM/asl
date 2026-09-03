#!/usr/bin/env python3
"""Token counts for every number docs/ASN_SPEC.md and the two ASN guides state.

Both guides used to assert -82%, -80%, -75%, -70%, -60%, -50%, -45% and -99%,
plus a scorecard of generation latencies, with no measurement behind any of
them. DESIGN.md §5 makes that a false claim rather than a design choice: every
number on a published surface must come from a command someone can re-run. The
figures that survived are the ones below; the rest were deleted.

Two of them decided a specification question rather than illustrating one.
`:dflt` costs exactly what `:default` costs, which is why docs/ASN_SPEC.md §13
keeps `:default` and needs no change to prelude/prelude.json. `:in-stock` costs
exactly what `"in-stock"` costs, which is why §3.2 can forbid a keyword in a
schema-bound column without charging anyone for it.

  bench/asn_tokens.py            print the table
  bench/asn_tokens.py --check    fail if it no longer matches the lock
  bench/asn_tokens.py --write    record a new figure, in the commit that earns it

Every ASN sample below is parsed with grammar/asn.lark before it is counted. A
saving measured against a payload that does not parse is a saving against
nothing, which is how the -82% row came to compare JSON with a form no reader
accepted.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "grammar"))

LOCK = Path(__file__).with_name("asn_tokens.lock")
ENCODING = "cl100k_base"

ROWS = [
    (1, "SSD-1TB", 89.99, "in-stock"),
    (2, "RAM-32GB", 129.50, "in-stock"),
    (3, "GPU-4070", 549.00, "low-stock"),
]

# 100 rows, deterministic, so the scorecard is reproducible rather than typed.
BULK = [(i, f"SKU-{i:04d}", round(10.0 + i * 1.25, 2),
         "in-stock" if i % 3 else "low-stock") for i in range(1, 101)]


def json_records(rows) -> str:
    return json.dumps([{"id": i, "sku": s, "price": p, "status": st}
                       for i, s, p, st in rows], indent=2)


def asn_records(rows) -> str:
    """One record per row, keys repeated. The middle column of the scorecard."""
    body = " ".join(f'(Item :id {i} :sku "{s}" :price {p} :status "{st}")'
                    for i, s, p, st in rows)
    return f"[{body}]"


def asn_rows(rows) -> str:
    """Schema-grouped rows: the constructor once, then bare positional vectors."""
    body = " ".join(f'[{i} "{s}" {p} "{st}"]' for i, s, p, st in rows)
    return f"(Item {body})"


def asn_table(rows) -> str:
    body = " ".join(f'[{i} "{s}" {p} "{st}"]' for i, s, p, st in rows)
    return f"([:id :sku :price :status] [{body}])"


EVENTS_FLAT = (
    '[(:ts 1714829100 :url "https://api.internal.invalid/v2/telemetry/nodes" '
    ':ctx {:region :us-east :env :prod} :status :ok) '
    '(:ts 1714829105 :url "https://api.internal.invalid/v2/telemetry/nodes" '
    ':ctx {:region :us-east :env :prod} :status :ok) '
    '(:ts 1714829110 :url "https://api.internal.invalid/v2/telemetry/nodes" '
    ':ctx {:region :us-east :env :prod} :status :warn)]'
)

EVENTS_POOLED = (
    '(:pool ["https://api.internal.invalid/v2/telemetry/nodes" '
    '{:region :us-east :env :prod}] '
    ':data [(:ts 1714829100 :url (:ref 0) :ctx (:ref 1) :status :ok) '
    '(:ts 1714829105 :url (:ref 0) :ctx (:ref 1) :status :ok) '
    '(:ts 1714829110 :url (:ref 0) :ctx (:ref 1) :status :warn)])'
)

ROWS_REPEATED = (
    '(Order [1 "SSD-1TB" 89.99 "USD" :prod 1042] '
    '[2 "RAM-32GB" 129.50 "USD" :prod 1042] '
    '[3 "GPU-4070" 549.00 "USD" :prod 1042])'
)

ROWS_ENVELOPED = (
    '(:curr "USD" :env :prod :tenant 1042 '
    ':data (Order [1 "SSD-1TB" 89.99] [2 "RAM-32GB" 129.50] [3 "GPU-4070" 549.00]))'
)

# name -> (text, is_asn). A pair whose two members answer one question sits
# together, so a reader of the lock can see what is being compared.
SAMPLES: dict[str, tuple[str, bool]] = {
    "json-3-records": (json_records(ROWS), False),
    "asn-3-records": (asn_records(ROWS), True),
    "asn-3-rows": (asn_rows(ROWS), True),
    "asn-3-table": (asn_table(ROWS), True),

    "json-100-records": (json_records(BULK), False),
    "asn-100-records": (asn_records(BULK), True),
    "asn-100-rows": (asn_rows(BULK), True),

    "json-string-vector": ('["alpha", "beta", "gamma", "delta"]', False),
    "asn-keyword-vector": ("[:alpha :beta :gamma :delta]", True),

    "json-matrix": ("[[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]", False),
    "asn-matrix": ("[[1.0 0.0 0.0] [0.0 1.0 0.0] [0.0 0.0 1.0]]", True),

    "asn-events-flat": (EVENTS_FLAT, True),
    "asn-events-pooled": (EVENTS_POOLED, True),

    "asn-rows-repeated": (ROWS_REPEATED, True),
    "asn-rows-enveloped": (ROWS_ENVELOPED, True),

    "column-keyword": (" :in-stock", False),
    "column-string": (' "in-stock"', False),
}

# The abbreviation table docs/CONTEXT_ECONOMY_GUIDELINES.md §2 publishes, long
# spelling against short. It claimed every short form was one token and every
# long one two to four.
#
# Each pair is counted TWICE, and the difference is the point. A keyword measured
# on its own is not the keyword a document contains: in real text it follows a
# space, and BPE merges that space into the token. Nine of these twenty verdicts
# change between the two measurements, so an isolated count is not evidence about
# a payload — it was the flaw in the first version of this file, and it is kept
# visible here rather than quietly corrected. The published verdict is the
# contextual one.
DICTIONARY = [
    (":default", ":dflt"), (":config", ":cfg"), (":context", ":ctx"),
    (":request", ":req"), (":response", ":resp"), (":argument", ":arg"),
    (":message", ":msg"), (":error", ":err"), (":function", ":fn"),
    (":length", ":len"), (":index", ":idx"), (":authentication", ":auth"),
    (":timestamp", ":ts"), (":payload", ":data"),
    (":timeout-milliseconds", ":t-out"), (":working-directory", ":cwd"),
    (":field", ":f"), (":case", ":c"), (":doc", ":d"), (":value", ":v"),
]

for _long, _short in DICTIONARY:
    SAMPLES[f"bare{_long}"] = (_long, False)
    SAMPLES[f"bare{_short}"] = (_short, False)
    SAMPLES[f"ctx{_long}"] = (" " + _long, False)
    SAMPLES[f"ctx{_short}"] = (" " + _short, False)

# Each pair is (baseline, candidate) and yields one published percentage.
SAVINGS = {
    "rows-vs-json-3": ("json-3-records", "asn-3-rows"),
    "rows-vs-json-100": ("json-100-records", "asn-100-rows"),
    "rows-vs-asn-records-100": ("asn-100-records", "asn-100-rows"),
    "asn-records-vs-json-100": ("json-100-records", "asn-100-records"),
    "table-vs-json-3": ("json-3-records", "asn-3-table"),
    "keyword-vector-vs-json": ("json-string-vector", "asn-keyword-vector"),
    "matrix-vs-json": ("json-matrix", "asn-matrix"),
    "pool-vs-flat": ("asn-events-flat", "asn-events-pooled"),
    "envelope-vs-repeated": ("asn-rows-repeated", "asn-rows-enveloped"),
    # Negative: writing the string COSTS this much against the keyword the rule
    # forbids. docs/ASN_SPEC.md section 3.2 keeps the rule anyway, on type grounds.
    "string-column-against-keyword": ("column-keyword", "column-string"),
}


def verdict(long_n: int, short_n: int) -> str:
    return "win" if short_n < long_n else "tie" if short_n == long_n else "loss"


def dictionary_verdicts(got: dict[str, int]) -> dict[str, str]:
    """Per row, as the keyword appears in a document: after a space.

    A row whose isolated verdict differs is marked, because that difference is
    the reason the published table changed and a reader should be able to see it
    without re-deriving it.
    """
    out = {}
    for long, short in DICTIONARY:
        ctx = verdict(got[f"ctx{long}"], got[f"ctx{short}"])
        bare = verdict(got[f"bare{long}"], got[f"bare{short}"])
        out[f"{long} -> {short}"] = ctx if ctx == bare else f"{ctx} (isolated: {bare})"
    return out


def check_asn_parses() -> list[str]:
    """Every ASN sample must be a document grammar/asn.lark accepts."""
    from validate_asn import accepts
    bad = []
    for name, (text, is_asn) in SAMPLES.items():
        if not is_asn:
            continue
        ok, why = accepts(text)
        if not ok:
            bad.append(f"{name}: {why}")
    return bad


def counts() -> dict[str, int]:
    import tiktoken
    enc = tiktoken.get_encoding(ENCODING)
    return {name: len(enc.encode(text)) for name, (text, _) in SAMPLES.items()}


def record() -> dict:
    got = counts()
    savings = {name: round(1 - got[cand] / got[base], 4)
               for name, (base, cand) in SAVINGS.items()}
    return {"encoding": ENCODING, "counts": got, "savings": savings,
            "dictionary": dictionary_verdicts(got)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    bad = check_asn_parses()
    if bad:
        print("ASN samples that do not parse under grammar/asn.lark:", file=sys.stderr)
        for b in bad:
            print(f"  {b}", file=sys.stderr)
        return 1

    try:
        got = record()
    except ImportError:
        print(f"tiktoken is not installed; cannot count with {ENCODING}", file=sys.stderr)
        return 2

    if args.write or not LOCK.exists():
        LOCK.write_text(json.dumps(got, indent=2) + "\n")
        print(f"wrote {LOCK}")
        return 0

    want = json.loads(LOCK.read_text())
    if args.check:
        if want != got:
            print("ASN token counts moved:", file=sys.stderr)
            print(f"  lock: {json.dumps(want, indent=2)}", file=sys.stderr)
            print(f"  now:  {json.dumps(got, indent=2)}", file=sys.stderr)
            print("Re-run with --write in the commit that earns the change.",
                  file=sys.stderr)
            return 1
        print(f"OK: {len(got['counts'])} samples, {len(got['savings'])} published "
              f"percentages, {len(got['dictionary'])} abbreviation rows ({ENCODING})")
        return 0

    width = max(len(k) for k in got["counts"])
    print(f"{ENCODING} token counts\n")
    for name, n in got["counts"].items():
        print(f"  {name.ljust(width)}  {n:5d}")
    print("\npublished savings")
    for name, (base, cand) in SAVINGS.items():
        pct = got["savings"][name] * 100
        print(f"  {name.ljust(width)}  {pct:6.1f}%   "
              f"({got['counts'][base]} -> {got['counts'][cand]})")
    print("\nabbreviation dictionary")
    for row, verdict in got["dictionary"].items():
        print(f"  {row.ljust(width)}  {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
