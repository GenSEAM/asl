(module asl-tools/fleet/mutate
  :x [Mutant MutantOut mutant defaultScratch mutantDirs! sweep! mutantRun!]
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
  (:f wt String))

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
fn ! sweep! scratch: String repo: String -> Int64
  (let [(stale (filter (fn [(n String)] -> Bool (not (resultOr (procAlive? (ownerPid n)) false))) (mutantDirs! scratch)))
        (gone (filter (fn [(n String)] -> Bool (dropCopy! (str scratch "/" n))) stale))
        (_ (git repo (list "worktree" "prune")))]
    (listLength gone))

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

fn notRun wt: String why: String -> MutantOut
  (MutantOut :applied false :exit -1 :executed 0 :out why :wt wt)

; (:m :ref MUTANT-IN-COPY :do "one mutant: sweep stale copies, add the copy at the writer's HEAD, fill it, apply the mutant, run the gate there under lim, remove the copy; :applied false when the mutant text is not found exactly once")
fn ! mutantRun! wt: String scratch: String m: Mutant gate: String lim: fr/Limits -> MutantOut
  (let [(_ (dirCreate scratch))
        (_ (sweep! scratch wt))
        (head (stringTrim (git wt (list "rev-parse" "HEAD")).out))
        (path (str scratch "/mut-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (added (git wt (list "worktree" "add" "--detach" "--quiet" path head)))]
    (if (!= added.exit 0)
      (notRun "" (str "worktree add failed: " (stringTrim added.out)))
      (let [(ready (match (fillCopy! wt path) ((ok _) (applyMutant! path m)) ((err e) (err e))))
            (res (match ready
                   ((err e) (notRun path e))
                   ((ok _)
                     (let [(d (fr/runShell! gate path (fr/childEnv (list)) lim))]
                       (MutantOut :applied true :exit d.exit :executed (optionOr (fr/executedOf d.out) 0) :out d.out :wt path)))))
            (_ (dropCopy! path))]
        res)))
