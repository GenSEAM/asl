(module asl-gates/tests/runnerParityTest
  :x [runTests replayChooseBaseFixtures!]
  :i [(asl-gates/runnerMain :a rm) (asl-parser/reader :a p) (tests/parity/gates/runnerCorpus :a gr)])

fn atom node: p/SExpr -> String
  (mt node ((p/sexprAtom s) s) (_ ""))

fn items node: p/SExpr -> (List p/SExpr)
  (p/sexprToList node)

fn field xs: (List p/SExpr) key: String -> (Option p/SExpr)
  (mt (listHead xs)
    ((none) (none))
    ((some k)
      (mt (listGet xs 1)
        ((none) (none))
        ((some v) (if (= (atom k) key) (some v) (field (optionOr (listSlice xs 2 (listLength xs)) (list)) key))))))

fn stringField xs: (List p/SExpr) key: String -> String
  (mt (field xs key) ((some v) (gr/decodeString (atom v))) ((none) ""))

fn fixtureCases! -> (List p/SExpr)
  (let [(text (mt (fileReadString "tests/parity/audit/runner.asn") ((ok s) s) ((err e) (do (assert false (str "read runner fixture: " e)) ""))))
        (form (p/parseSexpr text))]
    (optionOr (mt (field (optionOr (listTail (items form)) (list)) ":cases") ((some cs) (some (items cs))) ((none) (none))) (list)))

fn fixtureArgv node: p/SExpr -> (List String)
  (map (fn [(v p/SExpr)] -> String (gr/decodeString (atom v))) (items node))

fn envPairs xs: (List p/SExpr) -> (List String)
  (mt (listHead xs)
    ((none) (list))
    ((some k)
      (let [(key (atom k))
            (name (optionOr (stringSlice key 1 (stringLength key)) ""))]
        (mt (listGet xs 1)
          ((none) (do (assert false (str "fixture :env key " key " has a value")) (list)))
          ((some v)
            (do
              (assert (and (stringStartsWith? key ":") (not (stringEmpty? name))) (str "fixture :env key is a keyword: " key))
              (cons (str name "=" (gr/decodeString (atom v))) (envPairs (optionOr (listSlice xs 2 (listLength xs)) (list))))))))))

fn fixtureEnv node: p/SExpr -> (List String)
  (envPairs (items node))

fn workspaceRoot! -> String
  (mt (realPath ".") ((ok root) root) ((err e) (do (assert false (str "realPath . fails: " e)) "")))

fn ! timesLedger! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslRunnerParityTimes." (stringFromInt64 (procSelf)) ".asn")

fn childEnv! extras: (List String) -> (List String)
  (let [(path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (home (optionOr (envGet "HOME") "/") )
        (tmp (optionOr (envGet "TMPDIR") "/tmp"))]
    (listAppend (list (str "PATH=" path) (str "HOME=" home) (str "TMPDIR=" tmp) (str "ASL_GATE_TIMES=" (timesLedger!))) extras))

fn runnerCall! dir: String argv: (List String) env: (List String) -> gr/Captured
  (let [(root (workspaceRoot!))
        (cmd (listAppend (list (str root "/asl/host/out/asl-host") "run" (str root "/asl/packages/asl-gates/src/runnerMain.asl")) argv))
        (script (str "exec " (stringJoin (map (fn [(s String)] -> String (str "'" (stringReplace s "'" "'\\''") "'")) cmd) " ")))]
    (mt (gr/runCommand! (list "/bin/sh" "-c" script) dir (some (childEnv! env)))
      ((err e) (do (assert false (str "ASL runner spawned for " (stringJoin argv " ") ": " e)) (gr/Captured :exit 127 :stdout "" :stderr e)))
      ((ok r) r)))

fn replayCases! cases: (List p/SExpr) n: Int64 -> Int64
  (mt (listHead cases)
    ((none) n)
    ((some caseForm)
      (let [(xs (items caseForm))
            (id (stringField xs ":id"))
            (kind (stringField xs ":kind"))
            (repoFields (items (optionOr (field xs ":repo") (p/makeList (list)))))
            (setup (stringField repoFields ":setup"))
            (tmp (optionOr (envGet "TMPDIR") "/tmp"))
            (made (gr/runCommand! (list "/usr/bin/mktemp" "-d" (str tmp "/runnerParity." id ".XXXXXX")) (workspaceRoot!) (some (childEnv! (list)))))]
        (mt made
          ((err e) (do (assert false (str id ": temporary repository created: " e)) n))
          ((ok dirResult)
            (let [(dir (stringTrim dirResult.stdout))
                  (setupResult (gr/runCommand! (list "/bin/sh" "-c" setup) dir (some (childEnv! (list))) ))
                  (argv (fixtureArgv (optionOr (field xs ":argv") (p/makeVect (list)))))
                  (env (fixtureEnv (optionOr (field xs ":env") (p/makeVect (list)))))]
              (do
                (assert (= dirResult.exit 0) (str id ": scratch directory created"))
                (mt setupResult
                  ((err e) (assert false (str id ": synthetic Git repo setup ran: " e)))
                  ((ok setupRun) (assert (= setupRun.exit 0) (str id ": synthetic Git repo setup exits 0: " setupRun.stderr))))
                (if (= kind "chooseBase")
                  (let [(chosen (rm/chooseBaseAt! dir))
                        (wantBase (stringField xs ":base"))
                        (base (mt (pairFirst chosen) ((some rec) rec.sha) ((none) "none")))
                        (wantProblems (map (fn [(v p/SExpr)] -> String (gr/decodeString (atom v))) (items (optionOr (field xs ":problems") (p/makeVect (list))))))]
                    (do
                      (assert (= base wantBase) (str id ": chooseBase base matches Python recording"))
                      (assert (= (pairSecond chosen) wantProblems) (str id ": chooseBase problems match Python recording"))))
                  (let [(actual (runnerCall! dir argv env))
                        (wantExit (optionOr (stringToInt64 (atom (optionOr (field xs ":exit") (p/makeAtom "-999")))) -999))
                        (wantOut (stringField xs ":stdout"))
                        (wantErr (stringField xs ":stderr"))]
                    (do
                      (assert (= actual.exit wantExit) (str id ": runner exit matches Python recording"))
                      (assert (= actual.stdout wantOut) (str id ": runner stdout matches Python recording"))
                      (assert (= actual.stderr wantErr) (str id ": runner stderr matches Python recording")))))
                (assert (ok? (pathRemove dir)) (str id ": scratch repository removed"))
                (replayCases! (optionOr (listTail cases) (list)) (+ n 1)))))))))

fn replayChooseBaseFixtures! -> Bool
  (= (replayCases! (filter (fn [(item p/SExpr)] -> Bool
                               (= (stringField (items item) ":kind") "chooseBase"))
                           (fixtureCases!))
                   0)
     2)

fn testCorpusParity! -> Bool
  (do
    (assert (>= (listLength (stringLines (optionOr (mt (fileReadString "asl/packages/asl-gates/tests/fixtures/runner/corpus.txt") ((ok s) (some s)) ((err _) (none))) ""))) 25) "fixture source corpus still covers at least 25 suites")
    (assert (= (listLength (fixtureCases!)) 8) "all eight synthetic runner recordings load")
    (assert (= (listLength (filter (fn [(caseForm p/SExpr)] -> Bool (= (stringField (items caseForm) ":kind") "cli")) (fixtureCases!))) 3) "CLI fixtures include no command, unknown command, and run")
    (assert (= (listLength (filter (fn [(caseForm p/SExpr)] -> Bool (= (stringField (items caseForm) ":kind") "ledger")) (fixtureCases!))) 2) "ledger fixtures include held red and stale green")
    (assert (= (listLength (filter (fn [(caseForm p/SExpr)] -> Bool (= (stringField (items caseForm) ":kind") "timeout")) (fixtureCases!))) 1) "timeout fixture is recorded")
    (assert (= (fixtureEnv (optionOr (field (items (p/parseSexpr "(:env (:A \"1\" :B \"x y\"))")) ":env") (p/makeList (list)))) (list "A=1" "B=x y")) "fixture :env plist decodes to NAME=value entries")
    (assert (= (replayCases! (fixtureCases!) 0) 8) "all eight synthetic runner recordings replay exactly through ASL only")
    (assert (ok? (fileReadString (timesLedger!))) "runner calls wrote the private gateTimes ledger")
    (assert (ok? (pathRemove (timesLedger!))) "private gateTimes ledger removed")
    (assert (gr/replayCorpus!) "pinned 25-suite runner.py recordings replay through ASL only")
    true)

fn ! runTests -> Bool
  (do
    (assert (testCorpusParity!) "corpus parity")
    true)
