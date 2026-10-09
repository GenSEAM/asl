(module asl-forms/tests/gatesParityTest :x [runTests main] :i [(asl-forms/kernel :a k) (asl-forms/gate :a g) (asl-forms/ops :a ops) (asl-forms/wire :a w) (asl-forms/main :a m)])


(schema Case (:f id String) (:f kind String) (:f root String) (:f form String) (:f exit String) (:f stdout String) (:f log String) (:f lock String))

(schema Tally (:f cases Int64) (:f failures Int64))


fn kw row: String key: String -> String
  (optionOr (mapGet (k/parseStep row).kwargs key) "")

fn rowsOf text: String prefix: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l prefix)) (stringSplit text "\n"))

fn caseRows text: String tag: String id: String -> (List String)
  (rowsOf text (str "(:" tag " :case " id " "))

fn caseOf row: String -> Case
  (let [(p (k/parseStep row).kwargs)
        (get (fn [(key String)] -> String (optionOr (mapGet p key) "")))]
    (Case :id (get "id") :kind (get "kind") :root (get "root") :form (get "form") :exit (get "exit") :stdout (get "stdout") :log (get "log") :lock (get "lock")))

fn wsDir work: String name: String -> String
  (str work "/ws" name)

fn materialize! work: String text: String -> Bool
  (listAll? (fn [(row String)] -> Bool
              (let [(p (k/parseStep row).kwargs)
                    (target (str (wsDir work (optionOr (mapGet p "ws") "")) "/" (optionOr (mapGet p "path") "")))]
                (do (dirCreate (k/dirName target))
                    (mt (fileWrite target (optionOr (mapGet p "content") "")) ((ok _) true) ((err _) false)))))
            (rowsOf text "(:tree "))

fn dropKey? row: String -> Bool
  (let [(key (optionOr (listHead (stringSplit row "=")) ""))]
    (or (listContains? (list "ASL_SESSION" "ASL_ROOT" "ROOT_DIR" "SCRIPT_DIR" "ASL_HOST" "ASL_VFS_DIR" "ASL_AUDIT_TIMEOUT_S" "PATH" "STUB_WS" "STUB_LOG") key)
        (stringEndsWith? key "_API_KEY")))

fn placeholder work: String v: String -> String
  (cond
    ((= v "@NOHOST@") (str work "/noHost"))
    ((= v "@NOBIN@") (str work "/emptyBin"))
    ((= v "@NOTOOLS@") "/usr/bin:/bin")
    (else v))

fn caseEnv! repo: String work: String c: Case text: String -> (List String)
  (let [(stubs (str repo "/asl/packages/asl-forms/tests/fixtures/recorded/gatesStubs"))
        (ws (wsDir work c.root))
        (base (list (str "PATH=" stubs "/path:" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "SCRIPT_DIR=" stubs "/bin") (str "ROOT_DIR=" ws) (str "ASL_ROOT=" ws)
                    (str "ASL_HOST=" stubs "/bin/asl-host") (str "STUB_WS=" ws) (str "STUB_LOG=" work "/log" c.id)))
        (overrides (map (fn [(row String)] -> (Pair String String) (pair (kw row "name") (placeholder work (kw row "value")))) (caseRows text "env" c.id)))
        (names (map pairFirst overrides))
        (kept (filter (fn [(r String)] -> Bool (not (listContains? names (optionOr (listHead (stringSplit r "=")) "")))) base))]
    (listAppend (listAppend (filter (fn [(r String)] -> Bool (not (dropKey? r))) (envList)) kept)
                (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) overrides)))

fn masked out: String work: String stubs: String -> String
  (stringReplace (stringReplace out work "@WORK@") stubs "@STUBS@")

fn lockMasked text: String -> String
  (mt (stringIndexOf text ":measuredAt ")
    ((none) text)
    ((some i)
      (let [(b (stringToBytes text))
            (s (+ i 12))
            (e (digitEnd b (stringLength text) s))]
        (str (optionOr (stringSlice text 0 s) "") "0" (optionOr (stringSlice text e (stringLength text)) "")))))

fn digitEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (>= (bytesGet b i) 48) (<= (bytesGet b i) 57)) (digitEnd b n (+ i 1)) i)

fn stagedAfterWant text: String id: String -> String
  (stringJoin (map (fn [(row String)] -> String (str (kw row "path") "\n" (kw row "content"))) (caseRows text "stagedAfter" id)) "")

fn diffNote! label: String id: String want: String got: String -> Bool
  (if (= want got)
    true
    (do (println (str "(:gatesDiff :case " id " :aspect " label " :want \"" (k/escapeAsnVal want) "\" :got \"" (k/escapeAsnVal got) "\")")) false))

fn checkCase! repo: String work: String host: String text: String row: String t: Tally -> Tally
  (let [(c (caseOf row))
        (stubs (str repo "/asl/packages/asl-forms/tests/fixtures/recorded/gatesStubs"))
        (ws (wsDir work c.root))
        (logPath (str work "/log" c.id))
        (stagePath (str work "/stage" c.id))
        (lockPath (str ws "/asl/grammar/capabilities.lock"))
        (reset (do (fileWrite logPath "") (fileWrite stagePath "")))
        (r (g/runArgv! (list host "run" (str repo "/asl/packages/asl-forms/tests/gatesParityTest.asl") (str repo "/asl/packages/asl-forms/tests/fixtures/recorded/gates.asn") c.id work)
                      (some ws) (some (caseEnv! repo work c text)) 120000 0))
        (got (masked r.out work stubs))
        (gotLog (resultOr (fileReadString logPath) "<no log>"))
        (gotStage (resultOr (fileReadString stagePath) "<no stage>"))
        (gotLock (if (fileExists? lockPath) (lockMasked (resultOr (fileReadString lockPath) "")) ""))
        (gone (if (fileExists? lockPath) (pathRemove lockPath) (ok ())))
        (s1 (assert (diffNote! "stdout" c.id c.stdout got) (str "case " c.id " stdout matches recorded behavior")))
        (s2 (assert (diffNote! "exit" c.id c.exit (stringFromInt64 r.code)) (str "case " c.id " exit matches recorded behavior")))
        (s3 (assert (diffNote! "log" c.id c.log gotLog) (str "case " c.id " external calls match recorded behavior")))
        (s4 (assert (diffNote! "stage" c.id (stagedAfterWant text c.id) gotStage) (str "case " c.id " staging matches recorded behavior")))
        (s5 (assert (diffNote! "lock" c.id c.lock gotLock) (str "case " c.id " lock file matches recorded behavior")))
        (bad (or (!= c.stdout got) (!= c.exit (stringFromInt64 r.code)) (!= c.log gotLog) (!= (stagedAfterWant text c.id) gotStage) (!= c.lock gotLock)))]
    (do (if (and bad (not (stringEmpty? r.errText))) (println (str "(:gatesChildErr :case " c.id " :err \"" (k/escapeAsnVal r.errText) "\")")) (print ""))
        (Tally :cases (+ t.cases 1) :failures (+ t.failures (if bad 1 0)))))

fn ! currentHost repo: String -> (Option String)
  (mt (envGet "ASL_HOST")
    ((some h) (if (fileExists? h)
                (some (resultOr (realPath h) h))
                (do (println (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (assert false (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (none))))
    ((none) (let [(p (str repo "/asl/host/out/asl-host"))]
              (if (fileExists? p)
                (some (resultOr (realPath p) p))
                (do (println (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (none))))))

fn doctorUsesUnifiedIntel! repo: String dir: String host: String -> Bool
  (let [(bin (str dir "/staleBin"))
        (made (and (ok? (dirCreate bin))
                   (listAll? (fn [(name String)] -> Bool (let [(p (str bin "/" name))] (and (ok? (fileWrite p "#!/bin/sh\n")) (ok? (fileChmod p 493)))))
                             (list "asl" "asl-intel"))))
        (env (g/GateEnv :root repo :rootDir repo :binDir bin :host host :staged (list)))
        (out (g/doctorStep! env (fn [(id Int64) (form String)] -> (Pair (List String) Int64) (pair (list) 0)) 1 (mapEmpty) (list)))
        (text (stringJoin out.lines ""))]
    (and made (and (stringContains? text "(:capability :id \"intel\" :binary \"asl\" :status :present)") (not (stringContains? text "asl-intel")))))

fn ! runTests -> Bool
  (let [(repo (resultOr (realPath ".") "."))]
    (mt (currentHost repo)
      ((none) false)
      ((some host)
       (let [(text (resultOr (fileReadString (str repo "/asl/packages/asl-forms/tests/fixtures/recorded/gates.asn")) ""))
             (work (resultOr (realPath (str (optionOr (envGet "TMPDIR") "/tmp") "/")) "/tmp"))
             (dir (str work "/aslGatesParity" (stringFromInt64 (procSelf)) "x" (stringFromInt64 (monotonicNs))))
             (made (dirCreate (str dir "/emptyBin")))
             (rows (rowsOf text "(:case "))
             (n (listLength rows))]
         (assert (>= n 100) "the gates fixture holds at least 100 recorded cases")
         (assert (doctorUsesUnifiedIntel! repo dir host) "doctor probes bin/asl for intel even beside a stale asl-intel")
         (assert (materialize! dir text) "fixture trees materialize")
         (let [(tally (fold (fn [(t Tally) (row String)] -> Tally (checkCase! repo dir host text row t)) (Tally :cases 0 :failures 0) rows))]
           (do (pathRemove dir)
               (println (str "(:gatesParity :cases " (stringFromInt64 tally.cases) " :failures " (stringFromInt64 tally.failures) ")"))
               (assert (= tally.cases n) "every recorded case ran")
               (assert (= tally.failures 0) "every case matches recorded stdout, exit and external calls")
               true))))))

fn jsonStr s: String i: Int64 n: Int64 acc: (List String) -> (Pair String Int64)
  (let [(c (k/charAt s i))]
    (cond
      ((>= i n) (pair (stringJoin (listReverse acc) "") n))
      ((= c "\"") (pair (stringJoin (listReverse acc) "") (+ i 1)))
      ((= c "\\")
        (let [(e (k/charAt s (+ i 1)))]
          (cond
            ((= e "n") (jsonStr s (+ i 2) n (cons "\n" acc)))
            ((= e "t") (jsonStr s (+ i 2) n (cons "\t" acc)))
            ((= e "u") (jsonStr s (+ i 6) n (cons (optionOr (stringSlice s i (+ i 6)) "") acc)))
            (else (jsonStr s (+ i 2) n (cons e acc))))))
      (else (jsonStr s (+ i 1) n (cons c acc)))))

fn jsonList s: String i: Int64 n: Int64 acc: (List (Option String)) -> (List (Option String))
  (if (>= i n)
    (listReverse acc)
    (let [(c (k/charAt s i))]
      (cond
        ((= c "\"") (let [(r (jsonStr s (+ i 1) n (list)))] (jsonList s (pairSecond r) n (cons (some (pairFirst r)) acc))))
        ((= (optionOr (stringSlice s i (+ i 4)) "") "null") (jsonList s (+ i 4) n (cons (none) acc)))
        (else (jsonList s (+ i 1) n acc)))))

fn envOr! name: String -> String
  (optionOr (envGet name) "")

fn runForm! env: g/GateEnv root: String id: Int64 form: String -> (Pair (List String) Int64)
  (let [(p (k/parseStep form))]
    (if (g/gateOp? p.op)
      (let [(o (g/runGate! env (fn [(i Int64) (f String)] -> (Pair (List String) Int64) (runForm! env root i f)) id p.op p.kwargs p.args))]
        (pair o.lines o.errCount))
      (let [(o (ops/runStep! root id form))]
        (pair o.lines o.errCount))))

fn walkFiles! base: String rel: String -> (List String)
  (mt (dirList base)
    ((err _) (list))
    ((ok names)
      (let [(sorted (listSort names))
            (files (filter (fn [(nm String)] -> Bool (k/isFile! (k/joinPath base nm))) sorted))
            (dirs (filter (fn [(nm String)] -> Bool (k/isDir! (k/joinPath base nm))) sorted))
            (here (map (fn [(nm String)] -> String (let [(r (if (stringEmpty? rel) nm (str rel "/" nm)))] (str r "=" (resultOr (fileReadString (k/joinPath base nm)) "")))) files))]
        (listAppend here (fold (fn [(acc (List String)) (d String)] -> (List String) (listAppend acc (walkFiles! (k/joinPath base d) (if (stringEmpty? rel) d (str rel "/" d))))) (list) dirs)))))

fn fnCase! env: g/GateEnv root: String args: (List (Option String)) -> String
  (let [(name (optionOr (optionOr (listGet args 0) (none)) ""))
        (a1 (optionOr (optionOr (listGet args 1) (none)) ""))
        (path (str root "/" a1))]
    (cond
      ((= name "foreignSyntax")
        (let [(r (g/foreignSyntax! env path (optionOr (optionOr (listGet args 2) (none)) "")))]
          (str "(:status \"" (pairFirst r) "\" :message \"" (k/escapeAsnVal (pairSecond r)) "\")")))
      ((= name "validateStaged")
        (let [(r (g/validateStaged! env path (optionOr (listGet args 2) (none)) (optionOr (optionOr (listGet args 3) (none)) "") (= (optionOr (optionOr (listGet args 4) (none)) "") "true")))]
          (str "(:code \"" (optionOr (listGet r 0) "") "\" :message \"" (k/escapeAsnVal (optionOr (listGet r 1) "")) "\" :fields \"" (k/escapeAsnVal (optionOr (listGet r 2) "")) "\")")))
      ((= name "overlay")
        (mt (g/buildOverlay! env (filter (fn [(sp (Pair String String))] -> Bool (g/stagedWritable! root (pairFirst sp))) env.staged))
          ((err e) (str "(:overlayError \"" (k/escapeAsnVal e) "\")"))
          ((ok tmp) (let [(rows (walkFiles! tmp ""))] (do (pathRemove tmp) (str "(:files \"" (k/escapeAsnVal (stringJoin rows "\n--\n")) "\")"))))))
      (else (str "(:unknownHelper \"" (k/escapeAsnVal name) "\")"))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(text (resultOr (fileReadString (optionOr (listGet args 0) "")) ""))
        (id (optionOr (listGet args 1) ""))
        (work (optionOr (listGet args 2) ""))
        (row (optionOr (listHead (rowsOf text (str "(:case :id " id " "))) ""))
        (c (caseOf row))
        (root (wsDir work c.root))
        (staged (map (fn [(r String)] -> (Pair String String) (pair (str root "/" (kw r "path")) (kw r "content"))) (caseRows text "staged" id)))
        (env (g/GateEnv :root root :rootDir (envOr! "ROOT_DIR") :binDir (envOr! "SCRIPT_DIR") :host (envOr! "ASL_HOST") :staged staged))]
    (if (= c.kind "fn")
      (do (println (fnCase! env root (jsonList c.form 0 (stringLength c.form) (list)))) (ok 0))
      (let [(p (k/parseStep c.form))
            (o (g/runGate! env (fn [(i Int64) (f String)] -> (Pair (List String) Int64) (runForm! env root i f)) 1 p.op p.kwargs p.args))
            (ws (m/workspaceFor! root))
            (failed (> o.errCount 0))
            (wire (map (fn [(l String)] -> String (w/wireReceipt! ws l failed p.op)) o.lines))
            (stageFile (str work "/stage" id))]
        (do (mt o.stage ((some sp) (fileWrite stageFile (str (k/relToRoot root (pairFirst sp)) "\n" (pairSecond sp)))) ((none) (ok ())))
            (println (if (= (listLength wire) 1) (optionOr (listHead wire) "") (str "(:batch " (stringJoin wire " ") ")")))
            (ok (if (g/linesFailed? o.lines o.errCount) 1 0))))))
