(module asl/agentLoop/tests/replyParityTest
  :x [runTests]
  :i [(asl/agentLoop/reply :a r) (asl/agentLoop/core :a c) (asl/agentLoop/plan :a p) (asl/agentLoop/tests/parity :a t) (asl-proc/coreProcess :a cp)])

enum Env
  (env root: String repo: String norepo: String head: String)

fn resolve e: Env s: String -> String
  (mt e ((env root repo norepo head)
    (let [h (fn [k] (c/sliceOf head 0 (min k (stringLength head))))]
      (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s
        "$HEAD7UP" (stringUpper (h 7))) "$HEAD40" head) "$HEAD7" (h 7)) "$HEAD6" (h 6)) "$NOREPO" norepo) "$REPO" repo) "$ROOT" root))))

fn unroot e: Env s: String -> String
  (mt e ((env root _ _ _) (stringReplace s root "$ROOT")))

fn chars s: String off: Int64 -> Int64
  (r/charsBefore s off)

fn sSpan s: String sp: (Pair Int64 Int64) -> String
  (t/sList (list (t/sInt (chars s (pairFirst sp))) (t/sInt (chars s (pairSecond sp)))))

fn sSpans s: String xs: (List (Pair Int64 Int64)) -> String
  (t/sList (map (fn [sp] (sSpan s sp)) xs))

fn sVal v: c/KvVal -> String
  (mt v
    ((c/kvStr x) (t/sStr x))
    ((c/kvInt x) (mt (stringToInt64 x) ((some i) (t/sInt i)) (none (t/sStr x)))))

fn sOp op: (List (Pair String c/KvVal)) -> String
  (t/sDict (map (fn [pr] (pair (pairFirst pr) (sVal (pairSecond pr)))) op))

fn sOps ops: (List (List (Pair String c/KvVal))) -> String
  (t/sList (map sOp ops))

fn sCut full: String ci: r/CutInfo -> String
  (t/sDict (list (pair "offset" (t/sInt ci.offset)) (pair "bytes" (t/sInt ci.bytes)) (pair "head" (t/sOpt ci.head))
                 (pair "op" (t/sOpt ci.op)) (pair "file" (t/sOpt ci.file)) (pair "start" (t/sInt (chars full ci.start)))
                 (pair "text" (t/sStr ci.text))))

fn sItem it: r/RepairItem -> String
  (mt it ((r/repairItem k tok l co) (t/sList (list (t/sStr k) (t/sStr tok) (t/sInt l) (t/sInt co)))))

fn argItem n: p/SexpNode -> r/RepairItem
  (let [xs (t/argItems n)]
    (r/repairItem (t/argStr (t/argAt xs 0)) (t/argStr (t/argAt xs 1)) (t/argInt (t/argAt xs 2)) (t/argInt (t/argAt xs 3))))

fn nodeList n: p/SexpNode -> (List p/SexpNode)
  (mt n ((p/sexpList xs) xs) ((p/sexpAtom _) (list)) ((p/sexpStr _) (list)))

fn argOp n: p/SexpNode -> (List (Pair String c/KvVal))
  (map (fn [pr] (let [xs (nodeList pr)
                      v (t/argAt xs 1)]
                  (pair (t/argStr (t/argAt xs 0)) (mt v ((p/sexpStr s) (c/kvStr s)) ((p/sexpAtom a) (c/kvInt a)) ((p/sexpList _) (c/kvStr ""))))))
       (t/argItems n))

fn sAuto a: r/AutoRepair input: String -> String
  (t/sDict (listAppend
    (list (pair "text" (t/sStr a.text)) (pair "notice" (t/sOpt a.notice)) (pair "kinds" (t/sStrs a.kinds))
          (pair "left" (t/sInt a.left)) (pair "quoteCount" (t/sInt a.quoteCount)))
    (mt a.leftSpans ((some sp) (list (pair "leftSpans" (sSpans input sp)))) (none (list)))))

fn sFacts f: r/ReplyFacts input: String -> String
  (let [bound (r/bindRawBlocks input).text]
    (t/sDict (listAppend
      (list (pair "ops" (sOps f.ops)) (pair "repeated" (t/sInt f.repeated)) (pair "forms" (t/sStrs f.forms))
            (pair "prose" (t/sBool f.prose)) (pair "dataFindings" (t/sStrs f.dataFindings)))
      (mt f.cut ((some ci) (list (pair "cut" (sCut bound ci)))) (none (list))))))

fn sRun e: Env op: (List (Pair String c/KvVal)) rr: r/RunRead -> String
  (mt rr
    ((r/runUnchanged) (sOp op))
    ((r/runHint argv form msg)
      (t/sDict (list (pair "type" (t/sStr "step")) (pair "op" (t/sStr "run")) (pair "argv" (t/sStr (unroot e argv))) (pair "readHint" "true")
                     (pair "form" (t/sStr form)) (pair "message" (t/sStr (unroot e msg))))))
    ((r/runStep file fromRun form span)
      (t/sDict (listAppend
        (list (pair "type" (t/sStr "step")) (pair "op" (t/sStr "read")) (pair "file" (t/sStr (unroot e file))) (pair "fromRun" (t/sStr (unroot e fromRun)))
              (pair "form" (t/sStr form)))
        (mt span ((some sp) (list (pair "start" (t/sInt (pairFirst sp))) (pair "end" (t/sInt (pairSecond sp))))) (none (list)))))))

fn resolveOp e: Env op: (List (Pair String c/KvVal)) -> (List (Pair String c/KvVal))
  (map (fn [pr] (mt (pairSecond pr) ((c/kvStr s) (pair (pairFirst pr) (c/kvStr (resolve e s)))) ((c/kvInt _) pr))) op)

fn optPair o: (Option (Pair Int64 Int64)) s: String -> String
  (mt o ((some pr) (t/sList (list (t/sInt (chars s (pairFirst pr))) (t/sInt (pairSecond pr))))) (none "nil"))

fn ! dispatch fname: String args: (List p/SexpNode) -> String
  (let [a0 (t/argStr (t/argAt args 0))
        a1 (t/argAt args 1)]
    (cond
      ((= fname "commitMessageError") (t/sOpt (r/commitMessageError a0)))
      ((= fname "commitNamesHead")
        (withEnv! (fn [e] (mt (r/commitNamesHead! (resolve e a0) (resolve e (t/argStr a1))) ((ok b) (t/sBool b)) ((err m) (t/sDict (list (pair "raise" (t/sStr m)))))))))
      ((= fname "repairInnerQuotes") (mt (r/repairInnerQuotes a0) ((pair s k) (t/sList (list (t/sStr s) (t/sInt k))))))
      ((= fname "formChunks") (sSpans a0 (r/formChunks a0)))
      ((= fname "chunkOps") (mt (r/chunkOps a0) ((ok ops) (t/sList (list (sOps ops) "nil"))) ((err m) (t/sList (list "nil" (t/sStr m))))))
      ((= fname "recPairs") (t/sDict (map (fn [pr] (pair (pairFirst pr) (t/sStr (pairSecond pr)))) (r/recPairs (t/argStrs (t/argAt args 0))))))
      ((= fname "coreRepairDelimiters") (mt (r/coreRepairDelimiters a0 "asn") ((pair x y) (t/sList (list (t/sStr x) (t/sStr y))))))
      ((= fname "repairReceiptItems") (t/sList (map sItem (r/repairReceiptItems a0))))
      ((= fname "repairRefOffset") (t/sInt (chars a0 (r/repairRefOffset a0))))
      ((= fname "offsetToLinecol")
        (mt (r/offsetToLinecol a0 (c/charIndex a0 (stringLength a0) 0 (t/argInt a1))) ((pair l co) (t/sList (list (t/sInt l) (t/sInt co))))))
      ((= fname "delimiterFixDesc") (t/sStr (r/delimiterFixDesc (map argItem (t/argItems (t/argAt args 0))))))
      ((= fname "splitChunkLines") (t/sStrs (r/splitChunkLines a0)))
      ((= fname "hasUnclosedForm") (t/sBool (r/hasUnclosedForm a0)))
      ((= fname "locateParseFailure")
        (mt (r/locateParseFailure a0) ((some lf) (t/sList (list (t/sInt (chars a0 (pairFirst lf))) (t/sStr (pairSecond lf))))) (none "nil")))
      ((= fname "describeParseFailure") (t/sOpt (r/describeParseFailure a0)))
      ((= fname "autoRepairReply") (sAuto (r/autoRepairReply a0) a0))
      ((= fname "parseReply") (sOps (r/parseReply a0)))
      ((= fname "parseCutInfo")
        (let [ct (t/argStr a1)
              full (t/argStr (t/argAt args 2))
              start (c/charIndex full (stringLength full) 0 (t/argInt (t/argAt args 0)))]
          (sCut full (r/parseCutInfo start ct full))))
      ((= fname "detectCutForm") (mt (r/detectCutForm a0) ((some ci) (sCut a0 ci)) (none "nil")))
      ((= fname "topLevelSpans") (sSpans a0 (r/topLevelSpans a0)))
      ((= fname "degenerateCut") (optPair (r/degenerateCut a0) a0))
      ((= fname "capReply") (mt (r/capReply a0) ((pair s k) (t/sList (list (t/sStr s) (t/sInt k))))))
      ((= fname "replyFacts") (sFacts (r/replyFacts a0 (if (t/argNil? a1) none (some (t/argStrs a1)))) a0))
      ((= fname "needsConfirmReceipt")
        (let [rc (r/needsConfirmReceipt! a0)
              id rc.id
              hex (and (= (stringLength id) 12) (listAll? (fn [ch] (stringContains? "0123456789abcdef" ch)) (stringChars id)))]
          (t/sDict (list (pair "id" (t/sStr (if hex "hex12" id))) (pair "op" (t/sStr rc.op)) (pair "status" (t/sStr "needsConfirm"))
                         (pair "needsConfirm" "true") (pair "message" (t/sStr rc.message))))))
      ((= fname "shlexSplit")
        (mt (r/shlexSplit a0) ((ok ws) (t/sStrs ws)) ((err m) (t/sDict (list (pair "raise" (t/sStr (str "ValueError: " m))))))))
      ((= fname "runAsRead")
        (withEnv! (fn [e]
          (let [op0 (argOp (t/argAt args 0))
                op (resolveOp e op0)]
            (mt (r/runAsRead! op (resolve e (t/argStr a1)))
              ((ok rr) (sRun e op0 rr))
              ((err m) (t/sDict (list (pair "raise" (t/sStr m))))))))))
      ((= fname "tokenizeForm")
        (t/sList (map (fn [tk] (mt tk ((r/formTok x s2 e2) (t/sList (list (t/sStr x) (t/sInt (chars a0 s2)) (t/sInt (chars a0 e2))))))) (r/tokenizeForm a0))))
      ((= fname "rawFences")
        (t/sList (map (fn [f] (mt f ((r/fence s2 e2 body) (t/sList (list (t/sInt (chars a0 s2)) (t/sInt (chars a0 e2)) (t/sStr body)))))) (r/rawFences a0))))
      ((= fname "hoistInlineRaw") (t/sStr (r/hoistInlineRaw a0)))
      ((= fname "bindRawBlocks")
        (let [b (r/bindRawBlocks a0)]
          (t/sList (list (t/sStr b.text) (t/sInt b.count)
                         (t/sList (map (fn [pr] (t/sDict (list (pair "op" (t/sStr (pairFirst pr))) (pair "file" (t/sStr (pairSecond pr)))))) b.missing))))))
      ((= fname "unfence") (t/sStr (r/unfence a0)))
      (else (str "(unknown " fname ")"))))

fn gitEnv c0: cp/ProcessCmd -> cp/ProcessCmd
  (fold (fn [acc kv] (cp/withEnv acc (pairFirst kv) (pairSecond kv))) c0
    (list (pair "GIT_AUTHOR_NAME" "u6") (pair "GIT_AUTHOR_EMAIL" "u6@example.invalid") (pair "GIT_COMMITTER_NAME" "u6")
          (pair "GIT_COMMITTER_EMAIL" "u6@example.invalid") (pair "GIT_AUTHOR_DATE" "2026-01-01T00:00:00Z") (pair "GIT_COMMITTER_DATE" "2026-01-01T00:00:00Z")))

fn ! git! dir: String args: (List String) -> (Result String String)
  (mt (cp/exec! (cp/withTimeout (gitEnv (cp/withCwd (cp/cmd "git" args) dir)) 60000))
    ((ok out) (if (= out.exitCode 0) (ok out.stdout) (err (str "git " (c/joinSep args " ") ": " out.stderr))))
    ((err _) (err (str "git " (c/joinSep args " ") " does not spawn"))))

fn ! tempDir! tag: String -> (Result String String)
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        dir (str (if (stringEndsWith? base "/") base (str base "/")) "u6" tag (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))]
    (mt (dirCreate dir) ((ok _) (ok dir)) ((err e) (err e))))

fn then r: (Result String String) f: (fn [String] -> (Result String String)) -> (Result String String)
  (mt r ((ok v) (f v)) ((err e) (err e)))

fn ! fillRoot! dir: String -> (Result String String)
  (let [files (list (pair "a.txt" (c/joinAll (map (fn [i] (str "line " (stringFromInt64 i) "\n")) (range 1 13))))
                    (pair "crlf.txt" "l1\r\nl2\r\nl3") (pair "cr.txt" "a\rb\rc\r") (pair "empty.txt" "") (pair "sub/keep.txt" "x\n"))]
    (fold (fn [acc f] (then acc (fn [_] (mt (fileWrite (str dir "/" (pairFirst f)) (pairSecond f)) ((ok _) (ok dir)) ((err e) (err e))))))
      (mt (dirCreate (str dir "/sub")) ((ok _) (ok dir)) ((err e) (err e))) files))

fn ! fillRepo! repo: String -> (Result String String)
  (then (mt (fileWrite (str repo "/f.txt") "u6\n") ((ok _) (ok "")) ((err e) (err e)))
    (fn [_] (then (git! repo (list "init" "-q" "."))
      (fn [_] (then (git! repo (list "add" "f.txt"))
        (fn [_] (then (git! repo (list "commit" "-q" "-m" "u6"))
          (fn [_] (git! repo (list "rev-parse" "HEAD"))))))))))

fn ! withEnv! body: (fn [Env] -> String) -> String
  (let [dirs (map (fn [tag] (tempDir! tag)) (list "root" "repo" "norepo"))
        made (map (fn [d] (resultOr d "")) dirs)
        root (c/firstOf made)
        repo (c/firstOf (c/restOf made))
        norepo (c/firstOf (c/restOf (c/restOf made)))
        ready (then (then (c/firstOf dirs) (fn [_] (fillRoot! root)))
                (fn [_] (then (c/firstOf (c/restOf (c/restOf dirs))) (fn [_] (then (c/firstOf (c/restOf dirs)) (fn [_] (fillRepo! repo)))))))
        out (mt ready ((ok head) (body (env root repo norepo (r/pyStrip head)))) ((err e) (str "(setup failed " (t/sStr e) ")")))]
    (do
      (fold (fn [acc d] (if (= d "") acc (do (pathRemove d) acc))) 0 made)
      out))

fn ! timedCase -> Int64
  (let [line "(:step :op \"read\" :file \"a.txt\" :start 1 :end 20)\n"
        big (stringRepeat line 12000)
        t0 (monotonicNs)
        capped (r/capReply big)
        facts (r/replyFacts (pairFirst capped) none)
        ms (/ (- (monotonicNs) t0) 1000000)]
    (do
      (assert (= (pairSecond capped) (stringLength big)) "the large reply is over the cap and reports its size")
      (assert (= (listLength facts.forms) (/ (+ (stringLength (pairFirst capped)) 1) (stringLength line))) "every kept form is whole")
      (assert (< ms 60000) (str "cap and facts over 588 KB take under 60 s, took " (stringFromInt64 ms) " ms"))
      ms))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        fns (list "commitMessageError" "commitNamesHead" "repairInnerQuotes" "formChunks" "chunkOps" "recPairs" "coreRepairDelimiters"
                  "repairReceiptItems" "repairRefOffset" "offsetToLinecol" "delimiterFixDesc" "splitChunkLines" "hasUnclosedForm"
                  "locateParseFailure" "describeParseFailure" "autoRepairReply" "parseReply" "parseCutInfo" "detectCutForm" "topLevelSpans"
                  "degenerateCut" "capReply" "replyFacts" "needsConfirmReceipt" "shlexSplit" "runAsRead" "tokenizeForm" "rawFences"
                  "hoistInlineRaw" "bindRawBlocks" "unfence")
        passed (t/replay! (str root "/asl/agentLoop/tests/replyParityFixtures.asn") fns (fn [f a] (dispatch f a)))
        ms (timedCase)]
    (> passed 0))
