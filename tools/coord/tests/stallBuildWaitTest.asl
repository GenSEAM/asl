(module asl/tools/coord/tests/stallBuildWaitTest
  :x [runTests]
  :i [(asl-tools/coord/stall :a sl) (asl-tools/fleet/run :a fr)])

; (:m :ref STALL-BUILD-WAIT :do "fixture worktrees under a scratch dir in .asl/cache; file times are set with touch -t at fixed local minutes of 2020-01-01 and the now argument is derived from the stat of the journal, so ages need no sleeping and no clock; nothing is killed")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/stallBuildWaitTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! sh argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits 60 4))

fn ! mk dir: String -> Bool
  (= (sh (list "mkdir" "-p" dir)).exit 0)

fn ! stamp path: String text: String hhmm: String -> Bool
  (let [(parts (stringSplit path "/"))
        (_ (mk (stringJoin (listTake parts (- (listLength parts) 1)) "/")))
        (_ (fileWrite path text))]
    (= (sh (list "touch" "-t" (str "2020010" "1" hhmm) path)).exit 0))

; (:m :ref STALL-BUILD-WAIT :do "mkdir gives every directory of the fixture the real clock; the whole HOME subtree is restamped so file and directory times are the fixture's")
fn ! build wt: String file: String hhmm: String -> Bool
  (let [(home (str wt "/.asl/run/agentLoop/home"))
        (_ (stamp (str home "/.asl/run/" file) "o" hhmm))]
    (= (sh (list "find" home "-exec" "touch" "-t" (str "2020010" "1" hhmm) "{}" "+")).exit 0))

fn ! cleanup dir: String -> Bool
  (= (sh (list "rm" "-rf" dir)).exit 0)

fn min1 -> Int64
  60000

fn cfgRow row: String -> sl/Cfg
  (sl/cfgOf row)

fn plain -> sl/Cfg
  (cfgRow "(:stall :stalledMin 20 :sameOp 10 :emptyReplies 4 :escalateAfter 2 :everyS 60)")

fn ! journalAt wt: String hhmm: String -> Int64
  (let [(p (str wt "/.asl/run/agentLoop/s1.journal"))
        (_ (stamp p "(:served :turn 1 :model \"m\")\n(:turn 1 :reply \"(:step :op read :file a)\")\n" hhmm))]
    (sl/statMs p))

fn ! verdictAt cfg: sl/Cfg wt: String since: Int64 now: Int64 -> String
  (sl/verdictOf cfg (sl/signalOf! cfg (sl/Probe :id "U" :lane "l" :wt wt :alive true :sinceMs since) now))

; (:m :ref STALL-BUILD-WAIT :do "journal at 12:00 (J); builds at J+20 min, J+47 min or before the admit; a unit with a fresh build is ok until the journal passes buildMaxMin")
fn ! testBuild -> Bool
  (let [(root (scratch "b"))
        (_ (cleanup root))
        (a (str root "/a")) (b (str root "/b")) (c (str root "/c")) (d (str root "/d")) (e1 (str root "/e1")) (e2 (str root "/e2"))
        (ja (journalAt a "1200")) (jb (journalAt b "1200")) (jc (journalAt c "1200")) (jd (journalAt d "1200")) (je1 (journalAt e1 "1200")) (je2 (journalAt e2 "1200"))
        (_ (build a "nativeCli/cli-x/obj/out.o" "1220"))
        (_ (build c "nativeCli/cli-x/obj/out.o" "1247"))
        (_ (build d "nativeCli/cli-x/obj/out.o" "1130"))
        (_ (build e1 "hosts/h1/lock" "1220"))
        (_ (build e2 "jobserver/slot" "1220"))
        (cfg (plain))
        (cfg45 (cfgRow "(:stall :stalledMin 20 :buildMaxMin 45)"))
        (va (verdictAt cfg a ja (+ ja (* 25 (min1)))))
        (vb (verdictAt cfg b jb (+ jb (* 25 (min1)))))
        (vc (verdictAt cfg45 c jc (+ jc (* 50 (min1)))))
        (vcShort (verdictAt (cfgRow "(:stall :stalledMin 20 :buildMaxMin 60)") c jc (+ jc (* 50 (min1)))))
        (vd (verdictAt cfg d jd (+ jd (* 25 (min1)))))
        (dSince (sl/newestBuild! d jd))
        (dAll (sl/newestBuild! d 0))
        (ve1 (verdictAt cfg e1 je1 (+ je1 (* 25 (min1)))))
        (ve2 (verdictAt cfg e2 je2 (+ je2 (* 25 (min1)))))
        (_ (cleanup root))]
    (do (assert (= va "ok") (str "journal 25 min, build 5 min old: not stalled, got " va))
        (assert (= vb "stalled") (str "journal 25 min, no build: stalled as before, got " vb))
        (assert (= vc "stalled") (str "journal 50 min, fresh build, buildMaxMin 45: stalled, got " vc))
        (assert (= vcShort "ok") (str "the same at buildMaxMin 60: ok, got " vcShort))
        (assert (= vd "stalled") (str "a build file older than sinceMs is ignored: stalled, got " vd))
        (assert (= dSince 0) (str "newestBuild! drops a file older than sinceMs, got " (stringFromInt64 dSince)))
        (assert (> dAll 0) "and sees it with since 0")
        (assert (= ve1 "ok") (str "a fresh file under run/hosts: ok, got " ve1))
        (assert (= ve2 "ok") (str "a fresh file under run/jobserver: ok, got " ve2))
        true))

fn testConfig -> Bool
  (let [(none (cfgRow "(:stall :stalledMin 20)"))
        (set (cfgRow "(:stall :buildMaxMin 30)"))]
    (do (assert (and none.on (= none.buildMaxMin 45)) "a :stall row without :buildMaxMin is on with the default 45")
        (assert (and set.on (= set.buildMaxMin 30)) "a :buildMaxMin row is read")
        (assert (not (cfgRow "(:stall :buildMaxMin 0)").on) "buildMaxMin 0 is outside 1..1440")
        (assert (not (cfgRow "(:stall :buildMaxMin 1441)").on) "buildMaxMin 1441 is outside 1..1440")
        true))

fn ! runTests -> Bool
  (do (assert (testConfig) "buildMaxMin: default, read, range")
      (assert (testBuild) "build wait: fresh build holds a stall, cap, sinceMs, hosts and jobserver")
      true)
