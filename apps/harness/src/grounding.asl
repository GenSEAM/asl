(module aslHarness/grounding :x [verifyCitation verifyClaims allClaimsGrounded? detectContradiction] :i [(core :a core)])

fn verifyCitation docs: (List core/SourceDocument) cit: core/ClaimCitation -> core/VerificationResult
  (mt (core/findDocument docs cit.docId) ((none) (core/VerificationResult :verified false :citation cit :failureReason "Source document not found in active context")) ((some doc) (let [(quote cit.exactQuote)] (cond ((stringEmpty? quote) (core/VerificationResult :verified false :citation cit :failureReason "Citation quote cannot be empty")) ((not (stringContains? doc.content quote)) (core/VerificationResult :verified false :citation cit :failureReason "Exact quote not found in source document content")) ((< cit.confidence 0.5) (core/VerificationResult :verified false :citation cit :failureReason "Confidence score too low (< 0.5)")) (else (core/VerificationResult :verified true :citation cit :failureReason ""))))))

fn verifyClaims docs: (List core/SourceDocument) citations: (List core/ClaimCitation) -> (List core/VerificationResult)
  (map (fn [(c core/ClaimCitation)] -> core/VerificationResult (verifyCitation docs c)) citations)

fn allClaimsGrounded? results: (List core/VerificationResult) -> Bool
  (let [(failed (filter (fn [(r core/VerificationResult)] -> Bool (not r.verified)) results))] (listEmpty? failed))

fn detectContradiction claimA: Str claimB: Str -> Bool
  (let [(negA (or (stringContains? claimA " not ") (or (stringContains? claimA "cannot") (or (stringContains? claimA "false") (stringStartsWith? claimA "not "))))) (negB (or (stringContains? claimB " not ") (or (stringContains? claimB "cannot") (or (stringContains? claimB "false") (stringStartsWith? claimB "not ")))))] (and (or negA negB) (not (and negA negB))))
