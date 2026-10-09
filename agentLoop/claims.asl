(module asl/agentLoop/claims
  :x [extractClaims claimsResultTotal claimsResultUnbacked claimsResultClaims
      claimBacked claimCmd claimReceiptOpt claimExitOpt claimText claimIsEvidence? evidenceClaim proseClaim
      receiptOf receiptId receiptCmd receiptOp receiptStatus receiptError receiptNeedsConfirm
      receiptHasExit receiptExit receiptGateRuns receiptHasSpan receiptSpanStart receiptSpanEnd receiptFile
      receiptBacks isBacked isProseClaimBacked
      turnBringsEvidence evidenceUpdateNew evidenceUpdateCoverage evidenceUpdateSeenKeys
      turnEvidenceEntry forgetCutEvidence forgetCutResultText forgetCutResultCoverage forgetCutResultSeenKeys
      isTurnObservation unwrapReadTxns unwrapResultOps unwrapResultCount
      mergeFindings wrongCitationNote hasNegatorNear extractProseStrings collectProseStringsInner
      oldStructuralKeys newStructuralKeys
      Receipt Claim ClaimsResult EvidenceUpdate TurnEvidenceEntry ForgetCutResult UnwrapResult]
  :i [(asl/agentLoop/core :a c)])

enum Receipt
  (receiptOf id: String
             cmd: String
             op: String
             status: String
             error: String
             needsConfirm: Bool
             hasExit: Bool
             exit: Int64
             gateRuns: (List (Pair String Int64))
             hasSpan: Bool
             spanStart: Int64
             spanEnd: Int64
             file: String)

fn receiptId r: Receipt -> String
  (mt r ((receiptOf id _ _ _ _ _ _ _ _ _ _ _ _) id))

fn receiptCmd r: Receipt -> String
  (mt r ((receiptOf _ cmd _ _ _ _ _ _ _ _ _ _ _) cmd))

fn receiptOp r: Receipt -> String
  (mt r ((receiptOf _ _ op _ _ _ _ _ _ _ _ _ _) op))

fn receiptStatus r: Receipt -> String
  (mt r ((receiptOf _ _ _ status _ _ _ _ _ _ _ _ _) status))

fn receiptError r: Receipt -> String
  (mt r ((receiptOf _ _ _ _ error _ _ _ _ _ _ _ _) error))

fn receiptNeedsConfirm r: Receipt -> Bool
  (mt r ((receiptOf _ _ _ _ _ needsConfirm _ _ _ _ _ _ _) needsConfirm))

fn receiptHasExit r: Receipt -> Bool
  (mt r ((receiptOf _ _ _ _ _ _ hasExit _ _ _ _ _ _) hasExit))

fn receiptExit r: Receipt -> Int64
  (mt r ((receiptOf _ _ _ _ _ _ _ exit _ _ _ _ _) exit))

fn receiptGateRuns r: Receipt -> (List (Pair String Int64))
  (mt r ((receiptOf _ _ _ _ _ _ _ _ gateRuns _ _ _ _) gateRuns))

fn receiptHasSpan r: Receipt -> Bool
  (mt r ((receiptOf _ _ _ _ _ _ _ _ _ hasSpan _ _ _) hasSpan))

fn receiptSpanStart r: Receipt -> Int64
  (mt r ((receiptOf _ _ _ _ _ _ _ _ _ _ spanStart _ _) spanStart))

fn receiptSpanEnd r: Receipt -> Int64
  (mt r ((receiptOf _ _ _ _ _ _ _ _ _ _ _ spanEnd _) spanEnd))

fn receiptFile r: Receipt -> String
  (mt r ((receiptOf _ _ _ _ _ _ _ _ _ _ _ _ file) file))

enum Claim
  (evidenceClaim cmd: String receipt: (Option String) exit: (Option Int64) backed: Bool)
  (proseClaim text: String backed: Bool)

fn claimBacked c: Claim -> Bool
  (mt c ((evidenceClaim _ _ _ b) b) ((proseClaim _ b) b))

fn claimCmd c: Claim -> String
  (mt c ((evidenceClaim cmd _ _ _) cmd) ((proseClaim _ _) ""))

fn claimReceiptOpt c: Claim -> (Option String)
  (mt c ((evidenceClaim _ r _ _) r) ((proseClaim _ _) (none)))

fn claimExitOpt c: Claim -> (Option Int64)
  (mt c ((evidenceClaim _ _ e _) e) ((proseClaim _ _) (none)))

fn claimText c: Claim -> String
  (mt c ((evidenceClaim _ _ _ _) "") ((proseClaim t _) t))

fn claimIsEvidence? c: Claim -> Bool
  (mt c ((evidenceClaim _ _ _ _) true) ((proseClaim _ _) false))

enum ClaimsResult
  (claimsResult total: Int64 unbacked: Int64 claims: (List Claim))

fn claimsResultTotal r: ClaimsResult -> Int64
  (mt r ((claimsResult t _ _) t))

fn claimsResultUnbacked r: ClaimsResult -> Int64
  (mt r ((claimsResult _ u _) u))

fn claimsResultClaims r: ClaimsResult -> (List Claim)
  (mt r ((claimsResult _ _ cs) cs))

enum EvidenceUpdate
  (evidenceUpdate new: Bool
                  coverage: (List (Pair String (List (Pair Int64 Int64))))
                  seenKeys: (List (List c/KvVal)))

fn evidenceUpdateNew e: EvidenceUpdate -> Bool
  (mt e ((evidenceUpdate n _ _) n))

fn evidenceUpdateCoverage e: EvidenceUpdate -> (List (Pair String (List (Pair Int64 Int64))))
  (mt e ((evidenceUpdate _ cov _) cov))

fn evidenceUpdateSeenKeys e: EvidenceUpdate -> (List (List c/KvVal))
  (mt e ((evidenceUpdate _ _ k) k))

enum TurnEvidenceEntry
  (turnEvidenceEntry turn: Int64
                      reads: (List (Pair String (Pair Int64 Int64)))
                      keys: (List (List c/KvVal)))

fn teTurn e: TurnEvidenceEntry -> Int64
  (mt e ((turnEvidenceEntry t _ _) t))

fn teReads e: TurnEvidenceEntry -> (List (Pair String (Pair Int64 Int64)))
  (mt e ((turnEvidenceEntry _ r _) r))

fn teKeys e: TurnEvidenceEntry -> (List (List c/KvVal))
  (mt e ((turnEvidenceEntry _ _ k) k))

enum ForgetCutResult
  (forgetCutResult text: String
                   coverage: (List (Pair String (List (Pair Int64 Int64))))
                   seenKeys: (List (List c/KvVal)))

fn forgetCutResultText r: ForgetCutResult -> String
  (mt r ((forgetCutResult t _ _) t))

fn forgetCutResultCoverage r: ForgetCutResult -> (List (Pair String (List (Pair Int64 Int64))))
  (mt r ((forgetCutResult _ cov _) cov))

fn forgetCutResultSeenKeys r: ForgetCutResult -> (List (List c/KvVal))
  (mt r ((forgetCutResult _ _ k) k))

enum UnwrapResult
  (unwrapResult ops: (List (List (Pair String c/KvVal))) count: Int64)

fn unwrapResultOps r: UnwrapResult -> (List (List (Pair String c/KvVal)))
  (mt r ((unwrapResult ops _) ops))

fn unwrapResultCount r: UnwrapResult -> Int64
  (mt r ((unwrapResult _ n) n))


fn negatorsList -> (List String)
  (list "not" "no" "zero" "never")

fn punctSet -> (List String)
  (list "." "," ";" ":" "!" "?")

fn oldStructuralKeys -> (List String)
  (list "cmd" "file" "content" "old" "new" "op" "path" "anchor" "base" "rev" "limit" "claim")

fn newStructuralKeys -> (List String)
  (list "cmd" "file" "content" "old" "new" "op" "path" "anchor" "base" "rev" "limit" "commit")

fn argumentHeads -> (List String)
  (list "write" "edit" "read" "query" "outline" "check" "diff" "flush" "discard" "test" "tree" "fix"
        "txn" "tools" "help" "gitDiff" "gitLog" "gitShow" "gate" "run" "delete" "manage" "note" "observe"
        "search" "research" "crawl")

fn planOpsList -> (List String)
  (list "plan" "planDone" "planDrop")

fn readOnlyOpsList -> (List String)
  (list "read" "query" "q" "diff" "check" "tree" "tools" "help" "gitDiff" "gitLog" "gitShow" "gate" "note"
        "observe" "intent" "outline" "intel")

fn txnReadOpsList -> (List String)
  (list "read" "check" "query" "q" "tree" "diff" "gitDiff" "gitLog" "gitShow" "observe")

fn saysPassedWords -> (List String)
  (list "pass" "passed" "passes" "passing" "green" "ok" "verified")


fn kvToStr v: c/KvVal -> String
  (mt v ((c/kvStr t) t) ((c/kvInt t) t))

fn kvGetText kv: (List (Pair String c/KvVal)) k: String -> String
  (kvToStr (c/dictOr kv k))

fn kvGetInt kv: (List (Pair String c/KvVal)) k: String default: Int64 -> Int64
  (mt (c/dictGet kv k)
    ((some v) (optionOr (stringToInt64 (kvToStr v)) default))
    (none default))

fn kvGetStrOpt kv: (List (Pair String c/KvVal)) k: String -> (Option String)
  (mt (c/dictGet kv k)
    ((some v) (some (kvToStr v)))
    (none (none)))

fn firstNonEmpty a: String b: String -> String
  (if (!= a "") a b)

fn endsWith? s: String suffix: String -> Bool
  (let [sn (stringLength s) fx (stringLength suffix)]
    (and (>= sn fx) (= (c/sliceOf s (- sn fx) sn) suffix)))

fn lowerByte ch: String -> String
  (mt (stringIndexOf "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ch)
    ((some i) (c/sliceOf "abcdefghijklmnopqrstuvwxyz" i (+ i 1)))
    (none ch))

fn lowerStr s: String -> String
  (c/mapBytes s (stringLength s) 0 0 lowerByte (list))

fn wsTokensLoop s: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [a (c/runEnd s n i c/isSpace)]
    (if (>= a n)
      (listReverse acc)
      (let [b (c/runEnd s n a (fn [ch] (not (c/isSpace ch))))]
        (wsTokensLoop s n b (cons (c/sliceOf s a b) acc)))))

fn wsTokens s: String -> (List String)
  (wsTokensLoop s (stringLength s) 0 (list))

fn matchAt s: String n: Int64 i: Int64 word: String -> Bool
  (let [wn (stringLength word)]
    (and (>= i 0) (and (<= (+ i wn) n) (= (c/sliceOf s i (+ i wn)) word))))

fn isWordBoundaryBefore lc: String i: Int64 -> Bool
  (or (= i 0) (not (c/isWordByte (c/ch lc (- i 1)))))

fn isWordBoundaryAfter lc: String n: Int64 j: Int64 -> Bool
  (or (>= j n) (not (c/isWordByte (c/ch lc j))))

fn stripLeadingColons s: String -> String
  (c/stripLeft s (fn [ch] (= ch ":")))


fn punctStrip w: String -> String
  (c/stripRight (lowerStr w) (fn [ch] (listContains? (punctSet) ch)))

fn hasNegatorNear sentence: String matchStart: Int64 -> Bool
  (let [textBefore (c/sliceOf sentence 0 matchStart)
        words (wsTokens textBefore)
        wn (listLength words)
        window (if (>= wn 3) (optionOr (listSlice words (- wn 3) wn) (list)) words)]
    (listAny? (fn [w] (listContains? (negatorsList) (punctStrip w))) window))


fn oldDelimUnitLen text: String n: Int64 i: Int64 -> (Option Int64)
  (if (>= i n)
    (none)
    (let [ch (c/ch text i)]
      (if (or (= ch ".") (or (= ch ";") (= ch "\n"))) (some 1) (none))))

fn oldDelimRunLen text: String n: Int64 i: Int64 -> (Option Int64)
  (mt (oldDelimUnitLen text n i)
    ((some l) (mt (oldDelimRunLen text n (+ i l)) ((some more) (some (+ l more))) ((none) (some l))))
    ((none) (none)))

fn newDelimUnitLen text: String n: Int64 i: Int64 -> (Option Int64)
  (if (>= i n)
    (none)
    (let [ch (c/ch text i)]
      (cond
        ((= ch ";") (some 1))
        ((= ch "\n") (some 1))
        ((= ch ".")
          (let [afterDot (+ i 1)
                wsEnd (c/runEnd text n afterDot c/isSpace)]
            (if (> wsEnd afterDot) (some (- wsEnd i)) (if (>= afterDot n) (some 1) (none)))))
        (else (none)))))

fn newDelimRunLen text: String n: Int64 i: Int64 -> (Option Int64)
  (mt (newDelimUnitLen text n i)
    ((some l) (mt (newDelimRunLen text n (+ i l)) ((some more) (some (+ l more))) ((none) (some l))))
    ((none) (none)))

fn oldSplitLoop text: String n: Int64 i: Int64 segStart: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (c/sliceOf text segStart n) acc))
    (mt (oldDelimRunLen text n i)
      ((some len) (oldSplitLoop text n (+ i len) (+ i len) (cons (c/sliceOf text segStart i) acc)))
      ((none) (oldSplitLoop text n (+ i 1) segStart acc))))

fn newSplitLoop text: String n: Int64 i: Int64 segStart: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (c/sliceOf text segStart n) acc))
    (mt (newDelimRunLen text n i)
      ((some len) (newSplitLoop text n (+ i len) (+ i len) (cons (c/sliceOf text segStart i) acc)))
      ((none) (newSplitLoop text n (+ i 1) segStart acc))))

fn oldSplitSentences text: String -> (List String)
  (oldSplitLoop text (stringLength text) 0 0 (list))

fn newSplitSentences text: String -> (List String)
  (newSplitLoop text (stringLength text) 0 0 (list))


fn verbCoreLenAt lc: String n: Int64 i: Int64 includeFixed: Bool -> (Option Int64)
  (cond
    ((matchAt lc n i "ran") (some 3))
    ((matchAt lc n i "run") (some 3))
    ((matchAt lc n i "executed") (some 8))
    ((matchAt lc n i "verified") (some 8))
    ((matchAt lc n i "tested") (some 6))
    ((matchAt lc n i "passes") (some 6))
    ((matchAt lc n i "passed") (some 6))
    ((matchAt lc n i "pass") (some 4))
    ((matchAt lc n i "green") (some 5))
    ((and includeFixed (matchAt lc n i "fixed")) (some 5))
    (else (none)))

fn exitDigitsLenAt lc: String n: Int64 i: Int64 -> (Option Int64)
  (if (not (matchAt lc n i "exit"))
    (none)
    (let [afterExit (+ i 4)
          wsEnd (c/runEnd lc n afterExit c/isSpace)]
      (if (= wsEnd afterExit)
        (none)
        (let [digEnd (c/runEnd lc n wsEnd c/isDigit)]
          (if (= digEnd wsEnd) (none) (some (- digEnd i)))))))

fn matchLenAt lc: String n: Int64 i: Int64 includeFixed: Bool -> (Option Int64)
  (mt (verbCoreLenAt lc n i includeFixed)
    ((some len) (if (and (isWordBoundaryBefore lc i) (isWordBoundaryAfter lc n (+ i len))) (some len) (exitDigitsLenAt lc n i)))
    ((none) (exitDigitsLenAt lc n i)))

fn findClaimVerbStarts lc: String n: Int64 i: Int64 includeFixed: Bool acc: (List Int64) -> (List Int64)
  (if (>= i n)
    (listReverse acc)
    (mt (matchLenAt lc n i includeFixed)
      ((some len) (findClaimVerbStarts lc n (+ i len) includeFixed (cons i acc)))
      ((none) (findClaimVerbStarts lc n (+ i 1) includeFixed acc))))

fn findFirstNonNegated sentence: String starts: (List Int64) -> (Option Int64)
  (if (listEmpty? starts)
    (none)
    (let [s (c/firstOf starts)]
      (if (hasNegatorNear sentence s) (findFirstNonNegated sentence (c/restOf starts)) (some s))))


fn isNoteOrIntentStepPrefix text: String -> Bool
  (if (not (stringStartsWith? text "(:step"))
    false
    (let [n (stringLength text)
          afterStep (c/runEnd text n 6 c/isSpace)]
      (if (= afterStep 6)
        false
        (if (not (matchAt text n afterStep ":op"))
          false
          (let [afterOp (+ afterStep 3)
                afterOpWs (c/runEnd text n afterOp c/isSpace)]
            (if (= afterOpWs afterOp)
              false
              (or (matchAt text n afterOpWs "\"note\"") (matchAt text n afterOpWs "\"intent\""))))))))

fn backWordStart t: String p: Int64 -> Int64
  (if (and (> p 0) (c/isWordByte (c/ch t (- p 1)))) (backWordStart t (- p 1)) p)

fn trailingKey before: String -> String
  (let [t (c/trimSpace before)
        n (stringLength t)
        wordStart (backWordStart t n)]
    (if (or (= wordStart n) (= wordStart 0) (!= (c/ch t (- wordStart 1)) ":"))
      ""
      (c/sliceOf t wordStart n)))

fn collectLoop formText: String n: Int64 end: Int64 i: Int64 isEvidence: Bool structuralKeys: (List String) planOn: Bool out: (List String) -> (List String)
  (if (>= i end)
    out
    (let [ch (c/ch formText i)]
      (cond
        ((= ch "(")
          (mt (c/formEnd formText n (+ i 1) 1 false false)
            ((pair j _)
              (let [sub (c/sliceOf formText i j)
                    out2 (collectProseStringsInner sub isEvidence structuralKeys planOn out)]
                (collectLoop formText n end j isEvidence structuralKeys planOn out2)))))
        ((= ch "\"")
          (let [qStart (+ i 1)
                qEndRaw (c/strBodyEnd formText n qStart)
                qEnd (if (< qEndRaw 0) n qEndRaw)
                j (+ qEnd 1)
                literal (c/sliceOf formText qStart qEnd)
                key (trailingKey (c/sliceOf formText 0 i))
                out2 (if (listContains? structuralKeys key) out (listAppend out (list literal)))]
            (collectLoop formText n end j isEvidence structuralKeys planOn out2)))
        (else (collectLoop formText n end (+ i 1) isEvidence structuralKeys planOn out)))))

fn collectProseStringsInner formText: String inEvidence: Bool structuralKeys: (List String) planOn: Bool out: (List String) -> (List String)
  (let [head (c/headOf formText)
        isEvidence (or (= head "evidence") inEvidence)]
    (if isEvidence
      out
      (if (or (= head "note") (or (= head "intent") (and (= head "step") (isNoteOrIntentStepPrefix formText))))
        out
        (if (and planOn (listContains? (planOpsList) head))
          out
          (let [n (stringLength formText)
                end0 (- n 1)
                end (if (< end0 1) n end0)]
            (collectLoop formText n end 1 isEvidence structuralKeys planOn out))))))

fn extractProseStrings text: String structuralKeys: (List String) planOn: Bool -> (List String)
  (let [forms (c/parseForms text)
        literalsRaw (fold (fn [acc form]
                            (let [head (c/headOf form)]
                              (if (or (= head "step") (listContains? (argumentHeads) head))
                                acc
                                (collectProseStringsInner form false structuralKeys planOn acc))))
                      (list) forms)]
    (map c/asnUnescape literalsRaw))


fn claimReceiptOrCmd c: Claim -> String
  (optionOr (claimReceiptOpt c) (claimCmd c))

fn wrongCitationNote wrong: (List Claim) -> String
  (if (listEmpty? wrong)
    ""
    (str "wrong citation: " (c/joinSep (map (fn [c] (str "\"" (c/escapeAsn (claimReceiptOrCmd c)) "\"")) wrong) " ")
         " names no receipt of this session, or its recorded exit differs; an (:evidence (:receipt id ...)) form cites the :id of a receipt above and is never itself a claim"))


fn findReceiptById receipts: (List Receipt) rid: String -> (Option Receipt)
  (cond
    ((listEmpty? receipts) (none))
    ((= (receiptId (c/firstOf receipts)) rid) (some (c/firstOf receipts)))
    (else (findReceiptById (c/restOf receipts) rid)))

fn receiptBacks rid: String claimedExit: (Option Int64) receipts: (List Receipt) -> Bool
  (mt (findReceiptById receipts rid)
    ((none) false)
    ((some r)
      (mt claimedExit
        ((none) true)
        ((some ce)
          (let [exits0 (if (receiptHasExit r) (list (receiptExit r)) (map pairSecond (receiptGateRuns r)))
                exits (if (and (listEmpty? exits0) (= (receiptStatus r) "ok")) (list 0) exits0)]
            (and (not (listEmpty? exits)) (listAll? (fn [e] (= e ce)) exits)))))))

fn isBacked cmdStr: String claimedExit: Int64 receipts: (List Receipt) -> Bool
  (if (listEmpty? receipts)
    false
    (listAny? (fn [r]
                (let [rCmd (receiptCmd r)
                      rExit (if (receiptHasExit r) (receiptExit r) -1)
                      rId (receiptId r)]
                  (or (and (>= (stringLength cmdStr) 8) (and (stringContains? rCmd cmdStr) (= claimedExit rExit)))
                    (or (and (>= (stringLength rCmd) 8) (and (stringContains? cmdStr rCmd) (= claimedExit rExit)))
                      (and (!= rId "") (and (stringContains? cmdStr rId) (= claimedExit rExit)))))))
      receipts))


fn gatePassAltLen lc: String n: Int64 p: Int64 -> (Option Int64)
  (cond
    ((matchAt lc n p "passes") (some 6))
    ((matchAt lc n p "passed") (some 6))
    ((matchAt lc n p "pass") (some 4))
    ((matchAt lc n p "green") (some 5))
    ((matchAt lc n p "are")
      (let [ws2 (c/runEnd lc n (+ p 3) c/isSpace)]
        (if (and (> ws2 (+ p 3)) (matchAt lc n ws2 "green")) (some (- (+ ws2 5) p)) (none))))
    (else (none)))

fn gatePassCoreLen lc: String n: Int64 p: Int64 -> (Option Int64)
  (if (not (matchAt lc n p "gate"))
    (none)
    (let [afterGate (+ p 4)
          afterGateS (if (matchAt lc n afterGate "s") (+ afterGate 1) afterGate)
          wsEnd (c/runEnd lc n afterGateS c/isSpace)]
      (if (= wsEnd afterGateS)
        (none)
        (mt (gatePassAltLen lc n wsEnd)
          ((some al) (some (- (+ wsEnd al) p)))
          ((none) (none))))))

fn tryPrefixList lc: String n: Int64 i: Int64 -> (List Int64)
  (let [base (list i)
        withAll (if (matchAt lc n i "all")
                  (let [ws (c/runEnd lc n (+ i 3) c/isSpace)] (if (> ws (+ i 3)) (cons ws base) base))
                  base)
        withBoth (if (matchAt lc n i "both")
                   (let [ws (c/runEnd lc n (+ i 4) c/isSpace)] (if (> ws (+ i 4)) (cons ws withAll) withAll))
                   withAll)]
    withBoth)

fn gatePassMatchAt lc: String n: Int64 i: Int64 -> Bool
  (if (not (isWordBoundaryBefore lc i))
    false
    (listAny? (fn [pos] (mt (gatePassCoreLen lc n pos)
                          ((some cl) (isWordBoundaryAfter lc n (+ pos cl)))
                          ((none) false)))
      (tryPrefixList lc n i)))

fn gatePassSearchLoop lc: String n: Int64 i: Int64 -> Bool
  (if (>= i n)
    false
    (if (gatePassMatchAt lc n i) true (gatePassSearchLoop lc n (+ i 1))))

fn gatePassRegexMatches sentence: String -> Bool
  (let [lc (lowerStr sentence)]
    (gatePassSearchLoop lc (stringLength lc) 0))

fn lastDotLoop s: String n: Int64 i: Int64 acc: (Option Int64) -> (Option Int64)
  (if (>= i n) acc (lastDotLoop s n (+ i 1) (if (= (c/ch s i) ".") (some i) acc)))

fn beforeLastDot s: String -> String
  (mt (lastDotLoop s (stringLength s) 0 (none))
    ((some idx) (c/sliceOf s 0 idx))
    ((none) s))

fn suiteNameLoop parts: (List String) first: String -> String
  (if (listEmpty? parts)
    ""
    (let [p (c/firstOf parts) base (c/progName p)]
      (if (stringContains? base ".")
        (beforeLastDot base)
        (if (!= p first) base (suiteNameLoop (c/restOf parts) first)))))

fn suiteNameOf gCmd: String -> String
  (let [parts (wsTokens gCmd)]
    (if (listEmpty? parts) "" (suiteNameLoop parts (c/firstOf parts))))

fn hasGreenForCmd receipts: (List Receipt) targetCmd: String -> Bool
  (listAny? (fn [r]
              (or (and (= (receiptCmd r) targetCmd) (and (receiptHasExit r) (= (receiptExit r) 0)))
                (listAny? (fn [gr] (and (= (pairFirst gr) targetCmd) (= (pairSecond gr) 0))) (receiptGateRuns r))))
    receipts)

fn isProseClaimBacked sentence: String receipts: (List Receipt) gates: (List String) gatePassBacked: Bool -> Bool
  (if (and gatePassBacked (gatePassRegexMatches sentence))
    true
    (if (listEmpty? receipts)
      false
      (if (listAny? (fn [r]
                      (let [rCmd (receiptCmd r) rExit (if (receiptHasExit r) (receiptExit r) -1) rId (receiptId r)]
                        (or (and (>= (stringLength rCmd) 8) (and (stringContains? sentence rCmd) (= rExit 0)))
                          (and (and (!= rId "") (>= (stringLength rId) 8)) (and (stringContains? sentence rId) (= rExit 0))))))
            receipts)
        true
        (if (listEmpty? gates)
          false
          (let [latestGreen (filter (fn [g] (hasGreenForCmd receipts g)) gates)
                lc (lowerStr sentence)
                saysPassed (listAny? (fn [w] (stringContains? lc w)) (saysPassedWords))]
            (if (not saysPassed)
              false
              (listAny? (fn [g]
                          (or (stringContains? sentence g)
                            (let [sn (suiteNameOf g)]
                              (and (!= sn "") (or (stringContains? sentence sn) (stringContains? lc sn))))))
                latestGreen)))))))


fn extractEvidenceClaimLoop nestedAll: (List String) receipts: (List Receipt) claims: (List Claim) unbacked: Int64 -> (Pair (List Claim) Int64)
  (if (listEmpty? nestedAll)
    (pair claims unbacked)
    (let [nf (c/firstOf nestedAll)
          restNf (c/restOf nestedAll)
          nkv (c/parseKv nf)
          hasCmd (c/dictHas nkv "cmd")
          hasReceipt (c/dictHas nkv "receipt")]
      (if (not (or hasCmd hasReceipt))
        (extractEvidenceClaimLoop restNf receipts claims unbacked)
        (let [hasExitField (c/dictHas nkv "exit")
              claimedExit0 (if hasExitField (kvGetInt nkv "exit" 0) 0)
              cmdText (kvGetText nkv "cmd")
              receiptText (kvGetText nkv "receipt")
              cmdOrReceipt (firstNonEmpty cmdText receiptText)]
          (if hasReceipt
            (let [backedExitOpt (if hasExitField (some claimedExit0) (none))
                  backed (receiptBacks receiptText backedExitOpt receipts)
                  claim (evidenceClaim cmdOrReceipt (some receiptText) backedExitOpt backed)]
              (extractEvidenceClaimLoop restNf receipts (listAppend claims (list claim)) (if backed unbacked (+ unbacked 1))))
            (let [backed (isBacked cmdOrReceipt claimedExit0 receipts)
                  claim (evidenceClaim cmdOrReceipt (none) (some claimedExit0) backed)]
              (extractEvidenceClaimLoop restNf receipts (listAppend claims (list claim)) (if backed unbacked (+ unbacked 1)))))))))

fn extractEvidenceClaims replyText: String receipts: (List Receipt) -> (Pair (List Claim) Int64)
  (let [forms (c/parseForms replyText)
        evidenceForms (filter (fn [f] (= (c/headOf f) "evidence")) forms)
        nestedAll (fold (fn [acc ef] (listAppend acc (c/parseForms (c/sliceOf ef 1 (stringLength ef))))) (list) evidenceForms)]
    (extractEvidenceClaimLoop nestedAll receipts (list) 0))

fn extractProseClaimsOldLoop sentences: (List String) receipts: (List Receipt) claims: (List Claim) unbacked: Int64 -> (Pair (List Claim) Int64)
  (if (listEmpty? sentences)
    (pair claims unbacked)
    (let [sentRaw (c/firstOf sentences)
          rest (c/restOf sentences)
          sentence (c/trimSpace sentRaw)]
      (if (or (stringEmpty? sentence) (stringStartsWith? sentence "("))
        (extractProseClaimsOldLoop rest receipts claims unbacked)
        (let [lc (lowerStr sentence)
              starts (findClaimVerbStarts lc (stringLength lc) 0 false (list))
              firstOk (findFirstNonNegated sentence starts)]
          (mt firstOk
            ((none) (extractProseClaimsOldLoop rest receipts claims unbacked))
            ((some _)
              (let [backed (isProseClaimBacked sentence receipts (list) false)
                    claim (proseClaim sentence backed)]
                (extractProseClaimsOldLoop rest receipts (listAppend claims (list claim)) (if backed unbacked (+ unbacked 1))))))))))

fn extractProseClaimsOld replyText: String receipts: (List Receipt) -> (Pair (List Claim) Int64)
  (let [proseText0 (c/stripForms replyText)
        inner (extractProseStrings replyText (oldStructuralKeys) false)
        proseText (if (listEmpty? inner) proseText0 (str proseText0 "\n" (c/joinSep inner "\n")))
        sentences (oldSplitSentences proseText)]
    (extractProseClaimsOldLoop sentences receipts (list) 0))

fn extractProseClaimsNewLoop sentences: (List String) receipts: (List Receipt) gates: (List String) gatePassBacked: Bool claims: (List Claim) unbacked: Int64 -> (Pair (List Claim) Int64)
  (if (listEmpty? sentences)
    (pair claims unbacked)
    (let [sentRaw (c/firstOf sentences)
          rest (c/restOf sentences)
          sentence (c/trimSpace sentRaw)]
      (if (or (stringEmpty? sentence) (or (stringStartsWith? sentence "(") (endsWith? sentence ":")))
        (extractProseClaimsNewLoop rest receipts gates gatePassBacked claims unbacked)
        (let [lc (lowerStr sentence)
              starts (findClaimVerbStarts lc (stringLength lc) 0 true (list))
              firstOk (findFirstNonNegated sentence starts)]
          (mt firstOk
            ((none) (extractProseClaimsNewLoop rest receipts gates gatePassBacked claims unbacked))
            ((some _)
              (let [backed (isProseClaimBacked sentence receipts gates gatePassBacked)
                    claim (proseClaim sentence backed)]
                (extractProseClaimsNewLoop rest receipts gates gatePassBacked (listAppend claims (list claim)) (if backed unbacked (+ unbacked 1))))))))))

fn extractProseClaimsNew replyText: String receipts: (List Receipt) gates: (List String) gatePassBacked: Bool planOn: Bool -> (Pair (List Claim) Int64)
  (let [proseText0 (c/stripForms replyText)
        inner (extractProseStrings replyText (newStructuralKeys) planOn)
        proseText (if (listEmpty? inner) proseText0 (str proseText0 "\n" (c/joinSep inner "\n")))
        sentences (newSplitSentences proseText)]
    (extractProseClaimsNewLoop sentences receipts gates gatePassBacked (list) 0))

fn extractClaims replyText: String receipts: (List Receipt) isOldCall: Bool gates: (List String) checkProse: Bool gatePassBacked: Bool planOn: Bool -> ClaimsResult
  (let [ev (extractEvidenceClaims replyText receipts)
        evClaims (pairFirst ev) evUnbacked (pairSecond ev)]
    (if (and (not isOldCall) (not checkProse))
      (claimsResult (listLength evClaims) evUnbacked evClaims)
      (let [prose (if isOldCall (extractProseClaimsOld replyText receipts) (extractProseClaimsNew replyText receipts gates gatePassBacked planOn))
            proseClaimsL (pairFirst prose) proseUnbacked (pairSecond prose)
            allClaims (listAppend evClaims proseClaimsL)
            totalUnbacked (+ evUnbacked proseUnbacked)]
        (claimsResult (listLength allClaims) totalUnbacked allClaims))))


fn isTurnObservation ops: (List (List (Pair String c/KvVal))) -> Bool
  (if (listEmpty? ops)
    false
    (listAll? (fn [op] (and (= (c/dictOr op "type") (c/kvStr "step")) (listContains? (readOnlyOpsList) (kvGetText op "op")))) ops))

fn unwrapLoop ops: (List (List (Pair String c/KvVal))) acc: (List (List (Pair String c/KvVal))) n: Int64 -> UnwrapResult
  (if (listEmpty? ops)
    (unwrapResult acc n)
    (let [op (c/firstOf ops) rest (c/restOf ops)
          isTxn (= (c/dictOr op "op") (c/kvStr "txn"))]
      (if (not isTxn)
        (unwrapLoop rest (listAppend acc (list op)) n)
        (let [formText (kvGetText op "form")
              flen (stringLength formText)
              inner (if (< flen 2)
                      (list)
                      (c/parseReply (c/joinSep (filter (fn [f] (stringStartsWith? f "(:")) (c/parseForms (c/sliceOf formText 1 (- flen 1)))) " ")))
              qualifies (and (not (listEmpty? inner))
                          (listAll? (fn [i] (and (= (c/dictOr i "type") (c/kvStr "step")) (listContains? (txnReadOpsList) (kvGetText i "op")))) inner))]
          (if qualifies
            (unwrapLoop rest (listAppend acc inner) (+ n 1))
            (unwrapLoop rest (listAppend acc (list op)) n))))))

fn unwrapReadTxns ops: (List (List (Pair String c/KvVal))) -> UnwrapResult
  (unwrapLoop ops (list) 0)


fn findingHeadEnd form: String n: Int64 afterColon: Int64 -> (Option Int64)
  (cond
    ((and (matchAt form n afterColon "findings") (isWordBoundaryAfter form n (+ afterColon 8))) (some (+ afterColon 8)))
    ((and (matchAt form n afterColon "finding") (isWordBoundaryAfter form n (+ afterColon 7))) (some (+ afterColon 7)))
    (else (none)))

fn findingParts form: String -> (Pair String (Pair (List String) (List (List (Pair String c/KvVal)))))
  (let [n (stringLength form)
        hasOpenParen (and (> n 0) (= (c/ch form 0) "("))]
    (if (not hasOpenParen)
      (pair "" (pair (list) (list (c/parseKv form))))
      (let [i (c/runEnd form n 1 c/isSpace)
            hasColon (and (< i n) (= (c/ch form i) ":"))]
        (if (not hasColon)
          (pair "" (pair (list) (list (c/parseKv form))))
          (let [afterColon (+ i 1)
                headEnd (optionOr (findingHeadEnd form n afterColon) afterColon)
                head (c/sliceOf form 0 headEnd)
                body (if (> n 0) (c/sliceOf form headEnd (- n 1)) "")
                items (c/parseForms body)
                kvs (if (listEmpty? items) (list (c/parseKv form)) (map c/parseKv items))]
            (pair head (pair items kvs)))))))

fn findingKey kv: (List (Pair String c/KvVal)) -> (Option (Pair (Option String) (Option String)))
  (let [head (optionOr (kvGetStrOpt kv "_head") "")]
    (if (listContains? (list "claim" "finding" "retract") head)
      (let [fileOpt (kvGetStrOpt kv "file")
            anchorOpt (kvGetStrOpt kv "anchor")
            claimOpt (kvGetStrOpt kv "claim")
            secondOpt (mt anchorOpt
                        ((some a) (if (= a "") claimOpt (some a)))
                        ((none) claimOpt))]
        (some (pair fileOpt secondOpt)))
      (none)))

fn isRetract kv: (List (Pair String c/KvVal)) -> Bool
  (or (= (optionOr (kvGetStrOpt kv "_head") "") "retract")
    (= (stripLeadingColons (optionOr (kvGetStrOpt kv "retract") "")) "true"))

fn isLastOccurrence kvs: (List (List (Pair String c/KvVal))) i: Int64 key: (Pair (Option String) (Option String)) -> Bool
  (not (listAny? (fn [kv2] (mt (findingKey kv2) ((some k2) (= k2 key)) ((none) false)))
        (optionOr (listSlice kvs (+ i 1) (listLength kvs)) (list))))

fn compactKeys kvs: (List (List (Pair String c/KvVal))) -> (List (Pair (Option String) (Option String)))
  (fold (fn [acc kv] (mt (findingKey kv) ((some k) (listAppend acc (list k))) ((none) acc))) (list) kvs)

fn kvHeadIsClaimFindingRetract kv: (List (Pair String c/KvVal)) -> Bool
  (listContains? (list "claim" "finding" "retract") (optionOr (kvGetStrOpt kv "_head") ""))

fn kvAnchorFalsy? kv: (List (Pair String c/KvVal)) -> Bool
  (= (optionOr (kvGetStrOpt kv "anchor") "") "")

; (:m :tags (claims))
fn computeNewWholeFile kvs: (List (List (Pair String c/KvVal))) -> (List String)
  (fold (fn [acc kv]
          (let [file (optionOr (kvGetStrOpt kv "file") "")]
            (if (and (kvHeadIsClaimFindingRetract kv) (and (!= file "") (kvAnchorFalsy? kv)))
              (if (listContains? acc file) acc (listAppend acc (list file)))
              acc)))
    (list) kvs)

fn mergeEarlierLoop earlier: (List String) keys: (List (Pair (Option String) (Option String))) newWholeFile: (List String)
                     kept: (List String) replaced: Int64 -> (Pair (List String) Int64)
  (if (listEmpty? earlier)
    (pair kept replaced)
    (let [old (c/firstOf earlier)
          parts (findingParts old)
          oHead (pairFirst parts) oItemsRaw (pairFirst (pairSecond parts)) oKvs (pairSecond (pairSecond parts))
          oItems (if (listEmpty? oItemsRaw) (list old) oItemsRaw)
          idxs (range 0 (listLength oKvs))
          leftTexts (fold (fn [acc idx]
                            (let [kv (optionOr (listGet oKvs idx) (list))
                                  txt (optionOr (listGet oItems idx) old)
                                  fk (findingKey kv)
                                  keyOk (mt fk ((some k) (not (listContains? keys k))) ((none) true))
                                  supersededByWholeFile (and (listContains? newWholeFile (optionOr (kvGetStrOpt kv "file") "")) (kvAnchorFalsy? kv))
                                  keepIt (and keyOk (not supersededByWholeFile))]
                              (if keepIt (listAppend acc (list txt)) acc)))
                      (list) idxs)
          removedCount (- (listLength oKvs) (listLength leftTexts))
          newReplaced (+ replaced removedCount)
          newKept (if (listEmpty? leftTexts)
                    kept
                    (listAppend kept (list (if (= (listLength leftTexts) (listLength oKvs)) old (str oHead " " (c/joinSep leftTexts " ") ")")))))]
      (mergeEarlierLoop (c/restOf earlier) keys newWholeFile newKept newReplaced)))

fn mergeFindings form: String earlier: (List String) -> (Pair (List String) Int64)
  (let [parts (findingParts form)
        head (pairFirst parts) itemsRaw (pairFirst (pairSecond parts)) kvs (pairSecond (pairSecond parts))
        items (if (listEmpty? itemsRaw) (list form) itemsRaw)
        keys (compactKeys kvs)
        newWholeFile (computeNewWholeFile kvs)
        earlierResult (mergeEarlierLoop earlier keys newWholeFile (list) 0)
        kept0 (pairFirst earlierResult) replaced (pairSecond earlierResult)
        idxs (range 0 (listLength kvs))
        newTexts (fold (fn [acc idx]
                         (let [kv (optionOr (listGet kvs idx) (list))
                               txt (optionOr (listGet items idx) form)
                               gone (isRetract kv)
                               fk (findingKey kv)
                               keepIt (and (not gone) (mt fk ((some k) (isLastOccurrence kvs idx k)) ((none) true)))]
                           (if keepIt (listAppend acc (list txt)) acc)))
                   (list) idxs)
        finalKept (if (and (not (listEmpty? newTexts)) (< (listLength kept0) 20))
                    (let [resultForm (if (listEmpty? itemsRaw) form (str head " " (c/joinSep newTexts " ") ")"))
                          truncated (if (> (stringLength resultForm) 2000) (c/sliceOf resultForm 0 2000) resultForm)]
                      (listAppend kept0 (list truncated)))
                    kept0)]
    (pair finalKept replaced))


fn zipFilter ops: (List (List (Pair String c/KvVal))) receipts: (List Receipt) planOn: Bool
             reads: (List (Pair String (Pair Int64 Int64))) keyed: (List (List (Pair String c/KvVal)))
             -> (Pair (List (Pair String (Pair Int64 Int64))) (List (List (Pair String c/KvVal))))
  (if (or (listEmpty? ops) (listEmpty? receipts))
    (pair (listReverse reads) (listReverse keyed))
    (let [op (c/firstOf ops) r (c/firstOf receipts)
          skip (or (= (receiptError r) "ERR_EFFECT_UNDECLARED")
                (or (receiptNeedsConfirm r)
                  (or (listContains? (list "note" "intent") (receiptOp r))
                    (or (= (receiptStatus r) "seen")
                      (and planOn (listContains? (planOpsList) (receiptOp r)))))))]
      (if skip
        (zipFilter (c/restOf ops) (c/restOf receipts) planOn reads keyed)
        (if (and (= (receiptOp r) "read") (receiptHasSpan r))
          (zipFilter (c/restOf ops) (c/restOf receipts) planOn (cons (pair (receiptFile r) (pair (receiptSpanStart r) (receiptSpanEnd r))) reads) keyed)
          (zipFilter (c/restOf ops) (c/restOf receipts) planOn reads (cons op keyed))))))

fn addKeysLoop keys: (List (List c/KvVal)) seen: (List (List c/KvVal)) newFlag: Bool -> (Pair Bool (List (List c/KvVal)))
  (if (listEmpty? keys)
    (pair newFlag seen)
    (let [k (c/firstOf keys)]
      (if (listContains? seen k)
        (addKeysLoop (c/restOf keys) seen newFlag)
        (addKeysLoop (c/restOf keys) (listAppend seen (list k)) true))))

fn applyReadsLoop reads: (List (Pair String (Pair Int64 Int64))) coverage: (List (Pair String (List (Pair Int64 Int64)))) newFlag: Bool
                   -> (Pair Bool (List (Pair String (List (Pair Int64 Int64)))))
  (if (listEmpty? reads)
    (pair newFlag coverage)
    (mt (c/firstOf reads)
      ((pair path span)
        (mt span
          ((pair a b)
            (mt (c/recordRead coverage path a b)
              ((pair isNew cov2) (applyReadsLoop (c/restOf reads) cov2 (or newFlag isNew)))))))))

fn turnBringsEvidence ops: (List (List (Pair String c/KvVal))) receipts: (List Receipt)
                       coverage0: (List (Pair String (List (Pair Int64 Int64)))) seenKeys0: (List (List c/KvVal))
                       mode: String base: String planOn: Bool -> EvidenceUpdate
  (let [normMode (if (= mode "auto") "implement" mode)
        zf (zipFilter ops receipts planOn (list) (list))
        reads (pairFirst zf) keyed (pairSecond zf)
        keys (map (fn [op] (c/evidenceKey op normMode base)) keyed)
        readsResult (applyReadsLoop reads coverage0 false)
        newFromReads (pairFirst readsResult) coverage1 (pairSecond readsResult)
        keysResult (addKeysLoop keys seenKeys0 false)
        newFromKeys (pairFirst keysResult) seenKeys1 (pairSecond keysResult)]
    (evidenceUpdate (or newFromReads newFromKeys) coverage1 seenKeys1))


fn assocHasPath acc: (List (Pair String (List (Pair Int64 Int64)))) k: String -> Bool
  (listAny? (fn [p] (= (pairFirst p) k)) acc)

fn assocAddSpan acc: (List (Pair String (List (Pair Int64 Int64)))) k: String span: (Pair Int64 Int64)
                -> (List (Pair String (List (Pair Int64 Int64))))
  (if (assocHasPath acc k)
    (map (fn [p] (if (= (pairFirst p) k) (pair k (listAppend (pairSecond p) (list span))) p)) acc)
    (listAppend acc (list (pair k (list span)))))

fn groupSpansByPath reads: (List (Pair String (Pair Int64 Int64))) -> (List (Pair String (List (Pair Int64 Int64))))
  (fold (fn [acc r] (mt r ((pair path span) (assocAddSpan acc path span)))) (list) reads)

fn forgetCutEvidence turnEvidence: (List TurnEvidenceEntry) whole: (List Int64) -> ForgetCutResult
  (let [relevant (filter (fn [e] (listContains? whole (teTurn e))) turnEvidence)
        allReads (fold (fn [acc e] (listAppend acc (teReads e))) (list) relevant)
        allKeys (fold (fn [acc e] (listAppend acc (teKeys e))) (list) relevant)
        pathGroups (groupSpansByPath allReads)
        newCoverage (map (fn [pg] (pair (pairFirst pg) (c/mergeSpans (pairSecond pg)))) pathGroups)
        text (if (listEmpty? newCoverage) "" (c/renderSeen newCoverage))]
    (forgetCutResult text newCoverage allKeys))
