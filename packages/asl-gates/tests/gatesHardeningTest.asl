(module asl-gates/tests/gatesHardeningTest
  :d "Falsifiable verification and strict gate hardening tests for architectural layer stratification."
  :x [testStratification testVacuityRejection runTests]
  :i [(stratification :a st)
      (gates :a g)
      (shebangAudit :a sa)
      (manifestGate :a mg)
      (siteClaims :a sc)])

(df testStratification [] -> Bool
  :d "Asserts correct 4-tier layer mappings, boundary enforcement, and kernel hygiene."
  (let [(l0Parser (st/moduleLayer "asl-parser"))
        (l0Codec (st/moduleLayer "asl-codec"))
        (l1Intel (st/moduleLayer "intel/src/health.asl"))
        (l2Bus (st/moduleLayer "agent-bus"))
        (l2Core (st/moduleLayer "agent-core"))
        (l0Contracts (st/moduleLayer "asl-contracts"))
        (l3Harness (st/moduleLayer "harness"))
        (l1Mem (st/moduleLayer "mem"))
        (l2Crawler (st/moduleLayer "crawler"))
        (l3Bridge (st/moduleLayer "asl-bridge"))
        (l3Gates (st/moduleLayer "asl-gates"))]
    (assert (= l0Parser 0) "asl-parser must be classified as Layer 0")
    (assert (= l0Codec 0) "asl-codec must be classified as Layer 0")
    (assert (= l1Intel 1) "intel must be classified as Layer 1")
    (assert (= l2Bus 2) "agent-bus must be classified as Layer 2")
    (assert (= l2Core 2) "agent-core must be classified as Layer 2")
    (assert (= l0Contracts 0) "asl-contracts must be classified as Layer 0")
    (assert (= l3Harness 3) "harness must be classified as Layer 3")
    (assert (= l1Mem 1) "mem must be classified as Layer 1")
    (assert (= l2Crawler 2) "crawler must be classified as Layer 2")
    (assert (= l3Bridge 3) "asl-bridge must be classified as Layer 3")
    (assert (= l3Gates 3) "asl-gates must be classified as Layer 3")
    (assert (st/verifyLayerBoundary 3 2) "Layer 3 to Layer 2 downward dependency must be valid")
    (assert (st/verifyLayerBoundary 3 1) "Layer 3 to Layer 1 downward dependency must be valid")
    (assert (st/verifyLayerBoundary 3 0) "Layer 3 to Layer 0 downward dependency must be valid")
    (assert (st/verifyLayerBoundary 2 1) "Layer 2 to Layer 1 downward dependency must be valid")
    (assert (st/verifyLayerBoundary 1 0) "Layer 1 to Layer 0 downward dependency must be valid")
    (assert (st/verifyLayerBoundary 0 0) "Intra-layer dependency must be valid")
    (assert (not (st/verifyLayerBoundary 0 1)) "Illegal upward dependency Layer 0 to Layer 1 must be rejected")
    (assert (not (st/verifyLayerBoundary 0 3)) "Illegal upward dependency Layer 0 to Layer 3 must be rejected")
    (assert (not (st/verifyLayerBoundary 1 3)) "Illegal upward dependency Layer 1 to Layer 3 must be rejected")
    (assert (not (st/verifyLayerBoundary 2 3)) "Illegal upward dependency Layer 2 to Layer 3 must be rejected")
    (let [(cleanRep (st/auditStratification "asl-gates" "asl-parser"))
          (dirtyRep (st/auditStratification "asl-parser" "asl-gates"))]
      (assert (.-stratified cleanRep) "Valid downward edge must report stratified true")
      (assert (= (.-leakages cleanRep) 0) "Valid downward edge must report 0 leakages")
      (assert (.-healthy cleanRep) "Valid downward edge must report healthy true")
      (assert (not (.-stratified dirtyRep)) "Upward dependency edge must report stratified false")
      (assert (> (.-leakages dirtyRep) 0) "Upward dependency edge must report positive leakages")
      (assert (not (.-healthy dirtyRep)) "Upward dependency edge must report healthy false"))
    (assert (st/isKernelClean? "(module m :d \"clean\") (df f [] -> Int64 42)") "Clean module must pass kernel clean check")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@scout\")")) "Agent ID reference @scout in kernel must be rejected")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@coder\")")) "Agent ID reference @coder in kernel must be rejected")
    (assert (not (st/isKernelClean? "(module m) (df f [] -> Str \"@reviewer\")")) "Agent ID reference @reviewer in kernel must be rejected")
    (assert (not (st/isKernelClean? "(module m :i [(asl-bridge :a b)])")) "Host bridge import in kernel must be rejected")
    (assert (not (st/isKernelClean? "(module m :i [(asl-plugin :a p)])")) "Host plugin import in kernel must be rejected")
    true))

(df testVacuityRejection [] -> Bool
  :d "Asserts non-vacuous assertion execution and strict negative bounds across gates."
  (let [(lGates (st/moduleLayer "asl-gates"))
        (lParser (st/moduleLayer "asl-parser"))
        (foreignPaths (list "src/main.asl" "src/helper.py" "src/util.ts"))
        (foreignDetected (g/findForeignFilesInPaths foreignPaths))
        (elfHeader "\u007fELF\u0002\u0001\u0001\u0000")
        (peHeader "MZ\u0090\u0000\u0003\u0000")
        (machoHeader "\ucffa\u00ed\u00fe")
        (badMfEntry (mg/makeManifestRecord "manifest.asn" "pkg" "0.1.0" ""))
        (badMfSigil (mg/makeManifestRecord "manifest.asn" "@pkg" "0.1.0" "src/main.asl"))
        (badMfVer (mg/makeManifestRecord "manifest.asn" "pkg" "" "src/main.asl"))
        (unbalanced "(df foo [] -> I64 (+ 1 2")
        (ungroundedClaim (sc/auditClaim "99.9% theoretical" (sc/standardClaims)))]
    (assert (> lGates lParser) "asl-gates tier must strictly exceed asl-parser tier")
    (assert (st/verifyLayerBoundary lGates lParser) "Downward verification must hold")
    
    (assert (= (list-length foreignDetected) 2) "Gate 4 foreign detector must detect exactly 2 foreign files")
    (assert (list-contains? foreignDetected "src/helper.py") "helper.py must be detected as foreign")
    (assert (list-contains? foreignDetected "src/util.ts") "util.ts must be detected as foreign")
    (refute (list-contains? foreignDetected "src/main.asl") "main.asl must not be flagged as foreign")
    
    (assert (sa/isBinaryBlob elfHeader) "ELF magic must be rejected as binary blob")
    (assert (sa/isBinaryBlob peHeader) "PE magic must be rejected as binary blob")
    (assert (sa/isBinaryBlob machoHeader) "Mach-O magic must be rejected as binary blob")
    (refute (sa/isBinaryBlob "(module m)") "Pure ASL code must not be flagged as binary blob")
    
    (assert (not (mg/verifyManifestRecord badMfEntry)) "Manifest with missing entry must be rejected")
    (assert (not (mg/verifyManifestRecord badMfSigil)) "Manifest with @ sigil must be rejected")
    (assert (not (mg/verifyManifestRecord badMfVer)) "Manifest with missing version must be rejected")
    (refute (mg/verifyManifestRecord badMfEntry) "Refute validity of missing entry manifest")
    (refute (mg/verifyManifestRecord badMfSigil) "Refute validity of @ sigil manifest")
    
    (assert (not (g/verifyBalance unbalanced)) "Unbalanced S-expression must fail verifyBalance")
    (refute (g/verifyBalance unbalanced) "Refute balance for unclosed delimiter")
    
    (assert (not (.-grounded ungroundedClaim)) "Ungrounded theoretical metric must fail auditClaim")
    (refute (.-grounded ungroundedClaim) "Refute grounding for fabricated metric")
    true))

(df runTests [] -> Bool
  :d "Executes full layer stratification and gate hardening test suite."
  (and (testStratification)
       (testVacuityRejection)))
