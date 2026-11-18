(module aslAgent/tests/jailTaskHeadTest
  :x [runTests]
  :i [(aslAgent/jail :a jl)])

fn ! mtimeOf! p: String -> Int64
  (match (fileLstat p) ((ok st) st.mtimeNs) ((err _) -1))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn srcT -> Int64
  1750000000000000000

fn ! scenario! base: String tag: String aText: String bText: String bHead: String bSnap: String bStamp: Int64 -> String
  (let [fakeHome (str base "/" tag "Home")
        shared (str fakeHome "/.asl/run/nativeCli")
        tool (str base "/" tag "A")
        task (str base "/" tag "B")
        made (and (ok? (dirCreate (str shared "/cli-a/src/src"))) (and (ok? (dirCreate (str shared "/cli-b/src/src"))) (and (ok? (dirCreate (str tool "/src"))) (ok? (dirCreate (str task "/src"))))))
        toolReal (resultOr (realPath tool) tool)
        taskReal (resultOr (realPath task) task)
        hA (jl/cliHeadName toolReal)
        hB (jl/cliHeadName taskReal)
        w1 (and (ok? (fileWrite (str shared "/cli-a/deps") "src/a.asl\n")) (and (ok? (fileWrite (str shared "/cli-a/src/src/a.asl") aText)) (ok? (fileWrite (str shared "/cli-a/bin") "binA\n"))))
        w2 (and (ok? (fileWrite (str shared "/cli-b/deps") "src/a.asl\n")) (and (ok? (fileWrite (str shared "/cli-b/src/src/a.asl") bSnap)) (ok? (fileWrite (str shared "/cli-b/bin") "binB\n"))))
        w3 (and (ok? (fileWrite (str shared "/" hA) (str shared "/cli-a\n"))) (ok? (fileUtime (str shared "/" hA) 1800000000000000000)))
        w4 (if (stringEmpty? bHead) true (and (ok? (fileWrite (str shared "/" hB) (str shared "/" bHead "\n"))) (ok? (fileUtime (str shared "/" hB) bStamp))))
        w5 (and (ok? (fileWrite (str tool "/src/a.asl") aText)) (ok? (fileUtime (str tool "/src/a.asl") (srcT))))
        w6 (and (ok? (fileWrite (str task "/src/a.asl") bText)) (and (ok? (fileUtime (str task "/src/a.asl") (srcT))) (and (ok? (dirCreate (str task "/bin"))) (ok? (fileWrite (str task "/bin/asl") "#!/bin/sh\n")))))
        inherited (list "PATH=/usr/bin:/bin" (str "ASL_CLI_ROOT=" toolReal))
        rows (jl/childEnvIn! taskReal inherited (list) fakeHome true)
        priv (str (jl/jailHome taskReal) "/.asl/run/nativeCli")
        pa (str priv "/" hA)
        pb (str priv "/" hB)
        ta (stringTrim (readText! pa))
        tb (stringTrim (readText! pb))
        binA (stringTrim (readText! (str ta "/bin")))
        binB (stringTrim (readText! (str tb "/bin")))
        freshA (and (> (mtimeOf! pa) 0) (>= (mtimeOf! pa) (srcT)))
        freshB (and (> (mtimeOf! pb) 0) (>= (mtimeOf! pb) (srcT)))
        report (stringReplace (readText! (str (jl/jailHome taskReal) "/.asl/seedReport.asn")) "\n" "|")]
    (str "(:probe " tag " :fixture " (if (and made (and w1 (and w2 (and w3 (and w4 (and w5 w6)))))) "ok" "BAD")
      " :headA " (if (> (mtimeOf! pa) 0) binA "absent") " :headAFresh " (if freshA "yes" "no-REBUILD")
      " :headB " (if (> (mtimeOf! pb) 0) binB "absent") " :headBFresh " (if (> (mtimeOf! pb) 0) (if freshB "yes" (if (= (mtimeOf! pb) 1000000000) "verifyStamp(refresh-verify)" "no-REBUILD")) "absent-COLDBUILD")
      " :report \"" report "\")"))

fn want? line: String head: String fresh: String -> Bool
  (and (stringContains? line ":fixture ok") (and (stringContains? line ":headA binA :headAFresh yes") (stringContains? line (str ":headB " head " :headBFresh " fresh))))

fn ! runTests -> Bool
  (let [base (str (optionOr (envGet "TMPDIR") "/tmp") "/jailTaskHead" (stringFromInt64 (monotonicNs)))
        same "fn a -> Int64\n  1\n"
        other "fn a -> Int64\n  2\n"
        a1 (scenario! base "a1noOwnHead" same same "" "" 0)
        a2 (scenario! base "a2ownHeadOld" same same "cli-a" "" 1700000000000000000)
        b1 (scenario! base "b1noOwnHead" same other "" "" 0)
        b3 (scenario! base "b3ownStaleOld" same other "cli-b" same 1700000000000000000)
        cleaned (ok? (pathRemove base))]
    (do
      (assert (want? a1 "binA" "yes") (str "a1: a task with the tool's CLI sources and no shared head of its own borrows the tool entry, fresh, no build: " a1))
      (assert (want? a2 "binA" "yes") (str "a2: a task head older than its sources whose entry fits them is restamped, no rebuild: " a2))
      (assert (want? b1 "binA" "verifyStamp(refresh-verify)") (str "b1: a task whose CLI sources differ and has no head gets the verify stamp, so bin/asl checks and builds: " b1))
      (assert (want? b3 "binB" "no-REBUILD") (str "b3: a task head whose own entry no longer fits its sources stays old, so bin/asl rebuilds: " b3))
      (assert cleaned "the fixture directory was removed")
      true))
