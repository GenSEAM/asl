(module asl-gates/tests/stratificationTest
  :d "Comprehensive unit tests for stratification functionality covering all layer mappings and edge cases."
  :x [testModuleLayer testVerifyBoundary testIsKernelClean testAuditStratification runTests]
  :i [(stratification :a st)])

(df testModuleLayer [] -> Bool
  :d "Verifies moduleLayer mapping for all 4 tiers and edge cases"
  (do
    (assert (= (st/moduleLayer "asl-parser") 0) "asl-parser L0")
    (assert (= (st/moduleLayer "asl-codec") 0) "asl-codec L0")
    (assert (= (st/moduleLayer "asl-contracts") 0) "asl-contracts L0")
    (assert (= (st/moduleLayer "asl-text") 0) "asl-text L0")

    (assert (= (st/moduleLayer "intel/src/health.asl") 1) "intel L1")
    (assert (= (st/moduleLayer "mem") 1) "mem L1")
    (assert (= (st/moduleLayer "engine") 1) "engine L1")
    (assert (= (st/moduleLayer "vfs") 1) "vfs L1")
    (assert (= (st/moduleLayer "vdom") 1) "vdom L1")

    (assert (= (st/moduleLayer "agent-bus") 2) "agent-bus L2")
    (assert (= (st/moduleLayer "agent-core") 2) "agent-core L2")
    (assert (= (st/moduleLayer "crawler") 2) "crawler L2")
    (assert (= (st/moduleLayer "router") 2) "router L2")

    (assert (= (st/moduleLayer "harness") 3) "harness L3")
    (assert (= (st/moduleLayer "asl-gates") 3) "asl-gates L3")
    (assert (= (st/moduleLayer "asl-bridge") 3) "asl-bridge L3")
    (assert (= (st/moduleLayer "asl-cli") 3) "asl-cli L3")
    (assert (= (st/moduleLayer "bench") 3) "bench L3")
    (assert (= (st/moduleLayer "tools") 3) "tools L3")
    (assert (= (st/moduleLayer "asl-plugin") 3) "asl-plugin L3")

    (assert (= (st/moduleLayer "  asl-parser  ") 0) "whitespace trimming")
    (assert (= (st/moduleLayer "unknown-pkg") 0) "unknown defaults to L0")
    (assert (= (st/moduleLayer "dummy") 0) "dummy defaults to L0")
    (assert (= (st/moduleLayer "my-dummy-parser") 0) "dummy substring does not pollute layer")
    true))

(df testVerifyBoundary [] -> Bool
  :d "Verifies verifyLayerBoundary for all direction combinations"
  (do
    (assert (st/verifyLayerBoundary 3 0) "L3->L0 valid")
    (assert (st/verifyLayerBoundary 3 1) "L3->L1 valid")
    (assert (st/verifyLayerBoundary 3 2) "L3->L2 valid")
    (assert (st/verifyLayerBoundary 3 3) "L3->L3 intra valid")
    (assert (st/verifyLayerBoundary 2 1) "L2->L1 valid")
    (assert (st/verifyLayerBoundary 2 0) "L2->L0 valid")
    (assert (st/verifyLayerBoundary 1 0) "L1->L0 valid")
    (assert (st/verifyLayerBoundary 0 0) "L0->L0 intra valid")
    (assert (not (st/verifyLayerBoundary 0 1)) "L0->L1 upward rejected")
    (assert (not (st/verifyLayerBoundary 0 3)) "L0->L3 upward rejected")
    (assert (not (st/verifyLayerBoundary 1 2)) "L1->L2 upward rejected")
    (assert (not (st/verifyLayerBoundary 1 3)) "L1->L3 upward rejected")
    (assert (not (st/verifyLayerBoundary 2 3)) "L2->L3 upward rejected")
    true))

(df testIsKernelClean [] -> Bool
  :d "Verifies isKernelClean? for clean and contaminated sources"
  (do
    (assert (st/isKernelClean? "(module m :d \"clean\") (df f [] -> Int64 42)") "clean passes")
    (assert (st/isKernelClean? "(df pure-fn [(x Str)] -> Str x)") "pure fn passes")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@scout\")")) "@scout rejected")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@coder\")")) "@coder rejected")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@reviewer\")")) "@reviewer rejected")
    (assert (not (st/isKernelClean? "(module m :i [(asl-bridge :a b)])")) "bridge import rejected")
    (assert (not (st/isKernelClean? "(module m :i [(asl-plugin :a p)])")) "plugin import rejected")
    (assert (st/isKernelClean? "") "empty passes")
    true))

(df testAuditStratification [] -> Bool
  :d "Verifies auditStratification report for valid and invalid edges"
  (let [(validReport (st/auditStratification "asl-gates" "asl-parser"))
        (invalidReport (st/auditStratification "asl-parser" "asl-gates"))
        (intraReport (st/auditStratification "asl-parser" "asl-codec"))]
    (do
      (assert (.-stratified validReport) "valid downward stratified")
      (assert (= (.-leakages validReport) 0) "valid 0 leakages")
      (assert (.-healthy validReport) "valid healthy")
      (assert (= (.-layers validReport) 4) "valid 4 layers")

      (assert (not (.-stratified invalidReport)) "invalid upward not stratified")
      (assert (> (.-leakages invalidReport) 0) "invalid positive leakages")
      (assert (not (.-healthy invalidReport)) "invalid not healthy")

      (assert (.-stratified intraReport) "intra-layer stratified")
      (assert (= (.-leakages intraReport) 0) "intra-layer 0 leakages")
      (assert (.-healthy intraReport) "intra-layer healthy")
      true)))

(df runTests [] -> Bool
  :d "Master test runner for stratification."
  (do
    (assert (testModuleLayer) "testModuleLayer")
    (assert (testVerifyBoundary) "testVerifyBoundary")
    (assert (testIsKernelClean) "testIsKernelClean")
    (assert (testAuditStratification) "testAuditStratification")
    true))
