# @genseam/asl-intel

Native code intelligence and symbol graph engine, delivering $\ge 60\%$ context token reduction via dense ASN S-expression framing and $O(1)$ memory graph queries.

## Self-Describing Usage
```asn
;; Inspect dense AST outline without implementation body bloat
(:intel-outline
  :do "./bin/asl intel outline src/main.asl"
  :summary "Extract symbol signatures and docstrings within token budget")

;; Analyze call graph and blast radius
(:intel-callers
  :do "./bin/asl intel callers mySymbol"
  :summary "Resolve inbound callers and downstream impact graph")

;; Execute intel test suite
(:test-intel
  :do "./bin/asl test asl/packages/asl-intel/tests/codeIntelTest.asl"
  :summary "Verify graph-horizon paging, symbol extraction, and blast radius calculation")
```
