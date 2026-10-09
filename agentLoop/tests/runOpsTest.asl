(module asl/agentLoop/tests/runOpsTest
  :x [runTests]
  :i [(asl/agentLoop/runOps :a r) (asl/agentLoop/gitOps :a g) (asl/agentLoop/core :a c)])

fn kvGet kv: (List (Pair String c/KvVal)) k: String -> (Option c/KvVal)
  (mt (listHead (filter (fn [p] (= (pairFirst p) k)) kv))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt d) d))

fn getS kv: (List (Pair String c/KvVal)) k: String -> String
  (mt (kvGet kv k) ((some v) (kvText v)) ((none) ""))

fn getI kv: (List (Pair String c/KvVal)) k: String -> Int64
  (optionOr (stringToInt64 (getS kv k)) 0)

fn listed kv: (List (Pair String c/KvVal)) prefix: String -> (List String)
  (map (fn [i] (getS kv (str prefix (stringFromInt64 i)))) (range 0 (getI kv (str "n" prefix))))

fn envKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (c/sliceOf row 0 i)) ((none) row))

fn setupStep! base: String setupEnv: (List String) line: String -> Bool
  (let [kv (c/parseKv line)
        step (getS kv "step")
        path (str base "/" (getS kv "path"))]
    (cond
      ((= step "mkdir") (ok? (dirCreate path)))
      ((= step "write") (ok? (fileWrite path (getS kv "text"))))
      ((= step "run")
        (let [argv (map (fn [i] (getS kv (str "a" (stringFromInt64 i)))) (range 0 (getI kv "n")))
              env (listAppend (filter (fn [r] (not (stringStartsWith? (envKey r) "GIT_"))) (envList)) setupEnv)]
          (mt (g/runBounded! argv (some (str base "/" (getS kv "cwd"))) (some 60) (some env))
            ((ok b) (= (optionOr b.code -1) 0))
            ((err e) (do (eprintln (str "setup run failed: " e)) false)))))
      (else false)))

fn withBase base: String s: String -> String
  (stringReplace s "@BASE@" base)

fn subBase base: String s: String -> String
  (stringReplace s base "@BASE@")

fn serList xs: (List String) -> String
  (str "(" (stringJoin (map c/serString xs) " ") ")")

fn pidAlive! pid: Int64 tries: Int64 -> Bool
  (cond
    ((<= pid 0) false)
    ((err? (procKill pid "SIGCONT")) false)
    ((<= tries 0) true)
    (else (do (sleepMs 20) (pidAlive! pid (- tries 1)))))

fn walk! root: String rel: String -> (List (Pair String String))
  (let [dir (if (stringEmpty? rel) root (str root "/" rel))]
    (mt (dirList dir)
      ((err _) (list))
      ((ok names)
        (fold (fn [acc name]
                (let [sub (if (stringEmpty? rel) name (str rel "/" name))
                      full (str root "/" sub)]
                  (cond
                    ((and (stringEmpty? rel) (= name ".git")) acc)
                    ((mt (fileStat full) ((ok st) st.isDir) ((err _) false)) (listAppend acc (walk! root sub)))
                    (else (listAppend acc (list (pair sub (resultOr (fileReadString full) "(unreadable)"))))))))
          (list) names))))

fn treeText! root: String -> String
  (str "(tree" (c/joinAll (map (fn [p] (str " (f " (c/serString (pairFirst p)) " " (c/serString (pairSecond p)) ")")) (listSortBy pairFirst (walk! root "")))) ")")

fn readOr! path: String -> String
  (resultOr (fileReadString path) "")

fn journalAdd! logPath: String rel: String bytes: (Option String) mode: Int64 -> Bool
  (let [entry (str (c/serString rel) "\t(j " (c/serString rel) " " (mt bytes ((some b) (c/serString b)) ((none) "nil")) " " (stringFromInt64 mode) ")\n")]
    (ok? (fileWrite logPath (str (readOr! logPath) entry))))

fn journalText! logPath: String -> String
  (let [rows (filter (fn [l] (not (stringEmpty? l))) (stringLines (readOr! logPath)))
        firsts (fold (fn [acc row]
                       (let [key (optionOr (listHead (stringSplit row "\t")) "")]
                         (if (listAny? (fn [p] (= (pairFirst p) key)) acc) acc (listAppend acc (list (pair key (c/sliceOf row (+ (stringLength key) 1) (stringLength row))))))))
                 (list) rows)]
    (str "(journal" (c/joinAll (map (fn [p] (str " " (pairSecond p))) firsts)) ")"))

fn snapFile! logPath: String root: String rel: String -> Bool
  (let [full (str root "/" rel)]
    (mt (fileReadString full)
      ((ok bytes) (journalAdd! logPath rel (some bytes) (mt (fileStat full) ((ok st) (mod st.mode 4096)) ((err _) 0))))
      ((err _) false)))

fn runStep! base: String ctx: r/RunCtx logPath: String kv: (List (Pair String c/KvVal)) i: Int64 procs: r/Procs -> (Pair String r/Procs)
  (let [kind (getS kv (str "k" (stringFromInt64 i)))
        arg (withBase base (getS kv (str "f" (stringFromInt64 i))))
        rid (str "r" (stringFromInt64 i))
        root ctx.root
        onKeep (fn [rel pre mode] (journalAdd! logPath rel pre mode))
        head (str "(step " (stringFromInt64 i) " ")]
    (cond
      ((= kind "run")
        (let [res (r/execRunOp! (c/parseKv arg) ctx procs rid onKeep)]
          (pair (str head (r/serRec res.rec) ")") res.procs)))
      ((= kind "manage")
        (let [res (r/execManageOp! (c/parseKv arg) ctx procs rid onKeep)]
          (pair (str head (r/serRec res.rec) ")") res.procs)))
      ((= kind "delete")
        (pair (str head (r/serRec (r/execDeleteOp! (c/parseKv arg) ctx rid (fn [rel] (snapFile! logPath root rel)))) ")") procs))
      ((= kind "kill")
        (mt (r/killSpawned! ctx procs onKeep)
          ((ok k) (pair (str "(killed " (serList k.killed) " " (serList k.restored) " " (serList k.kept) ")") k.procs))
          ((err e) (pair (str "(killFailed " (c/serString e) ")") procs))))
      ((= kind "wait") (do (sleepMs (optionOr (stringToInt64 arg) 0)) (pair "" procs)))
      ((= kind "write")
        (let [w (c/parseKv arg)
              rel (getS w "path")
              wrote (fileWrite (str root "/" rel) (getS w "text"))]
          (mt (r/rebaseWritten! root (list rel) procs)
            ((ok ps) (pair (if (ok? wrote) "(rebased)" "(writeFailed)") ps))
            ((err e) (pair (str "(rebaseFailed " (c/serString e) ")") procs)))))
      ((= kind "unlink")
        (let [removed (pathRemove (str root "/" arg))]
          (mt (r/rebaseWritten! root (list arg) procs)
            ((ok ps) (pair (if (ok? removed) "(rebased)" "(unlinkFailed)") ps))
            ((err e) (pair (str "(rebaseFailed " (c/serString e) ")") procs)))))
      ((= kind "alive")
        (let [pid (optionOr (stringToInt64 (stringTrim (readOr! (str base "/" arg)))) 0)]
          (pair (str "(alive " (if (pidAlive! pid 100) "true" "false") ")") procs)))
      (else (pair (str "(unknownStep " kind ")") procs))))

fn runSteps! base: String ctx: r/RunCtx logPath: String kv: (List (Pair String c/KvVal)) i: Int64 n: Int64 procs: r/Procs acc: (List String) -> (Pair (List String) r/Procs)
  (if (>= i n)
    (pair (listReverse acc) procs)
    (let [res (runStep! base ctx logPath kv i procs)]
      (runSteps! base ctx logPath kv (+ i 1) n (pairSecond res) (if (stringEmpty? (pairFirst res)) acc (cons (pairFirst res) acc)))))

fn scenario! base: String kv: (List (Pair String c/KvVal)) id: String -> String
  (let [root (withBase base (getS kv "root"))
        ctx (r/makeRunCtx root (listed kv "o") (getS kv "session") (getI kv "t") (r/hiddenVars (getS kv "hidden")) (str base "/tool"))
        logPath (str base "/journal-" id ".log")
        cleared (fileWrite logPath "")
        steps (runSteps! base ctx logPath kv 0 (getI kv "steps") (r/newProcs) (list))
        tree (if (mt (fileStat root) ((ok st) st.isDir) ((err _) false)) (treeText! root) "(tree)")
        journal (journalText! logPath)
        cleanup (r/killSpawned! ctx (pairSecond steps) (fn [rel pre mode] true))]
    (str (if (ok? cleared) "" "(journalLogFailed) ") (stringJoin (pairFirst steps) " ") " " tree " " journal
      (if (ok? cleanup) "" " (cleanupFailed)")))

fn wordsText res: (Result (List String) String) -> String
  (mt res
    ((ok ws) (str "(words" (c/joinAll (map (fn [w] (str " " (c/serString w))) ws)) ")"))
    ((err e) (str "(error " (c/serString e) ")")))

fn runCase! base: String kv: (List (Pair String c/KvVal)) -> String
  (let [fnName (getS kv "fn")
        cmd (withBase base (getS kv "cmd"))]
    (cond
      ((= fnName "guard")
        (mt (r/checkRunGitGuard cmd)
          ((none) "nil")
          ((some p) (str "(refuse " (c/serString (pairFirst p)) " " (c/serString (pairSecond p)) ")"))))
      ((= fnName "words") (wordsText (r/shellWords cmd)))
      ((= fnName "readOnly") (if (r/runReadOnly cmd) "true" "false"))
      ((= fnName "outward")
        (mt (r/runOutward cmd (listed kv "o") (withBase base (getS kv "root")))
          ((ok w) (if (stringEmpty? w) "nil" (str "(why " (c/serString w) ")")))
          ((err e) (str "(error " (c/serString e) ")"))))
      ((= fnName "hidden") (str "(vars" (c/joinAll (map (fn [v] (str " " (c/serString v))) (r/hiddenVars (getS kv "text")))) ")"))
      ((= fnName "tail") (c/serString (r/logTail (getS kv "text") (getI kv "lines") (getI kv "cap"))))
      ((= fnName "scenario") (scenario! base kv (getS kv "id")))
      (else (str "(unknown fn " fnName ")"))))

fn firstDiff a: String b: String i: Int64 -> Int64
  (if (or (>= i (stringLength a)) (or (>= i (stringLength b)) (!= (c/sliceOf a i (+ i 1)) (c/sliceOf b i (+ i 1))))) i (firstDiff a b (+ i 1)))

fn around s: String i: Int64 -> String
  (c/sliceOf s (max 0 (- i 80)) (min (stringLength s) (+ i 160)))

fn replay! base: String lines: (List String) acc: (List (Pair String Bool)) -> (List (Pair String Bool))
  (if (listEmpty? lines)
    (listReverse acc)
    (let [kv (c/parseKv (c/firstOf lines))
          id (getS kv "id")
          want (getS kv "want")
          maxMs (getI kv "maxMs")
          t0 (monotonicNs)
          raw (subBase base (runCase! base kv))
          ms (/ (- (monotonicNs) t0) 1000000)
          got (if (and (> maxMs 0) (> ms maxMs)) (str raw " (slow " (stringFromInt64 ms) " ms)") raw)
          same (= got want)
          at (firstDiff got want 0)]
      (do
        (if same true (do (eprintln (str "MISMATCH " id " at " (stringFromInt64 at) "\n  want " (around want at) "\n  got  " (around got at))) false))
        (replay! base (c/restOf lines) (cons (pair id same) acc)))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/runOpsFixture.asn")) "")
        all (stringLines content)
        header (c/parseKv (optionOr (listHead all) ""))
        cases (filter (fn [l] (stringStartsWith? l "(:case ")) all)
        setups (filter (fn [l] (stringStartsWith? l "(:setup ")) all)
        setupEnv (map (fn [l] (let [kv (c/parseKv l)] (str (getS kv "k") "=" (getS kv "v"))))
                   (filter (fn [l] (stringStartsWith? l "(:env ")) all))
        tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/aslRunOpsTest" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        base (resultOr (realPath tmp) tmp)
        setupOk (listAll? (fn [l] (setupStep! base setupEnv l)) setups)
        n (listLength cases)]
    (do
      (assert (ok? made) "the temporary base directory is created")
      (assert setupOk "every setup step of the fixture recipe succeeds")
      (assert (= n (getI header "cases")) "the fixture holds the number of cases its header declares")
      (assert (>= n 170) "the fixture holds at least 170 cases")
      (let [results (replay! base cases (list))
            removed (pathRemove base)
            passed (listLength (filter (fn [q] (pairSecond q)) results))]
        (do
          (assert (ok? removed) "the temporary base directory is removed")
          (assert (= (listLength results) n) "every case of the fixture was replayed")
          (fold (fn [acc q] (do (assert (pairSecond q) (str "case " (pairFirst q) " matches the Python original")) acc)) true results)
          (= passed n)))))
