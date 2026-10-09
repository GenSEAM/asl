(module asl/agentLoop/tests/contextParityTest
  :x [runTests]
  :i [(asl/agentLoop/context :a x) (asl/agentLoop/tests/parity :a pa) (asl/agentLoop/plan :a p) (asl/agentLoop/core :a c)
      (asl-json/json :a j) (asl-proc/coreProcess :a cp)])

fn head n: p/SexpNode -> String
  (mt n ((p/sexpList xs) (mt (listHead xs) ((some h) (mt h ((p/sexpAtom a) a) (_ ""))) (none ""))) (_ ""))

fn toJson n: p/SexpNode -> j/Json
  (mt n
    ((p/sexpStr s) (j/jstr s))
    ((p/sexpAtom a)
      (cond
        ((= a "nil") (j/jnull))
        ((= a "true") (j/jbool true))
        ((= a "false") (j/jbool false))
        (else (j/jint (optionOr (stringToInt64 a) 0)))))
    ((p/sexpList xs)
      (let [h (head n)]
        (cond
          ((= h "l") (j/jarr (map toJson (pa/argItems n))))
          ((= h "d") (j/jobj (map (fn [kv] (let [ps (pa/argItems (p/sexpList (cons (p/sexpAtom "k") (mt kv ((p/sexpList ys) ys) (_ (list))))))]
                                               (pair (pa/argStr (pa/argAt ps 0)) (toJson (pa/argAt ps 1)))))
                              (pa/argItems n))))
          ((= h "f") (j/jfloat (floatOf (pa/argStr (pa/argAt (pa/argItems n) 0)))))
          (else (j/jstr (pa/argStr n)))))))

fn floatOf s: String -> Float64
  (cond
    ((= s "inf") (/ 1.0 0.0))
    ((= s "-inf") (/ -1.0 0.0))
    (else (optionOr (stringToFloat64 s) 0.0)))

fn arg args: (List p/SexpNode) i: Int64 -> p/SexpNode
  (pa/argAt args i)

fn aJ args: (List p/SexpNode) i: Int64 -> j/Json
  (toJson (arg args i))

fn aS args: (List p/SexpNode) i: Int64 -> String
  (pa/argStr (arg args i))

fn aI args: (List p/SexpNode) i: Int64 -> Int64
  (pa/argInt (arg args i))

fn aB args: (List p/SexpNode) i: Int64 -> Bool
  (pa/argBool (arg args i))

fn aOS args: (List p/SexpNode) i: Int64 -> (Option String)
  (pa/argOptStr (arg args i))

fn aJs args: (List p/SexpNode) i: Int64 -> (List j/Json)
  (map toJson (pa/argItems (arg args i)))

fn aSs args: (List p/SexpNode) i: Int64 -> (List String)
  (pa/argStrs (arg args i))

fn pairsOf n: p/SexpNode -> (List (Pair String p/SexpNode))
  (map (fn [kv] (let [ps (pa/argItems (p/sexpList (cons (p/sexpAtom "l") (pa/argItems kv))))]
                  (pair (pa/argStr (pa/argAt ps 0)) (pa/argAt ps 1))))
    (pa/argItems n))

fn intPairs n: p/SexpNode -> (List (Pair String Int64))
  (map (fn [pr] (pair (pairFirst pr) (pa/argInt (pairSecond pr)))) (pairsOf n))

fn objOf n: p/SexpNode -> j/Json
  (j/jobj (map (fn [pr] (pair (pairFirst pr) (toJson (pairSecond pr)))) (pairsOf n)))

fn sF f: Float64 -> String
  (str "(f \"" (x/floatRepr f) "\")")

fn sJ v: j/Json -> String
  (mt v
    ((j/jnull) "nil")
    ((j/jbool b) (pa/sBool b))
    ((j/jint i) (pa/sInt i))
    ((j/jfloat f) (sF f))
    ((j/jnum f) (sF f))
    ((j/jstr s) (pa/sStr s))
    ((j/jarr xs) (pa/sList (map sJ xs)))
    ((j/jobj kvs) (pa/sDict (map (fn [pr] (pair (pairFirst pr) (sJ (pairSecond pr)))) kvs))))

fn sSite s: (Pair String Int64) -> String
  (pa/sList (list (pa/sStr (pairFirst s)) (pa/sInt (pairSecond s))))

fn sReview r: x/Review -> String
  (mt r
    ((x/reviewError m) (pa/sDict (list (pair "error" (pa/sStr m)))))
    ((x/reviewVerdict met missing) (pa/sDict (list (pair "met" (pa/sBool met)) (pair "missing" (pa/sStrs missing))))))

fn sAdvice a: x/AdviceForm -> String
  (mt a
    ((x/adviceOf n why avoid)
      (pa/sDict (listAppend (list (pair "next" (pa/sStr n)))
                  (listAppend (mt why ((some w) (list (pair "why" (pa/sStr w)))) (none (list)))
                              (mt avoid ((some v) (list (pair "avoid" (pa/sStr v)))) (none (list))))))))

fn optJStr v: j/Json -> (Option String)
  (mt v ((j/jstr s) (some s)) (_ none))


fn subRoot s: String root: String -> String
  (stringReplace s "@ROOT@" root)

fn subRootJ v: j/Json root: String -> j/Json
  (mt v
    ((j/jstr s) (j/jstr (subRoot s root)))
    ((j/jarr xs) (j/jarr (map (fn [y] (subRootJ y root)) xs)))
    ((j/jobj kvs) (j/jobj (map (fn [pr] (pair (pairFirst pr) (subRootJ (pairSecond pr) root))) kvs)))
    (_ v))

fn ! run! root: String bin: String args: (List String) -> Bool
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd bin args) root) 60000))
    ((ok out) (if (= out.exitCode 0) true (do (eprintln (str "setup: " bin " exits " (stringFromInt64 out.exitCode) ": " out.stderr)) false)))
    ((err _) (do (eprintln (str "setup: " bin " does not spawn")) false)))

fn ! freshDir! -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        dir (str base "/u6ctxasl_" (stringFromInt64 (nowNs)) "_" (stringFromInt64 (monotonicNs)))]
    (do (dirCreate dir) (resultOr (realPath dir) dir)))

fn parentOf p: String -> String
  (let [parts (stringSplit p "/")]
    (c/joinSep (listTake parts (- (listLength parts) 1)) "/"))

fn ! buildTree! steps: p/SexpNode -> String
  (let [root (freshDir!)]
    (do
      (fold (fn [acc st]
              (let [xs (pa/argItems (p/sexpList (cons (p/sexpAtom "l") (pa/argItems st))))
                    kind (pa/argStr (pa/argAt xs 0))]
                (cond
                  ((= kind "write")
                    (let [full (str root "/" (pa/argStr (pa/argAt xs 1)))]
                      (do (dirCreate (parentOf full)) (fileWrite full (pa/argStr (pa/argAt xs 2))) acc)))
                  ((= kind "chmod") (do (run! root "chmod" (list (pa/argStr (pa/argAt xs 2)) (pa/argStr (pa/argAt xs 1)))) acc))
                  ((= kind "init") (do (run! root "git" (list "init" "-q")) acc))
                  ((= kind "commit")
                    (do (run! root "git" (list "add" "-A"))
                        (run! root "git" (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false" "commit" "-q" "-m" "m"))
                        acc))
                  (else acc))))
        0 (pa/argItems steps))
      root))

fn ! dropTree! root: String -> Bool
  (ok? (pathRemove root))

fn digestOf intent: String system: String user: String -> String
  (str intent "|" (stringFromInt64 (stringLength system)) "|" (stringFromInt64 (stringLength user)) "|"
    (bytesSha256 (stringToBytes (str system "\n--\n" user))))

fn fakeReply kind: String form: String -> (Result (Option String) String)
  (cond
    ((= kind "digest") (ok (some form)))
    ((stringStartsWith? kind "reply:") (ok (some (c/sliceOf kind 6 (stringLength kind)))))
    ((= kind "none") (ok none))
    ((stringStartsWith? kind "raise:") (err (c/sliceOf kind 6 (stringLength kind))))
    (else (err (str "unknown fake " kind))))

fn fakeAsk kind: String -> (fn [String String String] -> (Result (Option String) String))
  (fn [intent system user] (fakeReply kind (str "(:verdict :met false :missing (\"" (digestOf intent system user) "\"))")))

fn fakeAdvise kind: String -> (Option (fn [String String] -> (Result (Option String) String)))
  (if (= kind "absent")
    none
    (some (fn [system user] (fakeReply kind (str "(:advice :next \"" (digestOf "auto" system user) "\" :why \"w\")")))))

fn fakeOutline form: String -> (Pair Int64 String)
  (cond
    ((stringContains? form "fail") (pair 1 ""))
    ((stringContains? form "empty") (pair 0 "(:outline)"))
    (else (pair 0 (str "(:intel (:item :name \"n" (c/sliceOf (bytesSha256 (stringToBytes form)) 0 12) "\" :kind \"fn\" :start 1 :end "
                    (stringFromInt64 (c/charLen form)) ") (:item :name \"g\\\"h\" :kind \"cls\" :start 5 :end 9) (:item :name \"bad\" :kind \"x-y\" :start 1 :end 2))"))))

fn lastGatesOf n: p/SexpNode -> (List (Pair String (Pair j/Json j/Json)))
  (map (fn [pr] (let [v (pa/argItems (pairSecond pr))] (pair (pairFirst pr) (pair (toJson (pa/argAt v 0)) (toJson (pa/argAt v 1))))))
    (pairsOf n))

fn lastGatesTurn n: p/SexpNode -> (List (Pair String (Pair Int64 j/Json)))
  (map (fn [pr] (let [v (pa/argItems (pairSecond pr))] (pair (pairFirst pr) (pair (pa/argInt (pa/argAt v 0)) (toJson (pa/argAt v 1))))))
    (pairsOf n))

fn coverageOf n: p/SexpNode -> (List (Pair String (List (Pair Int64 Int64))))
  (map (fn [pr] (pair (pairFirst pr) (map (fn [sp] (let [ab (pa/argInts sp)] (pair (optionOr (listGet ab 0) 0) (optionOr (listGet ab 1) 0))))
                                        (pa/argItems (pairSecond pr)))))
    (pairsOf n))

fn winOf n: p/SexpNode -> (Option (List Int64))
  (if (pa/argNil? n) none (some (pa/argInts n)))

fn siteOf n: p/SexpNode -> (Pair String Int64)
  (let [xs (pa/argItems n)] (pair (pa/argStr (pa/argAt xs 0)) (pa/argInt (pa/argAt xs 1))))

fn evidenceOf n: p/SexpNode -> (List (Pair Int64 (List (Pair String (Pair Int64 Int64)))))
  (map (fn [e] (let [xs (pa/argItems e)]
                 (pair (pa/argInt (pa/argAt xs 0))
                   (map (fn [it] (let [ys (pa/argItems it)
                                       se (pa/argInts (pa/argAt ys 1))]
                                   (pair (pa/argStr (pa/argAt ys 0)) (pair (optionOr (listGet se 0) 0) (optionOr (listGet se 1) 0)))))
                     (pa/argItems (pa/argAt xs 1))))))
    (pa/argItems n))

fn bulkReceipts n: Int64 unit: String reps: Int64 -> (List j/Json)
  (map (fn [i] (j/jobj (list (pair "id" (j/jstr (str "r" (stringFromInt64 i)))) (pair "op" (j/jstr "read"))
                             (pair "file" (j/jstr (str "src/f" (stringFromInt64 i) ".py"))) (pair "content" (j/jstr (stringRepeat unit reps))))))
    (range 0 n))

fn ! hiddenFor raw: p/SexpNode env: p/SexpNode root: String -> (List (Pair String String))
  (if (pa/argNil? raw)
    (list)
    (map (fn [nm] (pair nm (fold (fn [acc pr] (if (= (pairFirst pr) nm) (subRoot (pa/argStr (pairSecond pr)) root) acc))
                              (optionOr (envGet nm) "") (pairsOf env))))
      (x/hiddenVars (pa/argStr raw))))


fn ! dispatchA f: String a: (List p/SexpNode) -> String
  (cond
    ((= f "vendorBounds")
      (let [t (arg a 0) q (arg a 1)
            miss (fn [n] (if (= (pa/argStr n) "missing") (j/jnull) (toJson n)))]
        (mt (x/vendorBounds (miss t) (miss q)) ((some b) (pa/sList (list (pa/sInt (pairFirst b)) (pa/sInt (pairSecond b))))) (none "nil"))))
    ((= f "fitVendorCall")
      (let [bs (pa/argInts (arg a 0))
            bounds (if (listEmpty? bs) none (some (pair (optionOr (listGet bs 0) 0) (optionOr (listGet bs 1) 0))))
            r (x/fitVendorCall bounds (aI a 1))
            tq (optionOr (pairSecond r) (pair (aI a 2) (aI a 3)))]
        (pa/sList (list (pa/sBool (pairFirst r)) (pa/sInt (pairFirst tq)) (pa/sInt (pairSecond tq))))))
    ((= f "contextTooLong")
      (let [e (x/contextTooLong (aS a 0))]
        (pa/sDict (list (pair "code" (pa/sStr (x/contextTooLongCode))) (pair "message" (pa/sStr (x/contextTooLongMessage e)))))))
    ((= f "contextTokensFor") (pa/sInt (x/contextTokensFor (optJStr (aJ a 0)) (aJ a 1) (aB a 2))))
    ((= f "modelBase") (pa/sStr (x/modelBase (aJ a 0))))
    ((= f "calibrationIndexPath") (pa/sStr (x/calibrationIndexPath (aOS a 0) (aS a 1))))
    ((= f "servedContextTokens")
      (let [dir (freshDir!)
            path (str dir "/index.asn")
            wrote (if (pa/argNil? (arg a 2)) true (ok? (fileWrite path (aS a 2))))
            r (x/servedContextTokens! (aJ a 0) (aB a 1) path)]
        (do (dropTree! dir) (if wrote (pa/sOptInt r) "write failed"))))
    ((= f "readPayloadChars") (pa/sInt (x/readPayloadChars (aI a 0))))
    ((= f "renderTranscript")
      (pa/sStr (x/renderTranscript (aJs a 0) (if (pa/argNil? (arg a 1)) 24000 (aI a 1)))))
    ((= f "renderTurnContext")
      (let [r (x/renderTurnContext (if (pa/argNil? (arg a 0)) none (some (coverageOf (arg a 0)))) (aJs a 1) (aI a 2))]
        (pa/sList (list (pa/sOpt (pairFirst r)) (pa/sStr (pairSecond r))))))
    ((= f "renderWindow")
      (let [r (x/renderWindow (coverageOf (arg a 0)) (aJs a 1) (aI a 2) (aI a 3) (aI a 4) (map stringFromInt64 (pa/argInts (arg a 5))))]
        (pa/sList (list (pa/sStr (pairFirst r)) (sJ (pairSecond r))))))
    ((= f "stableSectionAt") (pa/sStr (x/stableSectionAt (aS a 0) (aS a 1) (aI a 2))))
    ((= f "stableWindowTurn") (pa/sOptInt (x/stableWindowTurn (aS a 0) (aI a 1) (aI a 2))))
    ((= f "gateNow") (pa/sStr (x/gateNow (aJ a 0) (aJ a 1))))
    ((= f "noWriteNudge") (pa/sStr (x/noWriteNudge (aOS a 0) (aB a 1) (aI a 2) (aSs a 3) (winOf (arg a 4)) (aI a 5) (aJ a 6))))
    ((= f "batchingRates") (let [r (x/batchingRates (aJ a 0))] (pa/sList (list (sF (pairFirst r)) (sF (pairSecond r))))))
    ((= f "costForm") (pa/sStr (x/costForm (aJ a 0) (aJ a 1) (floatOf (pa/argStr (pa/argAt (pa/argItems (arg a 2)) 0))) (aI a 3))))
    ((= f "reinforceWhyFor")
      (pa/sStr (x/reinforceWhyFor (aJ a 0) (map pa/argStrs (pa/argItems (arg a 1))) (aOS a 2) (aB a 3) (aI a 4) (aI a 5) (aI a 6)
                 (intPairs (arg a 7)) (aI a 8) (intPairs (arg a 9)) (aI a 10) (aI a 11) (aJ a 12))))
    ((= f "escalationNear")
      (pa/sStr (x/escalationNear (aI a 0) (aI a 1) (intPairs (arg a 2)) (aI a 3) (intPairs (arg a 4)) (aI a 5) (aI a 6) (aB a 7) (aI a 8) (aB a 9))))
    ((= f "nowForm")
      (pa/sStr (x/nowForm (aI a 0) (aJ a 1) (aJ a 2) (aSs a 3) (lastGatesOf (arg a 4)) (intPairs (arg a 5)) (aS a 6) (aS a 7) (aS a 8))))
    ((= f "stepState")
      (let [root (buildTree! (arg a 0))
            r (x/stepState! (subRootJ (aJ a 1) root) (some root) (aJ a 2))]
        (do (dropTree! root) (sJ r))))
    ((= f "spanHolder")
      (mt (x/spanHolder (aJ a 0) (evidenceOf (arg a 1)) (pa/argInts (arg a 2)))
        ((some r) (pa/sList (list (pa/sInt (pairFirst r)) (pa/sList (list (pa/sInt (pairFirst (pairSecond r))) (pa/sInt (pairSecond (pairSecond r))))))))
        (none "nil")))
    ((= f "seenReceipt") (sJ (x/seenReceipt (aJ a 0) (aJ a 1) "rid000000000")))
    ((= f "failureSignatures") (pa/sStrs (x/failureSignatures (aJs a 0) (aJs a 1))))
    ((= f "coreDelta") (sJ (x/coreDelta (aJ a 0) (aJ a 1))))
    ((= f "coreStatsLine") (pa/sStr (x/coreStatsLine (aJ a 0))))
    (else (dispatchB f a)))

fn ! dispatchB f: String a: (List p/SexpNode) -> String
  (cond
    ((= f "formEnd") (pa/sInt (x/formEnd (aS a 0) (aI a 1))))
    ((= f "sitePath") (pa/sStr (x/sitePath (aJ a 0) (aJ a 1))))
    ((= f "possibleSitesOf") (pa/sList (map sSite (x/possibleSitesOf (aJ a 0) (aJ a 1)))))
    ((= f "readCovers")
      (mt (x/readCovers (aJ a 0) (aJ a 1) (aJ a 2))
        ((some cv) (mt cv ((x/coverOf path first last)
                            (pa/sList (list (pa/sStr path) (pa/sInt first) (mt last ((some l) (pa/sInt l)) (none "(f \"inf\")")))))))
        (none "nil")))
    ((= f "siteNamed") (pa/sBool (x/siteNamed (siteOf (arg a 0)) (aS a 1))))
    ((= f "openPossible")
      (pa/sList (map sSite (x/openPossible (map (fn [e] (let [xs (pa/argItems e)] (pair (siteOf (pa/argAt xs 0)) (pa/argBool (pa/argAt xs 1)))))
                                              (pa/argItems (arg a 0)))))))
    ((= f "findingsRun") (pa/sBool (x/findingsRun (aOS a 0) (aSs a 1))))
    ((= f "possibleSiteList") (pa/sStr (x/possibleSiteList (map siteOf (pa/argItems (arg a 0))))))
    ((= f "possibleNotice") (pa/sStr (x/possibleNotice (map siteOf (pa/argItems (arg a 0))))))
    ((= f "prefetchPaths")
      (let [root (buildTree! (arg a 0))
            r (x/prefetchPaths! (aOS a 1) (aSs a 2) root (hiddenFor (arg a 3) (arg a 4) root))]
        (do (dropTree! root) (pa/sStrs r))))
    ((= f "prefetchBlock")
      (let [root (buildTree! (arg a 0))
            r (x/prefetchBlock! (aOS a 1) (aSs a 2) root (aI a 3) (aI a 4) (list) fakeOutline)]
        (do (dropTree! root)
            (pa/sList (list (pa/sStr (pairFirst r)) (pa/sList (map (fn [kr] (pa/sList (list (pa/sStr (pairFirst kr)) (pa/sStr (pairSecond kr))))) (pairSecond r))))))))
    ((= f "receiptPhase") (pa/sOpt (x/receiptPhase (aJ a 0))))
    ((= f "taskHintLines") (pa/sStr (x/taskHintLines (aOS a 0) (aOS a 1))))
    ((= f "unmetForm") (pa/sStr (x/unmetForm (aOS a 0) (aB a 1) (aB a 2) (aSs a 3))))
    ((= f "specUnescape") (pa/sStr (x/specUnescape (aS a 0))))
    ((= f "specCheckDiff")
      (let [root (buildTree! (arg a 0))
            r (x/specCheckDiff! root (aOS a 1) (map (fn [w] (subRoot w root)) (aSs a 2)))]
        (do (dropTree! root) (mt r ((ok d) (pa/sStr d)) ((err e) (str "tool error: " e))))))
    ((= f "parseSpecVerdict")
      (mt (x/parseSpecVerdict (optJStr (aJ a 0)))
        ((some v) (pa/sDict (list (pair "met" (pa/sBool (pairFirst v))) (pair "missing" (pa/sStrs (pairSecond v))))))
        (none "nil")))
    ((= f "digestLine") (pa/sStr (x/digestLine (aJ a 0))))
    ((= f "evidenceDigest") (pa/sStr (x/evidenceDigest (aJs a 0) (if (pa/argNil? (arg a 1)) 12000 (aI a 1)))))
    ((= f "evidenceDigestBulk")
      (let [t0 (monotonicNs)
            r (x/evidenceDigest (bulkReceipts (aI a 0) (aS a 1) (aI a 2)) (aI a 3))
            ms (/ (- (monotonicNs) t0) 1000000)]
        (do (assert (< ms 60000) (str "bulk digest of " (stringFromInt64 (aI a 0)) " receipts took " (stringFromInt64 ms) " ms"))
            (pa/sStr r))))
    ((= f "runSpecCheck")
      (let [root (buildTree! (arg a 0))
            lg (if (pa/argNil? (arg a 8)) (j/jobj (list)) (objOf (arg a 8)))
            r (x/runSpecCheck! (fakeAsk (aS a 1)) (aOS a 2) root (aOS a 3) (map (fn [w] (subRoot w root)) (aSs a 4)) (aSs a 5) (aJs a 6) (aSs a 7) lg)]
        (do (dropTree! root) (mt r ((ok v) (sReview v)) ((err e) (str "tool error: " e))))))
    ((= f "askReviewer") (sReview (x/askReviewer! (fakeAsk (aS a 0)) (aS a 1) (aS a 2))))
    ((= f "runFindingsCheck") (sReview (x/runFindingsCheck! (fakeAsk (aS a 0)) (aOS a 1) (aSs a 2) (aJs a 3))))
    ((= f "advisorSkip") (pa/sStr (x/advisorSkip (aOS a 0) (intPairs (arg a 1)) (aI a 2))))
    ((= f "advisorGateOutput") (pa/sStr (x/advisorGateOutput (aJ a 0))))
    ((= f "advisorOpLine") (pa/sStr (x/advisorOpLine (aJ a 0))))
    ((= f "advisorSummary")
      (pa/sStr (x/advisorSummary (aOS a 0) (aOS a 1) (aOS a 2) (aSs a 3) (lastGatesTurn (arg a 4)) (aSs a 5) (aJs a 6) (aOS a 7))))
    ((= f "parseAdvice") (mt (x/parseAdvice (optJStr (aJ a 0))) ((some v) (sAdvice v)) (none "nil")))
    ((= f "askAdvisor")
      (mt (x/askAdvisor! (fakeAdvise (aS a 0)) (aS a 1))
        ((x/advisorSkipped w) (pa/sDict (list (pair "skip" (pa/sStr w)))))
        ((x/advisorError m) (pa/sDict (list (pair "error" (pa/sStr m)))))
        ((x/advisorAdvice v) (sAdvice v))))
    ((= f "adviceNotice")
      (let [d (aJ a 0)]
        (pa/sStr (x/adviceNotice (x/adviceOf (x/pyStr (x/jgetOr d "next")) (optJStr (x/jgetOr d "why")) (optJStr (x/jgetOr d "avoid")))))))
    ((= f "emitProgress") (pa/sStr (mt (x/progressLine (aJ a 0)) ((some l) (str l "\n")) (none ""))))
    (else (str "(unknown fn " f ")")))

fn portedFns -> (List String)
  (list "vendorBounds" "fitVendorCall" "contextTooLong" "contextTokensFor" "modelBase" "calibrationIndexPath" "servedContextTokens"
        "readPayloadChars" "renderTranscript" "renderTurnContext" "renderWindow" "stableSectionAt" "stableWindowTurn" "gateNow"
        "noWriteNudge" "batchingRates" "costForm" "reinforceWhyFor" "escalationNear" "nowForm" "stepState" "spanHolder" "seenReceipt"
        "failureSignatures" "coreDelta" "coreStatsLine" "formEnd" "sitePath" "possibleSitesOf" "readCovers" "siteNamed" "openPossible"
        "findingsRun" "possibleSiteList" "possibleNotice" "prefetchPaths" "prefetchBlock" "receiptPhase" "taskHintLines" "unmetForm"
        "specUnescape" "specCheckDiff" "parseSpecVerdict" "runSpecCheck" "digestLine" "evidenceDigest" "askReviewer" "runFindingsCheck"
        "advisorSkip" "advisorGateOutput" "advisorOpLine" "advisorSummary" "parseAdvice" "askAdvisor" "adviceNotice" "emitProgress"
        "evidenceDigestBulk")

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        path (str root "/asl/agentLoop/tests/contextParityFixtures.asn")
        passed (pa/replay! path (portedFns) (fn [f a] (dispatchA f a)))]
    (do
      (assert (= (x/pyStrip "  reply　") "reply") "pyStrip follows Python Unicode whitespace stripping")
      (assert (>= passed 300) (str "context parity: " (stringFromInt64 passed) " cases passed"))
      true))
