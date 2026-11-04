(module aslAgent/tests/poolTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/pool :a pl) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-POOL-20261026 :do "drives pool/poolMain! in-process against script/<id> providers: each task sleeps 1 s in a run step and writes its own file, so a serial pool shows end-before-start stamps and a parallel one shows every pair of tasks running at once")

fn ! initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
    (gk/initGitRepo! root "poolTest" "pool-test@example.invalid"))

fn ! fixture! root: String id: String replies: (List String) -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
    (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" id ".asn") (rk/scriptFixtureTextFromReplies! id replies))))

fn form root: String id: String owns: (List String) -> String
  (str "(:agent :task \"Run the step, then finish.\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
       "\" :owns (" (stringJoin (map (fn [(o String)] -> String (str "\"" o "\"")) owns) " ") ")"
       " :mode \"scout\" :budget 3 :contextTokens 8000)")

fn writeReply file: String -> String
  (str "(:step :op \"run\" :cmd \"sleep 1; mkdir -p src; echo done > " file "\")\n(:done)")

fn ! exists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! dirExists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isDir) ((err _) false))

fn field line: String key: String -> String
  (match (stringIndexOf line key)
    ((none) "")
    ((some i) (let [(rest (c/sliceOf line (+ i (stringLength key)) (stringLength line)))]
                (c/sliceOf rest 0 (optionOr (stringIndexOf rest " ") (stringLength rest))))))

fn slotsOf summary: String -> (List String)
  (filter (fn [(s String)] -> Bool (stringStartsWith? s ":idx ")) (stringSplit summary "(:slot "))

fn intOf s: String key: String -> Int64
  (optionOr (stringToInt64 (field s key)) -1)

fn slotAt slots: (List String) idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (= (intOf s ":idx ") idx)) slots)) "")

fn overlap? a: String b: String -> Bool
  (and (< (intOf a ":startNs ") (intOf b ":endNs ")) (< (intOf b ":startNs ") (intOf a ":endNs ")))

fn ! concurrent! repoRoot: String -> Bool
  (let [(roots (map (fn [(i Int64)] -> String (rk/freshRecorderRoot! (str "poolPar" (stringFromInt64 i)))) (range 0 3)))
        (ready (fold (fn [(acc Bool) (r String)] -> Bool (and acc (and (initRepo! r) (fixture! r "poolPar" (list (writeReply "out.txt")))))) true roots))
        (res (pl/poolMain! (map (fn [(r String)] -> String (form r "poolPar" (list "out.txt"))) roots) repoRoot repoRoot 0))
        (slots (slotsOf res.stdout))
        (s0 (slotAt slots 0)) (s1 (slotAt slots 1)) (s2 (slotAt slots 2))
        (latestStart (fold max 0 (map (fn [(s String)] -> Int64 (intOf s ":startNs ")) slots)))
        (earliestEnd (fold min 9223372036854775807 (map (fn [(s String)] -> Int64 (intOf s ":endNs ")) slots)))
        (journals (map (fn [(s String)] -> String (field s ":journal ")) slots))
        (journalsExist (listAll? (fn [(p (Pair String String))] -> Bool (exists?! (str (pairFirst p) "/" (stringReplace (pairSecond p) "\"" ""))))
                                 (zip roots journals)))
        (written (listAll? (fn [(r String)] -> Bool (exists?! (str r "/out.txt"))) roots))
        (wall (intOf res.stdout ":wallMs "))
        (sum (intOf res.stdout ":sumMs "))
        (cleaned (listAll? (fn [(r String)] -> Bool (ok? (pathRemove r))) roots))]
    (do
      (println (str "pool wallMs " wall " sumMs " sum))
      (assert ready "three fixture repos and scripts written")
      (assert (= res.exitCode 0) (str "a pool of three disjoint tasks exits 0: " res.stdout))
      (assert (stringStartsWith? res.stdout "(:poolReceipt :tasks 3 :admitted 3 :lanes 3 :ok 3 :failed 0 :refused 0 ") "the summary counts three admitted lanes, all ok")
      (assert (= (listLength slots) 3) "one slot per task")
      (assert (listAll? (fn [(s String)] -> Bool (stringContains? s ":status :ok :exit 0")) slots) "every slot carries its own ok receipt")
      (assert (and (overlap? s0 s1) (and (overlap? s0 s2) (overlap? s1 s2))) "every pair of tasks overlaps: each starts before the other ends")
      (assert (< latestStart earliestEnd) "the last task to start began before the first task to end finished: all three ran at once")
      (assert (= (listLength (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) journals))) 3) "three distinct journals")
      (assert journalsExist "each task's journal is under its own root")
      (assert written "each task's run step left its file in its own root")
      (assert (< wall sum) "the pool wall time is below the sum of the task times")
      (assert cleaned "fixture roots removed")
      true))

fn refuseLimits -> pl/PoolLimits
  (pl/PoolLimits :slots 0 :laneMs 0 :graceMs 30000 :maxDesc 64 :onOverlap "refuse")

fn ! refusesOverlap! repoRoot: String -> Bool
  (let [(shared (rk/freshRecorderRoot! "poolOwnsShared"))
        (other (rk/freshRecorderRoot! "poolOwnsOther"))
        (ready (and (and (initRepo! shared) (initRepo! other))
                    (and (fixture! shared "poolOwns" (list (writeReply "src/a.txt"))) (fixture! other "poolOwns" (list (writeReply "out.txt"))))))
        (res (pl/poolMainWith! (list (form shared "poolOwns" (list "src")) (form other "poolOwns" (list "out.txt")) (form shared "poolOwns" (list "src/a.txt")))
                               repoRoot repoRoot (refuseLimits) pl/runTask!))
        (untouched (and (not (exists?! (str shared "/src/a.txt"))) (not (dirExists?! (str shared "/.asl/run")))))
        (otherRan (exists?! (str other "/out.txt")))
        (cleaned (and (ok? (pathRemove shared)) (ok? (pathRemove other))))]
    (do
      (assert ready "overlap fixture repos written")
      (assert untouched "neither refused task wrote a file or opened a journal under the shared root")
      (assert (= res.exitCode 2) (str "a pool with a refused pair exits 2: " res.stdout))
      (assert (stringContains? res.stdout "(:refused :idx 0 :error ERR_OWNS_OVERLAP :with (2) ") "task 0 (src) is refused against task 2")
      (assert (stringContains? res.stdout "(:refused :idx 2 :error ERR_OWNS_OVERLAP :with (0) ") "task 2 (src/a.txt) is refused against task 0")
      (assert (stringContains? res.stdout ":tasks 3 :admitted 1 :lanes 1 :ok 1 :failed 0 :refused 2 ") "only the disjoint task is admitted")
      (assert otherRan "the disjoint task still ran")
      (assert cleaned "fixture roots removed")
      true))

fn ! failureIsolated! repoRoot: String -> Bool
  (let [(bad (rk/freshRecorderRoot! "poolFailBad"))
        (good (rk/freshRecorderRoot! "poolFailGood"))
        (ready (and (and (initRepo! bad) (initRepo! good))
                    (and (fixture! good "poolA" (list (writeReply "a.txt"))) (fixture! good "poolB" (list (writeReply "b.txt"))))))
        (res (pl/poolMain! (list (form bad "poolAbsent" (list "out.txt")) (form good "poolA" (list "a.txt")) (form good "poolB" (list "b.txt")))
                           repoRoot repoRoot 0))
        (slots (slotsOf res.stdout))
        (s0 (slotAt slots 0)) (s1 (slotAt slots 1)) (s2 (slotAt slots 2))
        (both (and (exists?! (str good "/a.txt")) (exists?! (str good "/b.txt"))))
        (cleaned (and (ok? (pathRemove bad)) (ok? (pathRemove good))))]
    (do
      (assert ready "failure fixture repos written")
      (assert (= res.exitCode 1) (str "a pool with a failed task exits 1: " res.stdout))
      (assert (and (not (stringContains? s0 ":status :ok")) (!= (intOf s0 ":exit ") 0)) (str "the task without a script fixture fails: " s0))
      (assert (and (stringContains? s1 ":status :ok :exit 0") (stringContains? s2 ":status :ok :exit 0")) "both tasks of the other root complete ok")
      (assert both "both same-root tasks wrote their files")
      (assert (= (intOf s1 ":lane ") (intOf s2 ":lane ")) "tasks sharing a git root share one lane")
      (assert (>= (intOf s2 ":startNs ") (intOf s1 ":endNs ")) "a lane runs its tasks one after the other")
      (assert (stringContains? res.stdout ":tasks 3 :admitted 3 :lanes 2 :ok 2 :failed 1 :refused 0 ") "the summary counts the failure beside two ok tasks")
      (assert cleaned "fixture roots removed")
      true))

fn ! runTests -> Bool
  (let [(repoRoot (resultOr (realPath ".") "."))]
    (and (concurrent! repoRoot) (and (refusesOverlap! repoRoot) (failureIsolated! repoRoot))))
