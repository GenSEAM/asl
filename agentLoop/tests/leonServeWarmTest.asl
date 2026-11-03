(module asl/agentLoop/tests/leonServeWarmTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run)])

; (:m :ref LEONSERVE-COLD-START :do "the deploy warm step on the real daemon entry: nativeTest prepare compiles leonServe's closure into a scratch store and keeps its binary, and the next start of the entry (it answers its usage error before opening any socket) compiles nothing and spawns no clang, so a restart after a deploy begins from the store instead of from a 7 minute build")
fn ! sh! cwd: String script: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (listAppend (list "/bin/sh" "-c" script "sh") args) cwd (run/childEnv env)) (run/limits 3000 24))

fn ! spawned! log: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listHead (stringSplit l " ")) ""))
       (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString log) ""))))

fn storeEnv store: String log: String -> (List String)
  (list "ASL_ROOT=" "ASL_PRELUDE=" (str "ASL_NATIVE_TEST_CACHE=" store) "ASL_NATIVE_TRACE=1" (str "ASL_SPAWN_LOG=" log))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (base (str root "/.asl/cache/leonServeWarm-" (stringFromInt64 (procSelf))))
        (store (str base "/store"))
        (made (dirCreate store))
        (entry "asl/agentLoop/leonServe.asl")
        (prepared (sh! root "exec ./bin/asl run asl/tools/nativeTest.asl prepare \"$1\" 2>&1" (list entry) (storeEnv store (str base "/prepare.log"))))
        (prepareSpawns (spawned! (str base "/prepare.log")))
        (warm (sh! root "exec ./bin/asl run \"$1\" 2>&1" (list entry) (storeEnv store (str base "/warm.log"))))
        (warmSpawns (spawned! (str base "/warm.log")))
        (cleaned (sh! "/" "rm -rf \"$1\"" (list base) (list)))]
    (do
      (assert (ok? made) "the scratch store is created")
      (assert (= prepared.exit 0) (str "nativeTest prepare keeps a binary for the daemon entry: " prepared.out))
      (assert (listContains? prepareSpawns "clang") (str "the prepare compiles with clang, so the warm run below is measured against a real cold build: " (stringJoin prepareSpawns " ")))
      (assert (stringContains? warm.out "usage: leonServe") (str "the warm start reaches the daemon's own usage error: " warm.out))
      (refute (stringContains? warm.out "NATIVE-MODULE-PHASE") (str "the warm start lowers and compiles no module: " warm.out))
      (refute (listContains? warmSpawns "clang") (str "the warm start spawns no clang: " (stringJoin warmSpawns " ")))
      (assert (= cleaned.exit 0) "the scratch root is removed")
      true))
