(module asl-tools/fleet/mutate
  :x [Mutant MutantOut mutant defaultScratch mutantDirs! sweep! sweepIn! mutantRun! mutantRunIn! verdictOf cacheDir! headFile seedable depHit? pinOf! depsOf!]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref MUTANT-IN-COPY :do "a mutant runs in a detached throwaway worktree of the writer's HEAD plus its uncommitted diff and untracked files, never in the writer's tree: a mutant job stopped mid-gate once left its edit in the writer's worktree and the next edits stacked on it (ESC-LADDER escRun4/5); the copy is removed on every exit of mutantRun!, and one left by a killed run is swept at the next start")

(schema Mutant
  (:f file String)
  (:f old String)
  (:f new String))

(schema MutantOut
  (:f applied Bool)
  (:f exit Int64)
  (:f executed Int64)
  (:f out String)
  (:f wt String)
  (:f verdict String)
  (:f red Bool)
  (:f cli String))

fn mutant file: String old: String new: String -> Mutant
  (Mutant :file file :old old :new new)

fn ! defaultScratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslMutants")

fn ! git dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))) (fr/limits 300 16))

fn ownerPid name: String -> Int64
  (if (stringStartsWith? name "mut-")
    (optionOr (stringToInt64 (optionOr (listGet (stringSplit name "-") 1) "")) -1)
    -1)

fn ! mutantDirs! scratch: String -> (List String)
  (filter (fn [(n String)] -> Bool (> (ownerPid n) 0)) (resultOr (dirList scratch) (list)))

fn ! dropCopy! path: String -> Bool
  (let [(_ (git path (list "worktree" "remove" "--force" path)))
        (_ (if (fileExists? path) (fr/runOneLimited (fr/job (list "rm" "-rf" path) "/" (fr/childEnv (list))) (fr/limits 120 4)) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "")))]
    (not (fileExists? path)))

; (:m :ref MUTANT-IN-COPY :do "a copy whose owner pid is gone was left by a killed run; it is removed and its worktree registration pruned; a live run's copy is kept")
fn ! sweepIn! scratch: String repo: String cache: String -> Int64
  (let [(stale (filter (fn [(n String)] -> Bool (not (resultOr (procAlive? (ownerPid n)) false))) (mutantDirs! scratch)))
        (_ (map (fn [(n String)] -> Bool (dropHead! scratch cache n)) stale))
        (gone (filter (fn [(n String)] -> Bool (dropCopy! (str scratch "/" n))) stale))
        (_ (git repo (list "worktree" "prune")))]
    (listLength gone))

fn ! sweep! scratch: String repo: String -> Int64
  (sweepIn! scratch repo (cacheDir!))

fn occurrences text: String part: String -> Int64
  (if (stringEmpty? part) 0 (- (listLength (stringSplit text part)) 1))

; (:m :ref MUTANT-IN-COPY :do "the copy gets the writer's HEAD, then its uncommitted diff and untracked non-ignored files; the writer's worktree is only read")
fn ! fillCopy! wt: String path: String -> (Result Unit String)
  (let [(d (git wt (list "diff" "--binary" "HEAD")))
        (patch (str path ".patch"))
        (applied (if (stringEmpty? (stringTrim d.out)) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "")
                   (let [(_ (fileWrite patch d.out))
                         (a (git path (list "apply" "--binary" patch)))
                         (_ (pathRemove patch))]
                     a)))
        (untracked (fr/runOneLimited (fr/job (list "sh" "-c" "git ls-files --others --exclude-standard -z | tar --null -T - -cf - | tar -xf - -C \"$1\"" "fill" path) wt (fr/childEnv (list))) (fr/limits 300 16)))]
    (cond
      ((!= d.exit 0) (err (str "diff failed: " (stringTrim d.out))))
      ((!= applied.exit 0) (err (str "apply failed: " (stringTrim applied.out))))
      ((!= untracked.exit 0) (err (str "untracked copy failed: " (stringTrim untracked.out))))
      (else (ok ()))))

fn ! applyMutant! path: String m: Mutant -> (Result Unit String)
  (let [(target (str path "/" m.file))
        (text (resultOr (fileReadString target) ""))
        (k (occurrences text m.old))]
    (if (!= k 1)
      (err (str "mutantNotApplied: " (stringFromInt64 k) " occurrences of the old text in " m.file))
      (match (fileWrite target (stringReplace text m.old m.new))
        ((ok _) (ok ()))
        ((err e) (err (str "mutant write failed: " e))))))

; (:m :ref MUTANT-SHARED-CLI :do "a copy whose changed files (the mutated file and the writer's uncommitted ones) are all outside the deps of the native CLI the writer's worktree is pinned to reuses that CLI: the copy gets a head pointer in the CLI cache naming the same build dir, read from the writer's pointer and never rebuilt into the writer's tree; a changed CLI input, an absent pointer or an absent deps list leaves the copy to build its own; the pointer is removed with the copy and a killed run's pointer by the next sweep")
fn ! cacheDir! -> String
  (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))

fn headFile cache: String root: String -> String
  (str cache "/head" (stringReplace root "/" "_"))

fn ! pinOf! cache: String wt: String -> String
  (let [(first (stringTrim (optionOr (listHead (stringLines (resultOr (fileReadString (headFile cache (resultOr (realPath wt) wt))) ""))) "")))]
    (if (and (not (stringEmpty? first)) (fileExists? (str first "/bin"))) first ""))

fn ! depsOf! pin: String -> (List String)
  (if (stringEmpty? pin) (list)
    (filter (fn [(d String)] -> Bool (not (stringEmpty? d))) (map stringTrim (stringLines (resultOr (fileReadString (str pin "/deps")) "")))))

fn depHit? deps: (List String) f: String -> Bool
  (listAny? (fn [(d String)] -> Bool (or (= d f) (stringStartsWith? f (str d "/")))) deps)

fn seedable pin: String deps: (List String) files: (List String) -> Bool
  (and (not (stringEmpty? pin)) (and (not (listEmpty? deps)) (not (listAny? (fn [(f String)] -> Bool (depHit? deps f)) files))))

fn ! changedFiles! wt: String -> (List String)
  (let [(a (git wt (list "diff" "--name-only" "HEAD")))
        (u (git wt (list "ls-files" "--others" "--exclude-standard")))]
    (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (listAppend (stringLines a.out) (stringLines u.out)))))

fn markerPath scratch: String name: String -> String
  (str scratch "/heads/" name)

fn ! seedHead! cache: String pin: String scratch: String name: String path: String -> Bool
  (let [(head (headFile cache (resultOr (realPath path) path)))
        (_ (dirCreate cache))
        (_ (dirCreate (str scratch "/heads")))]
    (and (ok? (fileWrite (markerPath scratch name) head)) (ok? (fileWrite head (str pin "\n")))))

; (:m :ref MUTANT-SHARED-CLI-LOWS :do "a marker path outside the cache dir is journaled, not removed")
fn ! dropHead! scratch: String cache: String name: String -> Bool
  (let [(m (markerPath scratch name))
        (head (stringTrim (resultOr (fileReadString m) "")))
        (inside (and (stringStartsWith? head (str cache "/")) (not (stringContains? head ".."))))
        (_ (cond
             ((stringEmpty? head) false)
             (inside (ok? (pathRemove head)))
             (else (ok? (fileAppend (str scratch "/headSkips.log") (str "(:headSkipped :marker " name " :path " head ")
"))))))
        (_ (pathRemove m))]
    true)

; (:m :ref MUTANT-INVALID :do "a nonzero exit counts as red only when the gate ran assertions or failed one; a mutant that does not load or check (or a gate killed by its limits before an assertion ran) is invalid and never red")
fn verdictOf exit: Int64 executed: Int64 out: String -> String
  (let [(fails (filter (fn [(l String)] -> Bool (stringStartsWith? l "FAIL ")) (stringLines out)))
        (ran (optionOr (fr/executedOf (stringJoin fails "
")) 0))]
    (cond
      ((= exit 0) "pass")
      ((listAny? (fn [(l String)] -> Bool (stringContains? l "ERR_ASSERT")) fails) "red")
      ((> ran 0) "red")
      (else "invalid")))

fn notRun wt: String why: String -> MutantOut
  (MutantOut :applied false :exit -1 :executed 0 :out why :wt wt :verdict "notApplied" :red false :cli "")

; (:m :ref MUTANT-IN-COPY :do "one mutant: sweep stale copies, add the copy at the writer's HEAD, fill it, apply the mutant, run the gate there under lim, remove the copy; :applied false when the mutant text is not found exactly once")
fn ! mutantRun! wt: String scratch: String m: Mutant gate: String lim: fr/Limits -> MutantOut
  (mutantRunIn! wt scratch (cacheDir!) m gate lim)

; (:m :ref FABLE-GATE-ADMIT :do "a mutant starts only under the load gate of the admission config (fr/admitLoad!, 2 times the cores by default): above it the run waits, and past the wait it is not run and says loadWait, which is neither red nor pass")
; (:m :ref GATEINTEGRITY-TIMEOUT-PASSES :do "a mutant gate the runner ended at its timeout has verdict timeout and is never red, whatever it printed before")
fn ! mutantRunIn! wt: String scratch: String cache: String m: Mutant gate: String lim: fr/Limits -> MutantOut
  (let [(la (fr/admitLoad! lim.jsDir))]
    (if (= la.state "expired")
      (MutantOut :applied false :exit -1 :executed 0 :out (fr/loadNote la) :wt "" :verdict "loadWait" :red false :cli "")
  (let [(_ (dirCreate scratch))
        (_ (sweepIn! scratch wt cache))
        (head (stringTrim (git wt (list "rev-parse" "HEAD")).out))
        (name (str "mut-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (path (str scratch "/" name))
        (added (git wt (list "worktree" "add" "--detach" "--quiet" path head)))]
    (if (!= added.exit 0)
      (notRun "" (str "worktree add failed: " (stringTrim added.out)))
      (let [(ready (match (fillCopy! wt path) ((ok _) (applyMutant! path m)) ((err e) (err e))))
            (res (match ready
                   ((err e) (notRun path e))
                   ((ok _)
                     (let [(pin (pinOf! cache wt))
                           (files (cons m.file (changedFiles! wt)))
                           (pinned (and (seedable pin (depsOf! pin) files) (seedHead! cache pin scratch name path)))
                           (d (fr/runShell! gate path (fr/childEnv (list)) lim))
                           (ex (optionOr (fr/executedOf d.out) 0))
                           (v (if (= (fr/gateVerdict d) "timeout") "timeout" (verdictOf d.exit ex d.out)))]
                       (MutantOut :applied true :exit d.exit :executed ex :out d.out :wt path :verdict v :red (= v "red") :cli (if pinned "pinned" "cold"))))))
            (_ (dropHead! scratch cache name))
            (_ (dropCopy! path))]
        res)))))
