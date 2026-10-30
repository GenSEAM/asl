(module asl-tools/coord/tests/e2eSmokeTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref COND3 :do "end to end, only when ASL_E2E=1: one doc-only unit goes write (Leon, free profile) -> gates (red before, green after) -> ladder (real models through the gateway) -> train merge onto a scratch dev branch -> worktree gc, in a scratch store and a scratch dev clone of this checkout; keys come from ASL_E2E_KEYS or <repo>/.env.free; the journal is printed; without ASL_E2E=1 the test skips with exit 0")
fn ! enabled -> Bool
  (= (optionOr (envGet "ASL_E2E") "") "1")

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/e2eSmoke-" name)

fn ! sh argv: (List String) cwd: String timeoutS: Int64 -> fr/Done
  (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits timeoutS 200))

fn readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! pump! ctx: cd/Ctx deadlineMs: Int64 -> Bool
  (let [(_ (cd/tick! ctx))]
    (cond
      ((cd/settled? ctx) true)
      ((> (/ (nowNs) 1000000) deadlineMs) false)
      (else (let [(_ (sleepMs 3000))] (pump! ctx deadlineMs)))))

; (:m :ref COND3 :do "a branch sh/E2E1 left in the source repo by an earlier run would be re-attached by the write stage with its old base, and the merge would carry a stale branch; both ends of a run drop the worktree registration and the branch")
fn ! leftover repo: String -> Unit
  (let [(_ (sh (list "git" "-C" repo "worktree" "prune") repo 60))
        (_ (sh (list "git" "-C" repo "branch" "-D" "sh/E2E1") repo 60))]
    ())

fn ! e2e -> Bool
  (let [(repo (resultOr (realPath ".") "."))
        (root (scratch "run"))
        (store (str root "/store"))
        (dev (str root "/dev"))
        (wts (str root "/wts"))
        (keys (optionOr (envGet "ASL_E2E_KEYS") (str repo "/.env.free")))
        (_ (sh (list "rm" "-rf" root) "." 120))
        (_ (dirCreate root))
        (_ (leftover repo))
        (clone (sh (list "git" "clone" "--quiet" repo dev) "." 600))
        (branch (sh (list "git" "-C" dev "checkout" "--quiet" "-b" "dev") dev 60))
        (built (sh (list "sh" "asl/host/build.sh") dev 1800))
        (args (list "--repo" repo "--dev-repo" dev "--dev" "dev" "--worktrees" wts "--keys" keys "--lanes" (optionOr (envGet "ASL_E2E_LANES") (str repo "/.asl/mem/work/CAL/reviewLanes.asn")) "--profile" (optionOr (envGet "ASL_E2E_PROFILE") "freeBulk") "--writer-alias" (optionOr (envGet "ASL_E2E_WRITER") "flashLow")))
        (baseSha (stringTrim (sh (list "git" "-C" repo "rev-parse" "HEAD") repo 60).out))
        (_ (dirCreate (str store "/tasks")))
        (_ (fileWrite (str store "/tasks/E2E1.txt")
                      "Create the file docs/e2eSmoke.md containing exactly one line: conductor e2e smoke. Change nothing else."))
        (put (st/put! store (st/Task :id "E2E1" :owns (list "docs/e2eSmoke.md") :reads (list) :gate "grep -q 'conductor e2e smoke' docs/e2eSmoke.md && echo '1 assertion(s) executed (1 passed)'" :channel "free" :model "" :base baseSha :after (list) :st "queued" :epoch 0 :receipt "")))
        (ctx (cd/Ctx :dir store :holder "e2e" :ttlMs 3600000 :maxWait 100 :maxSame 3 :stageSec 3000 :maxDesc 200 :launch (cd/realLaunch args store) :pace (cd/fixedPace 1 1)))
        (settled (pump! ctx (+ (/ (nowNs) 1000000) 2400000)))
        (journal (readOr (str store "/journal.asn")))
        (status (cd/status! ctx))
        (devLog (sh (list "git" "-C" dev "log" "--oneline" "-3") dev 60))
        (devDoc (sh (list "git" "-C" dev "show" "HEAD:docs/e2eSmoke.md") dev 60))
        (mainBranch (sh (list "git" "-C" repo "log" "--oneline" "-1" "--" "docs/e2eSmoke.md") repo 60))
        (_ (cd/stopAll! ctx))
        (_ (println (str "(:e2eJournal\n" journal ")")))
        (_ (println status))
        (runRows (sh (list "cat" (str store "/escalations.asn")) "." 60))
        (_ (println (str "(:runRows\n" runRows.out ")")))
        (_ (println (str "(:devLog " devLog.out ")")))
        (_ (sh (list "rm" "-rf" root) "." 300))
        (_ (leftover repo))]
    (do (assert (and (= clone.exit 0) (= branch.exit 0)) "scratch dev clone with branch dev")
        (assert (= built.exit 0) (str "scratch dev host built: " built.out))
        (assert (ok? put) "unit put")
        (assert settled "the unit settled before the deadline")
        (assert (stringContains? status "(:unit :id \"E2E1\" :st merged") (str "E2E1 merged: " status))
        (assert (stringContains? devDoc.out "conductor e2e smoke") (str "the doc landed on dev: " devDoc.out))
        (assert (stringEmpty? (stringTrim mainBranch.out)) "the source checkout's history has no e2eSmoke commit")
        (assert (and (stringContains? journal ":stage write") (stringContains? journal ":stage gates") (stringContains? journal ":stage review") (stringContains? journal ":stage merge")) "journal has write, gates, review and merge rows")
        true))

fn ! runTests -> Bool
  (let [(on (enabled))]
    (do (assert (or (not on) (e2e)) (if on "e2e smoke" "skipped: ASL_E2E is not 1"))
        true))
