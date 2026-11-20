(module asl-tools/coord/tests/trainKeepTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref N2-TRAIN-RED-VANISH :do "the merge stage keeps every train attempt whole: a temp source repo with two unit branches and a temp dev clone whose bin/asl stands in for the train, printing a numbered line, a streamed red and a receipt that is red only on the base, and exiting 1. Three attempts of one unit under :conductorTrainKeep 2 leave the two newest files, each with its attempt row and the full output; without the row the adopted default keeps all three; the signature reads train baseRed, apart from train red")

fn receipt fresh: String pre: String -> String
  (str "(:train :head \"abc\" :merged \"def\" :branches (\"sh/X\") :changed 1 :selected 1 :keyMs 1 :cached 0 :ran 1 :green 0 :invariants 0"
       " :red (" fresh ") :preexisting (" pre ") :assertLoss () :baseKnown 0 :knownRed () :blocked (:fresh 0 :preexisting 1)"
       " :carried (:forced () :added ()) :redsNotSelected () :suites (\"asl/b/bTest.asl\") :cachedSuites () :ranSuites (\"asl/b/bTest.asl\") :seconds 1)")

fn preRow -> String
  "(\"asl/b/bTest.asl\" \"base\" 1 0 :kind suite :why preexisting)"

fn stubText -> String
  (str "#!/bin/sh\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\nN=$(( $(cat \"$D/.git/trainCalls\" 2>/dev/null || echo 0) + 1 ))\necho $N > \"$D/.git/trainCalls\"\n"
       "echo '(:redLive \"asl/b/bTest.asl\" 1 0 :kind suite)'\necho \"attempt $N line\"\ncat \"$D/.git/trainReceipt\"\nexit 1\n")

fn ! devClone! root: String -> String
  (let [(dev (str root "/dev"))
        (made (pf/sh (str "git clone -q " root "/repo " dev " && cd " dev " && git config user.email t@example.invalid && git config user.name t && git checkout -q -b dev && mkdir -p bin && echo bin/asl >> .git/info/exclude && echo madeOk")))
        (w1 (fileWrite (str dev "/bin/asl") (stubText)))
        (w2 (fileWrite (str dev "/.git/trainReceipt") (str (receipt "" (preRow)) "\n")))
        (mode (pf/sh (str "chmod 755 " dev "/bin/asl && echo modeOk")))]
    (if (and (stringContains? made "madeOk") (and (ok? w1) (and (ok? w2) (stringContains? mode "modeOk")))) dev ""))

fn stubPass rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 0 "(:mergeCheck :verdict pass)")

fn ! filesOf store: String id: String -> (List String)
  (cd/attemptFiles (resultOr (dirList (cd/trainsDir store id)) (list)))

fn testSig -> Bool
  (let [(live "(:redLive \"asl/a/aTest.asl\" 1 3 :kind suite)\n(:redLive \"asl/b/bTest.asl\" 1 0 :kind suite)\n")
        (both (cd/gateSig (str live (receipt "(\"asl/a/aTest.asl\" \"sh/X\" 1 3 :kind suite :why only)" (preRow)) "\n")))
        (base (cd/gateSig (str live (receipt "" (preRow)) "\n")))]
    (do (assert (= both "train red: asl/a/aTest.asl") (str "a red of the unit names only the fresh suite: " both))
        (assert (= base "train baseRed: asl/b/bTest.asl") (str "a train red only on the base says so and names the base-red suite: " base))
        (assert (= (cd/trainKeepOf "") (cd/trainKeepDefault)) "no config row: the adopted default")
        (assert (= (cd/trainKeepOf "(:aslConfig\n  :conductorTrainKeep 3\n)\n") 3) "the config row sets the count")
        (assert (and (= (cd/trainKeepOf "  :conductorTrainKeep 0\n") 1) (= (cd/trainKeepOf "  :conductorTrainKeep 99999\n") 500)) "the count stays within 1..500")
        (assert (= (cd/attemptFiles (list "000010.out" "x.out" "000002.out" "000003.tmp" "notes")) (list "000002.out" "000010.out")) "attempt files are the numbered .out files, oldest first")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "trainKeep" "w"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (wt1 (pf/seedUnit! root (pf/unitIn "T1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wt2 (pf/seedUnit! root (pf/unitIn "T2" "sh check.sh impl.txt") "merging" "impl.txt"))
        (dev (devClone! root))
        (store (str root "/store"))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--dev-repo" dev "--dev" "dev" "--worktrees" (str root "/wts") "--home" (str root "/home")) store))
        (cfg (fileWrite (str root "/repo/.asl.config.asn") "(:aslConfig\n  :conductorTrainKeep 2\n)\n"))
        (u1 (pf/unitIn "T1" "sh check.sh impl.txt"))
        (c1 (pf/cuIn "T1" "merging" wt1 "sh/T1"))
        (r1 (cd/mergeResWith rc store u1 c1 stubPass))
        (after1 (filesOf store "T1"))
        (r2 (cd/mergeResWith rc store u1 c1 stubPass))
        (r3 (cd/mergeResWith rc store u1 c1 stubPass))
        (after3 (filesOf store "T1"))
        (last (resultOr (fileReadString (str (cd/trainsDir store "T1") "/000003.out")) ""))
        (times (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trainTimes :unit \"T1\" ")) (pf/journalLines store)))
        (gone (pathRemove (str root "/repo/.asl.config.asn")))
        (pinned (pf/sh (str "cd " wt2 " && mkdir -p .asl && printf pin > .asl/gatewayProfilePin.asn && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm pin && echo pinOk")))
        (u2 (pf/unitIn "T2" "sh check.sh impl.txt"))
        (c2 (pf/cuIn "T2" "merging" wt2 "sh/T2"))
        (q1 (cd/mergeResWith rc store u2 c2 stubPass))
        (q2 (cd/mergeResWith rc store u2 c2 stubPass))
        (q3 (cd/mergeResWith rc store u2 c2 stubPass))
        (afterDefault (filesOf store "T2"))
        (netT2 (pf/sh (str "cd " root "/repo && git diff --name-only main...sh/T2")))
        (dropRows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:pinDropped :unit \"T2\" :sha ")) (pf/journalLines store)))
        ; (:m :ref COND-TRAIN-PIN-WEAK :do "T3 starts from a main that carries a pin and changes it; main's pin then moves, so the branch would conflict")
        (pin ".asl/gatewayProfilePin.asn")
        (mainPin (pf/sh (str "cd " root "/repo && mkdir -p .asl && printf '(:profile \"target\")\\n' > " pin " && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm 'main carries a pin' && echo mainOk")))
        (u3 (pf/unitIn "T3" "sh check.sh impl.txt"))
        (wt3 (pf/seedUnit! root u3 "merging" "work3.txt"))
        (c3 (pf/cuIn "T3" "merging" wt3 "sh/T3"))
        (own3 (pf/sh (str "cd " wt3 " && printf '(:profile \"three\")\\n' > " pin " && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm 'wip changes the pin' && echo ownOk")))
        (moved (pf/sh (str "cd " root "/repo && printf '(:profile \"moved\")\\n' > " pin " && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm 'the pin of main moves' && echo movedOk")))
        (conflict3 (pf/sh (str "cd " root "/repo && (git merge -q --no-ff -m m sh/T3 >/dev/null 2>&1 && echo mergedEarly || (git merge --abort; echo conflictOk))")))
        (drop3 (cd/pinDrop! rc store "T3" c3))
        (again3 (cd/pinDrop! rc store "T3" c3))
        (net3 (stringTrim (pf/sh (str "cd " root "/repo && git diff --name-only main...sh/T3"))))
        (kept3 (resultOr (fileReadString (str wt3 "/" pin)) ""))
        (last3 (pf/sh (str "cd " root "/repo && git log -1 --format=%s sh/T3 && git show --name-only --format= sh/T3")))
        (merge3 (pf/sh (str "cd " root "/repo && git merge -q --no-ff -m m sh/T3 && git show main:" pin " && git ls-tree -r --name-only main")))
        (rows3 (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:pinDropped :unit \"T3\" :sha ")) (pf/journalLines store)))
        (skips (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:pinDropSkipped ")) (pf/journalLines store)))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))
        (stubLeft (fr/stubDirsOwnedBy (procSelf)))]
    (do (assert (and stubGone (listEmpty? stubLeft)) (str "the stand-in host dir of this run is removed before any assert: " (stringJoin stubLeft " ")))
        (assert (testSig) "signature and keep-count rules")
        (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (and (not (stringEmpty? wt1)) (and (not (stringEmpty? wt2)) (ok? cfg))))) "fixture: source repo, dev clone with the stand-in train, two unit branches, the config row")
        (assert (and (= r1.ok 0) (= r1.sig "train baseRed: asl/b/bTest.asl")) (str "a train red only on the base fails the merge with its own signature: " r1.sig))
        (assert (= after1 (list "000001.out")) (str "the first attempt is kept: " (stringJoin after1 " ")))
        (assert (and (= r2.ok 0) (= r3.ok 0) (= after3 (list "000002.out" "000003.out"))) (str "three attempts under :conductorTrainKeep 2 leave the two newest: " (stringJoin after3 " ")))
        (assert (stringStartsWith? last "(:trainAttempt :unit \"T1\" :n 3 :branch \"sh/T1\" ") (str "the kept file starts with its attempt row: " (cd/utf8Clip last 200)))
        (assert (and (stringContains? last " :exit 1 ") (stringContains? last " :sig \"train baseRed: asl/b/bTest.asl\")")) (str "the row carries exit and signature: " (cd/utf8Clip last 300)))
        (assert (and (stringContains? last "attempt 3 line") (stringContains? last "(:redLive \"asl/b/bTest.asl\" 1 0 :kind suite)")) "the whole train output follows, streamed rows included")
        (assert (and (stringContains? last " :suites (\"asl/b/bTest.asl\") :cachedSuites () :ranSuites (\"asl/b/bTest.asl\")") (stringContains? last " :preexisting ((\"asl/b/bTest.asl\" \"base\" ")) "and the receipt with its selected, cached and run lists and the base red")
        (assert (and (= (listLength times) 3) (stringContains? (optionOr (listLast times) "") " :n 3 :exit 1 ")) (str "each attempt leaves its (:trainTimes ...) row in the journal: " (stringJoin times "|")))
        (assert (and (ok? gone) (and (= q1.ok 0) (and (= q2.ok 0) (= q3.ok 0)))) "the second unit runs three attempts without the config row")
        (assert (and (stringContains? pinned "pinOk") (and (= (listLength dropRows) 1) (and (stringContains? netT2 "impl.txt") (not (stringContains? netT2 "gatewayProfilePin"))))) (str "a branch that carries the gateway profile pin loses it before its first train, one commit and one journal row over three merges: rows " (stringFromInt64 (listLength dropRows)) " diff " netT2))
        (assert (and (stringContains? mainPin "mainOk") (and (not (stringEmpty? wt3)) (and (stringContains? own3 "ownOk") (and (stringContains? moved "movedOk") (stringContains? conflict3 "conflictOk"))))) (str "fixture: T3 changed the pin its base carries and conflicts with main on it: " conflict3))
        (assert (and drop3 (and (not again3) (= (listLength rows3) 1))) (str "pinDrop! commits once, journalled once; a second call has nothing to do: rows " (stringFromInt64 (listLength rows3))))
        (assert (listEmpty? skips) (str "branches with no pin change are left alone, no commit is tried on them: " (stringJoin skips "|")))
        (assert (= net3 "work3.txt") (str "the branch now differs from its merge base by its work alone: " net3))
        (assert (and (stringContains? last3 "unit T3: the gateway profile pin leaves the branch") (stringEndsWith? (stringTrim last3) pin)) (str "one commit that touches only the pin: " last3))
        (assert (= kept3 "(:profile \"three\")\n") (str "the pin file in the worktree is as the gateway wrote it: " kept3))
        (assert (and (stringContains? merge3 "(:profile \"moved\")") (stringContains? merge3 "work3.txt")) (str "the branch merges, main keeps its pin and gets the work: " merge3))
        (assert (= afterDefault (list "000001.out" "000002.out" "000003.out")) (str "the adopted default keeps all three: " (stringJoin afterDefault " ")))
        true))
