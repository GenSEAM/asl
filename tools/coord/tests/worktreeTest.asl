(module asl/tools/coord/tests/worktreeTest
  :x [runTests]
  :i [(asl-tools/coord/worktree :a w) (asl-tools/fleet/run :a fr)])

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/worktreeTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! git dir: String args: (List String) -> Bool
  (= (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).exit 0)

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! gitOut dir: String args: (List String) -> String
  (stringTrim (sh dir (cons "git" args)).out)

fn ! cfgOf root: String -> w/Cfg
  (w/Cfg :repo (str root "/repo") :base (str root "/wts") :prefix "asex-" :archive (str root "/archive") :mainRef "main")

fn ! fixture root: String -> Bool
  (let [(repo (str root "/repo"))]
    (and (= (sh "." (list "mkdir" "-p" repo)).exit 0)
      (and (git repo (list "init" "-q" "-b" "main"))
        (and (put (str repo "/data.txt") "1\n")
          (and (put (str repo "/.gitignore") "out/\n")
            (and (git repo (list "add" "-A"))
              (git repo (list "commit" "-q" "-m" "base"))))))))

fn ! resText r: (Result String String) -> String
  (match r ((ok s) s) ((err e) (str "ERR " e)))

fn ! unitsOf cfg: w/Cfg -> (List String)
  (match (w/listWt! cfg) ((ok ws) (map (fn [(x w/Wt)] -> String x.unit) ws)) ((err e) (list (str "ERR " e))))

fn ! wtOf cfg: w/Cfg unit: String -> (Option w/Wt)
  (match (w/listWt! cfg) ((ok ws) (listHead (filter (fn [(x w/Wt)] -> Bool (= x.unit unit)) ws))) ((err _) (none)))

fn ! testPure -> Bool
  (do (assert (w/safeUnit? "FKWT-1.a") "plain unit names are safe")
      (assert (not (w/safeUnit? "../x")) "dot segments are unsafe")
      (assert (not (w/safeUnit? "a b")) "spaces are unsafe")
      (assert (not (w/safeUnit? "-rf")) "a leading dash is unsafe")
      (assert (not (w/safeUnit? "")) "empty is unsafe")
      (let [(es (w/parseWorktrees "worktree /a\nHEAD abc\nbranch refs/heads/main\n\nworktree /b\nHEAD def\ndetached\n"))]
        (do (assert (= (listLength es) 2) "two porcelain blocks parsed")
            (assert (= (map (fn [(e w/Entry)] -> String e.branch) es) (list "main" "")) "branch parsed without refs/heads")
            (assert (= (map (fn [(e w/Entry)] -> Bool e.detached) es) (list false true)) "detached parsed")
            true)))

fn ! testLifecycle root: String -> Bool
  (let [(cfg (cfgOf root))
        (repo (str root "/repo"))]
    (do
      (assert (match (w/addWt! cfg "u1" "") ((ok _) true) ((err e) false)) "add u1")
      (assert (= (gitOut repo (list "rev-parse" "--abbrev-ref" "sh/u1")) "sh/u1") "add makes branch sh/UNIT")
      (assert (match (w/addWt! cfg "u1" "") ((ok _) false) ((err _) true)) "adding an existing unit is refused")
      (assert (match (w/addWt! cfg "../evil" "") ((ok _) false) ((err _) true)) "an unsafe unit is refused")
      (assert (put (str root "/wts/asex-u1/out.txt") "x") "scratch file")
      (assert (= (sh "." (list "mkdir" "-p" (str root "/wts/asex-u1/out"))).exit 0) "ignored dir")
      (assert (put (str root "/wts/asex-u1/out/b.o") "obj") "ignored file")
      (assert (match (wtOf cfg "u1") ((some x) (and (= x.dirty 1) (and (= x.ignored 1) x.merged))) ((none) false)) "u1 lists dirty 1 (out.txt), ignored 1, merged")
      (assert (= (sh "." (list "rm" (str root "/wts/asex-u1/out.txt"))).exit 0) "u1 made clean")
      (assert (stringContains? (resText (w/removeWt! cfg "u1" false)) "wtRemoved") "merged clean worktree is removed, ignored output does not block")
      (assert (not (fileExists? (str root "/wts/asex-u1"))) "u1 path gone")
      (assert (match (w/addWt! cfg "u2" "") ((ok _) true) ((err _) false)) "add u2")
      (assert (put (str root "/wts/asex-u2/new.txt") "n") "u2 file")
      (assert (git (str root "/wts/asex-u2") (list "add" "-A")) "u2 add")
      (assert (git (str root "/wts/asex-u2") (list "commit" "-q" "-m" "u2 work")) "u2 commit")
      (assert (stringContains? (resText (w/removeWt! cfg "u2" false)) "unmerged") "unmerged clean worktree is kept")
      (assert (fileExists? (str root "/wts/asex-u2")) "u2 still there")
      (assert (match (w/addWt! cfg "u3" "") ((ok _) true) ((err _) false)) "add u3")
      (assert (put (str root "/wts/asex-u3/data.txt") "changed\n") "u3 tracked change")
      (assert (put (str root "/wts/asex-u3/loose.txt") "loose\n") "u3 untracked")
      (assert (put (str root "/wts/asex-u3/odd\nname.txt") "odd\n") "u3 untracked name with a newline")
      (assert (stringContains? (resText (w/removeWt! cfg "u3" false)) "dirty") "dirty worktree is kept without force")
      (assert (fileExists? (str root "/wts/asex-u3/loose.txt")) "u3 untouched")
      (let [(r (resText (w/removeWt! cfg "u3" true)))]
        (do (assert (stringContains? r "wtRemoved") (str "forced removal: " r))
            (assert (not (fileExists? (str root "/wts/asex-u3"))) "u3 path gone after force")
            (let [(files (resultOr (dirList (str root "/archive")) (list)))
                  (diffName (optionOr (listHead (filter (fn [(n String)] -> Bool (stringEndsWith? n ".diff")) files)) ""))
                  (tarName (optionOr (listHead (filter (fn [(n String)] -> Bool (stringEndsWith? n ".tar")) files)) ""))
                  (tarList (sh "." (list "tar" "-tf" (str root "/archive/" tarName))))
                  (diffText (resultOr (fileReadString (str root "/archive/" diffName)) ""))
                  (arch (str diffText tarList.out))]
              (do (assert (stringContains? arch "+changed") "archive holds the tracked diff")
                  (assert (stringContains? arch "loose.txt") "archive holds the untracked file")
                  (assert (stringContains? arch "odd\\nname.txt") "archive holds an untracked name with a newline")
                  true))))
      (assert (match (w/addWt! cfg "u4" "") ((ok _) true) ((err _) false)) "add u4")
      (assert (git (str root "/wts/asex-u4") (list "checkout" "-q" "--detach")) "u4 detached")
      (assert (put (str root "/wts/asex-u4/d.txt") "d") "u4 file")
      (assert (git (str root "/wts/asex-u4") (list "add" "-A")) "u4 add")
      (assert (git (str root "/wts/asex-u4") (list "commit" "-q" "-m" "detached work")) "u4 commit")
      (let [(head (gitOut (str root "/wts/asex-u4") (list "rev-parse" "HEAD")))
            (r (resText (w/removeWt! cfg "u4" false)))
            (rescued (gitOut repo (list "branch" "--list" "rescue/u4-*" "--format=%(objectname)")))]
        (do (assert (stringContains? r "unmerged") (str "detached unmerged head is kept: " r))
            (assert (= rescued head) "a rescue branch points at the detached head")
            (assert (stringContains? (resText (w/removeWt! cfg "u4" true)) "rescue") "forced removal reports the rescue branch")
            (assert (not (fileExists? (str root "/wts/asex-u4"))) "u4 path gone")
            (assert (= (gitOut repo (list "branch" "--list" "rescue/u4-*" "--format=%(objectname)")) head) "the rescue branch survives removal")
            true))
      (assert (git repo (list "worktree" "add" "-q" "--detach" (str root "/wts/vtbotfeature") "main")) "foreign worktree")
      (assert (= (unitsOf cfg) (list "u2")) (str "list shows only prefixed units: " (stringJoin (unitsOf cfg) ",")))
      (assert (match (w/removeWt! cfg "vtbotfeature" true) ((ok _) false) ((err _) true)) "a foreign worktree cannot be removed")
      (assert (fileExists? (str root "/wts/vtbotfeature")) "foreign worktree intact")
      true))

fn ! exitOf r: (Result Int64 String) -> Int64
  (match r ((ok n) n) ((err _) -9))

fn ! mkUnit cfg: w/Cfg unit: String -> Bool
  (match (w/addWt! cfg unit "") ((ok _) true) ((err _) false))

fn ! testGc root: String -> Bool
  (let [(cfg (cfgOf root))
        (repo (str root "/repo"))
        (wt (fn [(u String)] -> String (str root "/wts/asex-" u)))
        (args (fn [(verb String) (extra (List String))] -> (List String) (listAppend (list verb "--repo" repo "--base" (str root "/wts") "--archive" (str root "/archive")) extra)))]
    (do
      (assert (and (mkUnit cfg "g1") (and (mkUnit cfg "g2") (and (mkUnit cfg "g3") (and (mkUnit cfg "g4") (mkUnit cfg "train"))))) "gc units added")
      (assert (put (str (wt "g2") "/wip.txt") "w") "g2 dirty")
      (assert (put (str (wt "g3") "/new.txt") "n") "g3 file")
      (assert (git (wt "g3") (list "add" "-A")) "g3 add")
      (assert (git (wt "g3") (list "commit" "-q" "-m" "g3 work")) "g3 unmerged commit")
      (assert (git repo (list "worktree" "add" "-q" "--detach" (str root "/wts/vtbotgc") "main")) "foreign worktree")
      (let [(dry (resText (w/gcWt! cfg (list) (list) false)))]
        (do (assert (stringContains? dry ":apply false") (str "dry receipt: " dry))
            (assert (stringContains? dry ":unmerged 1") "dry counts the unmerged worktree")
            (assert (stringContains? dry ":unit g1") "dry lists the merged clean worktree")
            (assert (stringContains? dry ":removed ()") "dry removes nothing")
            (assert (fileExists? (wt "g1")) "dry keeps g1")
            true))
      (assert (= (exitOf (w/main (args "audit" (list "--older" "-1")))) 1) "audit exits 1 when a merged worktree is older than the threshold")
      (assert (= (exitOf (w/main (args "audit" (list "--older" "7200")))) 0) "audit exits 0 when no merged worktree is that old")
      (let [(only (resText (w/gcWt! cfg (list) (list "sh/g4") true)))]
        (do (assert (stringContains? only "wtRemoved :unit g4") (str "only g4 removed: " only))
            (assert (fileExists? (wt "g1")) "only keeps g1")
            true))
      (let [(r (resText (w/gcWt! cfg (list) (list) true)))]
        (do (assert (stringContains? r "wtRemoved :unit g1") (str "apply removes merged clean g1: " r))
            (assert (not (fileExists? (wt "g1"))) "g1 path gone")
            (assert (stringContains? r "reason dirtyMerged") "apply keeps dirty merged g2")
            (assert (stringContains? r ":archive") "apply archives g2")
            (assert (fileExists? (wt "g2")) "g2 kept")
            (assert (fileExists? (str (wt "g2") "/wip.txt")) "g2 file kept")
            (assert (fileExists? (wt "g3")) "g3 unmerged kept")
            (assert (fileExists? (wt "train")) "train scratch protected")
            (assert (stringContains? r "reason protected") "protected reported")
            (assert (fileExists? (str root "/wts/vtbotgc")) "foreign worktree untouched")
            (assert (not (listEmpty? (resultOr (dirList (str root "/archive")) (list)))) "archive dir holds g2")
            true))
      (assert (= (exitOf (w/main (args "audit" (list "--older" "-1")))) 1) "audit still lists the kept dirty merged worktree")
      (assert (stringContains? (resText (w/removeWt! cfg "g2" true)) "wtRemoved") "g2 force-removed")
      (assert (= (exitOf (w/main (args "audit" (list "--older" "-1")))) 0) "audit exits 0 once only unmerged and protected remain")
      true))

; (:m :ref COORD-WIP-RESCUE :do "wipCommit! turns a dirty unit tree into one wip commit with an ASN message naming unit and reason, leaves a clean tree untouched, and gives a detached head a rescue branch")
fn ! testWip root: String -> Bool
  (let [(cfg (cfgOf root))
        (repo (str root "/repo"))
        (wt (fn [(u String)] -> String (str root "/wts/asex-" u)))]
    (do
      (assert (and (mkUnit cfg "w1") (mkUnit cfg "w2")) "wip units added")
      (assert (= (resText (w/wipCommit! cfg "w1" "leaseLost")) "") "a clean tree commits nothing")
      (assert (put (str (wt "w1") "/data.txt") "edited\n") "w1 tracked edit")
      (assert (put (str (wt "w1") "/fresh.txt") "f\n") "w1 untracked file")
      (assert (and (= (sh "." (list "mkdir" "-p" (str (wt "w1") "/out"))).exit 0) (put (str (wt "w1") "/out/x") "ignored\n")) "w1 ignored output")
      (let [(sha (resText (w/wipCommit! cfg "w1" "leaseLost")))]
        (do (assert (not (stringEmpty? sha)) (str "a dirty tree yields a sha: " sha))
            (assert (stringContains? (gitOut repo (list "log" "-1" "--format=%s" "sh/w1")) "(:c :a wip :do \"unit w1 stopped: leaseLost\"") "message is one ASN line naming unit and reason")
            (assert (stringContains? (gitOut repo (list "show" "--stat" "--format=" "sh/w1")) "fresh.txt") "untracked file committed")
            (assert (not (stringContains? (gitOut repo (list "show" "--stat" "--format=" "sh/w1")) "out/x")) "ignored output not committed")
            (assert (stringEmpty? (gitOut (wt "w1") (list "status" "--porcelain"))) "tree clean after")
            true))
      (assert (git (wt "w2") (list "checkout" "-q" "--detach")) "w2 detached")
      (assert (put (str (wt "w2") "/data.txt") "d\n") "w2 edit")
      (let [(sha (resText (w/wipCommit! cfg "w2" "stopped")))
            (branches (gitOut repo (list "branch" "--list" "rescue/w2-*")))]
        (do (assert (not (stringEmpty? sha)) "detached dirty tree committed")
            (assert (stringContains? branches "rescue/w2-") (str "detached wip is kept on a rescue branch: " branches))
            true))
      (assert (= (resText (w/wipCommit! cfg "nope" "x")) "") "an absent unit commits nothing and is not an error")
      (assert (put (str repo "/data.txt") "dirty main\n") "the repo's own checkout is dirty")
      (assert (stringContains? (resText (w/wipCommitAt! cfg "main" repo "x")) "ERR not a worktree") "the repo's own checkout is refused as a wip target")
      (assert (and (not (w/isWorktreeOf! cfg repo)) (w/isWorktreeOf! cfg (wt "w1"))) "only linked worktrees count")
      (assert (= (gitOut repo (list "log" "-1" "--format=%s" "main")) "base") "and main got no commit")
      (assert (git repo (list "checkout" "-q" "--" "data.txt")) "main checkout restored")
      (assert (mkUnit cfg "w3") "w3 added")
      (assert (and (put (str (wt "w3") "/code.txt") "c\n") (and (put (str (wt "w3") "/.env") "KEY=1\n") (put (str (wt "w3") "/id_rsa") "k\n"))) "w3 holds code, a .env and an id_rsa")
      (let [(sha (resText (w/wipCommitAt! cfg "w3" (wt "w3") "stopped")))
            (shown (gitOut repo (list "show" "--stat" "--format=" "sh/w3")))]
        (do (assert (not (stringEmpty? sha)) "the code is committed")
            (assert (stringContains? shown "code.txt") "code.txt is in the wip commit")
            (assert (not (or (stringContains? shown ".env") (stringContains? shown "id_rsa"))) (str "secret-path files are not committed: " shown))
            (assert (and (fileExists? (str (wt "w3") "/.env")) (fileExists? (str (wt "w3") "/id_rsa"))) "and are left in the tree")
            (assert (= (w/secretUntracked! (wt "w3")) (list ".env" "id_rsa")) "which the left count names")
            true))
      (assert (mkUnit cfg "w5") "w5 added")
      (assert (and (put (str (wt "w5") "/code5.txt") "c\n") (and (= (sh "." (list "mkdir" "-p" (str (wt "w5") "/.asl/mem"))).exit 0) (put (str (wt "w5") "/.asl/mem/grades.asn") "(:gradesHead :since \"x\")\n"))) "w5 holds a ledger and code")
      (assert (and (git (wt "w5") (list "add" "-f" ".asl/mem/grades.asn")) (git (wt "w5") (list "commit" "-q" "-m" "ledger"))) "the ledger is tracked on the unit branch")
      (assert (put (str (wt "w5") "/.asl/mem/grades.asn") "(:gradesHead :since \"x\")\n(:grade :ev \"EVIL\")\n") "and then edited by the writer")
      (let [(sha (resText (w/wipCommitAt! cfg "w5" (wt "w5") "stopped")))
            (shown (gitOut repo (list "show" "--stat" "--format=" "sh/w5")))]
        (do (assert (not (stringEmpty? sha)) "the code is committed")
            (assert (and (stringContains? shown "code5.txt") (not (stringContains? shown "grades.asn"))) (str "the ledger is left out of the wip commit: " shown))
            (assert (fileExists? (str (wt "w5") "/.asl/mem/grades.asn")) "and stays in the tree")
            true))
      (assert (mkUnit cfg "w6") "w6 added")
      (assert (and (= (sh "." (list "mkdir" "-p" (str (wt "w6") "/own"))).exit 0) (and (put (str (wt "w6") "/own/in.txt") "i\n") (put (str (wt "w6") "/out.txt") "o\n"))) "w6 holds an owned and an unowned untracked file")
      (assert (= (w/outsideUntracked! (wt "w6") (list "own")) (list "out.txt")) "the outside list names the unowned file")
      (assert (= (w/outsideUntracked! (wt "w6") (list)) (list)) "empty owns: nothing is outside")
      (let [(sha (resText (w/wipCommitOwned! cfg "w6" (wt "w6") "stopped" (list "own"))))
            (shown (gitOut repo (list "show" "--stat" "--format=" "sh/w6")))]
        (do (assert (not (stringEmpty? sha)) "the owned file is committed")
            (assert (and (stringContains? shown "own/in.txt") (not (stringContains? shown "out.txt"))) (str "only the owned file: " shown))
            (assert (fileExists? (str (wt "w6") "/out.txt")) "the unowned file stays in the tree")
            true))
      (assert (mkUnit cfg "w4") "w4 added")
      (assert (put (str (wt "w4") "/.env") "KEY=2\n") "w4 holds only a .env")
      (assert (= (resText (w/wipCommitAt! cfg "w4" (wt "w4") "stopped")) "") "only secrets: nothing to commit, no empty commit")
      (assert (and (= (sh "." (list "mkdir" "-p" (str root "/plain"))).exit 0) (put (str root "/plain/f.txt") "f\n")) "a plain dir")
      (assert (stringContains? (resText (w/wipCommitAt! cfg "plain" (str root "/plain") "x")) "ERR not a worktree") "a path that is not a worktree of the repo is refused")
      (assert (fileExists? (str root "/plain/f.txt")) "and left untouched")
      true))

fn ! runTests -> Bool
  (let [(root (scratch))]
    (do (assert (fixture root) "fixture repository built")
        (assert (testPure) "pure helpers")
        (assert (testLifecycle root) "lifecycle")
        (assert (testWip root) "wip commit")
        (assert (fixture (str root "/gc")) "gc fixture repository built")
        (assert (testGc (str root "/gc")) "gc and audit")
        (assert (= (sh "." (list "rm" "-rf" root)).exit 0) "fixture removed")
        true))
