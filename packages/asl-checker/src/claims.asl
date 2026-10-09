(module asl-checker/claims
  :x [ClaimCitation GroundedReceipt makeCitation makeReceipt extractClaimsFromRegistry extractField matchClaimToReceipt refuteUnbackedClaims verifyClaimsGrounding groundClaims!]
  :i [])

(schema ClaimCitation
  (:f metric Str)
  (:f category Str)
  (:f source Str)
  (:f citation Str)
  (:f isGrounded Bool))

(schema GroundedReceipt
  (:f claimId Str)
  (:f metric Str)
  (:f receiptSource Str)
  (:f executedAsserts Int64)
  (:f verifiedDate Str))

fn makeCitation metric: Str category: Str source: Str citation: Str isGrounded: Bool -> ClaimCitation
  (ClaimCitation :metric metric :category category :source source :citation citation :isGrounded isGrounded)

fn makeReceipt claimId: Str metric: Str receiptSource: Str executedAsserts: Int64 verifiedDate: Str -> GroundedReceipt
  (GroundedReceipt :claimId claimId :metric metric :receiptSource receiptSource :executedAsserts executedAsserts :verifiedDate verifiedDate)

fn extractField text: Str fieldKey: Str -> Str
  (let [(needle (str fieldKey " \""))]
    (mt (stringIndexOf text needle)
      ((none) "")
      ((some idx)
       (let [(startPos (+ idx (stringLength needle)))
             (tail (optionOr (stringSlice text startPos (stringLength text)) ""))]
         (mt (stringIndexOf tail "\"")
           ((none) "")
           ((some endIdx)
            (optionOr (stringSlice tail 0 endIdx) "")))))))

fn extractClaimsFromRegistry registryContent: Str -> (List ClaimCitation)
  (let [(tokens (stringSplit registryContent "(:claim"))]
    (let [(validChunks (filter (fn [(chunk Str)] -> Bool
                                 (and (stringContains? chunk ":metric")
                                      (and (stringContains? chunk ":category")
                                           (stringContains? chunk ":source"))))
                               tokens))]
      (map (fn [(chunk Str)] -> ClaimCitation
             (let [(metric (extractField chunk ":metric"))
                   (category (extractField chunk ":category"))
                   (source (extractField chunk ":source"))
                   (citation (str source "#" metric))]
               (makeCitation metric category source citation true)))
           validChunks)))

fn matchClaimToReceipt claim: ClaimCitation receipts: (List GroundedReceipt) -> Bool
  (let [(m claim.metric)]
    (let [(matched (filter (fn [(r GroundedReceipt)] -> Bool (= r.metric m)) receipts))]
      (not (listEmpty? matched))))

fn refuteUnbackedClaims claims: (List ClaimCitation) receipts: (List GroundedReceipt) -> (List ClaimCitation)
  (filter (fn [(c ClaimCitation)] -> Bool
            (not (matchClaimToReceipt c receipts)))
          claims)

fn verifyClaimsGrounding claims: (List ClaimCitation) receipts: (List GroundedReceipt) -> (Result Int64 Str)
  (let [(unbacked (refuteUnbackedClaims claims receipts))]
    (if (listEmpty? unbacked)
        (ok (listLength claims))
        (err (str "Refuted " (stringFromInt64 (listLength unbacked)) " ungrounded claim(s) lacking test receipts"))))

fn groundClaims! registryPath: Str -> (Result (List ClaimCitation) Str)
  (let [(readRes (fileRead registryPath))]
    (mt readRes
      ((err _) (err (str "Failed to read claims registry: " registryPath)))
      ((ok content)
       (let [(claims (extractClaimsFromRegistry content))]
         (if (listEmpty? claims)
             (err "Claims registry contains zero valid claims")
             (ok claims))))))

