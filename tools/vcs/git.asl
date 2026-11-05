(module asl-tools/vcs/git
  :x [peerStaged! Out Tx gitRun! head! changes! diff! stageNamed! prepare! finish! discard! branchCreate! mergeFf! log! isAncestor! pathOk? isDirPath? refOk? resolve! clean capOut]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref VCS-LAYER-CORE :do "the git backend and the only file of the vcs layer that spawns git: every call is a bounded fleet child run through env -u GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE .. so a caller's git environment never redirects it, as git --literal-pathspecs -C repo with core.hooksPath=/dev/null, core.fsmonitor off and quotepath off")
(schema Out
  (:f exit Int64)
  (:f out String))

(schema Tx
  (:f ok Bool)
  (:f why String)
  (:f dir String)
  (:f index String)
  (:f old String))

fn clean s: String -> String
  (stringTrim s)

; (:m :do "diff and log text is cut at this many characters with a truncation marker")
fn maxOut -> Int64
  200000

fn capOut s: String -> String
  (if (> (stringLength s) (maxOut))
    (str (optionOr (stringSlice s 0 (maxOut)) "") "\n(:truncated :at " (stringFromInt64 (maxOut)) ")")
    s)

fn ! gitRunIn! repo: String idx: String args: (List String) secs: Int64 -> Out
  (let [(argv (listAppend (listAppend (list "env" "-u" "GIT_DIR" "-u" "GIT_WORK_TREE" "-u" "GIT_INDEX_FILE" "-u" "GIT_COMMON_DIR" "-u" "GIT_OBJECT_DIRECTORY" "-u" "GIT_NAMESPACE")
                                      (if (stringEmpty? idx) (list) (list (str "GIT_INDEX_FILE=" idx))))
                          (listAppend (list "git" "--literal-pathspecs" "-C" repo "-c" "core.quotepath=off" "-c" "core.hooksPath=/dev/null" "-c" "core.fsmonitor=") args)))
        (d (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits secs 16)))]
    (Out :exit d.exit :out d.out))

fn ! gitRun! repo: String args: (List String) secs: Int64 -> Out
  (gitRunIn! repo "" args secs)

fn ! head! repo: String -> Out
  (gitRun! repo (list "rev-parse" "HEAD") 20)

fn ! changes! repo: String paths: (List String) -> Out
  (gitRun! repo (listAppend (list "status" "--porcelain=v1" "--untracked-files=normal") (if (listEmpty? paths) (list) (cons "--" paths))) 30)

; (:m :do "a ref or range text the layer passes to git: non-empty, no leading dash or colon, no whitespace or control characters, so it can never be read as an option or a pathspec")
fn refOk? r: String -> Bool
  (and (not (stringEmpty? r))
       (not (stringStartsWith? r "-"))
       (not (stringStartsWith? r ":"))
       (not (stringContains? r " "))
       (not (stringContains? r "\n"))
       (not (stringContains? r "\t")))

; (:m :do "the full commit sha a ref names, exit 1 when it names none")
fn ! resolve! repo: String ref: String -> Out
  (if (refOk? ref)
    (let [(o (gitRun! repo (list "rev-parse" "--verify" "--quiet" (str ref "^{commit}")) 20))]
      (Out :exit (if (= o.exit 0) 0 1) :out (clean o.out)))
    (Out :exit 1 :out (str "ref not accepted: " ref)))

fn ! diff! repo: String base: String headRef: String paths: (List String) -> Out
  (let [(a (resolve! repo base))
        (b (resolve! repo headRef))]
    (cond
      ((!= a.exit 0) (Out :exit 1 :out (str "unknown ref " base)))
      ((!= b.exit 0) (Out :exit 1 :out (str "unknown ref " headRef)))
      (else (let [(o (gitRun! repo (listAppend (list "diff" "--no-color" "--no-ext-diff" (str a.out ".." b.out)) (if (listEmpty? paths) (list) (cons "--" paths))) 60))]
              (Out :exit o.exit :out (capOut o.out))))))

; (:m :do "a path the layer accepts, judged by segments: not empty, no leading slash dash or colon, no empty segment (so no trailing slash), no . or .. or .git segment; a name like a..b.txt is fine; pathspec magic is also off in every call by --literal-pathspecs")
fn pathOk? p: String -> Bool
  (and (not (stringEmpty? p))
       (not (stringStartsWith? p "/"))
       (not (stringStartsWith? p "-"))
       (not (stringStartsWith? p ":"))
       (listAll? (fn [(s String)] -> Bool (and (not (stringEmpty? s)) (and (!= s ".") (and (!= s "..") (!= s ".git"))))) (stringSplit p "/")))

; (:m :do "true when the path is a directory in the repo: a directory is refused unless a caller names its files, since a directory would stage and commit everything under it")
fn ! isDirPath? repo: String p: String -> Bool
  (match (fileStat (str repo "/" p)) ((ok st) st.isDir) ((err _) false))

fn ! stageNamed! repo: String paths: (List String) -> Out
  (let [(present (filter (fn [(p String)] -> Bool (fileExists? (str repo "/" p))) paths))
        (gone (filter (fn [(p String)] -> Bool (not (fileExists? (str repo "/" p)))) paths))
        (none0 (Out :exit 0 :out ""))
        (a (if (listEmpty? present) none0 (gitRun! repo (listAppend (list "add" "-A" "--") present) 60)))
        (g (if (listEmpty? gone) none0 (gitRun! repo (listAppend (list "rm" "-q" "-r" "--cached" "--ignore-unmatch" "--") gone) 60)))]
    (if (!= a.exit 0) a g))

fn ! tmpIndexDir! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsIdx-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn failedTx why: String dir: String -> Tx
  (Tx :ok false :why why :dir dir :index "" :old "")

; (:m :ref VCS-LAYER-CORE :do "a private index for the commit: GIT_INDEX_FILE is set only on our children, filled from HEAD with read-tree, then the named paths are added into it (vanished ones removed); the shared index is never touched, so the guard can judge exactly these blobs and the commit lands exactly them")
fn ! prepare! repo: String paths: (List String) -> Tx
  (let [(dir (tmpIndexDir!))
        (idx (str dir "/index"))
        (mk (fr/runOneLimited (fr/job (list "mkdir" "-p" dir) "." (fr/childEnv (list))) (fr/limits 20 16)))
        (h (head! repo))
        (rt (if (and (= mk.exit 0) (= h.exit 0)) (gitRunIn! repo idx (list "read-tree" "HEAD") 60) (Out :exit 1 :out "")))
        (present (filter (fn [(p String)] -> Bool (fileExists? (str repo "/" p))) paths))
        (gone (filter (fn [(p String)] -> Bool (not (fileExists? (str repo "/" p)))) paths))
        (a (if (and (= rt.exit 0) (not (listEmpty? present))) (gitRunIn! repo idx (listAppend (list "add" "-A" "--") present) 60) (Out :exit rt.exit :out rt.out)))
        (r (if (and (= a.exit 0) (not (listEmpty? gone))) (gitRunIn! repo idx (listAppend (list "rm" "-q" "-r" "--cached" "--ignore-unmatch" "--") gone) 60) a))]
    (cond
      ((!= mk.exit 0) (failedTx "cannot create the private index dir" dir))
      ((!= h.exit 0) (failedTx (str "no HEAD: " (clean h.out)) dir))
      ((!= r.exit 0) (failedTx (str "private index: " (clean r.out)) dir))
      (else (Tx :ok true :why "" :dir dir :index idx :old (clean h.out)))))

fn ! discard! tx: Tx -> Bool
  (if (stringContains? tx.dir "/vcsIdx-")
    (= (fr/runOneLimited (fr/job (list "rm" "-rf" tx.dir) "." (fr/childEnv (list))) (fr/limits 20 16)).exit 0)
    false)

; (:m :ref VCS-LAYER-CORE :do "land the private index: write-tree, refuse when the tree equals HEAD's, commit-tree on the recorded HEAD, update-ref HEAD with the old value as the expected one so a moved HEAD fails the commit, then reset only the named paths in the shared index to the new HEAD; the out of an ok result is the new sha")
fn ! finish! repo: String tx: Tx msg: String paths: (List String) -> Out
  (let [(wt (gitRunIn! repo tx.index (list "write-tree") 60))
        (ot (gitRun! repo (list "rev-parse" "HEAD^{tree}") 20))
        (tree (clean wt.out))]
    (cond
      ((!= wt.exit 0) (Out :exit 1 :out (str "write-tree failed: " (clean wt.out))))
      ((!= ot.exit 0) (Out :exit 1 :out (str "HEAD tree unreadable: " (clean ot.out))))
      ((= tree (clean ot.out)) (Out :exit 1 :out "nothing to commit: the named paths equal HEAD"))
      (else
        (let [(ct (gitRun! repo (list "commit-tree" tree "-p" tx.old "-m" msg) 60))
              (sha (clean ct.out))]
          (if (!= ct.exit 0)
            (Out :exit 1 :out (str "commit-tree failed: " sha))
            (let [(ur (gitRun! repo (list "update-ref" "-m" "vcs commit" "HEAD" sha tx.old) 30))]
              (if (!= ur.exit 0)
                (Out :exit 1 :out (str "HEAD moved during the commit, nothing landed: " (clean ur.out)))
                (let [(rs (gitRun! repo (listAppend (list "reset" "-q" "--") paths) 60))]
                  (Out :exit (if (= rs.exit 0) 0 2) :out sha)))))))))

; (:m :do "a branch name git accepts (check-ref-format --branch) and a base that resolves to a commit")
fn ! branchCreate! repo: String name: String base: String -> Out
  (let [(ck (if (refOk? name) (gitRun! repo (list "check-ref-format" "--branch" name) 20) (Out :exit 1 :out "name not accepted")))
        (b (resolve! repo base))]
    (cond
      ((!= ck.exit 0) (Out :exit 1 :out (str "branch name not accepted: " name)))
      ((!= b.exit 0) (Out :exit 1 :out (str "unknown base " base)))
      (else (gitRun! repo (list "branch" name b.out) 20))))

; (:m :do "fast-forward only: the source is resolved to a sha first, so no ref text reaches git as an option; a non-ff source fails and no merge commit is made")
fn ! mergeFf! repo: String source: String -> Out
  (let [(s (resolve! repo source))]
    (if (!= s.exit 0)
      (Out :exit 1 :out (str "unknown source " source))
      (gitRun! repo (list "merge" "--ff-only" s.out) 120)))

fn ! log! repo: String range: String paths: (List String) fmt: String -> Out
  (if (or (not (refOk? range)) (stringStartsWith? fmt "-"))
    (Out :exit 1 :out "range or format not accepted")
    (let [(o (gitRun! repo (listAppend (list "log" (str "--format=" fmt) "--end-of-options" range) (if (listEmpty? paths) (list) (cons "--" paths))) 60))]
      (Out :exit o.exit :out (capOut o.out))))

; (:m :do "ok true when a is an ancestor of b, ok false when not, err for an unknown commit, a missing repo or any other git failure")
fn ! isAncestor! repo: String a: String b: String -> (Result Bool String)
  (let [(x (resolve! repo a))
        (y (resolve! repo b))]
    (cond
      ((!= x.exit 0) (err (str "unknown commit " a)))
      ((!= y.exit 0) (err (str "unknown commit " b)))
      (else (let [(o (gitRun! repo (list "merge-base" "--is-ancestor" x.out y.out) 20))]
              (cond ((= o.exit 0) (ok true))
                    ((= o.exit 1) (ok false))
                    (else (err (clean o.out))))))))

; (:m :ref VCS-LAYER-CORE :do "named paths whose entry in the shared index is a blob that differs from both HEAD's blob and the working file: a peer staged something this commit would silently drop from the index")
fn ! peerRow! repo: String path: String idxSha: String -> Bool
  (let [(h (gitRun! repo (list "rev-parse" "--verify" "--quiet" (str "HEAD:" path)) 20))
        (w (if (fileExists? (str repo "/" path)) (gitRun! repo (list "hash-object" "--" path) 20) (Out :exit 1 :out "")))]
    (and (!= idxSha (clean h.out)) (!= idxSha (clean w.out))))

fn ! peerFold! repo: String lines: (List String) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) acc)
    ((some l)
      (let [(tab (stringSplit l "\t"))
            (meta (stringSplit (optionOr (listHead tab) "") " "))
            (path (optionOr (listGet tab 1) ""))
            (sha (optionOr (listGet meta 1) ""))
            (rest (optionOr (listTail lines) (list)))]
        (peerFold! repo rest (if (peerRow! repo path sha) (listAppend acc (list path)) acc)))))

fn ! peerStaged! repo: String paths: (List String) -> (List String)
  (let [(ls (gitRun! repo (listAppend (list "ls-files" "-s" "--") paths) 30))]
    (peerFold! repo (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines ls.out)) (list)))
