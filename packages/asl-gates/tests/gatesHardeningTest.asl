(module asl-gates/tests/gatesHardeningTest :x [testStratification testVacuityRejection runTests] :i [(stratification :a st) (gates :a g) (shebangAudit :a sa) (manifestGate :a mg) (siteClaims :a sc) (gateRunner :a rn)])

fn testStratification -> Bool
  (let [(l0Parser (st/moduleLayer "asl-parser")) (l0Codec (st/moduleLayer "asl-transpile")) (l1Intel (st/moduleLayer "intel/src/health.asl")) (l2Bus (st/moduleLayer "agent-bus")) (l2Core (st/moduleLayer "agent-core")) (l0Contracts (st/moduleLayer "asl-contracts")) (l3Harness (st/moduleLayer "harness")) (l1Mem (st/moduleLayer "mem")) (l2Crawler (st/moduleLayer "crawler")) (l3Bridge (st/moduleLayer "asl-bridge")) (l3Gates (st/moduleLayer "asl-gates"))] (assert (= l0Parser 0) "asl-parser must be classified as Layer 0") (assert (= l0Codec 0) "asl-transpile must be classified as Layer 0") (assert (= l1Intel 1) "intel must be classified as Layer 1") (assert (= l2Bus 2) "agent-bus must be classified as Layer 2") (assert (= l2Core 2) "agent-core must be classified as Layer 2") (assert (= l0Contracts 0) "asl-contracts must be classified as Layer 0") (assert (= l3Harness 3) "harness must be classified as Layer 3") (assert (= l1Mem 1) "mem must be classified as Layer 1") (assert (= l2Crawler 2) "crawler must be classified as Layer 2") (assert (= l3Bridge 3) "asl-bridge must be classified as Layer 3") (assert (= l3Gates 3) "asl-gates must be classified as Layer 3") (assert (st/verifyLayerBoundary 3 2) "Layer 3 to Layer 2 downward dependency must be valid") (assert (st/verifyLayerBoundary 3 1) "Layer 3 to Layer 1 downward dependency must be valid") (assert (st/verifyLayerBoundary 3 0) "Layer 3 to Layer 0 downward dependency must be valid") (assert (st/verifyLayerBoundary 2 1) "Layer 2 to Layer 1 downward dependency must be valid") (assert (st/verifyLayerBoundary 1 0) "Layer 1 to Layer 0 downward dependency must be valid") (assert (st/verifyLayerBoundary 0 0) "Intra-layer dependency must be valid") (assert (not (st/verifyLayerBoundary 0 1)) "Illegal upward dependency Layer 0 to Layer 1 must be rejected") (assert (not (st/verifyLayerBoundary 0 3)) "Illegal upward dependency Layer 0 to Layer 3 must be rejected") (assert (not (st/verifyLayerBoundary 1 3)) "Illegal upward dependency Layer 1 to Layer 3 must be rejected") (assert (not (st/verifyLayerBoundary 2 3)) "Illegal upward dependency Layer 2 to Layer 3 must be rejected") (let [(cleanRep (st/auditStratification "asl-gates" "asl-parser")) (dirtyRep (st/auditStratification "asl-parser" "asl-gates"))] (assert cleanRep.stratified "Valid downward edge must report stratified true") (assert (= cleanRep.leakages 0) "Valid downward edge must report 0 leakages") (assert cleanRep.healthy "Valid downward edge must report healthy true") (assert (not dirtyRep.stratified) "Upward dependency edge must report stratified false") (assert (> dirtyRep.leakages 0) "Upward dependency edge must report positive leakages") (assert (not dirtyRep.healthy) "Upward dependency edge must report healthy false")) (assert (st/isKernelClean? "(module m) (fn f [] -> Int64 42)") "Clean module must pass kernel clean check") (assert (not (st/isKernelClean? "(module m) (fn f [] -> Str \"@scout\")")) "Agent ID reference @scout in kernel must be rejected") (assert (not (st/isKernelClean? "(module m) (fn f [] -> Str \"@coder\")")) "Agent ID reference @coder in kernel must be rejected") (assert (not (st/isKernelClean? "(module m) (fn f [] -> Str \"@reviewer\")")) "Agent ID reference @reviewer in kernel must be rejected") (assert (not (st/isKernelClean? "(module m :i [(asl-bridge :a b)])")) "Host bridge import in kernel must be rejected") (assert (not (st/isKernelClean? "(module m :i [(asl-plugin :a p)])")) "Host plugin import in kernel must be rejected") true)

fn testVacuityRejection -> Bool
  (let [(lGates (st/moduleLayer "asl-gates")) (lParser (st/moduleLayer "asl-parser")) (foreignPaths (list "src/main.asl" "src/helper.py" "src/util.ts")) (foreignDetected (g/findForeignFilesInPaths foreignPaths)) (elfHeader "\u007fELF\u0002\u0001\u0001\u0000") (peHeader "MZ\u0090\u0000\u0003\u0000") (machoHeader "\xcf\xfa\xed\xfe") (badMfEntry (mg/makeManifestRecord "manifest.asn" "pkg" "0.1.0" "")) (badMfSigil (mg/makeManifestRecord "manifest.asn" "@pkg" "0.1.0" "src/main.asl")) (badMfVer (mg/makeManifestRecord "manifest.asn" "pkg" "" "src/main.asl")) (unbalanced "(fn foo [] -> I64 (+ 1 2") (ungroundedClaim (sc/auditClaim "99.9% theoretical" (sc/standardClaims)))] (assert (> lGates lParser) "asl-gates tier must strictly exceed asl-parser tier") (assert (st/verifyLayerBoundary lGates lParser) "Downward verification must hold") (assert (= (listLength foreignDetected) 2) "Gate 4 foreign detector must detect exactly 2 foreign files") (assert (listContains? foreignDetected "src/helper.py") "helper.py must be detected as foreign") (assert (listContains? foreignDetected "src/util.ts") "util.ts must be detected as foreign") (refute (listContains? foreignDetected "src/main.asl") "main.asl must not be flagged as foreign") (assert (sa/isBinaryBlob elfHeader) "ELF magic must be rejected as binary blob") (assert (sa/isBinaryBlob peHeader) "PE magic must be rejected as binary blob") (assert (sa/isBinaryBlob machoHeader) "Mach-O magic must be rejected as binary blob") (refute (sa/isBinaryBlob "(module m)") "Pure ASL code must not be flagged as binary blob") (assert (not (mg/verifyManifestRecord badMfEntry)) "Manifest with missing entry must be rejected") (assert (not (mg/verifyManifestRecord badMfSigil)) "Manifest with @ sigil must be rejected") (assert (not (mg/verifyManifestRecord badMfVer)) "Manifest with missing version must be rejected") (refute (mg/verifyManifestRecord badMfEntry) "Refute validity of missing entry manifest") (refute (mg/verifyManifestRecord badMfSigil) "Refute validity of @ sigil manifest") (assert (not (g/verifyBalance unbalanced)) "Unbalanced S-expression must fail verifyBalance") (refute (g/verifyBalance unbalanced) "Refute balance for unclosed delimiter") (assert (not ungroundedClaim.grounded) "Ungrounded theoretical metric must fail auditClaim") (refute ungroundedClaim.grounded "Refute grounding for fabricated metric") true)

fn ! freshDir! tag: Str -> Str
  (let [(dir (str "/tmp/aslGatesHardening." tag "." (stringFromInt64 (nowNs))))] (do (assert (ok? (dirCreate dir)) (str "fixture dir created: " dir)) dir))

fn errNames? res: (Result Unit Str) needle: Str -> Bool
  (mt res ((ok _) false) ((err e) (stringContains? e needle)))

fn ! testCommandLines -> Bool
  (let [(missing (str "/tmp/aslGatesHardening.missing." (stringFromInt64 (nowNs)))) (failCmd (str "find " missing " -type f")) (failed (rn/commandLines failCmd (processRun failCmd))) (okCmd "printf 'b\\n\\na\\n'") (listed (rn/commandLines okCmd (processRun okCmd)))]
    (do (mt failed
          ((ok lines) (assert false (str "a failing find must not list as ok: " (stringJoin lines ","))))
          ((err e) (do (assert (stringContains? e failCmd) (str "the error names the command: " e)) (assert (stringContains? e "No such file") (str "the error carries stderr: " e)))))
        (mt listed
          ((ok lines) (assert (= lines (list "a" "b")) (str "lines are sorted and blank lines dropped: " (stringJoin lines ","))))
          ((err e) (assert false (str "a zero-exit command must list: " e))))
        true))

fn ! testCheckPaths -> Bool
  (let [(passAll (fn [(p Str)] -> (Result Unit Str) (ok ()))) (failB (fn [(p Str)] -> (Result Unit Str) (if (= p "b") (err "b: broken") (ok ())))) (fromErr (rn/checkPaths "things" (err "listing exploded") passAll)) (fromEmpty (rn/checkPaths "things" (ok (list)) passAll)) (fromBad (rn/checkPaths "things" (ok (list "a" "b" "c")) failB)) (fromGood (rn/checkPaths "things" (ok (list "a" "c")) failB))]
    (do (mt fromErr ((ok _) (assert false "a listing error must not pass")) ((err e) (assert (= e "listing exploded") (str "the listing error passes through: " e))))
        (mt fromEmpty ((ok _) (assert false "an empty listing must not pass")) ((err e) (assert (stringContains? e "No things found") (str "the empty listing is named: " e))))
        (mt fromBad ((ok _) (assert false "a failing path must not pass")) ((err e) (assert (stringContains? e "1 of 3 things failed: b: broken") (str "the failing path is named: " e))))
        (mt fromGood ((ok ps) (assert (= (listLength ps) 2) "all passing paths are returned")) ((err e) (assert false (str "passing paths must pass: " e))))
        true))

fn ! testPathChecks -> Bool
  (let [(dir (freshDir! "pathChecks")) (missing (str dir "/missing")) (badManifest (str dir "/bad.asn")) (goodManifest (str dir "/good.asn")) (unbalanced (str dir "/u.asl")) (balanced (str dir "/b.asl")) (noFence (str dir "/SKILL.md")) (fenced (str dir "/fenced.md"))
        (wrote (and (ok? (fileWrite badManifest "(:not-a-package 1)")) (and (ok? (fileWrite goodManifest "(:package asl-fixture :version \"0.1.0\" :entry \"src/main.asl\")")) (and (ok? (fileWrite unbalanced "(fn f -> I64 (+ 1 2)\n")) (and (ok? (fileWrite balanced "(fn f -> I64 (+ 1 2))\n")) (and (ok? (fileWrite noFence "# no fence\n")) (ok? (fileWrite fenced "---\nname: x\n---\n"))))))))
        (r0 (rn/manifestCheck! missing)) (r1 (rn/manifestCheck! badManifest)) (r2 (rn/manifestCheck! goodManifest)) (r3 (rn/balanceCheck! missing)) (r4 (rn/balanceCheck! unbalanced)) (r5 (rn/balanceCheck! balanced)) (r6 (rn/skillCheck! missing)) (r7 (rn/skillCheck! noFence)) (r8 (rn/skillCheck! fenced))
        (cleaned (pathRemove dir))]
    (do (assert wrote "path check fixtures written")
        (assert (errNames? r0 missing) "an unreadable manifest is a named error")
        (assert (errNames? r1 badManifest) "an invalid manifest is a named error")
        (assert (ok? r2) "a valid manifest passes")
        (assert (errNames? r3 missing) "an unreadable source file is a named balance error")
        (assert (errNames? r4 unbalanced) "an unbalanced source file is a named error")
        (assert (ok? r5) "a balanced source file passes")
        (assert (errNames? r6 missing) "an unreadable skill is a named error")
        (assert (errNames? r7 noFence) "a skill without a frontmatter fence is a named error")
        (assert (ok? r8) "a fenced skill passes")
        true))

fn ! testClaimsGroundingNamesFailures -> Bool
  (let [(dir (freshDir! "claims")) (missing (str dir "/missing.asn")) (unterminated (str dir "/unterminated.asn")) (few (str dir "/few.asn")) (ungrounded (str dir "/ungrounded.asn"))
        (claimRows (fn [(ms (List Str))] -> Str (stringJoin (map (fn [(m Str)] -> Str (str "(:claim :metric \"" m "\")\n")) ms) "")))
        (wrote (and (ok? (fileWrite unterminated "(:claims (:claim :metric \"57%-65%")) (and (ok? (fileWrite few (claimRows (list "57%-65%" "24MB")))) (ok? (fileWrite ungrounded (claimRows (listAppend (sc/standardClaims) (list "999x fabricated")))))))) 
        (rMissing (sc/claimsGroundingAt! (list missing))) (rUnterminated (sc/claimsGroundingAt! (list missing unterminated))) (rFew (sc/claimsGroundingAt! (list few))) (rUngrounded (sc/claimsGroundingAt! (list ungrounded))) (rLive (sc/claimsGrounding!))
        (cleaned (pathRemove dir))]
    (do (assert wrote "claims fixtures written")
        (mt rMissing ((ok n) (assert false "a missing claims file must not ground")) ((err e) (assert (stringContains? e missing) (str "the missing claims file is named: " e))))
        (mt rUnterminated ((ok n) (assert false "an unterminated metric must not ground")) ((err e) (assert (and (stringContains? e unterminated) (stringContains? e "unterminated")) (str "the unterminated metric is named: " e))))
        (mt rFew ((ok n) (assert false "two claims must not ground")) ((err e) (assert (stringContains? e "Only 2 published claims") (str "too few claims is named: " e))))
        (mt rUngrounded ((ok n) (assert false "an ungrounded claim must not ground")) ((err e) (assert (stringContains? e "999x fabricated") (str "the ungrounded claim is named: " e))))
        (mt rLive ((ok n) (assert (>= n 12) "the live claims file grounds at least 12 claims")) ((err e) (assert false (str "the live claims file must ground: " e))))
        true))

fn ! runTests -> Bool
  (and (testStratification) (and (testVacuityRejection) (and (testCommandLines) (and (testCheckPaths) (and (testPathChecks) (testClaimsGroundingNamesFailures))))))
