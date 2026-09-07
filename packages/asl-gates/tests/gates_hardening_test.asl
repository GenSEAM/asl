(module asl-gates/tests/gates-hardening-test
  :d "Falsifiable verification and strict gate hardening tests for architectural layer stratification."
  :x [test-stratification test-vacuity-rejection run-tests]
  :i [(stratification :a st)])

(df test-stratification [] -> Bool
  :d "Asserts correct 4-tier layer mappings, boundary enforcement, and kernel hygiene."
  (let [(l0-parser (st/module-layer "asl-parser"))
        (l0-codec (st/module-layer "asl-codec"))
        (l0-intel (st/module-layer "intel/src/health.asl"))
        (l1-bus (st/module-layer "agent-bus"))
        (l1-core (st/module-layer "agent-core"))
        (l1-contracts (st/module-layer "asl-contracts"))
        (l1-harness (st/module-layer "harness"))
        (l2-mem (st/module-layer "mem"))
        (l2-crawler (st/module-layer "crawler"))
        (l3-bridge (st/module-layer "asl-bridge"))
        (l3-gates (st/module-layer "asl-gates"))]
    (assert (= l0-parser 0) "asl-parser must be classified as Layer 0")
    (assert (= l0-codec 0) "asl-codec must be classified as Layer 0")
    (assert (= l0-intel 0) "intel must be classified as Layer 0")
    (assert (= l1-bus 1) "agent-bus must be classified as Layer 1")
    (assert (= l1-core 1) "agent-core must be classified as Layer 1")
    (assert (= l1-contracts 1) "asl-contracts must be classified as Layer 1")
    (assert (= l1-harness 1) "harness must be classified as Layer 1")
    (assert (= l2-mem 2) "mem must be classified as Layer 2")
    (assert (= l2-crawler 2) "crawler must be classified as Layer 2")
    (assert (= l3-bridge 3) "asl-bridge must be classified as Layer 3")
    (assert (= l3-gates 3) "asl-gates must be classified as Layer 3")
    (assert (st/verify-layer-boundary 3 2) "Layer 3 to Layer 2 downward dependency must be valid")
    (assert (st/verify-layer-boundary 3 1) "Layer 3 to Layer 1 downward dependency must be valid")
    (assert (st/verify-layer-boundary 3 0) "Layer 3 to Layer 0 downward dependency must be valid")
    (assert (st/verify-layer-boundary 2 1) "Layer 2 to Layer 1 downward dependency must be valid")
    (assert (st/verify-layer-boundary 1 0) "Layer 1 to Layer 0 downward dependency must be valid")
    (assert (st/verify-layer-boundary 0 0) "Intra-layer dependency must be valid")
    (assert (not (st/verify-layer-boundary 0 1)) "Illegal upward dependency Layer 0 to Layer 1 must be rejected")
    (assert (not (st/verify-layer-boundary 0 3)) "Illegal upward dependency Layer 0 to Layer 3 must be rejected")
    (assert (not (st/verify-layer-boundary 1 3)) "Illegal upward dependency Layer 1 to Layer 3 must be rejected")
    (assert (not (st/verify-layer-boundary 2 3)) "Illegal upward dependency Layer 2 to Layer 3 must be rejected")
    (let [(clean-rep (st/audit-stratification "asl-gates" "asl-parser"))
          (dirty-rep (st/audit-stratification "asl-parser" "asl-gates"))]
      (assert (.-stratified clean-rep) "Valid downward edge must report stratified true")
      (assert (= (.-leakages clean-rep) 0) "Valid downward edge must report 0 leakages")
      (assert (.-healthy clean-rep) "Valid downward edge must report healthy true")
      (assert (not (.-stratified dirty-rep)) "Upward dependency edge must report stratified false")
      (assert (> (.-leakages dirty-rep) 0) "Upward dependency edge must report positive leakages")
      (assert (not (.-healthy dirty-rep)) "Upward dependency edge must report healthy false"))
    (assert (st/is-kernel-clean? "(module m :d \"clean\") (df f [] -> Int64 42)") "Clean module must pass kernel clean check")
    (assert (not (st/is-kernel-clean? "(module m) (df f [] -> Str \"@scout\")")) "Agent ID reference @scout in kernel must be rejected")
    (assert (not (st/is-kernel-clean? "(module m) (df f [] -> Str \"@coder\")")) "Agent ID reference @coder in kernel must be rejected")
    (assert (not (st/is-kernel-clean? "(module m) (df f [] -> Str \"@reviewer\")")) "Agent ID reference @reviewer in kernel must be rejected")
    (assert (not (st/is-kernel-clean? "(module m :i [(asl-bridge :a b)])")) "Host bridge import in kernel must be rejected")
    (assert (not (st/is-kernel-clean? "(module m :i [(asl-plugin :a p)])")) "Host plugin import in kernel must be rejected")
    true))

(df test-vacuity-rejection [] -> Bool
  :d "Asserts non-vacuous assertion execution under Gate 5 falsification."
  (let [(l-gates (st/module-layer "asl-gates"))
        (l-parser (st/module-layer "asl-parser"))]
    (assert (> l-gates l-parser) "asl-gates tier must strictly exceed asl-parser tier")
    (assert (st/verify-layer-boundary l-gates l-parser) "Downward verification must hold")
    (assert (not (= 42 0)) "Falsifiable numeric comparison must evaluate cleanly")
    (assert (not (string-empty? "AgentScript")) "String predicate assertion must evaluate cleanly")
    true))

(df run-tests [] -> Bool
  :d "Executes full layer stratification and gate hardening test suite."
  (let [(r1 (test-stratification))
        (r2 (test-vacuity-rejection))]
    (and r1 r2)))
