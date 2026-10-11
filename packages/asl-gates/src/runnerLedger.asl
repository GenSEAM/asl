(module asl-gates/runnerLedger
  :x [parseLedger ledgerAt delta reconcile! receipt makeLedgerEntry makeReconcileCheck makeReconcileResult LedgerEntry ReconcileCheck ReconcileResult]
  :i [(asl-gates/suiteRunner :a sr)])

(schema LedgerEntry
  (:f suite String)
  (:f cause String)
  (:f digest String)
  (:f since String))

(schema ReconcileCheck
  (:f err String)
  (:f suite String)
  (:f ev String))

(schema ReconcileResult
  (:f checks (List ReconcileCheck))
  (:f notEvaluated Int64)
  (:f held Int64))

fn makeLedgerEntry suite: String cause: String digest: String since: String -> LedgerEntry
  (LedgerEntry :suite suite :cause cause :digest digest :since since)

fn makeReconcileCheck err: String suite: String ev: String -> ReconcileCheck
  (ReconcileCheck :err err :suite suite :ev ev)

fn makeReconcileResult checks: (List ReconcileCheck) notEvaluated: Int64 held: Int64 -> ReconcileResult
  (ReconcileResult :checks checks :notEvaluated notEvaluated :held held)

fn parseField rest: String prefix: String -> (Option (Pair String String))
  (if (not (stringStartsWith? rest prefix))
    (none)
    (let [(afterPref (optionOr (stringSlice rest (stringLength prefix) (stringLength rest)) ""))
          (quoteIdx (optionOr (stringIndexOf afterPref "\"") -1))]
      (if (< quoteIdx 0)
        (none)
        (let [(val (optionOr (stringSlice afterPref 0 quoteIdx) ""))
              (remainder (optionOr (stringSlice afterPref quoteIdx (stringLength afterPref)) ""))]
          (some (pair val remainder))))))

fn parseLedgerLine line: String -> (Option LedgerEntry)
  (let [(trimmed (stringTrim line))]
    (mt (parseField trimmed "(:suite \"")
      ((none) (none))
      ((some p1)
       (let [(suite (pairFirst p1))]
         (if (stringEmpty? suite)
           (none)
           (mt (parseField (pairSecond p1) "\" :cause \"")
             ((none) (none))
             ((some p2)
              (let [(cause (pairFirst p2))]
                (if (stringEmpty? cause)
                  (none)
                  (mt (parseField (pairSecond p2) "\" :failedAssertDigest \"")
                    ((none) (none))
                    ((some p3)
                     (mt (parseField (pairSecond p3) "\" :since \"")
                       ((none) (none))
                       ((some p4)
                        (if (stringStartsWith? (pairSecond p4) "\")")
                          (some (LedgerEntry :suite suite :cause cause :digest (pairFirst p3) :since (pairFirst p4)))
                          (none)))))))))))))))

fn parseLedger text: String -> (List LedgerEntry)
  (let [(lines (stringLines text))]
    (fold (fn [(acc (List LedgerEntry)) (line String)] -> (List LedgerEntry)
            (mt (parseLedgerLine line)
              ((none) acc)
              ((some entry) (listAppend acc (list entry)))))
          (list)
          lines))

fn ! ledgerAt root: String rev: (Option String) -> (Result (List LedgerEntry) String)
  (mt rev
    ((none)
     (let [(path (str root "/.asl/mem/knownRed.asn"))]
       (if (not (sr/isFile! path))
         (ok (list))
         (resultMap (fileReadString path) parseLedger))))
    ((some r)
     (mt (sr/gitRun! root (list "show" (str r ":.asl/mem/knownRed.asn")))
       ((err e) (err e))
       ((ok d) (ok (if (= d.code 0) (parseLedger d.out) (list)))))))

fn entryKey e: LedgerEntry -> String
  (str e.suite "|" e.cause "|" e.digest)

fn hasKey? entries: (List LedgerEntry) k: String -> Bool
  (fold (fn [(acc Bool) (e LedgerEntry)] -> Bool
          (or acc (= (entryKey e) k)))
        false
        entries)

fn delta base: (List LedgerEntry) now: (List LedgerEntry) -> String
  (let [(added (filter (fn [(e LedgerEntry)] -> Bool (not (hasKey? base (entryKey e)))) now))
        (removed (filter (fn [(e LedgerEntry)] -> Bool (not (hasKey? now (entryKey e)))) base))
        (parts1 (list "(:knownRedDelta"))
        (parts2 (if (listEmpty? added)
                  parts1
                  (let [(items (map (fn [(e LedgerEntry)] -> String
                                      (str "(:suite \"" (sr/esc e.suite 400) "\" :cause \"" (sr/esc e.cause 400) "\" :confirmation :unverified)"))
                                    added))]
                    (listAppend parts1 (list (str "(:added " (stringJoin items " ") ")"))))))
        (parts3 (if (listEmpty? removed)
                  parts2
                  (let [(items (map (fn [(e LedgerEntry)] -> String
                                      (str "(:suite \"" (sr/esc e.suite 400) "\" :cause \"" (sr/esc e.cause 400) "\")"))
                                    removed))]
                    (listAppend parts2 (list (str "(:removed " (stringJoin items " ") ")"))))))]
    (str (stringJoin parts3 " ") ")"))

fn findSuiteEntries ledger: (List LedgerEntry) suite: String -> (List LedgerEntry)
  (filter (fn [(e LedgerEntry)] -> Bool (= e.suite suite)) ledger)

fn hasMatchingFailure entries: (List LedgerEntry) cause: String digest: String -> Bool
  (fold (fn [(acc Bool) (e LedgerEntry)] -> Bool
          (or acc (and (= e.cause cause) (= e.digest digest))))
        false
        entries)

fn reconcile! results: (List sr/SuiteResult) ledger: (List LedgerEntry) root: String -> ReconcileResult
  (let [(ran (map (fn [(r sr/SuiteResult)] -> String r.suite) results))
        (step1 (fold (fn [(acc (Pair (List ReconcileCheck) Int64)) (r sr/SuiteResult)] -> (Pair (List ReconcileCheck) Int64)
                       (let [(chkList (pairFirst acc))
                             (heldCount (pairSecond acc))
                             (entries (findSuiteEntries ledger r.suite))]
                         (cond
                           ((= r.cause "OK")
                            (if (not (listEmpty? entries))
                              (pair (cons (ReconcileCheck :err "ERR_STALE_KNOWN_RED" :suite r.suite :ev "listed in knownRed but passed") chkList) heldCount)
                              acc))
                           ((hasMatchingFailure entries r.cause r.digest)
                            (pair chkList (+ heldCount 1)))
                           (else
                             (let [(baseErr (cond
                                              ((= r.cause "ERR_VACUOUS_SUITE") "ERR_VACUOUS_SUITE")
                                              ((= r.cause "ERR_DECLARED_GAP") "ERR_DECLARED_GAP")
                                              ((= r.cause "ERR_TIMEOUT") "ERR_TIMEOUT")
                                              (else "ERR_NEW_RED_SUITE")))
                                   (sig0 (str r.cause " " r.digest " " r.failLine))
                                   (err (if (not (listEmpty? entries))
                                          (if (= baseErr "ERR_NEW_RED_SUITE") "ERR_KNOWN_RED_DRIFT" baseErr)
                                          baseErr))
                                   (sig (if (not (listEmpty? entries))
                                          (str sig0 " (knownRed signature differs)")
                                          sig0))]
                               (pair (cons (ReconcileCheck :err err :suite r.suite :ev sig) chkList) heldCount))))))
                     (pair (list) 0)
                     results))
        (resChecks (pairFirst step1))
        (held (pairSecond step1))
        (step2 (fold (fn [(acc (Pair (List ReconcileCheck) Int64)) (e LedgerEntry)] -> (Pair (List ReconcileCheck) Int64)
                       (let [(chkList (pairFirst acc))
                             (notEvalCount (pairSecond acc))]
                         (if (listContains? ran e.suite)
                           acc
                           (let [(fullPath (if (stringEmpty? root) e.suite (str root "/" e.suite)))]
                             (if (not (sr/isFile! fullPath))
                               (pair (cons (ReconcileCheck :err "ERR_STALE_KNOWN_RED" :suite e.suite :ev "knownRed entry names no suite file") chkList) notEvalCount)
                               (pair chkList (+ notEvalCount 1)))))))
                     (pair resChecks 0)
                     ledger))]
    (ReconcileResult :checks (listReverse (pairFirst step2))
                     :notEvaluated (pairSecond step2)
                     :held held))

fn receipt results: (List sr/SuiteResult) checks: (List ReconcileCheck) notEvaluated: Int64 held: Int64 deltaForm: String excluded: String scope: String frozen: Int64 -> (Pair String Bool)
  (let [(passed (and (listEmpty? checks) (not (listEmpty? results))))
        (status (if passed ":passed" ":failed"))
        (passedSuites (fold (fn [(acc Int64) (r sr/SuiteResult)] -> Int64
                              (if (= r.cause "OK") (+ acc 1) acc))
                            0
                            results))
        (executedAsserts (fold (fn [(acc Int64) (r sr/SuiteResult)] -> Int64 (+ acc r.asserts)) 0 results))
        (executedRefutes (fold (fn [(acc Int64) (r sr/SuiteResult)] -> Int64 (+ acc r.refutes)) 0 results))
        (declaredAsserts (fold (fn [(acc Int64) (r sr/SuiteResult)] -> Int64 (+ acc r.declared)) 0 results))
        (head (str "(:runner :status " status " :scope " scope " :suites " (stringFromInt64 (listLength results))
                   " :passedSuites " (stringFromInt64 passedSuites)
                   " :knownRedHeld " (stringFromInt64 held)
                   " :notEvaluated " (stringFromInt64 notEvaluated)
                   " :executedAsserts " (stringFromInt64 executedAsserts)
                   " :executedRefutes " (stringFromInt64 executedRefutes)
                   " :declaredAsserts " (stringFromInt64 declaredAsserts)
                   " :frozen " (stringFromInt64 frozen)))
        (parts1 (list head))
        (parts2 (if (listEmpty? results)
                  (cons "(:check :id discovery :status :failed :err ERR_NO_SUITES :ev \"no suite discovered in scope\")" parts1)
                  parts1))
        (parts3 (fold (fn [(acc (List String)) (c ReconcileCheck)] -> (List String)
                        (cons (str "(:check :id suite :status :failed :err " c.err
                                   " :suite \"" (sr/esc c.suite 400)
                                   "\" :ev \"" (sr/esc c.ev 400) "\")")
                              acc))
                      parts2
                      checks))
        (parts4 (cons deltaForm parts3))
        (parts5 (cons excluded parts4))
        (text (str (stringJoin (listReverse parts5) " ") ")"))]
    (pair text passed))
