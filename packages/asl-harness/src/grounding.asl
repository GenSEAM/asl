(module asl-harness/grounding
  :d "Anti-hallucination citation verification and epistemic grounding engine."
  :x [verify-citation verify-claims all-claims-grounded? detect-contradiction]
  :i [(core :a core)])

(df verify-citation [(docs (List core/SourceDocument)) (cit core/ClaimCitation)] -> core/VerificationResult
  :d "Verifies whether a claim citation is strictly grounded in an exact source quote."
  (mt (core/find-document docs (.-doc-id cit))
    ((none)
     (core/VerificationResult
       :verified false
       :citation cit
       :failure-reason "Source document not found in active context"))
    ((some doc)
     (let [(quote (.-exact-quote cit))]
       (cond
         ((string-empty? quote)
          (core/VerificationResult
            :verified false
            :citation cit
            :failure-reason "Citation quote cannot be empty"))
         ((not (string-contains? (.-content doc) quote))
          (core/VerificationResult
            :verified false
            :citation cit
            :failure-reason "Exact quote not found in source document content"))
         ((< (.-confidence cit) 0.5)
          (core/VerificationResult
            :verified false
            :citation cit
            :failure-reason "Confidence score too low (< 0.5)"))
         (:else
          (core/VerificationResult
            :verified true
            :citation cit
            :failure-reason "")))))))

(df verify-claims [(docs (List core/SourceDocument)) (citations (List core/ClaimCitation))] -> (List core/VerificationResult)
  :d "Verifies a batch of claim citations against active source documents."
  (map (fn [(c core/ClaimCitation)] -> core/VerificationResult (verify-citation docs c)) citations))

(df all-claims-grounded? [(results (List core/VerificationResult))] -> Bool
  :d "Returns true if every evaluated claim citation passed verification."
  (let [(failed (filter (fn [(r core/VerificationResult)] -> Bool (not (.-verified r))) results))]
    (list-empty? failed)))

(df detect-contradiction [(claim-a Str) (claim-b Str)] -> Bool
  :d "Checks whether two claims assert mutually contradictory polarity."
  (let [(neg-a (or (string-contains? claim-a " not ")
                   (or (string-contains? claim-a "cannot")
                       (or (string-contains? claim-a "false")
                           (string-starts-with? claim-a "not ")))))
        (neg-b (or (string-contains? claim-b " not ")
                   (or (string-contains? claim-b "cannot")
                       (or (string-contains? claim-b "false")
                           (string-starts-with? claim-b "not ")))))]
    (and (or neg-a neg-b)
         (not (and neg-a neg-b)))))
