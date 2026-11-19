(module asl-tools/coord/tests/condAuditFixTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref COND-AUDIT-FIX :do "fixes of the merged-code audit, each on a scratch repo under this worktree's .asl/cache with a stand-in bin/asl (know gen writes the card text of WORKTREE.gen, the row driver call is handed to this tree's mergeRows): a gates debt survives the conductor's own cards commit and is paid by a writer commit only; the cards commit names what it is; a commit the guard refuses is one cardsInfra row and a clean tree; freshBase! and leonGuard! rebase two branches that appended different doc.asn rows in a repo with no configured row driver")

fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/condAuditFixTest-" (stringFromInt64 (procSelf)))

fn ! sh! cmd: String -> String
  (resultOr (fr/shellOut cmd 120000) "")

fn ! cleanup root: String -> String
  (let [(d (fr/runOneLimited (fr/job (list "rm" "-rf" root) "." (fr/childEnv (list))) (fr/limits 60 4)))]
    (if (and (= d.exit 0) (not (fileExists? root))) "" (str "exit " (stringFromInt64 d.exit) " " d.verdict " " d.out)))

fn ! git dir: String argv: (List String) -> String
  (stringTrim (cd/gitOut dir argv).out)

fn docPath -> String
  "asl/packages/pk/doc.asn"

fn docRow sym: String -> String
  (str "(:doc :symbol \"asl/packages/pk/src/a.asl#" sym "\" :text \"returns " sym "\")")

; (:m :do "the stand-in host of the fixture repo: check passes, know gen copies WORKTREE.gen into the pk card, missing reports no new row, and a run of mergeRows.asl goes to the real tree's CLI and script, which is what trn/rowDriverArgs names for a real conductor repo")
fn stubText real: String -> String
  (str "#!/bin/sh\n"
       "if [ \"$1\" = check ]; then shift; for f in \"$@\"; do echo \"ok $f: x\"; done; exit 0; fi\n"
       "case \"$2\" in */mergeRows.asl) exec '" real "/bin/asl' run '" real "/asl/tools/mergeRows/mergeRows.asl' \"$3\" \"$4\" \"$5\" \"$6\";; esac\n"
       "if [ \"$3\" = gen ]; then mkdir -p \"$ASL_ROOT/asl/packages/asl-know/cards\"; cat \"$ASL_ROOT.gen\" > \"$ASL_ROOT/asl/packages/asl-know/cards/pk.asn\"; fi\n"
       "if [ \"$3\" = missing ]; then echo \"(:know :missing :new 0)\"; fi\n"
       "exit 0\n")

; (:m :do "main c0 holds the package, one contract row and the stand-in host; each unit branch gets its worktree and one commit of its own (a file, or a row appended to doc.asn); then main moves: another row and a file under asl-agent")
fn ! build! root: String real: String -> Bool
  (let [(repo (str root "/repo"))
        (wt (fn [(id String) (edit String)] -> String
              (str " && git worktree add -q -b sh/" id " " root "/wt" id " main && (cd " root "/wt" id " && " edit " && git add -A && git commit -qm 'unit " id "')")))
        (_ (sh! (str "mkdir -p " repo "/bin " repo "/asl/packages/pk/src " repo "/asl/packages/asl-know/cards " root "/store")))
        (_ (fileWrite (str repo "/bin/asl") (stubText real)))
        (_ (fileWrite (str repo "/.gitattributes") "doc.asn merge=asnRows\n"))
        (_ (fileWrite (str repo "/" (docPath)) (str (docRow "old") "\n")))
        (_ (fileWrite (str repo "/asl/packages/pk/src/a.asl") "(module pk/a :x [old] :i [])\nfn old -> Int64\n  1\n"))
        (_ (fileWrite (str repo "/asl/packages/asl-know/missing.asn") "(:knowMissing :rule \"only shrinks\")\n"))
        (made (sh! (str "cd " repo " && chmod +x bin/asl && git init -q -b main && git config user.email t@example.invalid && git config user.name t && git add -A && git commit -qm c0"
                        (wt "B1" "echo impl > impl.txt")
                        (wt "D1" "echo impl > impl.txt")
                        (wt "C1" (str "echo '" (docRow "alpha") "' >> " (docPath)))
                        (wt "L1" (str "echo '" (docRow "gamma") "' >> " (docPath)))
                        " && echo '" (docRow "beta") "' >> " (docPath) " && mkdir -p asl/packages/asl-agent && echo x > asl/packages/asl-agent/x.txt && git add -A && git commit -qm c1 && echo madeOk")))]
    (stringContains? made "madeOk"))

fn unit id: String -> st/Task
  (st/Task :id id :owns (list "asl/packages/pk/src/a.asl") :reads (list) :gate "" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")

; (:m :do "B and D: the debt across the harness commit, the commit subject, the refused commit")
fn ! testCards root: String -> Bool
  (let [(dir (str root "/store"))
        (b (str root "/wtB1"))
        (d (str root "/wtD1"))
        (_ (fileWrite (str b ".gen") "(:card :id \"pk\" :n 1)\n"))
        (h0 (git b (list "rev-parse" "HEAD")))
        (_ (cd/failHeadSave! dir "B1" b "gates" "fail: exit 1 asserts 3"))
        (owed0 (cd/workFixOwed? dir "B1" b))
        (landed (cd/cardsRegen! dir b (unit "B1") "m" b))
        (h1 (git b (list "rev-parse" "HEAD")))
        (subject (git b (list "log" "-1" "--format=%s")))
        (files (git b (list "show" "--name-only" "--format=" "HEAD")))
        (owed1 (cd/workFixOwed? dir "B1" b))
        (sig1 (cd/gatesFailureAt! dir "B1" b))
        (_ (sh! (str "cd " b " && echo fix > impl.txt && git commit -qam 'writer fix'")))
        (owed2 (cd/workFixOwed? dir "B1" b))
        (_ (fileWrite (str b ".gen") "(:card :id \"pk\" :n 2)\n"))
        (landed2 (cd/cardsRegen! dir b (unit "B1") "m" b))
        (owed3 (cd/workFixOwed? dir "B1" b))
        (_ (fileWrite (str d ".gen") "(:card :id \"pk\"\n"))
        (hd0 (git d (list "rev-parse" "HEAD")))
        (refused (cd/cardsRegen! dir d (unit "D1") "m" d))
        (hd1 (git d (list "rev-parse" "HEAD")))
        (dirty (git d (list "status" "--porcelain" "--untracked-files=all")))
        (journal (resultOr (fileReadString (str dir "/journal.asn")) ""))]
    (do (assert (and owed0 (and landed (!= h0 h1))) (str "a debt is recorded and the conductor's cards commit lands on top: " h0 " " h1))
        (assert (stringContains? files "asl/packages/asl-know/cards/pk.asn") (str "the commit carries the regenerated card: " files))
        (assert owed1 "the conductor's own cards commit pays no debt: a fix is still owed at the new head")
        (assert (stringContains? sig1 "exit 1 asserts 3") (str "the debt keeps its stage and signature: " sig1))
        (assert (not owed2) "a writer commit pays the debt")
        (assert (and landed2 (not owed3)) "a later cards commit does not bring a paid debt back")
        (assert (and (stringStartsWith? subject "(:c :a coord :do \"regenerated know cards") (stringContains? subject ":ev (B1)")) (str "the cards commit names what it is: " subject))
        (assert (not (or (stringContains? subject "gate passed") (stringContains? subject "gate exit 0"))) (str "it claims no gate and no writer's work: " subject))
        (assert (and (not refused) (= hd0 hd1)) "a card the commit guard refuses (unbalanced) lands no commit")
        (assert (stringContains? journal "(:cardsInfra :unit \"D1\" :why \"commit refused") (str "the refusal is one cardsInfra row: " journal))
        (assert (stringEmpty? dirty) (str "the refused commit leaves the tree clean: " dirty))
        (assert (not (stringContains? journal "(:cardsInfra :unit \"B1\"")) "a landed cards commit writes no cardsInfra row")
        true))

; (:m :do "C: both rebases with rows appended on each side")
fn ! testRebase root: String -> Bool
  (let [(repo (str root "/repo"))
        (dir (str root "/store"))
        (rc (cd/realCfg (list "--repo" repo "--home" (str root "/home") "--worktrees" (str root "/wts")) dir))
        (c (str root "/wtC1"))
        (l (str root "/wtL1"))
        (noDriver (stringEmpty? (git repo (list "config" "--get" "merge.asnRows.driver"))))
        (fresh (cd/freshBase! rc (unit "C1") c))
        (docC (resultOr (fileReadString (str c "/" (docPath))) ""))
        (stale (git repo (list "branch" "--list" "sh/C1-stale-*")))
        (onMain (cd/gitOut c (list "merge-base" "--is-ancestor" "main" "HEAD")).exit)
        (guard (cd/leonGuard! repo l))
        (docL (resultOr (fileReadString (str l "/" (docPath))) ""))
        (onMainL (cd/gitOut l (list "merge-base" "--is-ancestor" "main" "HEAD")).exit)
        (has (fn [(t String) (s String)] -> Bool (stringContains? t (docRow s))))]
    (do (assert noDriver "the fixture repo has no configured row driver")
        (assert (and (ok? fresh) (= onMain 0)) "freshBase! rebases the unit branch onto the moved base")
        (assert (and (has docC "old") (and (has docC "alpha") (has docC "beta"))) (str "freshBase! keeps the unit's row and the base's row: " docC))
        (assert (stringEmpty? stale) (str "the branch is not renamed stale: " stale))
        (assert (and (not (some? guard)) (= onMainL 0)) "leonGuard! rebases the unit branch onto the head that moved asl-agent")
        (assert (and (has docL "old") (and (has docL "gamma") (has docL "beta"))) (str "leonGuard! keeps the unit's row and the base's row: " docL))
        (assert (not (or (stringContains? docC "<<<<<<<") (stringContains? docL "<<<<<<<"))) "no conflict marker in doc.asn")
        true))

fn ! runTests -> Bool
  (let [(root (scratch))
        (_ (cleanup root))
        (built (build! root (resultOr (realPath ".") ".")))
        (cards (if built (testCards root) false))
        (rebase (if built (testRebase root) false))
        (left (cleanup root))]
    (do (assert built "fixture repo built")
        (assert cards "cards commit: debt, subject, refusal")
        (assert rebase "rebases carry the row driver")
        (assert (stringEmpty? left) (str "fixture removed: " left))
        true))
