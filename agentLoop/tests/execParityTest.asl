(module asl/agentLoop/tests/execParityTest
  :x [runTests]
  :i [(asl/agentLoop/exec :a x)
      (asl/agentLoop/core :a c)
      (asl/agentLoop/plan :a p)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/runOps :a r)])

fn items n: p/SexpNode -> (List p/SexpNode)
  (mt n ((p/sexpList xs) xs) (_ (list)))

fn atomOf n: p/SexpNode -> String
  (mt n ((p/sexpAtom a) a) (_ ""))

fn strOf n: p/SexpNode -> String
  (mt n ((p/sexpStr s) s) ((p/sexpAtom a) a) (_ ""))

fn at xs: (List p/SexpNode) i: Int64 -> p/SexpNode
  (optionOr (listGet xs i) (p/sexpAtom ""))

fn headAtom n: p/SexpNode -> String
  (atomOf (at (items n) 0))

fn restItems n: p/SexpNode -> (List p/SexpNode)
  (optionOr (listTail (items n)) (list))

fn part xs: (List p/SexpNode) name: String -> (List p/SexpNode)
  (mt (listHead (filter (fn [n] (= (headAtom n) name)) xs))
    ((some n) (restItems n))
    ((none) (list)))

fn partStr xs: (List p/SexpNode) name: String -> String
  (strOf (at (part xs name) 0))

fn place s: String root: String base: String -> String
  (stringReplace (stringReplace s "@ROOT@" root) "@BASE@" base)

fn unplace s: String root: String base: String -> String
  (stringReplace (stringReplace s root "@ROOT@") base "@BASE@")

fn opField n: p/SexpNode root: String base: String -> (Pair String c/KvVal)
  (let [xs (items n)
        kind (atomOf (at xs 0))
        k (strOf (at xs 1))]
    (cond
      ((= kind "s") (pair k (c/kvStr (place (strOf (at xs 2)) root base))))
      ((= kind "i") (pair k (c/kvInt (atomOf (at xs 2)))))
      (else (pair k (c/kvStr "True")))))

fn valOf n: p/SexpNode -> x/Val
  (mt n
    ((p/sexpStr s) (x/vStr s))
    ((p/sexpAtom a)
      (cond
        ((= a "none") (x/vNone))
        ((= a "true") (x/vBool true))
        ((= a "false") (x/vBool false))
        (else (x/vInt (optionOr (stringToInt64 a) 0)))))
    ((p/sexpList xs)
      (cond
        ((listEmpty? xs) (x/vStrs (list)))
        ((= (headAtom (at xs 0)) "r") (x/vRecs (map recOf xs)))
        ((listAll? (fn [e] (mt e ((p/sexpStr _) true) (_ false))) xs) (x/vStrs (map strOf xs)))
        (else (x/vPair (optionOr (stringToInt64 (atomOf (at xs 0))) 0) (optionOr (stringToInt64 (atomOf (at xs 1))) 0))))))

fn recOf n: p/SexpNode -> (List (Pair String x/Val))
  (map (fn [f] (let [fx (items f)] (pair (atomOf (at fx 0)) (valOf (at fx 1))))) (restItems n))

fn ! writeOk path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! appendLine path: String line: String -> Bool
  (writeOk path (str (readOr path) line "\n"))

fn logItems text: String -> (List String)
  (filter (fn [l] (not (stringEmpty? l))) (stringSplit text "\n"))

fn logList text: String -> String
  (str "(" (stringJoin (logItems text) " ") ")")

fn serStrs xs: (List String) -> String
  (str "(" (stringJoin (map c/serString xs) " ") ")")

fn ! runOk argv: (List String) cwd: (Option String) env: (Option (List String)) -> Bool
  (mt (procSpawnv argv cwd env)
    ((ok sp) (= (procWaitPid sp.pid false) (ok (some 0))))
    ((err _) false))


fn parentOf path: String -> String
  (let [parts (stringSplit path "/")]
    (stringJoin (optionOr (listSlice parts 0 (max 1 (- (listLength parts) 1))) (list)) "/"))

fn ! setupRow row: (List p/SexpNode) template: String gitEnv: (List String) -> Bool
  (let [kind (atomOf (at row 1))]
    (if (= kind "file")
      (let [full (str template "/" (strOf (at row 2)))]
        (and (runOk (list "mkdir" "-p" (parentOf full)) (none) (none)) (writeOk full (strOf (at row 3)))))
      (runOk (cons "git" (map strOf (optionOr (listSlice row 2 (listLength row)) (list)))) (some template)
        (some (listAppend (envList) gitEnv)))))

fn ! nextId path: String -> String
  (let [k (+ 1 (optionOr (stringToInt64 (stringTrim (readOr path))) 0))]
    (if (writeOk path (stringFromInt64 k)) (str "x" (stringFromInt64 k)) "idCounterWriteFailed"))

fn callOf n: p/SexpNode root: String base: String -> (Pair String t/AslRun)
  (let [xs (items n)]
    (pair (place (strOf (at xs 1)) root base)
      (t/aslRun (optionOr (stringToInt64 (atomOf (at xs 2))) 0) (place (strOf (at xs 3)) root base) (place (strOf (at xs 4)) root base))))

fn ! replayRun calls: (List (Pair String t/AslRun)) sentLog: String counter: String -> (fn [String String] -> t/AslRun)
  (fn [form rootDir]
    (let [k (optionOr (stringToInt64 (stringTrim (readOr counter))) 0)
          logged (and (appendLine sentLog (c/serString form)) (writeOk counter (stringFromInt64 (+ k 1))))]
      (mt (listGet calls k)
        ((some cl) (if logged (pairSecond cl) (t/aslRun 97 "" "replay log write failed")))
        ((none) (t/aslRun 98 "" (str "replay: no recorded call " (stringFromInt64 k)))))))

fn ! execCase xs: (List p/SexpNode) base: String template: String repo: String effects: (List (Pair String String)) -> Bool
  (let [cid (strOf (at xs 1))
        root (str base "/" cid)
        copied (runOk (list "cp" "-R" template root) (none) (none))
        op (map (fn [f] (opField f root base)) (restItems (at xs 2)))
        owns (map strOf (part xs "owns"))
        hiddenNode (part xs "hidden")
        hiddenValues (map (fn [h] (pair (strOf (at (items h) 0)) (place (strOf (at (items h) 1)) root base)))
                       (optionOr (listTail hiddenNode) (list)))
        env (x/makeExecEnv root repo (partStr xs "mode") owns (= (atomOf (at (part xs "persisted") 0)) "true") (partStr xs "base")
              (map strOf (part xs "gates")) effects (strOf (at hiddenNode 0)) hiddenValues 8000 60 (none) "leon" (none))
        calls (map (fn [n] (callOf n root base)) (part xs "calls"))
        ids (str base "/" cid ".ids")
        snaps (str base "/" cid ".snaps")
        keeps (str base "/" cid ".keeps")
        sent (str base "/" cid ".sent")
        replayed (str base "/" cid ".replayed")
        cleared (and (writeOk ids "0") (and (writeOk snaps "") (and (writeOk keeps "") (and (writeOk sent "") (writeOk replayed "0")))))
        onKeep (fn [rel pre mode] (appendLine keeps (c/serString rel)))
        out (x/execOp! op env (r/newProcs) (fn [] (nextId ids)) (fn [f] (appendLine snaps (c/serString f))) onKeep (replayRun calls sent replayed))
        ctx (r/makeRunCtx root owns "leon" 60 (r/hiddenVars (strOf (at hiddenNode 0))) repo)
        killed (r/killSpawned! ctx out.procs onKeep)
        rec out.rec
        got (str (x/serRec rec) "\n" (x/formatOpReceipt rec 8000) "\n" (logList (readOr snaps)) "\n" (logList (readOr keeps))
              "\n" (stringJoin (logItems (readOr sent)) " "))
        want (str (partStr xs "want") "\n" (stringJoin (map (fn [cl] (c/serString (pairFirst cl))) calls) " "))
        same (= (unplace got root base) (place want root base))]
    (do
      (if (and copied (and cleared (ok? killed)))
        ()
        (eprintln (str cid ": case setup: copied " (if copied "yes" "no") ", logs " (if cleared "yes" "no") ", kill " (if (ok? killed) "ok" "failed"))))
      (if same () (eprintln (str "MISMATCH " cid "\n  want " (place want root base) "\n  got  " (unplace got root base))))
      (and same (and copied (and cleared (ok? killed))))))

fn fmtCase! xs: (List p/SexpNode) -> Bool
  (let [cid (strOf (at xs 1))
        got (x/formatOpReceipt (recOf (at xs 3)) (optionOr (stringToInt64 (atomOf (at xs 2))) 0))
        want (partStr xs "want")]
    (do
      (if (= got want) () (eprintln (str "MISMATCH " cid "\n  want " want "\n  got  " got)))
      (= got want)))

fn ! tableCase xs: (List p/SexpNode) effects: (List (Pair String String)) -> Bool
  (let [kind (headAtom (p/sexpList xs))
        want (partStr xs "want")
        a1 (strOf (at xs 1))
        got (cond
              ((= kind "shape") (mt (listHead (filter (fn [pr] (= (pairFirst pr) a1)) (x/opShapes))) ((some pr) (pairSecond pr)) ((none) "(missing)")))
              ((= kind "accepted") (serStrs (x/acceptedOpsForMode a1 effects)))
              ((= kind "terminal") (serStrs (x/terminalForms a1)))
              ((= kind "undeclared") (x/serRec (x/undeclaredAnswer a1 (strOf (at xs 2)) effects)))
              (else
                (serStrs (x/collectProseStrings (strOf (at xs 2)) (= (atomOf (at xs 3)) "true") (map strOf (items (at xs 6)))
                           (= (atomOf (at xs 4)) "true") (= (atomOf (at xs 5)) "true")))))]
    (do
      (if (= got want) () (eprintln (str "MISMATCH " kind " " a1 "\n  want " want "\n  got  " got)))
      (= got want)))

fn ! runCases rows: (List (List p/SexpNode)) base: String template: String repo: String effects: (List (Pair String String)) -> Int64
  (if (listEmpty? rows)
    0
    (let [xs (c/firstOf rows)
          kind (atomOf (at xs 0))
          matched (cond
                ((= kind "case") (execCase xs base template repo effects))
                ((= kind "fmt") (fmtCase! xs))
                ((listContains? (list "shape" "accepted" "terminal" "undeclared" "prose") kind) (tableCase xs effects))
                (else false))]
      (do
        (assert matched (str "exec behavior case " (strOf (at xs 1))))
        (+ (if matched 0 1) (runCases (c/restOf rows) base template repo effects)))))

fn rowOf line: String -> (List p/SexpNode)
  (mt (p/planTree line)
    ((ok nodes) (mt (listHead nodes) ((some nd) (items nd)) ((none) (list))))
    ((err _) (list)))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        text (readOr (str repo "/asl/agentLoop/tests/execParityFixture.asn"))
        rows (map rowOf (filter (fn [l] (not (stringEmpty? l))) (stringSplit text "\n")))
        header (optionOr (listHead rows) (list))
        declared (optionOr (stringToInt64 (atomOf (at header 3))) -1)
        gitEnv (map (fn [xs] (str (strOf (at xs 1)) "=" (strOf (at xs 2)))) (filter (fn [xs] (= (atomOf (at xs 0)) "env")) rows))
        setups (filter (fn [xs] (= (atomOf (at xs 0)) "setup")) rows)
        cases (filter (fn [xs] (listContains? (list "case" "fmt" "shape" "accepted" "terminal" "undeclared" "prose") (atomOf (at xs 0)))) rows)
        caseIds (map (fn [xs] (strOf (at xs 1))) cases)
        tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/execParityTest" (stringFromInt64 (monotonicNs)))
        made (dirCreate tmp)
        base (resultOr (realPath tmp) tmp)
        template (str base "/template")
        built (and (ok? made) (and (ok? (dirCreate template)) (listAll? (fn [row] (setupRow row template gitEnv)) setups)))
        effects (list
          (pair "read" "local") (pair "query" "local") (pair "write" "local") (pair "edit" "local")
          (pair "check" "local") (pair "diff" "local") (pair "flush" "local") (pair "discard" "local")
          (pair "test" "local") (pair "tree" "local") (pair "observe" "local") (pair "outline" "local")
          (pair "intel" "local") (pair "fix" "local") (pair "txn" "local") (pair "tools" "local")
          (pair "help" "local") (pair "findings" "local") (pair "step" "local") (pair "evidence" "local")
          (pair "escalate" "local") (pair "done" "local") (pair "gitDiff" "local") (pair "gitLog" "local")
          (pair "gitShow" "local") (pair "note" "local") (pair "delete" "local") (pair "run" "local")
          (pair "gate" "local") (pair "push" "needsConfirm") (pair "search" "local")
          (pair "research" "local") (pair "crawl" "local") (pair "manage" "local")
          (pair "engine" "needsConfirm") (pair "job" "needsConfirm") (pair "agent" "needsConfirm"))
        executed (if built (runCases cases base template repo effects) 0)
        removed (runOk (list "rm" "-rf" base) (none) (none))]
    (do
      (assert (and built (= (listLength cases) declared)) (str "the template repo builds and all " (stringFromInt64 declared) " declared cases ran"))
      (assert (and (listContains? caseIds "fmtContentAtCap") (listContains? caseIds "fmtContentCapPlusOne")) "content formatting cases cover the cap and cap+1")
      (assert (and (listContains? caseIds "fmtDiffAtCap") (listContains? caseIds "fmtDiffCapPlusOne")) "diff formatting cases cover the cap and cap+1")
      (assert (listContains? caseIds "gateNCountPlusOne") "gate index case covers declared count+1")
      (assert (listContains? caseIds "writeRawThresholdExact") "write case covers exactly 400 escaped bytes")
      (assert (and (listContains? caseIds "writeRawThresholdOver") (listContains? caseIds "writeRawTabEscape")) "write cases cover 401 escaped bytes and the tab-only form escape")
      (assert (and (listContains? caseIds "declaredGateThroughRun") (listContains? caseIds "runTailLines")) "run cases cover a declared gate and the 20-line tail boundary")
      (assert (listContains? caseIds "missingGateFiles") "gate case covers two missing files")
      (assert (listContains? caseIds "intentWhyEmptyQuoted") "intent case covers empty quoted :why")
      (assert removed "the temporary tree is removed")
      true))
