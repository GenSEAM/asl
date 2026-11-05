(module asl-tools/vcs/git
  :x [Out gitRun! head! changes! diff! stageNamed! commitNamed! branchCreate! mergeFf! log! isAncestor! pathOk? clean]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref VCS-LAYER-CORE :do "the git backend and the only file of the vcs layer that spawns git: every call is a bounded fleet child run as git -C repo with core.hooksPath=/dev/null so user-level hooks never run inside our commits, core.fsmonitor off and quotepath off")
(schema Out
  (:f exit Int64)
  (:f out String))

fn clean s: String -> String
  (stringTrim s)

fn ! gitRun! repo: String args: (List String) secs: Int64 -> Out
  (let [(d (fr/runOneLimited (fr/job (listAppend (list "git" "-C" repo "-c" "core.quotepath=off" "-c" "core.hooksPath=/dev/null" "-c" "core.fsmonitor=" "-c" "user.useConfigOnly=false") args) "." (fr/childEnv (list))) (fr/limits secs 16)))]
    (Out :exit d.exit :out d.out))

fn ! head! repo: String -> Out
  (gitRun! repo (list "rev-parse" "HEAD") 20)

; (:m :do "name-status lines of the working tree against HEAD, restricted to paths when given")
fn ! changes! repo: String paths: (List String) -> Out
  (gitRun! repo (listAppend (list "status" "--porcelain=v1" "--untracked-files=normal") (if (listEmpty? paths) (list) (cons "--" paths))) 30)

fn ! diff! repo: String base: String headRef: String paths: (List String) -> Out
  (gitRun! repo (listAppend (list "diff" "--no-color" "--no-ext-diff" (str base ".." headRef)) (if (listEmpty? paths) (list) (cons "--" paths))) 60)

; (:m :do "a path the layer accepts: relative, non-empty, no leading dash, no .. segment, no glob star, so a staging call can never widen to the whole tree")
fn pathOk? p: String -> Bool
  (and (not (stringEmpty? p))
       (not (stringStartsWith? p "/"))
       (not (stringStartsWith? p "-"))
       (not (= p "."))
       (not (stringContains? p ".."))
       (not (stringContains? p "*")))

; (:m :do "stage exactly paths: present ones with add -A over those paths only, vanished ones with rm --cached; the first failing step is returned")
fn ! stageNamed! repo: String paths: (List String) -> Out
  (let [(present (filter (fn [(p String)] -> Bool (fileExists? (str repo "/" p))) paths))
        (gone (filter (fn [(p String)] -> Bool (not (fileExists? (str repo "/" p)))) paths))
        (none0 (Out :exit 0 :out ""))
        (a (if (listEmpty? present) none0 (gitRun! repo (listAppend (list "add" "-A" "--") present) 60)))
        (g (if (listEmpty? gone) none0 (gitRun! repo (listAppend (list "rm" "-q" "-r" "--cached" "--ignore-unmatch" "--") gone) 60)))]
    (if (!= a.exit 0) a g))

fn ! commitNamed! repo: String paths: (List String) msg: String -> Out
  (gitRun! repo (listAppend (list "commit" "-q" "-m" msg "--") paths) 60)

fn ! branchCreate! repo: String name: String base: String -> Out
  (gitRun! repo (list "branch" name base) 20)

fn ! mergeFf! repo: String source: String -> Out
  (gitRun! repo (list "merge" "--ff-only" source) 120)

fn ! log! repo: String range: String paths: (List String) fmt: String -> Out
  (gitRun! repo (listAppend (list "log" (str "--format=" fmt) range) (if (listEmpty? paths) (list) (cons "--" paths))) 60)

fn ! isAncestor! repo: String a: String b: String -> Bool
  (= (gitRun! repo (list "merge-base" "--is-ancestor" a b) 20).exit 0)
