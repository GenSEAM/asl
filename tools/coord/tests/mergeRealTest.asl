(module asl-tools/coord/tests/mergeRealTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-GATES :do "G3: the real merge stage (realRes merge, which runs mergeRes) on a temp source repo with unit branches and a temp dev clone on branch dev; the dev clone's bin/asl is a recording stand-in for asl train (the one fake, a train needs a full workspace): it merges the branch it is given, fails red, or prints :commitError by the mode file; everything else (branch guard, promoteDev!, fetch by path, remote drop, worktree collection, exit and signature mapping) is conductor code")
fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! trainFake! dev: String -> Bool
  (let [(_ (dirCreate (str dev "/bin")))
        (_ (fileWrite (str dev "/bin/asl") "#!/bin/sh\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\necho \"$@\" >> \"$D/.git/trainArgs\"\ncase \"$(cat \"$D/.git/trainMode\" 2>/dev/null)\" in\n  red) echo \"FAIL train gates red on impl.txt\"; exit 1 ;;\n  commitError) echo \"(:commitError :why x)\"; exit 0 ;;\n  noop) exit 0 ;;\n  *) git -C \"$D\" merge --no-ff -q -m \"train $2\" \"$2\" || exit 1; exit 0 ;;\nesac\n"))
        (made (pf/sh (str "mkdir -p " dev "/bin && chmod 755 " dev "/bin/asl && echo bin/asl >> " dev "/.git/info/exclude && echo madeOk")))]
    (stringContains? made "madeOk"))

fn ! devClone! root: String name: String branch: String -> String
  (let [(dev (str root "/" name))
        (made (pf/sh (str "git clone -q " root "/repo " dev " && cd " dev " && git config user.email t@example.invalid && git config user.name t"
                          (if (= branch "main") "" (str " && git checkout -q -b " branch)) " && echo madeOk")))
        (_ (fileWrite (str dev "/.git/trainMode") "ok"))
        (fake (trainFake! dev))]
    (if (and fake (stringContains? made "madeOk")) dev ""))

fn rcFor root: String dev: String devBranch: String -> cd/RealCfg
  (cd/realCfg (list "--repo" (str root "/repo") "--dev-repo" dev "--dev" devBranch "--worktrees" (str root "/wts") "--home" (str root "/home")) (str root "/store"))

fn ! mergeOf! rc: cd/RealCfg root: String id: String -> cd/Res
  (cd/realRes rc (str root "/store") "merge" (pf/unitIn id "sh check.sh impl.txt") (pf/cuIn id "merging" (str root "/wts/asex-" id) (str "sh/" id)))

fn ! runTests -> Bool
  (let [(root (pf/scratch "mergeReal" "g3"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (wtOk (pf/seedUnit! root (pf/unitIn "M1" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtRed (pf/seedUnit! root (pf/unitIn "M2" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtCe (pf/seedUnit! root (pf/unitIn "M3" "sh check.sh impl.txt") "merging" "impl.txt"))
        (wtMain (pf/seedUnit! root (pf/unitIn "M4" "sh check.sh impl.txt") "merging" "impl.txt"))
        (dev (devClone! root "dev" "dev"))
        (devMain (devClone! root "devMain" "main"))
        (sha1 (gitIn repo "rev-parse sh/M1"))
        (head0 (gitIn dev "rev-parse HEAD"))
        (rc (rcFor root dev "dev"))
        (wtHad (fileExists? (str wtOk "/.git")))
        (rOk (mergeOf! rc root "M1"))
        (head1 (gitIn dev "rev-parse HEAD"))
        (inDev (stringContains? (pf/sh (str "git -C " dev " merge-base --is-ancestor " sha1 " HEAD && echo yes")) "yes"))
        (devHasFile (fileExists? (str dev "/impl.txt")))
        (remotes (gitIn dev "remote"))
        (args (stringTrim (resultOr (fileReadString (str dev "/.git/trainArgs")) "")))
        (wtGone (not (fileExists? (str wtOk "/.git"))))
        (_ (fileWrite (str dev "/.git/trainMode") "red"))
        (rRed (mergeOf! rc root "M2"))
        (head2 (gitIn dev "rev-parse HEAD"))
        (_ (fileWrite (str dev "/.git/trainMode") "commitError"))
        (rCe (mergeOf! rc root "M3"))
        (redKept (fileExists? (str wtRed "/.git")))
        (head3 (gitIn dev "rev-parse HEAD"))
        (_ (fileWrite (str dev "/.git/trainMode") "ok"))
        (_ (fileWrite (str dev "/.git/trainMode") "noop"))
        (rMissing (cd/realRes rc (str root "/store") "merge" (pf/unitIn "NOPE" "sh check.sh impl.txt") (pf/cuIn "NOPE" "merging" (str root "/wts/asex-NOPE") "sh/NOPE")))
        (head4 (gitIn dev "rev-parse HEAD"))
        (mainHead0 (gitIn devMain "rev-parse HEAD"))
        (rcMain (rcFor root devMain "main"))
        (rMainRefused (mergeOf! rcMain root "M4"))
        (rWrongBranch (mergeOf! (rcFor root dev "other") root "M4"))
        (rMasterRefused (mergeOf! (rcFor root dev "master") root "M4"))
        (mainHead1 (gitIn devMain "rev-parse HEAD"))
        (devHead5 (gitIn dev "rev-parse HEAD"))
        (trainArgsMain (resultOr (fileReadString (str devMain "/.git/trainArgs")) ""))
        (m4Branch (gitIn repo "rev-parse --verify --quiet sh/M4"))
        (rMain (mergeOf! rc root "M4"))
        (_ (pf/cleanup root))]
    (do (assert (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (and (not (stringEmpty? devMain)) (and (not (stringEmpty? wtOk)) (and (not (stringEmpty? wtRed)) (and (not (stringEmpty? wtCe)) (not (stringEmpty? wtMain)))))))) "fixture: source repo, two dev clones, four unit branches")
        (assert (and (not (stringEmpty? sha1)) (!= head0 head1)) (str "dev HEAD moved: " head0 " -> " head1))
        (assert (and (= rOk.ok 1) (and (stringEmpty? rOk.sig) (= rOk.exit 0))) (str "a green train is ok 1 with no signature: " (stringFromInt64 rOk.ok) " " rOk.sig))
        (assert (and inDev devHasFile) "dev now holds the unit commit and its file")
        (assert (= args (str "train sh/M1 --onto HEAD --repo " dev " --commit")) (str "the train ran onto dev with the unit branch: " args))
        (assert (stringEmpty? remotes) (str "the dev clone's remotes were dropped before the train: " remotes))
        (assert (and wtHad wtGone) "the unit worktree existed and is collected after a merge")
        (assert (and (= rRed.ok 0) (stringContains? rRed.sig "FAIL train gates red")) (str "a red train is ok 0 with the train's failure line as signature: " (stringFromInt64 rRed.ok) " " rRed.sig))
        (assert (= head2 head1) "a red train leaves dev HEAD where it was")
        (assert redKept "a red train keeps the unit worktree")
        (assert (and (= rCe.ok 0) (not (stringEmpty? rCe.sig))) (str "a train that reports :commitError is ok 0 with a signature: " rCe.sig))
        (assert (= head3 head2) "a commit error leaves dev HEAD where it was")
        (assert (and (= rMissing.ok 0) (and (not (stringEmpty? rMissing.sig)) (= head4 head3))) (str "a unit branch that is not in the source repo is ok 0 and dev is untouched: " rMissing.sig))
        (assert (and (= rMainRefused.ok 0) (stringContains? rMainRefused.sig "refused")) (str "dev branch main is refused: " rMainRefused.sig))
        (assert (and (= rWrongBranch.ok 0) (stringContains? rWrongBranch.sig "refused: devRepo is on dev, dev branch other")) (str "a dev repo on another branch than the configured one is refused: " rWrongBranch.sig))
        (assert (and (= rMasterRefused.ok 0) (stringContains? rMasterRefused.sig "refused")) (str "dev branch master is refused: " rMasterRefused.sig))
        (assert (and (= mainHead1 mainHead0) (stringEmpty? trainArgsMain) (= devHead5 head4)) (str "a refused merge never starts the train and moves no HEAD: " trainArgsMain))
        (assert (not (stringEmpty? m4Branch)) "the refused unit's branch is still there")
        (assert (and (= rMain.ok 1) (!= (gitIn dev "rev-parse HEAD") head4)) "control: the same unit merges onto the configured dev branch")
        true))
