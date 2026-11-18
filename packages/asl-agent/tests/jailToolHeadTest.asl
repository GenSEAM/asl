(module aslAgent/tests/jailToolHeadTest
  :x [runTests]
  :i [(aslAgent/jail :a jl)])

fn ! mtimeOf! p: String -> Int64
  (match (fileLstat p) ((ok st) st.mtimeNs) ((err _) -1))

fn ! jailFor! base: String tag: String snapshot: String -> (Pair Int64 Int64)
  (let [fakeHome (str base "/" tag "Home")
        shared (str fakeHome "/.asl/run/nativeCli")
        tool (str base "/" tag "Tool")
        task (str base "/" tag "Task")
        cli (str shared "/cli-" tag)
        made (and (ok? (dirCreate (str cli "/src/src"))) (and (ok? (dirCreate (str tool "/src"))) (ok? (dirCreate (str task "/.git")))))
        toolReal (resultOr (realPath tool) tool)
        taskReal (resultOr (realPath task) task)
        head (str shared "/" (jl/cliHeadName toolReal))
        wrote (and (ok? (fileWrite (str cli "/deps") "src/a.asl\n"))
                (and (ok? (fileWrite (str cli "/src/src/a.asl") snapshot))
                  (and (ok? (fileWrite (str cli "/bin") "binary\n"))
                    (and (ok? (fileWrite head (str cli "\n")))
                      (and (ok? (fileUtime head 1700000000000000000))
                        (ok? (fileWrite (str tool "/src/a.asl") "fn a -> Int64\n  1\n")))))))
        inherited (list "PATH=/usr/bin:/bin" (str "ASL_CLI_ROOT=" toolReal))
        rows (jl/childEnvIn! taskReal inherited (list) fakeHome true)
        priv (str (jl/jailHome taskReal) "/.asl/run/nativeCli/" (jl/cliHeadName toolReal))]
    (pair (mtimeOf! priv) (mtimeOf! (str toolReal "/src/a.asl"))))

; (:m :ref LEON-STEP-BODY-LOST :do "a task whose root is its own fresh git repository (a test fixture, a consumer project) runs the tool root's bin/asl in its jail: the private head of the tool root is checked against the tool root's sources, so a built CLI whose snapshot matches them is stamped fresh and not rebuilt (grader 2026-11-18: stepBodyLostTest and writeFailTopTest rebuilt the CLI for 263 s in the fixture's jail and the write got ERR_NATIVE_STALE); a CLI whose snapshot differs stays older than its sources, so bin/asl still rebuilds it")
fn ! runTests -> Bool
  (let [base (str (optionOr (envGet "TMPDIR") "/tmp") "/jailToolHead" (stringFromInt64 (monotonicNs)))
        fresh (jailFor! base "fits" "fn a -> Int64\n  1\n")
        stale (jailFor! base "moved" "fn a -> Int64\n  0\n")
        cleaned (ok? (pathRemove base))]
    (do
      (assert (and (> (pairFirst fresh) 0) (>= (pairFirst fresh) (pairSecond fresh))) (str "the tool root's private head is not older than its sources when the CLI snapshot matches them, got head " (stringFromInt64 (pairFirst fresh)) " source " (stringFromInt64 (pairSecond fresh))))
      (assert (and (> (pairFirst stale) 0) (< (pairFirst stale) (pairSecond stale))) (str "a CLI whose snapshot differs from the tool root's sources stays older than them, got head " (stringFromInt64 (pairFirst stale)) " source " (stringFromInt64 (pairSecond stale))))
      true))
