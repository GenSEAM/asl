(module asl-tools/coord/tests/conductorMergeCheckTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref CONDUCTOR-MERGE-CHECK :do "the merge stage runs mergeCheck before the train, on a temp source repo with unit branches and a temp dev clone whose bin/asl answers audit with a canned receipt and records train calls; a clean branch merges and journals an exit 0 receipt, a branch that grows knownRed.asn is blocked with dev and train untouched, an unverifiable check holds the unit with one lead-stream row, and finish! parks a block or a hold without a failure count")
fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! devClone! root: String -> String
  (let [(dev (str root "/dev"))
        (made (pf/sh (str "git clone -q " root "/repo " dev " && cd " dev " && git config user.email t@example.invalid && git config user.name t && git checkout -q -b dev && mkdir -p bin"
                          " && printf '#!/bin/sh\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\nif [ \"$1\" = audit ]; then if [ \"$(cat \"$D/.git/auditMode\" 2>/dev/null)\" = junk ]; then echo nothing; exit 0; fi; echo \"(:audit :sub $2 :status :passed)\"; exit 0; fi\necho \"$@\" >> \"$D/.git/trainArgs\"\ngit -C \"$D\" merge --no-ff -q -m \"(:c :a t :do train)\" \"$2\" || exit 1\nexit 0\n' > bin/asl && chmod 755 bin/asl && echo bin/asl >> .git/info/exclude && echo madeOk")))]
    (if (stringContains? made "madeOk") dev ""))

; (:m :do "a unit branch whose one commit grows the shrink-only ledger .asl/mem/knownRed.asn")
fn ! seedGrowth! root: String u: st/Task -> String
  (let [(wt (pf/seedUnit! root u "merging" ""))
        (made (pf/sh (str "cd " wt " && mkdir -p .asl/mem && printf '(:suite \"t/aTest.asl\" :cause \"x\" :failedAssertDigest \"d1\")\\n' > .asl/mem/knownRed.asn && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm '(:c :a t :do grow)' && echo madeOk")))]
    (if (stringContains? made "madeOk") wt ""))

fn stubUnverified rc: cd/RealCfg c: cd/CUnit base: String -> (Pair Int64 String)
  (pair 3 "(:mergeCheck :verdict unverified :unverified (\"gates:deadline\") :structure () :regressions ())")

fn rowsOf root: String needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) (stringLines (resultOr (fileReadString (str root "/lead/stream.asn")) ""))))

fn journalOf root: String -> String
  (resultOr (fileReadString (cd/journalPath (str root "/store"))) "")

fn resOf ok: Int64 verdict: String sig: String -> cd/Res
  (cd/Res :ok ok :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict verdict :tiers "")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "mcTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 4 4))

fn ! parkOf! root: String id: String verdict: String sig: String -> cd/CUnit
  (let [(dir (str root "/store"))
        (u (pf/unitIn id "sh check.sh impl.txt"))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir (pf/cuIn id "merging" "" (str "sh/" id))))
        (c (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" "")))
        (_ (cd/finish! (ctxFor root) u c (resOf 0 verdict sig)))]
    (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" "")))

fn ! runTests -> Bool
  (let [(root (pf/scratch "condMc" "w"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (wtClean (pf/seedUnit! root (pf/unitIn "C1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtGrow (seedGrowth! root (pf/unitIn "K1" "sh check.sh impl.txt")))
        (wtHold (pf/seedUnit! root (pf/unitIn "H1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtStub (pf/seedUnit! root (pf/unitIn "H2" "sh check.sh impl.txt") "merging" "impl.txt"))
        (dev (devClone! root))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--dev-repo" dev "--dev" "dev" "--worktrees" (str root "/wts") "--home" (str root "/home")) (str root "/store")))
        (store (str root "/store"))
        (head0 (gitIn dev "rev-parse HEAD"))
        (rGrow (cd/mergeRes rc store (pf/unitIn "K1" "sh check.sh impl.txt") (pf/cuIn "K1" "merging" wtGrow "sh/K1")))
        (headGrow (gitIn dev "rev-parse HEAD"))
        (argsGrow (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (_ (fileWrite (str dev "/.git/auditMode") "junk"))
        (rHold (cd/mergeRes rc store (pf/unitIn "H1" "sh check.sh impl.txt") (pf/cuIn "H1" "merging" wtHold "sh/H1")))
        (headHold (gitIn dev "rev-parse HEAD"))
        (_ (fileWrite (str dev "/.git/auditMode") "ok"))
        (rStub (cd/mergeResWith rc store (pf/unitIn "H2" "sh check.sh impl.txt") (pf/cuIn "H2" "merging" wtStub "sh/H2") stubUnverified))
        (headStub (gitIn dev "rev-parse HEAD"))
        (rOk (cd/mergeRes rc store (pf/unitIn "C1" "sh check.sh impl.txt") (pf/cuIn "C1" "merging" wtClean "sh/C1")))
        (headOk (gitIn dev "rev-parse HEAD"))
        (argsOk (resultOr (fileReadString (str dev "/.git/trainArgs")) ""))
        (journal (journalOf root))
        (blockedC (parkOf! root "P1" "block" "mergeCheck: ledgerGrew"))
        (heldC (parkOf! root "P2" "hold" "mergeCheck unverified exit 3: gates:deadline"))
        (nHold (rowsOf root "mergeCheckHold"))
        (nH1 (rowsOf root "H1"))
        (nH2 (rowsOf root "H2"))
        (wtKept (fileExists? (str wtGrow "/.git")))
        (_ (pf/cleanup root))]
    (do (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (and (not (stringEmpty? wtClean)) (and (not (stringEmpty? wtGrow)) (and (not (stringEmpty? wtHold)) (not (stringEmpty? wtStub))))))) "fixture: source repo, dev clone and four unit branches are up")
        (assert (and (= rGrow.ok 0) (= rGrow.verdict "block") (stringStartsWith? rGrow.sig "mergeCheck:") (stringContains? rGrow.sig "ledgerGrew")) (str "a branch that grows knownRed.asn is blocked with the ledger in the signature: " rGrow.verdict " " rGrow.sig))
        (assert (and (= headGrow head0) (stringEmpty? argsGrow)) (str "a blocked check leaves dev where it was and never starts the train: " argsGrow))
        (assert wtKept "a blocked check keeps the unit worktree")
        (assert (and (= rHold.ok 0) (= rHold.verdict "hold") (stringContains? rHold.sig "mergeCheck unverified exit 3")) (str "an audit with no receipt is unverified and holds the unit: " rHold.verdict " " rHold.sig))
        (assert (= headHold head0) "a held unit leaves dev where it was")
        (assert (and (= rStub.verdict "hold") (stringContains? rStub.sig "gates:deadline") (= headStub head0)) (str "a stubbed unverified check holds with its unverified step in the signature: " rStub.sig))
        (assert (and (= nHold 2) (and (= nH1 1) (= nH2 1))) (str "one lead-stream row per held unit: " (stringFromInt64 nHold)))
        (assert (and (= rOk.ok 1) (stringEmpty? rOk.sig) (!= headOk head0)) (str "a clean branch passes the check and merges: " rOk.sig))
        (assert (stringContains? argsOk "train sh/C1 --onto HEAD") (str "the train ran for the clean branch only: " argsOk))
        (assert (and (stringContains? journal "(:mergeReceipt :unit \"C1\" :exit 0 ") (stringContains? journal "(:mergeReceipt :unit \"K1\" :exit 1 ") (stringContains? journal "(:mergeReceipt :unit \"H1\" :exit 3 ")) "the journal holds the mergeCheck receipt of a pass, a block and a hold")
        (assert (and (= blockedC.st "blocked") (= blockedC.fails 0) (stringContains? blockedC.sig "ledgerGrew") (stringEmpty? blockedC.await)) (str "finish! parks a block as blocked with no failure count: " blockedC.st " " (stringFromInt64 blockedC.fails)))
        (assert (and (= heldC.st "blocked") (= heldC.fails 0) (= heldC.await "mergeHold")) (str "finish! parks a hold as blocked await mergeHold with no failure count: " heldC.st " " heldC.await))
        true))
