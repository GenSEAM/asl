(module asl-gates/tests/suiteEnvTest
  :x [runTests main]
  :i [(asl-gates/suiteRunner :a sr)])

fn sessionKeys -> (List String)
  (list "ASL_ROOT" "ASL_LAUNCHED" "ASL_UNIT" "ASL_AGENT" "ASL_LEASE_PID" "ASL_CLI_ROOT" "ASL_PRELUDE")

fn ! jobLines kind: String suite: String -> (List String)
  (map (fn [(kv String)] -> String (str kind "\t" kv))
       (optionOr (sr/suiteJob! "/snap" suite 60).env (list)))

fn ! main args: (List String) -> (Result Int64 String)
  (do
    (println (stringJoin (listAppend (jobLines "sh" "tests/probeTest.sh") (jobLines "asl" "tests/probeTest.asl")) "\n"))
    (ok 0))

fn kindEnv lines: (List String) kind: String -> (List String)
  (let [(prefix (str kind "\t"))]
    (map (fn [(l String)] -> String (optionOr (stringSlice l (stringLength prefix) (stringLength l)) ""))
         (filter (fn [(l String)] -> Bool (stringStartsWith? l prefix)) lines)))

fn withKey env: (List String) key: String -> (List String)
  (filter (fn [(kv String)] -> Bool (stringStartsWith? kv (str key "="))) env)

fn checkKind! lines: (List String) kind: String -> Bool
  (let [(env (kindEnv lines kind))]
    (do
      (assert (listContains? env "ASL_SCRUB_PROBE=kept") (str kind " job keeps ordinary inherited environment"))
      (assert (listContains? env "ASL_IN_RUNNER=1") (str kind " job carries the runner's ASL_IN_RUNNER"))
      (assert (= (withKey env "ASL_GATE_TIMES") (list "ASL_GATE_TIMES=/snap/.git/aslGateTimes.asn"))
        (str kind " job has only the runner's ASL_GATE_TIMES: " (stringJoin (withKey env "ASL_GATE_TIMES") " ")))
      (fold (fn [(acc Bool) (key String)] -> Bool
              (do
                (assert (listEmpty? (withKey env key)) (str kind " job does not inherit " key))
                acc))
            true
            (sessionKeys))))

fn ! runTests -> Bool
  (let [(prelude (resultOr (realPath "asl/host/out/prelude.asl") "asl/host/out/prelude.asl"))
        (leaks (stringJoin (map (fn [(k String)] -> String (if (= k "ASL_PRELUDE") (str k "=" prelude) (str k "=leak"))) (listAppend (sessionKeys) (list "ASL_GATE_TIMES"))) " "))
        (child (processRun (str "env " leaks " ASL_SCRUB_PROBE=kept asl/host/out/asl-host run asl/packages/asl-gates/tests/suiteEnvTest.asl")))
        (lines (stringSplit child.stdout "\n"))]
    (do
      (assert (= child.exitCode 0) (str "child relaunch succeeds: " child.stderr))
      (checkKind! lines "sh")
      (checkKind! lines "asl")
      true))
