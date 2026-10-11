(module asl/packages/asl-checker/tests/claimsGroundingTest
  :x [testCitationConstructors testGroundedReceiptConstructors testPublishedClaimsExtraction! testUnbackedClaimRefutation testFullClaimsGroundingPass testRulesClaimGrounding! testDualPolarityRefutations! runTests RunTests!]
  :i [(asl-checker/claims :a cl)])

fn testCitationConstructors -> Bool
  (let [(c1 (cl/makeCitation "57%-65%" "token_compression" "bench/token_frames.py" "bench/token_frames.py#57%-65%" true))
        (c2 (cl/makeCitation "-64.7%" "token_compression" "bench/token_frames.py" "bench/token_frames.py#-64.7%" false))]
    (do
      (assert (= c1.metric "57%-65%") "Citation c1 metric matches")
      (assert (= c1.category "token_compression") "Citation c1 category matches")
      (assert (= c1.source "bench/token_frames.py") "Citation c1 source matches")
      (assert c1.isGrounded "Citation c1 isGrounded is true")
      (assert (= c2.metric "-64.7%") "Citation c2 metric matches")
      (assert (not c2.isGrounded) "Citation c2 isGrounded is false")
      (refute (= c1.metric c2.metric) "Different citations have distinct metrics")
      (refute (= c1.isGrounded c2.isGrounded) "Grounded status differs")
      true))

fn testGroundedReceiptConstructors -> Bool
  (let [(r1 (cl/makeReceipt "claim-1" "57%-65%" "tests/bench/tokenTest.asl" 42 "2026-09-18"))
        (r2 (cl/makeReceipt "claim-2" "-64.7%" "tests/bench/frameTest.asl" 18 "2026-09-18"))]
    (do
      (assert (= r1.claimId "claim-1") "Receipt r1 claimId matches")
      (assert (= r1.metric "57%-65%") "Receipt r1 metric matches")
      (assert (= r1.receiptSource "tests/bench/tokenTest.asl") "Receipt r1 source matches")
      (assert (> r1.executedAsserts 0) "Receipt r1 executed asserts must be strictly positive")
      (assert (= r1.executedAsserts 42) "Receipt r1 assert count matches")
      (assert (= r1.verifiedDate "2026-09-18") "Receipt r1 verified date matches")
      (assert (= r2.executedAsserts 18) "Receipt r2 assert count matches")
      (refute (= r1.executedAsserts 0) "Refute zero asserts in valid receipt")
      (refute (= r1.claimId r2.claimId) "Receipts have distinct claim IDs")
      true))

fn testPublishedClaimsExtraction! -> Bool
  (let [(res (cl/groundClaims! "asl/bench/publishedClaims.asn"))]
    (do
      (assert (ok? res) "groundClaims must parse publishedClaims.asn cleanly")
      (refute (err? res) "publishedClaims.asn read must not fail")
      (mt res
        ((err _) false)
        ((ok claims)
         (do
           (assert (>= (listLength claims) 12) "publishedClaims.asn must declare at least 12 benchmark claims")
           (refute (listEmpty? claims) "Claims list must not be empty")
           (let [(firstClaim (optionOr (listHead claims) (cl/makeCitation "" "" "" "" false)))]
             (do
               (assert (!= firstClaim.metric "") "First claim metric must be non-empty")
               (assert (!= firstClaim.category "") "First claim category must be non-empty")
               (assert (!= firstClaim.source "") "First claim source must be non-empty")
               (refute (= firstClaim.metric "") "Refute empty metric")
               true)))))
      true))

fn testUnbackedClaimRefutation -> Bool
  (let [(c1 (cl/makeCitation "metric-backed" "category" "source" "source#metric" true))
        (c2 (cl/makeCitation "metric-unbacked" "category" "source" "source#metric" true))
        (claims (list c1 c2))
        (r1 (cl/makeReceipt "c1" "metric-backed" "test.asl" 10 "2026-09-18"))
        (receipts (list r1))
        (unbacked (cl/refuteUnbackedClaims claims receipts))
        (checkRes (cl/verifyClaimsGrounding claims receipts))]
    (do
      (assert (= (listLength unbacked) 1) "Exactly one unbacked claim must be refuted and returned")
      (refute (listEmpty? unbacked) "Refute empty unbacked list when an unbacked claim exists")
      (let [(refutedClaim (optionOr (listHead unbacked) (cl/makeCitation "" "" "" "" false)))]
        (assert (= refutedClaim.metric "metric-unbacked") "Refuted claim must be the unbacked one"))
      (assert (err? checkRes) "verifyClaimsGrounding must return err when unbacked claims exist")
      (refute (ok? checkRes) "verifyClaimsGrounding must not succeed on unbacked claims")
      (mt checkRes
        ((err msg)
         (do
           (assert (stringContains? msg "Refuted") "Error message must report refutation")
           (assert (stringContains? msg "1 ungrounded claim") "Error message must report ungrounded count")
           true))
        ((ok _) false))
      true))

fn testFullClaimsGroundingPass -> Bool
  (let [(c1 (cl/makeCitation "m1" "cat" "src" "src#m1" true))
        (c2 (cl/makeCitation "m2" "cat" "src" "src#m2" true))
        (claims (list c1 c2))
        (r1 (cl/makeReceipt "c1" "m1" "test1.asl" 5 "2026-09-18"))
        (r2 (cl/makeReceipt "c2" "m2" "test2.asl" 8 "2026-09-18"))
        (receipts (list r1 r2))
        (unbacked (cl/refuteUnbackedClaims claims receipts))
        (checkRes (cl/verifyClaimsGrounding claims receipts))]
    (do
      (assert (listEmpty? unbacked) "All claims backed by receipts must yield empty unbacked list")
      (refute (not (listEmpty? unbacked)) "Refute non-empty unbacked when all claims are backed")
      (assert (ok? checkRes) "verifyClaimsGrounding must return ok when all claims backed")
      (refute (err? checkRes) "verifyClaimsGrounding must refute err on complete grounding")
      (mt checkRes
        ((ok count) (assert (= count 2) "Grounded count must equal claims count"))
        ((err _) (assert false "verifyClaimsGrounding returned err")))
      true))

fn basisTokens parts: (List Str) i: Int64 -> (List Str)
  (filter (fn [(t Str)] -> Bool (not (stringEmpty? t)))
    (stringSplit (optionOr (listHead (stringSplit (optionOr (listGet parts i) "") ")")) "") " "))

fn isDecisionId tok: Str -> Bool
  (and (stringStartsWith? tok "D") (and (> (stringLength tok) 1) (stringContains? "0123456789" (optionOr (stringSlice tok 1 2) "x"))))

fn checkBasisToken! principles: Str acc: Int64 tok: Str -> Int64
  (if (isDecisionId tok)
    (let [(ls (processRun (str "/bin/ls .asl/mem/decisions/" tok "[A-Z]*.asn")))]
      (do
        (assert (= ls.exitCode 0) (str "rules basis " tok " must resolve to a decision record under .asl/mem/decisions"))
        (+ acc 1)))
    (do
      (assert (stringContains? principles (str "(:principle :id \"" tok "\"")) (str "rules basis " tok " must resolve to a principle in .asl/mem/principles.asn"))
      (+ acc 1)))

fn testRulesClaimGrounding! -> Bool
  (let [(readRes (fileRead "asl/grammar/rules.asn"))
        (principlesRes (fileRead ".asl/mem/principles.asn"))
        (wsRes (fileRead ".asl/rules.asn"))
        (wsContent (resultOr wsRes ""))]
    (do
      (assert (ok? readRes) "rules.asn must be readable on disk")
      (refute (err? readRes) "rules.asn read must refute error")
      (assert (ok? principlesRes) "principles.asn must be readable on disk")
      (mt readRes
        ((err _) false)
        ((ok content)
         (let [(principles (resultOr principlesRes ""))
               (allContent (str content wsContent))
               (parts (stringSplit allContent ":basis ("))
               (tokens (fold (fn [(acc (List Str)) (i Int64)] -> (List Str) (listAppend acc (basisTokens parts i))) (list) (range 1 (listLength parts))))
               (grounded (fold (fn [(acc Int64) (tok Str)] -> Int64 (checkBasisToken! principles acc tok)) 0 tokens))
               (srcDecision (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit content ":src ") 1) "") " ")) ""))]
           (do
             (assert (stringContains? content ":basis \".asl/mem/principles.asn\"") "rules.asn must name principles.asn as its basis")
             (assert (isDecisionId srcDecision) "rules.asn :src must name a decision id")
             (assert (= (checkBasisToken! principles 0 srcDecision) 1) "rules.asn :src decision must resolve")
             (assert (> (listLength tokens) 0) "rules.asn and the workspace rules file together must cite at least one basis")
             (assert (= grounded (listLength tokens)) "every basis across rules.asn and the workspace rules file, when present, must be grounded")
             (refute (stringContains? allContent "%") "rules.asn and the workspace rules file must carry no figure; figures live in principles.asn entries or bench locks")
             (refute (stringContains? allContent "arXiv") "rules.asn and the workspace rules file must refute unsourced paper citations")
             (refute (stringContains? allContent "TODO") "rules.asn and the workspace rules file must refute ungrounded TODO citations")
             true))))
      true))

fn testDualPolarityRefutations! -> Bool
  (let [(badRead (cl/groundClaims! "nonexistent/claims/registry.asn"))
        (emptyClaims (list))
        (emptyReceipts (list))
        (emptyRes (cl/verifyClaimsGrounding emptyClaims emptyReceipts))]
    (do
      (assert (err? badRead) "Missing registry file must return err")
      (refute (ok? badRead) "Missing registry file must refute ok")
      (assert (ok? emptyRes) "Empty claims and empty receipts verify vacuously")
      (refute (err? emptyRes) "Empty list must not report unbacked claims")
      true))

fn ! runTests -> Bool
  (do
    (assert (testCitationConstructors) "testCitationConstructors passed")
    (assert (testGroundedReceiptConstructors) "testGroundedReceiptConstructors passed")
    (assert (testPublishedClaimsExtraction!) "testPublishedClaimsExtraction passed")
    (assert (testUnbackedClaimRefutation) "testUnbackedClaimRefutation passed")
    (assert (testFullClaimsGroundingPass) "testFullClaimsGroundingPass passed")
    (assert (testRulesClaimGrounding!) "testRulesClaimGrounding passed")
    (assert (testDualPolarityRefutations!) "testDualPolarityRefutations passed")
    true)

fn RunTests! -> Bool
  (runTests)
