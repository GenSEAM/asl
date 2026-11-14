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
        (gone (pathRemove (str root "/repo/.asl.config.asn")))
        (u2 (pf/unitIn "T2" "sh check.sh impl.txt"))
        (c2 (pf/cuIn "T2" "merging" wt2 "sh/T2"))
        (q1 (cd/mergeResWith rc store u2 c2 stubPass))
        (q2 (cd/mergeResWith rc store u2 c2 stubPass))
        (q3 (cd/mergeResWith rc store u2 c2 stubPass))
        (afterDefault (filesOf store "T2"))
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
        (assert (and (ok? gone) (and (= q1.ok 0) (and (= q2.ok 0) (= q3.ok 0)))) "the second unit runs three attempts without the config row")
        (assert (= afterDefault (list "000001.out" "000002.out" "000003.out")) (str "the adopted default keeps all three: " (stringJoin afterDefault " ")))
        true))
