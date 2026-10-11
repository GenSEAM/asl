(module asl/agentLoop/coreCli
  :x [main]
  :i [(asl/agentLoop/core :a c) (asl-forms/repair :a rep) (asl/agentLoop/plan :a p) (asl/agentLoop/retry :a r) (asl/agentLoop/claims :a cl) (asl/agentLoop/gates :a g) (asl/agentLoop/diff :a d) (asl/agentLoop/turn :a tr) (asl/agentLoop/loop :a lp)])

fn digitsEnd s: String i: Int64 -> Int64
  (if (= (c/sliceOf s i (+ i 1)) ":") i (digitsEnd s (+ i 1)))

fn netString s: String i: Int64 -> (Pair String Int64)
  (let [colon (digitsEnd s i)
        len (optionOr (stringToInt64 (c/sliceOf s i colon)) -1)]
    (pair (c/sliceOf s (+ colon 1) (+ (+ colon 1) len)) (+ (+ colon 1) len)))

fn netStrings s: String i: Int64 k: Int64 acc: (List String) -> (Pair (List String) Int64)
  (if (= k 0)
    (pair (listReverse acc) i)
    (mt (netString s i) ((pair v j) (netStrings s j (- k 1) (cons v acc)))))

fn toInt s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn toFloat s: String -> Float64
  (optionOr (stringToFloat64 s) 0.0)

fn triples xs: (List String) acc: (List (List String)) -> (List (List String))
  (if (listEmpty? xs)
    (listReverse acc)
    (triples (optionOr (listSlice xs 3 (listLength xs)) (list)) (cons (optionOr (listSlice xs 0 3) (list)) acc)))

fn spanPairs xs: (List String) acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (listEmpty? xs)
    (listReverse acc)
    (spanPairs (c/restOf (c/restOf xs)) (cons (pair (toInt (c/firstOf xs)) (toInt (c/firstOf (c/restOf xs)))) acc)))

fn arg fs: (List String) i: Int64 -> String
  (optionOr (listGet fs i) "")

fn coverageRun reads: (List (List String)) -> String
  (mt (fold (fn [st r]
              (mt st ((pair news cov)
                (mt (c/recordRead cov (arg r 0) (toInt (arg r 1)) (toInt (arg r 2)))
                  ((pair new cov2) (pair (cons (if new " true" " false") news) cov2))))))
        (pair (list) (list)) reads)
    ((pair news cov) (str "(new" (c/joinAll (listReverse news)) ") " (c/serString (c/renderSeen cov)))))

fn restFrom fs: (List String) i: Int64 -> (List String)
  (optionOr (listSlice fs i (listLength fs)) (list))

fn coverageFields fs: (List String) acc: (List (Pair String (List (Pair Int64 Int64)))) -> (List (Pair String (List (Pair Int64 Int64))))
  (if (listEmpty? fs)
    (listReverse acc)
    (let [k (* 2 (toInt (arg fs 1)))
          spans (restFrom fs 2)]
      (coverageFields (restFrom spans k)
        (cons (pair (c/firstOf fs) (spanPairs (optionOr (listSlice spans 0 k) (list)) (list))) acc))))

fn serCoverage cov: (List (Pair String (List (Pair Int64 Int64)))) -> String
  (str "(coverage" (c/joinAll (map (fn [e] (mt e ((pair p sp) (str " (" (c/serString p) " " (c/serSpans sp) ")")))) cov)) ")")

fn readsRun reads: (List (List String)) cov0: (List (Pair String (List (Pair Int64 Int64)))) -> String
  (mt (fold (fn [st r]
              (mt st ((pair news cov)
                (mt (c/recordRead cov (arg r 0) (toInt (arg r 1)) (toInt (arg r 2)))
                  ((pair new cov2) (pair (cons (if new " true" " false") news) cov2))))))
        (pair (list) cov0) reads)
    ((pair news cov) (str "(new" (c/joinAll (listReverse news)) ") " (serCoverage cov))))

fn opFields xs: (List (List String)) -> (List (Pair String c/KvVal))
  (map (fn [t] (pair (arg t 0) (c/fieldVal (= (arg t 1) "i") (arg t 2)))) xs)

fn boolOf s: String -> Bool
  (= s "1")

fn chunks xs: (List String) n: Int64 acc: (List (List String)) -> (List (List String))
  (if (listEmpty? xs)
    (listReverse acc)
    (chunks (optionOr (listSlice xs n (listLength xs)) (list)) n (cons (optionOr (listSlice xs 0 n) (list)) acc)))

fn gateFromFields fs: (List String) -> r/GateRec
  (r/makeGateRec (arg fs 0) (toInt (arg fs 1)) (boolOf (arg fs 2)) (toInt (arg fs 3)) (arg fs 4) (arg fs 5))

fn gatesFrom fs: (List String) -> (List r/GateRec)
  (map gateFromFields (chunks fs 6 (list)))

fn receiptFromFields fs: (List String) -> r/ReceiptRec
  (r/makeReceiptRec (arg fs 0) (arg fs 1) (arg fs 2) (arg fs 3) (arg fs 4) (arg fs 5) (arg fs 6) (arg fs 7)
                     (arg fs 8) (arg fs 9) (arg fs 10) (toInt (arg fs 11)) (arg fs 12) (arg fs 13) (arg fs 14))

fn receiptsFrom fs: (List String) -> (List r/ReceiptRec)
  (map receiptFromFields (chunks fs 15 (list)))

fn kvIntFromFields fs: (List String) -> (Pair String Int64)
  (pair (arg fs 0) (toInt (arg fs 1)))

fn kvIntsFrom fs: (List String) -> (List (Pair String Int64))
  (map kvIntFromFields (chunks fs 2 (list)))

fn serOptStr o: (Option String) -> String
  (mt o ((some v) (str "(some " (c/serString v) ")")) ((none) "(none)"))

fn serStrList xs: (List String) -> String
  (str "(" (c/joinAll (map (fn [s] (str " " (c/serString s))) xs)) ")")

fn strListGroup fs: (List String) -> (Pair (List String) (List String))
  (let [k (toInt (arg fs 0)) rest (restFrom fs 1)]
    (pair (optionOr (listSlice rest 0 k) (list)) (restFrom rest k)))

fn strListGroups fs: (List String) n: Int64 acc: (List (List String)) -> (Pair (List (List String)) (List String))
  (if (= n 0)
    (pair (listReverse acc) fs)
    (mt (strListGroup fs) ((pair g rest) (strListGroups rest (- n 1) (cons g acc)))))


fn serNode node: p/SexpNode -> String
  (mt node
    ((p/sexpAtom a) (str "(atom " (c/serString a) ")"))
    ((p/sexpStr s) (str "(str " (c/serString s) ")"))
    ((p/sexpList items) (str "(list" (c/joinAll (map (fn [it] (str " " (serNode it))) items)) ")")))

fn serTree tree: (List p/SexpNode) -> String
  (str "(tree" (c/joinAll (map (fn [n] (str " " (serNode n))) tree)) ")")


fn parseGateRuns fs: (List String) k: Int64 acc: (List (Pair String Int64)) -> (List (Pair String Int64))
  (if (= k 0)
    (listReverse acc)
    (parseGateRuns (restFrom fs 2) (- k 1) (cons (pair (arg fs 0) (toInt (arg fs 1))) acc)))

fn parseReceiptAt fs: (List String) -> (Pair cl/Receipt (List String))
  (let [id (arg fs 0) cmd (arg fs 1) op (arg fs 2) status (arg fs 3) error (arg fs 4)
        needsConfirm (= (arg fs 5) "true")
        hasExit (= (arg fs 6) "true")
        exit (toInt (arg fs 7))
        numGateRuns (toInt (arg fs 8))
        afterCount (restFrom fs 9)
        gateRunsList (parseGateRuns afterCount numGateRuns (list))
        afterGateRuns (restFrom afterCount (* 2 numGateRuns))
        hasSpan (= (arg afterGateRuns 0) "true")
        spanStart (toInt (arg afterGateRuns 1))
        spanEnd (toInt (arg afterGateRuns 2))
        file (arg afterGateRuns 3)
        rest (restFrom afterGateRuns 4)
        r (cl/receiptOf id cmd op status error needsConfirm hasExit exit gateRunsList hasSpan spanStart spanEnd file)]
    (pair r rest))

fn parseReceiptsLoop fs: (List String) k: Int64 acc: (List cl/Receipt) -> (Pair (List cl/Receipt) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (mt (parseReceiptAt fs)
      ((pair r rest) (parseReceiptsLoop rest (- k 1) (cons r acc)))))

fn parseReceipts fs: (List String) -> (Pair (List cl/Receipt) (List String))
  (let [n (toInt (arg fs 0))]
    (parseReceiptsLoop (restFrom fs 1) n (list)))

fn parseSpansN fs: (List String) k: Int64 acc: (List (Pair Int64 Int64)) -> (Pair (List (Pair Int64 Int64)) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (parseSpansN (restFrom fs 2) (- k 1) (cons (pair (toInt (arg fs 0)) (toInt (arg fs 1))) acc)))

fn parseCoverageEntry fs: (List String) -> (Pair (Pair String (List (Pair Int64 Int64))) (List String))
  (let [path (arg fs 0) k (toInt (arg fs 1)) spansResult (parseSpansN (restFrom fs 2) k (list))]
    (pair (pair path (pairFirst spansResult)) (pairSecond spansResult)))

fn parseCoverageEntriesLoop fs: (List String) k: Int64 acc: (List (Pair String (List (Pair Int64 Int64)))) -> (Pair (List (Pair String (List (Pair Int64 Int64)))) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (mt (parseCoverageEntry fs)
      ((pair e rest) (parseCoverageEntriesLoop rest (- k 1) (cons e acc)))))

fn parseCoverage fs: (List String) -> (Pair (List (Pair String (List (Pair Int64 Int64)))) (List String))
  (let [n (toInt (arg fs 0))]
    (parseCoverageEntriesLoop (restFrom fs 1) n (list)))

fn parseStringsN fs: (List String) k: Int64 acc: (List String) -> (Pair (List String) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (parseStringsN (restFrom fs 1) (- k 1) (cons (arg fs 0) acc)))

fn parseStringList fs: (List String) -> (Pair (List String) (List String))
  (let [n (toInt (arg fs 0))]
    (parseStringsN (restFrom fs 1) n (list)))

fn parseReadTriplesN fs: (List String) k: Int64 acc: (List (Pair String (Pair Int64 Int64))) -> (Pair (List (Pair String (Pair Int64 Int64))) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (parseReadTriplesN (restFrom fs 3) (- k 1) (cons (pair (arg fs 0) (pair (toInt (arg fs 1)) (toInt (arg fs 2)))) acc)))

fn parseOneKeyFields fs: (List String) k: Int64 acc: (List c/KvVal) -> (Pair (List c/KvVal) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (parseOneKeyFields (restFrom fs 2) (- k 1) (cons (c/fieldVal (= (arg fs 0) "i") (arg fs 1)) acc)))

fn parseKeysLoop fs: (List String) k: Int64 acc: (List (List c/KvVal)) -> (Pair (List (List c/KvVal)) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (let [n (toInt (arg fs 0))
          oneResult (parseOneKeyFields (restFrom fs 1) n (list))]
      (parseKeysLoop (pairSecond oneResult) (- k 1) (cons (pairFirst oneResult) acc))))

fn parseKeys fs: (List String) -> (Pair (List (List c/KvVal)) (List String))
  (let [n (toInt (arg fs 0))]
    (parseKeysLoop (restFrom fs 1) n (list)))

fn serKeysList keys: (List (List c/KvVal)) -> String
  (str "(seenKeys" (c/joinAll (map (fn [k] (str " " (c/serKey k))) keys)) ")")

fn parseTurnEntry fs: (List String) -> (Pair cl/TurnEvidenceEntry (List String))
  (let [turn (toInt (arg fs 0))
        numReads (toInt (arg fs 1))
        readsResult (parseReadTriplesN (restFrom fs 2) numReads (list))
        reads (pairFirst readsResult) afterReads (pairSecond readsResult)
        keysResult (parseKeys afterReads)
        keys (pairFirst keysResult) afterKeys (pairSecond keysResult)]
    (pair (cl/turnEvidenceEntry turn reads keys) afterKeys))

fn parseTurnEntriesLoop fs: (List String) k: Int64 acc: (List cl/TurnEvidenceEntry) -> (Pair (List cl/TurnEvidenceEntry) (List String))
  (if (= k 0)
    (pair (listReverse acc) fs)
    (mt (parseTurnEntry fs)
      ((pair e rest) (parseTurnEntriesLoop rest (- k 1) (cons e acc)))))

fn buildWrongClaims fs: (List String) k: Int64 acc: (List cl/Claim) -> (List cl/Claim)
  (if (= k 0)
    (listReverse acc)
    (let [hasReceipt (= (arg fs 0) "true") text (arg fs 1)]
      (buildWrongClaims (restFrom fs 2) (- k 1)
        (cons (cl/evidenceClaim text (if hasReceipt (some text) (none)) (none) false) acc))))

fn serClaim c: cl/Claim -> String
  (if (cl/claimIsEvidence? c)
    (str "(:evidence :cmd " (c/serString (cl/claimCmd c))
         " :hasReceipt " (mt (cl/claimReceiptOpt c) ((some _) "true") ((none) "false"))
         " :receipt " (c/serString (optionOr (cl/claimReceiptOpt c) ""))
         " :hasExit " (mt (cl/claimExitOpt c) ((some _) "true") ((none) "false"))
         " :exit " (stringFromInt64 (optionOr (cl/claimExitOpt c) 0))
         " :backed " (if (cl/claimBacked c) "true" "false") ")")
    (str "(:prose :text " (c/serString (cl/claimText c)) " :backed " (if (cl/claimBacked c) "true" "false") ")"))

fn serClaimsResult r: cl/ClaimsResult -> String
  (str "(claims :total " (stringFromInt64 (cl/claimsResultTotal r))
       " :unbacked " (stringFromInt64 (cl/claimsResultUnbacked r))
       " :items (" (c/joinSep (map serClaim (cl/claimsResultClaims r)) " ") "))")

fn serEvidenceUpdate e: cl/EvidenceUpdate -> String
  (str "(evidenceUpdate :new " (if (cl/evidenceUpdateNew e) "true" "false")
       " :coverage " (serCoverage (cl/evidenceUpdateCoverage e))
       " :seenKeys " (serKeysList (cl/evidenceUpdateSeenKeys e)) ")")

fn serForgetCut r: cl/ForgetCutResult -> String
  (str "(forgetCut :text " (c/serString (cl/forgetCutResultText r))
       " :coverage " (serCoverage (cl/forgetCutResultCoverage r))
       " :seenKeys " (serKeysList (cl/forgetCutResultSeenKeys r)) ")")

fn serUnwrap r: cl/UnwrapResult -> String
  (str "(unwrap :count " (stringFromInt64 (cl/unwrapResultCount r)) " :ops " (c/serOps (cl/unwrapResultOps r)) ")")

fn parsePairs xs: (List String) acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (if (listEmpty? xs)
    (listReverse acc)
    (parsePairs (c/restOf (c/restOf xs)) (cons (pair (toInt (c/firstOf xs)) (c/firstOf (c/restOf xs))) acc)))

fn parseStrPairs xs: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (if (listEmpty? xs)
    (listReverse acc)
    (parseStrPairs (c/restOf (c/restOf xs)) (cons (pair (c/firstOf xs) (c/firstOf (c/restOf xs))) acc)))

fn gateResultsFromFields xs: (List String) acc: (List g/GateResult) -> (List g/GateResult)
  (if (< (listLength xs) 6)
    (listReverse acc)
    (let [cmd (arg xs 0)
          exitCode (toInt (arg xs 1))
          stdout (arg xs 2)
          stderr (arg xs 3)
          timeout (= (arg xs 4) "1")
          sec (toInt (arg xs 5))
          res (g/makeGateResult cmd exitCode stdout stderr timeout sec)]
      (gateResultsFromFields (restFrom xs 6) (cons res acc))))

fn sessionHeaderFrom fs: (List String) -> String
  (let [ownsGroup (strListGroup (restFrom fs 5))
        owns (pairFirst ownsGroup)
        afterOwns (pairSecond ownsGroup)
        gatesGroup (strListGroup afterOwns)
        gates (pairFirst gatesGroup)
        rest (pairSecond gatesGroup)]
    (lp/sessionHeader (arg fs 0) (arg fs 1) (arg fs 2) (arg fs 3) (arg fs 4) owns gates
      (arg rest 0) (arg rest 1) (arg rest 2) (arg rest 3) (arg rest 4) (arg rest 5) (arg rest 6) (= (arg rest 7) "1")))

fn runCase! kind: String fs: (List String) -> String
  (cond
    ((= kind "sessionHeader") (c/serString (sessionHeaderFrom fs)))
    ((= kind "endStatus")
      (lp/endStatus (arg fs 0) (arg fs 1) (= (arg fs 2) "1") (= (arg fs 3) "1")))
    ((= kind "finalGatesGreen")
      (if (lp/finalGatesGreen (restFrom fs 1)) "true" "false"))
    ((= kind "preserveFiles")
      (if (lp/preserveFiles (arg fs 0) (arg fs 1) (toInt (arg fs 2)) (toInt (arg fs 3)) (toInt (arg fs 4)) (= (arg fs 5) "1")) "true" "false"))
    ((= kind "handBackRestore")
      (if (lp/handBackRestore (arg fs 0) (= (arg fs 1) "1")) "true" "false"))
    ((= kind "loopBoundary")
      (lp/loopBoundary (= (arg fs 0) "1") (toInt (arg fs 1)) (toInt (arg fs 2)) (arg fs 3) (= (arg fs 4) "1")
        (toFloat (arg fs 5)) (toFloat (arg fs 6)) (toInt (arg fs 7)) (toFloat (arg fs 8)) (toFloat (arg fs 9))
        (toInt (arg fs 10)) (toInt (arg fs 11))))
    ((= kind "specCheckKind")
      (lp/specCheckKind (= (arg fs 0) "1") (= (arg fs 1) "1") (arg fs 2) (= (arg fs 3) "1")
        (= (arg fs 4) "1") (= (arg fs 5) "1") (toInt (arg fs 6)) (toInt (arg fs 7))))
    ((= kind "finalOutcome")
      (lp/finalOutcome (arg fs 0) (arg fs 1) (= (arg fs 2) "1") (= (arg fs 3) "1") (toInt (arg fs 4)) (toInt (arg fs 5))))
    ((= kind "specCheckAction")
      (lp/specCheckAction (= (arg fs 0) "1") (= (arg fs 1) "1") (toInt (arg fs 2)) (toInt (arg fs 3))))
    ((= kind "unescape") (c/serString (c/asnUnescape (arg fs 0))))
    ((= kind "vendorRetryPause")
      (let [n (toInt (arg fs 2))
            schedule (map toInt (optionOr (listSlice fs 3 (+ 3 n)) (list)))
            left (toInt (arg fs (+ 3 n)))
            budget (if (< left 0) none (some left))]
        (stringFromInt64 (tr/vendorRetryPause (arg fs 0) (toInt (arg fs 1)) schedule budget))))
    ((= kind "turnReply")
      (let [declaredCount (toInt (arg fs 1))
            declared (if (< declaredCount 0) none (some (optionOr (listSlice fs 2 (+ 2 declaredCount)) (list))))
            tr (tr/turnReply (arg fs 0) declared)
            facts tr.facts
            cut facts.cut]
        (str "(turnReply " (c/serString tr.text) " " (c/serString tr.preBindText) " " (stringFromInt64 (mt tr.degenerateAt ((some n) n) (none -1))) " " (stringFromInt64 tr.degenerateRepeats) " " (stringFromInt64 tr.capBytes)
          " " (stringFromInt64 tr.rawBlocks) " " (stringFromInt64 tr.unfenced) " "
          (c/serOps facts.ops) " (forms" (c/joinAll (map (fn [f] (str " " (c/serString f))) facts.forms)) ") "
          (if facts.prose "true" "false") " " (stringFromInt64 facts.repeated)
          " (findings" (c/joinAll (map (fn [f] (str " " (c/serString f))) facts.dataFindings)) ") "
          (mt cut ((some ci) (str "(cut " (stringFromInt64 ci.bytes) " " (stringFromInt64 ci.start) " " (mt ci.head ((some x) (c/serString x)) (none "(:none)")) " " (mt ci.op ((some x) (c/serString x)) (none "(:none)")) " " (mt ci.file ((some x) (c/serString x)) (none "(:none)")) " " (stringFromInt64 ci.offset) " " (c/serString ci.text) ")")) (none "(:none)")) " "
          (mt tr.repair
            ((some a) (str "(repair " (c/serString (optionOr a.notice "")) " " (stringFromInt64 a.left) " "
                         (stringFromInt64 a.quoteCount) " (kinds"
                         (c/joinAll (map (fn [k] (str " " (c/serString k))) a.kinds)) "))"))
            ((none) "(:none)")) ")")))
    ((= kind "forms") (str "(forms" (c/joinAll (map (fn [f] (str " " (c/serString f))) (c/parseForms (arg fs 0)))) ")"))
    ((= kind "parse") (c/serOps (c/parseReply (arg fs 0))))
    ((= kind "prose") (if (c/isProseWrapped (arg fs 0)) "true" "false"))
    ((= kind "evidence")
      (str "(keys" (c/joinAll (map (fn [op] (str " " (c/serKey (c/evidenceKey op (arg fs 1) (arg fs 2))))) (c/parseReply (arg fs 0)))) ")"))
    ((= kind "owns") (if (c/checkOwns (arg fs 0) (optionOr (listSlice fs 2 (listLength fs)) (list)) (arg fs 1)) "true" "false"))
    ((= kind "merge") (c/serSpans (c/mergeSpans (spanPairs fs (list)))))
    ((= kind "coverage") (coverageRun (triples fs (list))))
    ((= kind "transcript")
      (c/serString (c/renderTranscript
        (map (fn [t] (c/makeTurn (arg t 0) (arg t 1) (arg t 2))) (triples (c/restOf fs) (list)))
        (toInt (arg fs 0)))))
    ((= kind "window")
      (mt (c/renderWindow
            (map (fn [t] (c/makeTurn (arg t 0) (arg t 1) (arg t 2))) (triples (restFrom fs (+ 4 (toInt (arg fs 3)))) (list)))
            (toInt (arg fs 0)) (toInt (arg fs 1)) (toInt (arg fs 2)) (optionOr (listSlice fs 4 (+ 4 (toInt (arg fs 3)))) (list)))
        ((c/windowOf text last cut dropped used whole)
          (str "(window " (stringFromInt64 cut) " " (stringFromInt64 dropped) " " (stringFromInt64 used)
            " (whole" (c/joinAll (map (fn [t] (str " " (c/serString t))) whole)) ") " (c/serString text) " " (c/serString last) ")"))))
    ((= kind "strip") (c/serString (c/stripForms (arg fs 0))))
    ((= kind "kv") (c/serOps (list (c/parseKv (arg fs 0)))))
    ((= kind "key") (c/serKey (c/evidenceKey (opFields (triples (restFrom fs 2) (list))) (arg fs 0) (arg fs 1))))
    ((= kind "seen") (c/serString (c/renderSeen (coverageFields fs (list)))))
    ((= kind "spanSeen")
      (if (c/spanSeen (coverageFields (restFrom fs 3) (list)) (arg fs 0) (toInt (arg fs 1)) (toInt (arg fs 2))) "true" "false"))
    ((= kind "reads")
      (let [k (* 3 (toInt (arg fs 0)))]
        (readsRun (triples (optionOr (listSlice fs 1 (+ 1 k)) (list)) (list)) (coverageFields (restFrom fs (+ 1 k)) (list)))))
    ((= kind "steps") (c/serOps (c/uniqueSteps (c/parseReply (arg fs 0)))))
    ((= kind "dataFindings")
      (str "(forms" (c/joinAll (map (fn [f] (str " " (c/serString f))) (c/dataFindings (arg fs 0) (restFrom fs 1)))) ")"))
    ((= kind "nearest") (c/serString (c/nearestOp (arg fs 0) (restFrom fs 1))))
    ((= kind "gate") (c/gateVerdict (= (arg fs 0) "1") (toInt (arg fs 1)) (arg fs 2) (arg fs 3)))
    ((= kind "note") (c/noteStep (arg fs 0) (toInt (arg fs 1))))
    ((= kind "outward")
      (let [k (toInt (arg fs 1))]
        (c/serString (c/runOutward (restFrom fs (+ 2 k)) (optionOr (listSlice fs 2 (+ 2 k)) (list)) (arg fs 0)))))
    ((= kind "readOnly") (if (c/runReadOnly fs) "true" "false"))
    ((= kind "hidden")
      (let [k (toInt (arg fs 1))]
        (str "(flags" (c/joinAll (map (fn [w] (if (c/hiddenPath w (optionOr (listSlice fs 2 (+ 2 k)) (list)) (arg fs 0)) " true" " false")) (restFrom fs (+ 2 k)))) ")")))
    ((= kind "harness")
      (str "(flags" (c/joinAll (map (fn [w] (if (c/harnessPath w (arg fs 0)) " true" " false")) (restFrom fs 1))) ")"))
    ((= kind "changePlan")
      (let [k (toInt (arg fs 1))]
        (str "(plan" (c/joinAll (map (fn [v] (str " " (c/serString v))) (c/changePlan (restFrom fs (+ 2 k)) (optionOr (listSlice fs 2 (+ 2 k)) (list)) (arg fs 0)))) ")")))
    ((= kind "terminal") (str "(forms" (c/joinAll (map (fn [f] (str " " (c/serString f))) (c/terminalForms (arg fs 0)))) ")"))
    ((= kind "repair")
      (let [(res (rep/repairAtSite (arg fs 0) (arg fs 1)))]
        (str "(repair " (c/serString (rep/repairResultText res)) " " (c/serString (rep/repairResultReceipt res)) ")")))
    ((or (= kind "planTree") (= kind "plan_tree"))
      (mt (p/planTree (arg fs 0))
        ((ok tree) (str "(ok " (serTree tree) ")"))
        ((err e) (str "(err " (c/serString e) ")"))))
    ((or (= kind "planFields") (= kind "plan_fields"))
      (mt (p/planTree (arg fs 0))
        ((ok tree)
          (let [items (mt (listHead tree)
                        ((some h) (mt h ((p/sexpList it) it) ((p/sexpAtom _) tree) ((p/sexpStr _) tree)))
                        (none (list)))
                fields (p/planFields items)
                kv (pairFirst fields)
                lists (pairSecond fields)]
            (str "(fields (kv"
              (c/joinAll (map (fn [pr]
                                (mt pr ((pair k val)
                                  (mt val
                                    ((p/valFlag b) (str " (" k " " (if b "true" "false") ")"))
                                    ((p/valStr s) (str " (" k " " (c/serString s) ")"))
                                    ((p/valList l) (str " (" k " (list" (c/joinAll (map (fn [n] (str " " (serNode n))) l)) "))"))))))
                              kv))
              ") (lists"
              (c/joinAll (map (fn [l] (str " (list" (c/joinAll (map (fn [n] (str " " (serNode n))) l)) ")")) lists))
              "))")))
        ((err e) (str "(err " (c/serString e) ")"))))
    ((or (= kind "planSteps") (= kind "plan_steps"))
      (mt (p/planTree (arg fs 0))
        ((ok tree)
          (let [nodes (mt (listHead tree)
                        ((some h) (mt h ((p/sexpList it) (if (p/isStepForm it) tree it)) ((p/sexpAtom _) tree) ((p/sexpStr _) tree)))
                        (none (list)))]
            (mt (p/planSteps nodes)
              ((ok steps) (str "(ok (steps" (c/joinAll (map (fn [s] (str " (:step :id " (p/stepId s) " :do " (c/serString (p/stepDoText s)) " :check " (c/serString (p/stepCheckText s)) ")")) steps)) "))"))
              ((err e) (str "(err " (c/serString e) ")")))))
        ((err e) (str "(err " (c/serString e) ")"))))
    ((or (= kind "planOpen") (= kind "plan_open"))
      (let [plan (p/parsePlanState (arg fs 0))
            openIds (p/planOpen plan)]
        (str "(open" (c/joinAll (map (fn [id] (str " " (c/serString id))) openIds)) ")")))
    ((or (= kind "planAdvance") (= kind "plan_advance"))
      (let [plan (p/parsePlanState (arg fs 0))
            turn (toInt (arg fs 1))]
        (p/serPlanState (p/planAdvance plan turn))))
    ((or (= kind "planSlot") (= kind "plan_slot"))
      (let [plan (p/parsePlanState (arg fs 0))]
        (c/serString (p/planSlot plan))))
    ((or (= kind "planNow") (= kind "plan_now"))
      (let [plan (p/parsePlanState (arg fs 0))
            turn (toInt (arg fs 1))]
        (c/serString (p/planNow plan turn))))
    ((or (= kind "planSummary") (= kind "plan_summary"))
      (let [plan (p/parsePlanState (arg fs 0))
            s (p/planSummary plan)]
        (str "(summary " (stringFromInt64 (p/summarySteps s)) " "
                         (stringFromInt64 (p/summaryDone s)) " "
                         (stringFromInt64 (p/summaryDropped s)) " "
                         (stringFromInt64 (p/summaryRevisions s)) ")")))
    ((or (= kind "planField") (= kind "plan_field"))
      (let [s (if (>= (listLength fs) 4)
                (p/summaryOf (toInt (arg fs 0)) (toInt (arg fs 1)) (toInt (arg fs 2)) (toInt (arg fs 3)))
                (p/planSummary (p/parsePlanState (arg fs 0))))]
        (c/serString (p/planField s))))
    ((or (= kind "planEvidenceIds") (= kind "plan_evidence_ids"))
      (let [recTriples (triples fs (list))
            receipts (map (fn [t] (p/makeReceipt (arg t 0) (arg t 1) (arg t 2))) recTriples)
            ids (p/planEvidenceIds receipts)]
        (str "(ids" (c/joinAll (map (fn [id] (str " " (c/serString id))) ids)) ")")))
    ((or (= kind "planStep") (= kind "plan_step"))
      (let [plan (p/parsePlanState (arg fs 0))
            opName (arg fs 1)
            opForm (arg fs 2)
            rid (arg fs 3)
            numEv (toInt (arg fs 4))
            evIds (optionOr (listSlice fs 5 (+ 5 numEv)) (list))
            res (p/planStep plan opName opForm rid evIds)]
        (mt res
          ((p/stepResult st op msg err ent newPlan)
            (str "(stepResult " (c/serString st) " " (c/serString op) " " (c/serString msg) " " (c/serString err) " "
                 (mt ent ((some e) (c/serString e)) ((none) (c/serString ""))) " "
                 (c/serString (p/serPlanState newPlan)) ")")))))
    ((or (= kind "planReplay") (= kind "plan_replay"))
      (p/serPlanState (p/planReplay (arg fs 0))))
    ((= kind "batchingRates")
      (let [rates (r/batchingRates (toInt (arg fs 0)) (toInt (arg fs 1)) (toInt (arg fs 2)))]
        (str "(rate " (stringFromFloat64 (pairFirst rates)) " " (stringFromFloat64 (pairSecond rates)) ")")))
    ((= kind "costForm")
      (mt (stringToFloat64 (arg fs 4))
        ((some wallSec)
          (c/serString (r/costForm (toInt (arg fs 0)) (toInt (arg fs 1)) (toInt (arg fs 2)) (toInt (arg fs 3))
                                    wallSec (toInt (arg fs 5)))))
        ((none) (str "ERR_BAD_FLOAT costForm wallSec " (arg fs 4)))))
    ((= kind "escalationNear")
      (let [nRetries (toInt (arg fs 8))
            retriesFields (optionOr (listSlice fs 9 (+ 9 (* 2 nRetries))) (list))
            afterRetries (+ 9 (* 2 nRetries))
            nFailure (toInt (arg fs afterRetries))
            failureFields (restFrom fs (+ afterRetries 1))]
        (c/serString (r/escalationNear (toInt (arg fs 0)) (toInt (arg fs 1)) (kvIntsFrom retriesFields) (toInt (arg fs 2))
                                        (kvIntsFrom (optionOr (listSlice failureFields 0 (* 2 nFailure)) (list)))
                                        (toInt (arg fs 3)) (toInt (arg fs 4)) (boolOf (arg fs 5)) (toInt (arg fs 6)) (boolOf (arg fs 7))))))
    ((= kind "reinforceWhyFor")
      (let [parseDefect (boolOf (arg fs 0))
            nHistory (toInt (arg fs 1))
            historyParsed (strListGroups (restFrom fs 2) nHistory (list))
            history (pairFirst historyParsed)
            rest1 (pairSecond historyParsed)
            deliver (arg rest1 0)
            writesPersisted (boolOf (arg rest1 1))
            turnsWithoutEvidence (toInt (arg rest1 2))
            turnNum (toInt (arg rest1 3))
            budget (toInt (arg rest1 4))
            nRetries (toInt (arg rest1 5))
            rest2 (restFrom rest1 6)
            retries (kvIntsFrom (optionOr (listSlice rest2 0 (* 2 nRetries)) (list)))
            rest3 (restFrom rest2 (* 2 nRetries))
            maxRetries (toInt (arg rest3 0))
            nFailure (toInt (arg rest3 1))
            rest4 (restFrom rest3 2)
            failureCounts (kvIntsFrom (optionOr (listSlice rest4 0 (* 2 nFailure)) (list)))
            rest5 (restFrom rest4 (* 2 nFailure))
            parseDefectCount (toInt (arg rest5 0))
            readStreak (toInt (arg rest5 1))
            redGateHas (boolOf (arg rest5 2))
            redGate (if redGateHas (some (arg rest5 3)) none)]
        (c/serString (r/reinforceWhyFor parseDefect history deliver writesPersisted turnsWithoutEvidence turnNum budget
                                         retries maxRetries failureCounts parseDefectCount readStreak redGate))))
    ((= kind "nowForm")
      (let [turn (toInt (arg fs 0))
            contextTokens (toInt (arg fs 1))
            winHas (boolOf (arg fs 2))
            winUsed (toInt (arg fs 3))
            winLast (arg fs 4)
            win (if winHas (some (pair winUsed winLast)) none)
            nWritten (toInt (arg fs 5))
            rest1 (restFrom fs 6)
            written (optionOr (listSlice rest1 0 nWritten) (list))
            rest2 (restFrom rest1 nWritten)
            nLastGates (toInt (arg rest2 0))
            rest3 (restFrom rest2 1)
            lgFieldsLen (* nLastGates 7)
            lgFlat (optionOr (listSlice rest3 0 lgFieldsLen) (list))
            lastGates (map (fn [grp] (pair (toInt (arg grp 0)) (gateFromFields (restFrom grp 1)))) (chunks lgFlat 7 (list)))
            rest4 (restFrom rest3 lgFieldsLen)
            nRetriesLeft (toInt (arg rest4 0))
            rest5 (restFrom rest4 1)
            retriesLeft (kvIntsFrom (optionOr (listSlice rest5 0 (* 2 nRetriesLeft)) (list)))
            rest6 (restFrom rest5 (* 2 nRetriesLeft))
            nudge (arg rest6 0) cost (arg rest6 1) plan (arg rest6 2)]
        (c/serString (r/nowForm turn contextTokens win written lastGates retriesLeft nudge cost plan))))
    ((= kind "noWriteNudge")
      (let [deliver (arg fs 0) wrote (boolOf (arg fs 1)) done (toInt (arg fs 2)) nFiles (toInt (arg fs 3))
            rest1 (restFrom fs 4)
            files (optionOr (listSlice rest1 0 nFiles) (list))
            rest2 (restFrom rest1 nFiles)
            nWhole (toInt (arg rest2 0))
            rest3 (restFrom rest2 1)
            whole (map toInt (optionOr (listSlice rest3 0 nWhole) (list)))
            rest4 (restFrom rest3 nWhole)
            readStreak (toInt (arg rest4 0))
            redGateHas (boolOf (arg rest4 1))
            redGate (if redGateHas (some (arg rest4 2)) none)]
        (c/serString (r/noWriteNudge deliver wrote done files whole readStreak redGate))))
    ((= kind "gateNow")
      (c/serString (r/gateNow (toInt (arg fs 0)) (gateFromFields (restFrom fs 1)))))
    ((= kind "buildRetryBrief")
      (let [retryCount (toInt (arg fs 0))
            truncated (boolOf (arg fs 1))
            parseDefectHas (boolOf (arg fs 2))
            parseDefectReply (if parseDefectHas (some (arg fs 3)) none)
            parseFailureWhereHas (boolOf (arg fs 4))
            parseFailureWhere (if parseFailureWhereHas (some (arg fs 5)) none)
            swallowedFileHas (boolOf (arg fs 6))
            swallowedFile (if swallowedFileHas (some (arg fs 7)) none)
            swallowedLine (toInt (arg fs 8))
            swallowedRule (if swallowedFileHas (some (arg fs 9)) none)
            nGates (toInt (arg fs 10))
            rest1 (restFrom fs 11)
            gatesFlat (optionOr (listSlice rest1 0 (* nGates 6)) (list))
            gates (gatesFrom gatesFlat)
            rest2 (restFrom rest1 (* nGates 6))
            placeholderFileHas (boolOf (arg rest2 0))
            placeholderFile (if placeholderFileHas (some (arg rest2 1)) none)
            placeholderLine (toInt (arg rest2 2))
            placeholderText (if placeholderFileHas (some (arg rest2 3)) none)
            rest3 (restFrom rest2 4)
            nMissing (toInt (arg rest3 0))
            rest4 (restFrom rest3 1)
            missingFlat (optionOr (listSlice rest4 0 (* nMissing 2)) (list))
            missingGateFiles (map (fn [grp] (pair (toInt (arg grp 0)) (arg grp 1))) (chunks missingFlat 2 (list)))
            rest5 (restFrom rest4 (* nMissing 2))
            nTurnReceipts (toInt (arg rest5 0))
            rest6 (restFrom rest5 1)
            turnReceiptLines (optionOr (listSlice rest6 0 nTurnReceipts) (list))
            rest7 (restFrom rest6 nTurnReceipts)
            unbackedCount (toInt (arg rest7 0))
            nUnbackedItems (toInt (arg rest7 1))
            rest8 (restFrom rest7 2)
            unbackedItems (optionOr (listSlice rest8 0 nUnbackedItems) (list))
            rest9 (restFrom rest8 nUnbackedItems)
            nUndeclared (toInt (arg rest9 0))
            rest10 (restFrom rest9 1)
            undeclaredLines (optionOr (listSlice rest10 0 nUndeclared) (list))
            rest11 (restFrom rest10 nUndeclared)
            acceptedOpShapesJoined (arg rest11 0)]
        (c/serString (r/buildRetryBrief retryCount truncated parseDefectReply parseFailureWhere
                                         swallowedFile swallowedLine swallowedRule gates
                                         placeholderFile placeholderLine placeholderText
                                         missingGateFiles turnReceiptLines
                                         unbackedCount unbackedItems undeclaredLines acceptedOpShapesJoined))))
    ((= kind "advisorSkip")
      (let [why (arg fs 0) nRetries (toInt (arg fs 1)) rest1 (restFrom fs 2)
            retries (kvIntsFrom (optionOr (listSlice rest1 0 (* 2 nRetries)) (list)))
            rest2 (restFrom rest1 (* 2 nRetries))
            parseDefectCount (toInt (arg rest2 0))]
        (c/serString (r/advisorSkip why retries parseDefectCount))))
    ((= kind "parseAdvice")
      (mt (r/parseAdvice (arg fs 0))
        ((none) "(none)")
        ((some a) (str "(some " (c/serString (r/adviceNext a)) " " (serOptStr (r/adviceWhy a)) " " (serOptStr (r/adviceAvoid a)) ")"))))
    ((= kind "parseSpecVerdict")
      (mt (r/parseSpecVerdict (arg fs 0))
        ((none) "(none)")
        ((some v) (str "(some " (if (r/verdictMet v) "true" "false") " " (serStrList (r/verdictMissing v)) ")"))))
    ((= kind "digestLine")
      (c/serString (r/digestLine (receiptFromFields fs))))
    ((= kind "evidenceDigest")
      (let [cap (toInt (arg fs 0)) nReceipts (toInt (arg fs 1)) rest1 (restFrom fs 2)]
        (c/serString (r/evidenceDigest (receiptsFrom (optionOr (listSlice rest1 0 (* nReceipts 15)) (list))) cap))))
    ((= kind "advisorGateOutput")
      (c/serString (r/advisorGateOutput (gateFromFields fs))))
    ((= kind "advisorOpLine")
      (c/serString (r/advisorOpLine (receiptFromFields fs))))
    ((= kind "advisorSummary")
      (let [task (arg fs 0) deliver (arg fs 1) why (arg fs 2) nGates (toInt (arg fs 3))
            rest1 (restFrom fs 4)
            gates (optionOr (listSlice rest1 0 nGates) (list))
            rest2 (restFrom rest1 nGates)
            nLastGates (toInt (arg rest2 0))
            rest3 (restFrom rest2 1)
            lgLen (* nLastGates 8)
            lgFlat (optionOr (listSlice rest3 0 lgLen) (list))
            lastGates (map (fn [grp] (pair (arg grp 0) (pair (toInt (arg grp 1)) (gateFromFields (restFrom grp 2))))) (chunks lgFlat 8 (list)))
            rest4 (restFrom rest3 lgLen)
            nWritten (toInt (arg rest4 0))
            rest5 (restFrom rest4 1)
            written (optionOr (listSlice rest5 0 nWritten) (list))
            rest6 (restFrom rest5 nWritten)
            nReceipts (toInt (arg rest6 0))
            rest7 (restFrom rest6 1)
            receiptsFlat (optionOr (listSlice rest7 0 (* nReceipts 15)) (list))
            receipts (receiptsFrom receiptsFlat)
            rest8 (restFrom rest7 (* nReceipts 15))
            lastBrief (arg rest8 0)]
        (c/serString (r/advisorSummary task deliver why gates lastGates written receipts lastBrief))))
    ((= kind "extractClaims")
      (let [replyText (arg fs 0)
            isOldCall (= (arg fs 1) "true")
            gatesResult (parseStringList (restFrom fs 2))
            gates (pairFirst gatesResult) afterGates (pairSecond gatesResult)
            checkProse (= (arg afterGates 0) "true")
            gatePassBacked (= (arg afterGates 1) "true")
            planOn (= (arg afterGates 2) "true")
            receiptsResult (parseReceipts (restFrom afterGates 3))
            receipts (pairFirst receiptsResult)]
        (serClaimsResult (cl/extractClaims replyText receipts isOldCall gates checkProse gatePassBacked planOn))))
    ((= kind "receiptBacks")
      (let [rid (arg fs 0)
            hasCE (= (arg fs 1) "true")
            ce (toInt (arg fs 2))
            receiptsResult (parseReceipts (restFrom fs 3))
            receipts (pairFirst receiptsResult)
            ceOpt (if hasCE (some ce) (none))]
        (if (cl/receiptBacks rid ceOpt receipts) "true" "false")))
    ((= kind "isBacked")
      (let [cmdStr (arg fs 0) ce (toInt (arg fs 1))
            receiptsResult (parseReceipts (restFrom fs 2))
            receipts (pairFirst receiptsResult)]
        (if (cl/isBacked cmdStr ce receipts) "true" "false")))
    ((= kind "isProseClaimBacked")
      (let [sentence (arg fs 0)
            receiptsResult (parseReceipts (restFrom fs 1))
            receipts (pairFirst receiptsResult) afterR (pairSecond receiptsResult)
            gatesResult (parseStringList afterR)
            gates (pairFirst gatesResult) afterGates (pairSecond gatesResult)
            gatePassBacked (= (arg afterGates 0) "true")]
        (if (cl/isProseClaimBacked sentence receipts gates gatePassBacked) "true" "false")))
    ((= kind "turnBringsEvidence")
      (let [ops (c/parseReply (arg fs 0))
            receiptsResult (parseReceipts (restFrom fs 1))
            receipts (pairFirst receiptsResult) afterReceipts (pairSecond receiptsResult)
            covResult (parseCoverage afterReceipts)
            coverage0 (pairFirst covResult) afterCov (pairSecond covResult)
            keysResult (parseKeys afterCov)
            seenKeys0 (pairFirst keysResult) afterKeys (pairSecond keysResult)
            mode (arg afterKeys 0) base (arg afterKeys 1) planOn (= (arg afterKeys 2) "true")]
        (serEvidenceUpdate (cl/turnBringsEvidence ops receipts coverage0 seenKeys0 mode base planOn))))
    ((= kind "forgetCutEvidence")
      (let [n (toInt (arg fs 0))
            entriesResult (parseTurnEntriesLoop (restFrom fs 1) n (list))
            entries (pairFirst entriesResult) afterEntries (pairSecond entriesResult)
            wholeResult (parseStringList afterEntries)
            whole (map toInt (pairFirst wholeResult))]
        (serForgetCut (cl/forgetCutEvidence entries whole))))
    ((= kind "isTurnObservation")
      (if (cl/isTurnObservation (c/parseReply (arg fs 0))) "true" "false"))
    ((= kind "unwrapReadTxns")
      (serUnwrap (cl/unwrapReadTxns (c/parseReply (arg fs 0)))))
    ((= kind "mergeFindings")
      (let [form (arg fs 0)
            earlierResult (parseStringList (restFrom fs 1))
            earlier (pairFirst earlierResult)
            mergeResult (cl/mergeFindings form earlier)
            kept (pairFirst mergeResult) replaced (pairSecond mergeResult)]
        (str "(merge :replaced " (stringFromInt64 replaced) " :kept (" (c/joinSep (map c/serString kept) " ") "))")))
    ((= kind "wrongCitationNote")
      (let [n (toInt (arg fs 0))
            claims (buildWrongClaims (restFrom fs 1) n (list))]
        (c/serString (cl/wrongCitationNote claims))))
    ((= kind "hasNegatorNear")
      (if (cl/hasNegatorNear (arg fs 0) (toInt (arg fs 1))) "true" "false"))
    ((= kind "extractProseStrings")
      (let [text (arg fs 0) useOld (= (arg fs 1) "true") planOn (= (arg fs 2) "true")
            keys (if useOld (cl/oldStructuralKeys) (cl/newStructuralKeys))]
        (str "(strings" (c/joinAll (map (fn [s] (str " " (c/serString s))) (cl/extractProseStrings text keys planOn))) ")")))
    ((= kind "collectProseStrings")
      (let [formText (arg fs 0) inEvidence (= (arg fs 1) "true") useOld (= (arg fs 2) "true") planOn (= (arg fs 3) "true")
            keys (if useOld (cl/oldStructuralKeys) (cl/newStructuralKeys))
            out (cl/collectProseStringsInner formText inEvidence keys planOn (list))]
        (str "(strings" (c/joinAll (map (fn [s] (str " " (c/serString s))) out)) ")")))
    ((or (= kind "gateVerdicts") (= kind "gate_verdicts"))
      (let [reverted (= (arg fs 0) "1")
            results (gateResultsFromFields (restFrom fs 1) (list))
            verdicts (g/gateVerdicts results reverted)]
        (str "(verdicts" (c/joinAll (map (fn [v] (str " " (c/serString v))) verdicts)) ")")))
    ((or (= kind "vacuousOutsideOwns") (= kind "vacuous_outside_owns"))
      (let [rootDir (arg fs 0)
            numOwns (toInt (arg fs 1))
            owns (optionOr (listSlice fs 2 (+ 2 numOwns)) (list))
            results (gateResultsFromFields (restFrom fs (+ 2 numOwns)) (list))
            res (g/vacuousOutsideOwns! results owns rootDir)]
        (mt res
          ((some p) (str "(unowned " (c/serString (pairFirst p)) " " (c/serString (pairSecond p)) ")"))
          ((none) "(:none)"))))
    ((or (= kind "isSwallowedExceptLine") (= kind "is_swallowed_except_line"))
      (if (g/isSwallowedExceptLine (arg fs 0)) "true" "false"))
    ((or (= kind "isPassLine") (= kind "is_pass_line"))
      (if (g/isPassLine (arg fs 0)) "true" "false"))
    ((or (= kind "isSingleLineSwallow") (= kind "is_single_line_swallow"))
      (if (g/isSingleLineSwallow (arg fs 0)) "true" "false"))
    ((or (= kind "findSwallowedInAdded") (= kind "find_swallowed_in_added"))
      (let [numLines (toInt (arg fs 0))
            pairs (parsePairs (optionOr (listSlice fs 1 (+ 1 (* 2 numLines))) (list)) (list))
            res (g/findSwallowedInAdded pairs)]
        (str "(lines" (c/joinAll (map (fn [n] (str " " (stringFromInt64 n))) res)) ")")))
    ((or (= kind "scanSwallowed") (= kind "scan_swallowed"))
      (let [isNew (= (arg fs 0) "1")
            oldLines (if isNew (list) (d/splitLinesKeepEnds (arg fs 1)))
            newLines (d/splitLinesKeepEnds (arg fs 2))
            res (g/scanHunkSwallowed! oldLines newLines)]
        (str "(lines" (c/joinAll (map (fn [n] (str " " (stringFromInt64 n))) res)) ")")))
    ((or (= kind "placeholderHit") (= kind "placeholder_hit"))
      (let [numGates (toInt (arg fs 0))
            gateFields (optionOr (listSlice fs 1 (+ 1 (* 6 numGates))) (list))
            results (gateResultsFromFields gateFields (list))
            filesOffset (+ 1 (* 6 numGates))
            numFiles (toInt (arg fs filesOffset))
            filePairs (parseStrPairs (optionOr (listSlice fs (+ filesOffset 1) (+ filesOffset 1 (* 2 numFiles))) (list)) (list))
            res (g/placeholderHit results filePairs)]
        (mt res
          ((some h) (str "(hit " (c/serString (g/hitFile h)) " " (stringFromInt64 (g/hitLine h)) " " (c/serString (g/hitText h)) ")"))
          ((none) "(:none)"))))
    ((or (= kind "missingGatePaths") (= kind "missing_gate_paths"))
      (let [paths (g/missingGatePaths! (arg fs 0) (arg fs 1))]
        (str "(paths" (c/joinAll (map (fn [p] (str " " (c/serString p))) paths)) ")")))
    ((or (= kind "missingGateFiles") (= kind "missing_gate_files"))
      (let [rootDir (arg fs 0)
            results (gateResultsFromFields (restFrom fs 1) (list))
            res (g/missingGateFiles! results rootDir)]
        (str "(missingFiles" (c/joinAll (map (fn [p] (str " (file " (stringFromInt64 (pairFirst p)) " " (c/serString (pairSecond p)) ")")) res)) ")")))
    ((or (= kind "gateRunScripts") (= kind "gate_run_scripts"))
      (let [scripts (g/gateRunScripts fs)]
        (str "(scripts" (c/joinAll (map (fn [s] (str " " (c/serString s))) scripts)) ")")))
    ((or (= kind "gatePartitionFiles") (= kind "gate_changed_files"))
      (let [numChanged (toInt (arg fs 0))
            changed (optionOr (listSlice fs 1 (+ 1 numChanged)) (list))
            scripts (restFrom fs (+ 1 numChanged))
            res (g/gatePartitionFiles changed scripts)]
        (str "(partition (gateFiles" (c/joinAll (map (fn [f] (str " " (c/serString f))) (pairFirst res))) ") (implFiles" (c/joinAll (map (fn [f] (str " " (c/serString f))) (pairSecond res))) "))")))
    ((or (= kind "gateVacuousMessage") (= kind "gate_vacuous_summary"))
      (let [numResults (toInt (arg fs 0))
            gateFields (optionOr (listSlice fs 1 (+ 1 (* 6 numResults))) (list))
            results (gateResultsFromFields gateFields (list))
            verdicts (restFrom fs (+ 1 (* 6 numResults)))
            res (g/gateVacuousMessage results verdicts)]
        (mt res
          ((some msg) (c/serString msg))
          ((none) "(:none)"))))
    ((or (= kind "gateRevertVerdict") (= kind "gate_revert_verdict"))
      (let [numReverted (toInt (arg fs 0))
            reverted (gateResultsFromFields (optionOr (listSlice fs 1 (+ 1 (* 6 numReverted))) (list)) (list))
            offsetV (+ 1 (* 6 numReverted))
            numV (toInt (arg fs offsetV))
            verdicts (optionOr (listSlice fs (+ offsetV 1) (+ offsetV 1 numV)) (list))
            offsetI (+ offsetV 1 numV)
            numI (toInt (arg fs offsetI))
            impl (optionOr (listSlice fs (+ offsetI 1) (+ offsetI 1 numI)) (list))
            offsetN (+ offsetI 1 numI)
            newFiles (restFrom fs (+ offsetN 1))
            res (g/gateRevertVerdict reverted verdicts impl newFiles)]
        (str "(revertVerdict " (if (pairFirst res) "true" "false") " " (c/serString (pairSecond res)) ")")))
    (else (str "ERR_UNKNOWN_KIND " kind)))

fn caseLoop! s: String n: Int64 i: Int64 idx: Int64 -> Int64
  (if (>= i n)
    idx
    (mt (netString s i)
      ((pair kind j)
        (mt (netString s j)
          ((pair count k)
            (mt (netStrings s k (toInt count) (list))
              ((pair fs next)
                (do
                  (println (str (stringFromInt64 idx) " " kind " " (runCase! kind fs)))
                  (caseLoop! s n next (+ idx 1))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (if (listEmpty? args)
    (err "usage: bin/asl run asl/agentLoop/coreCli.asl CORPUS")
    (mt (fileReadString (c/firstOf args))
      ((ok s) (let [(n (caseLoop! s (stringLength s) 0 0))] (ok 0)))
      ((err e) (err e))))
