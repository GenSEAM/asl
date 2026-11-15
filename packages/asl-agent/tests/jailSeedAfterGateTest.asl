(module aslAgent/tests/jailSeedAfterGateTest
  :x [runTests]
  :i [(aslAgent/aslOps :a o) (aslAgent/jail :a jl)])

; (:m :ref LOOPRED-JAIL-SEED :do "d8af79111 seeded the private caches only for a root with bin/asl, but a gate or run env (jl/childEnv!) on a fixture root still created them empty, and the seed skipped any cache whose directory existed, so the next asl read op saw an empty nativeCli and failed ERR_NATIVE_ABSENT; this gate runs the gate env first on a root without bin/asl, then a read op, and holds that the seeded nativeCli keeps only the active entry")
fn ! tmpBase! -> String
  (match (fileStat "/private/tmp") ((ok st) (if st.isDir "/private/tmp" "/tmp")) ((err _) "/tmp"))

fn ! cliDirs! home: String -> (List String)
  (filter (fn [n] (stringStartsWith? n "cli-")) (resultOr (dirList (str home "/.asl/run/nativeCli")) (list)))

fn ! runTests -> Bool
  (let [base (str (tmpBase!) "/leonjailseed-" (stringFromInt64 (monotonicNs)))
        root (str base "/root")
        repo (resultOr (realPath ".") ".")
        made (and (ok? (dirCreate base)) (ok? (dirCreate root)))
        wrote (fileWrite (str root "/a.txt") "SEEDMARK\n")
        gateEnv (jl/childEnv! root (envList) (list))
        home (jl/jailHome root)
        emptyBefore (listEmpty? (resultOr (dirList (str home "/.asl/run/nativeCli")) (list)))
        res (o/runAsl repo "(:read :file \"a.txt\")" root 300 none "subprocess")
        dirs (cliDirs! home)
        entries (resultOr (dirList (str home "/.asl/run/nativeCli")) (list))
        other (filter (fn [n] (not (or (stringStartsWith? n "head") (stringStartsWith? n "cli-")))) entries)
        cleaned (pathRemove base)]
    (do
      (assert made "the fixture root was created")
      (assert (not (ok? (fileStat (str root "/bin/asl")))) "the fixture root has no bin/asl")
      (assert emptyBefore "the gate env left the private nativeCli empty, the state the seed must handle")
      (assert (= (o/runExit res) 0) (str "an asl read op after the gate env exits 0: " (o/runStdout res) " " (o/runStderr res)))
      (assert (stringContains? (o/runStdout res) "SEEDMARK") (str "the read op returned the file content: " (o/runStdout res)))
      (assert (not (stringContains? (str (o/runStdout res) (o/runStderr res)) "ERR_NATIVE_ABSENT")) "no ERR_NATIVE_ABSENT")
      (assert (and (>= (listLength dirs) 1) (<= (listLength dirs) 2)) (str "the seeded nativeCli holds only the active cli directories: " (stringFromInt64 (listLength dirs))))
      (assert (<= (listLength other) 2) (str "the seeded nativeCli holds head pointers and cli directories only: " (stringJoin other " ")))
      (assert (ok? cleaned) "the fixture was removed")
      true))
