(module asl-tools/fleet/tests/childEnvHomeTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref WT-FRESH-HOST-BUILD :do "fr/childEnv with a HOME override and no ASL_NATIVE_TEST_CACHE passes the compile cache row cacheEnv! gives (in a linked worktree this HOME store, in a main checkout none, the child keeps the root cache); an explicit row wins and appears once; without a HOME override nothing is added")
fn ! rowsOf env: (List String) name: String -> (List String)
  (filter (fn [(r String)] -> Bool (stringStartsWith? r (str name "="))) env)

fn ! runTests -> Bool
  (let [(want (rowsOf (fr/cacheEnv!) "ASL_NATIVE_TEST_CACHE"))
        (linked (match (fileStat ".git") ((ok st) (not st.isDir)) ((err _) false)))
        (home (rowsOf (fr/childEnv (list "HOME=/nonexistent/childEnvHomeTest")) "ASL_NATIVE_TEST_CACHE"))
        (given (rowsOf (fr/childEnv (list "HOME=/nonexistent/childEnvHomeTest" "ASL_NATIVE_TEST_CACHE=/given")) "ASL_NATIVE_TEST_CACHE"))
        (plain (rowsOf (fr/childEnv (list "X_CHILD_ENV_TEST=1")) "ASL_NATIVE_TEST_CACHE"))
        (inherited (rowsOf (envList) "ASL_NATIVE_TEST_CACHE"))]
    (do (assert (= (listLength want) (if (or linked (not (listEmpty? inherited))) 1 0)) (str "cacheEnv! gives a compile cache row in a linked worktree: " (stringJoin want " ")))
        (assert (= home want) (str "a child with its own HOME gets the parent compile cache row: " (stringJoin home " ")))
        (assert (= given (list "ASL_NATIVE_TEST_CACHE=/given")) (str "an explicit compile cache row wins and appears once: " (stringJoin given " ")))
        (assert (= plain inherited) (str "without a HOME override only the inherited row passes: " (stringJoin plain " ")))
        true))
