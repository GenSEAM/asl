(module asl-tools/coord/tests/trialSetupTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref TRIAL-SETUP :do "trial.asl setup on a temp tree: a production source checkout on main and a production dev repo, a production lanes file with a commandCode lane, a gateway naming providers; --dry-run prints the command list and creates nothing, a setup aimed inside production or with a noCredit writer is refused, the real setup builds a trial source and dev repo with no remote and their own build, writes the panel lanes and a run spec whose heads pin production, passes check, leaves production unmoved and runs again idempotently")

fn ! gitIn dir: String args: String -> String
  (stringTrim (pf/sh (str "git -C " dir " " args)))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn gatewayText -> String
  "(:gateway :v 2 :models ((:model :id hzQ :provider hetzner :name \"q\") (:model :id ovh :provider ovh :name \"o\") (:model :id ccLing :provider commandCode :name \"c\") (:model :id nimX :provider nim :name \"n\")))\n"

fn lanesText -> String
  (str "(:reviewLanes :v 1 :date \"2026-11-02\" :by lead :host node2\n  :familyExtra \"(:f :match km :family moonshot)\"\n"
       "  :lanes ((:lane :alias hzQ :tier free :quality 8 :allowance 3)\n          (:lane :alias ccLing :tier paid :quality 7 :allowance 2)\n"
       "          (:lane :alias ovh :tier free :quality 7 :allowance 2)\n          (:lane :alias nimX :tier free :quality 5 :allowance 3)))\n"
       "(:writeProfiles :tier free :profiles (freeWriterNim) :weights (1) :leads (nim))\n")

fn seedPatch -> String
  "diff --git a/seed.txt b/seed.txt\nnew file mode 100644\n--- /dev/null\n+++ b/seed.txt\n@@ -0,0 +1 @@\n+seeded\n"

fn specText root: String here: String repo: String writer: String -> String
  (str "(:trialSpec :store \"" root "/store\" :repo \"" repo "\" :toolRoot \"" here "\" :devRepo \"" root "/asexTrial\" :devBase \"trialBase\" :worktrees \"" root "/wts\""
       " :home \"" root "/home\" :lanes \"" root "/trialLanes.asn\" :base \"main\" :minFreeMb 0 :minDiskMb 1)\n"
       "(:setup :src \"" root "/pm/repo\" :build (\"sh\" \"" root "/fakeBuild.sh\") :ref \"main\" :seed \"" root "/seed.patch\" :lanesFrom \"" root "/prodLanes.asn\" :reviewers (\"hzQ\" \"ovh\")"
       " :noCredit (\"commandCode\") :noCreditPrefix (\"cc\") :heads (\"" root "/pm/repo\" \"" root "/pm/dev\") :date \"2026-11-06\")\n"
       "(:model :tag \"W\" :alias \"" writer "\")\n"
       "(:task :id \"T1\" :owns (\"impl.txt\") :gate \"sh check.sh impl.txt\" :do \"write impl\" :known merge)\n")

; (:m :do "stand-in for asl/host/build.sh plus the tracked bin/asl, run in the tree it builds: a marker, an aslNativeBuild that answers its usage line as the real one does, and a bin/asl when the tree has none")
fn buildScript -> String
  (str "#!/bin/sh\nmkdir -p asl/host/out bin\necho built > asl/host/out/marker\n"
       "printf '#!/bin/sh\\necho \"usage: nativeBuild ROOT\" >&2\\nexit 2\\n' > asl/host/out/aslNativeBuild\nchmod 755 asl/host/out/aslNativeBuild\n"
       "[ -e bin/asl ] || { printf '#!/bin/sh\\nexit 0\\n' > bin/asl; chmod 755 bin/asl; }\n")

; (:m :do "production stand-ins from pipeFix: <root>/pm/repo on main (repoIn) and its clone <root>/pm/dev on dev (devCloneFor!); home gateway, production lanes, seed patch and the stand-in build script beside them")
fn ! fixture! root: String -> Bool
  (let [(repo (pf/repoIn (str root "/pm")))
        (dev (pf/devCloneFor! (str root "/pm")))
        (_ (dirCreate (str root "/home/.asl")))
        (g (fileWrite (str root "/home/.asl/gateway.asn") (gatewayText)))
        (l (fileWrite (str root "/prodLanes.asn") (lanesText)))
        (p (fileWrite (str root "/seed.patch") (seedPatch)))
        (b (fileWrite (str root "/fakeBuild.sh") (buildScript)))]
    (and (not (stringEmpty? repo)) (and (not (stringEmpty? dev)) (and (ok? g) (and (ok? l) (and (ok? p) (ok? b)))))))

; (:m :do "the printed build step of one tree: cwd and the env-stripped build argv")
fn buildCmd cwd: String script: String -> String
  (str "(:cmd :cwd \"" cwd "\" :argv (\"env\" \"-u\" \"ASL_ROOT\" \"-u\" \"ASL_PRELUDE\" \"sh\" \"" script "\"))")

fn ! trial! here: String args: (List String) sec: Int64 -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str here "/bin/asl") "run" (str here "/asl/tools/coord/trial.asl")) args) here (fr/childEnv (list))) (fr/limits sec 100))

fn ! runTests -> Bool
  (let [(here (pf/here))
        (root (pf/scratch "trialSetup" "s1"))
        (_ (pf/cleanup root))
        (fx (fixture! root))
        (spec (str root "/setup.asn"))
        (bad (str root "/setupBad.asn"))
        (w1 (fileWrite spec (specText root here (str root "/trialSrc") "nimX")))
        (w2 (fileWrite bad (specText root here (str root "/pm/repo/trialSrc") "ccLing")))
        (sha (gitIn (str root "/pm/repo") "rev-parse HEAD"))
        (devSha (gitIn (str root "/pm/dev") "rev-parse HEAD"))
        (defSpec (str root "/setupDefault.asn"))
        (w3 (fileWrite defSpec (stringReplace (specText root here (str root "/trialSrc") "nimX") (str " :build (\"sh\" \"" root "/fakeBuild.sh\")") "")))
        (dry (trial! here (list "setup" "--spec" spec "--dry-run") 300))
        (dryDef (trial! here (list "setup" "--spec" defSpec "--dry-run") 300))
        (dryLeft (or (fileExists? (str root "/trialSrc")) (or (fileExists? (str root "/asexTrial")) (or (fileExists? (str root "/trialLanes.asn")) (fileExists? (str root "/store"))))))
        (refused (trial! here (list "setup" "--spec" bad) 300))
        (badLeft (fileExists? (str root "/pm/repo/trialSrc")))
        (real (trial! here (list "setup" "--spec" spec) 900))
        (srcBase (gitIn (str root "/trialSrc") "rev-parse main^"))
        (srcHead (gitIn (str root "/trialSrc") "rev-parse main"))
        (srcRemote (gitIn (str root "/trialSrc") "remote"))
        (devBranch (gitIn (str root "/asexTrial") "branch --show-current"))
        (devHead (gitIn (str root "/asexTrial") "rev-parse HEAD"))
        (devRemote (gitIn (str root "/asexTrial") "remote"))
        (seeded (readOr (str root "/trialSrc/seed.txt")))
        (built (and (fileExists? (str root "/trialSrc/asl/host/out/aslNativeBuild")) (fileExists? (str root "/asexTrial/asl/host/out/aslNativeBuild"))))
        (lanes (readOr (str root "/trialLanes.asn")))
        (runSpec (readOr (str root "/store/trialSpec.asn")))
        (_ (fileWrite (str root "/runCc.asn") (str runSpec "(:model :tag \"Cc\" :alias \"ccLing\")\n")))
        (ccCheck (trial! here (list "check" "--spec" (str root "/runCc.asn")) 300))
        (again (trial! here (list "setup" "--spec" spec) 900))
        (srcBase2 (gitIn (str root "/trialSrc") "rev-parse main^"))
        (sha1 (gitIn (str root "/pm/repo") "rev-parse HEAD"))
        (prodBranch (gitIn (str root "/pm/repo") "branch --show-current"))
        (prodDirty (gitIn (str root "/pm/repo") "status --porcelain"))
        (devSha1 (gitIn (str root "/pm/dev") "rev-parse HEAD"))
        (_ (pf/cleanup root))]
    (do (assert (and fx (and (ok? w1) (and (ok? w2) (and (not (stringEmpty? sha)) (not (stringEmpty? devSha)))))) "fixture: production stand-ins, lanes, gateway, seed, specs")
        (assert (and (= dry.exit 0) (and (stringContains? dry.out ":dryRun true") (and (stringContains? dry.out (buildCmd (str root "/trialSrc") (str root "/fakeBuild.sh"))) (stringContains? dry.out (str "\"fetch\" \"-q\" \"--no-tags\" \"" root "/pm/repo\" \"" sha "\""))))) (str "dry run prints the command list with the pinned source sha: " dry.out))
        (assert (and (stringContains? dry.out (str "(:vcs :op switch :repo \"" root "/trialSrc\" :args (\"main\" \"" sha "\"))")) (and (stringContains? dry.out (str "(:vcs :op switch :repo \"" root "/asexTrial\" :args (\"trialBase\" \"FETCH_HEAD\"))")) (stringContains? dry.out (str "(:vcs :op seedCommit :repo \"" root "/trialSrc\"")))) (str "branch switches and the seed commit go through the vcs layer: " dry.out))
        (assert (stringContains? dry.out (buildCmd (str root "/asexTrial") (str root "/fakeBuild.sh"))) (str "dry run includes the host build of the dev repo, the tree mergeCheck runs: " dry.out))
        (assert (and (ok? w3) (and (= dryDef.exit 0) (and (stringContains? dryDef.out (buildCmd (str root "/asexTrial") "asl/host/build.sh")) (stringContains? dryDef.out (buildCmd (str root "/trialSrc") "asl/host/build.sh"))))) (str "without :build both trees run their own asl/host/build.sh: " dryDef.out))
        (assert (and (stringContains? dry.out (str ":heads (\"(:head :repo \\\"" root "/pm/repo\\\" :sha \\\"" sha "\\\")\"")) (stringContains? dry.out ":lanes 2)")) (str "dry run names the heads it would pin and the two panel lanes: " dry.out))
        (assert (not dryLeft) "dry run created nothing")
        (assert (not (or (stringContains? dry.out "systemctl") (or (stringContains? dry.out "deploy") (or (stringContains? dry.out "\"push\"") (stringContains? dry.out "\"clone\""))))) (str "the command list has no systemctl, deploy, push or clone: " dry.out))
        (assert (and (= refused.exit 1) (and (stringContains? refused.out (str "isProduction:" root "/pm/repo/trialSrc")) (and (stringContains? refused.out "writerNoCredit:ccLing") (not badLeft)))) (str "a setup inside production or with a noCredit writer is refused before any command: " refused.out))
        (assert (and (= real.exit 0) (stringContains? real.out ":check 0)")) (str "setup runs and the run spec passes check: " (stringFromInt64 real.exit) " " real.out))
        (assert (and (= srcBase sha) (and (= (stringTrim seeded) "seeded") (stringEmpty? srcRemote))) (str "trial source main is the production sha plus the seed commit, no remote: " srcBase " " srcRemote))
        (assert (and (= devBranch "trialBase") (and (= devHead srcHead) (stringEmpty? devRemote))) (str "dev repo on trialBase at the trial main, no remote: " devBranch " " devHead " " srcHead))
        (assert built "both trees got their own host build")
        (assert (and (stringContains? lanes "(:lane :alias hzQ ") (and (stringContains? lanes "(:lane :alias ovh ") (and (not (stringContains? lanes ":alias ccLing ")) (not (stringContains? lanes ":alias nimX "))))) (str "trial lanes hold the panel only: " lanes))
        (assert (and (stringContains? lanes ":noCredit (:providers (\"commandCode\") :prefixes (\"cc\") :aliases (\"ccLing\"))") (and (stringContains? lanes ":familyExtra ") (not (stringContains? lanes ":writeProfiles")))) (str "trial lanes list the noCredit lane and keep familyExtra: " lanes))
        (assert (and (stringContains? runSpec (str "(:head :repo \"" root "/pm/repo\" :sha \"" sha "\")")) (and (stringContains? runSpec (str "(:head :repo \"" root "/pm/dev\" :sha \"" devSha "\")")) (and (not (stringContains? runSpec "(:setup ")) (stringContains? runSpec "(:model :tag \"W\"")))) (str "run spec pins both production heads and keeps cells: " runSpec))
        (assert (and (= ccCheck.exit 1) (stringContains? ccCheck.out "aliasNoCredit:ccLing")) (str "check refuses a writer pinned on a noCredit lane: " ccCheck.out))
        (assert (and (= again.exit 0) (= srcBase2 sha)) (str "setup runs again on the existing trees: " again.out))
        (assert (and (= sha1 sha) (and (= prodBranch "main") (and (stringEmpty? prodDirty) (= devSha1 devSha)))) (str "production heads, branch and tree unchanged: " prodDirty))
        true))
