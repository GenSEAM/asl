(module asl-tools/coord/worktree
  :x [Cfg Wt Entry safeUnit? wtPath parseWorktrees listWt! addWt! rescueBranch! removeWt! renderWt]
  :i [(asl-tools/fleet/run :a fr)])

(schema Cfg
  (:f repo String)
  (:f base String)
  (:f prefix String)
  (:f archive String)
  (:f mainRef String))

(schema Entry
  (:f path String)
  (:f head String)
  (:f branch String)
  (:f detached Bool))

(schema Wt
  (:f unit String)
  (:f path String)
  (:f head String)
  (:f branch String)
  (:f detached Bool)
  (:f dirty Int64)
  (:f ignored Int64)
  (:f merged Bool)
  (:f lease String))

; (:m :ref FK-WORKTREE :do "node-local worktree lifecycle: every git call is an argv under the fleet run bound, units live only at base/prefixUNIT, so worktrees of other projects are never listed or touched; config comes from Cfg, never from env")
fn ! git! dir: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons "git" (listAppend (list "-C" dir "-c" "core.fsmonitor=") args)) dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! run! argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits 120 16))

fn unitChar? c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" c)

fn safeUnit? unit: String -> Bool
  (and (not (stringEmpty? unit))
    (and (not (stringStartsWith? unit "."))
      (and (not (stringStartsWith? unit "-"))
        (and (not (stringContains? unit ".."))
          (and (not (stringEndsWith? unit ".lock"))
            (listAll? (fn [(c String)] -> Bool (unitChar? c)) (stringChars unit)))))))

fn wtPath cfg: Cfg unit: String -> String
  (str cfg.base "/" cfg.prefix unit)

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) "")

fn flushEntry acc: (List Entry) cur: (Option Entry) -> (List Entry)
  (match cur ((none) acc) ((some e) (listAppend acc (list e))))

fn entryStep st: (Pair (List Entry) (Option Entry)) line: String -> (Pair (List Entry) (Option Entry))
  (let [(acc (pairFirst st))
        (cur (pairSecond st))]
    (cond
      ((stringStartsWith? line "worktree ")
        (pair (flushEntry acc cur) (some (Entry :path (optionOr (stringSlice line 9 (stringLength line)) "") :head "" :branch "" :detached false))))
      ((stringStartsWith? line "HEAD ")
        (pair acc (match cur ((some e) (some (Entry :path e.path :head (optionOr (stringSlice line 5 (stringLength line)) "") :branch e.branch :detached e.detached))) ((none) (none)))))
      ((stringStartsWith? line "branch ")
        (pair acc (match cur ((some e) (some (Entry :path e.path :head e.head :branch (stringReplace (optionOr (stringSlice line 7 (stringLength line)) "") "refs/heads/" "") :detached e.detached))) ((none) (none)))))
      ((= line "detached")
        (pair acc (match cur ((some e) (some (Entry :path e.path :head e.head :branch "" :detached true))) ((none) (none)))))
      (else st)))

fn parseWorktrees text: String -> (List Entry)
  (let [(st (fold entryStep (pair (list) (none)) (stringLines text)))]
    (flushEntry (pairFirst st) (pairSecond st)))

fn ! realPath! p: String -> String
  (resultOr (realPath p) "")

fn countLines text: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text)))

fn ! mergedInto! cfg: Cfg head: String -> Bool
  (= (git! cfg.repo (list "merge-base" "--is-ancestor" head cfg.mainRef)).exit 0)

fn ! statusCounts! path: String -> (Pair Int64 Int64)
  (let [(s (git! path (list "status" "--porcelain" "--ignored")))
        (rows (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines s.out)))
        (ign (filter (fn [(l String)] -> Bool (stringStartsWith? l "!! ")) rows))]
    (pair (- (listLength rows) (listLength ign)) (listLength ign)))

fn unitOfEntry cfg: Cfg realBase: String e: Entry -> (Option String)
  (let [(parent (stringReplace e.path (str "/" (baseName e.path)) ""))
        (name (baseName e.path))]
    (if (and (= parent realBase) (stringStartsWith? name cfg.prefix))
      (let [(u (optionOr (stringSlice name (stringLength cfg.prefix) (stringLength name)) ""))]
        (if (safeUnit? u) (some u) (none)))
      (none)))

; (:m :ref FK-WORKTREE :do "list shows only worktrees directly under base named prefixUNIT; dirty counts non-ignored paths, ignored build output is counted apart; merged means the head is an ancestor of mainRef; lease stays unknown until the coord store is on the base")
fn ! listWt! cfg: Cfg -> (Result (List Wt) String)
  (let [(rb (realPath! cfg.base))
        (g (git! cfg.repo (list "worktree" "list" "--porcelain")))]
    (cond
      ((!= g.exit 0) (err (str "git worktree list failed: " (stringTrim g.out))))
      ((stringEmpty? rb) (ok (list)))
      (else
        (ok (fold (fn [(acc (List Wt)) (e Entry)] -> (List Wt)
                    (match (unitOfEntry cfg rb e)
                      ((none) acc)
                      ((some u)
                        (let [(c (statusCounts! e.path))]
                          (listAppend acc (list (Wt :unit u :path e.path :head e.head :branch e.branch :detached e.detached
                                                    :dirty (pairFirst c) :ignored (pairSecond c)
                                                    :merged (mergedInto! cfg e.head) :lease "unknown")))))))
                  (list) (parseWorktrees g.out))))))

fn renderWt w: Wt -> String
  (str "(:wt :unit " w.unit " :head " w.head " :branch \"" w.branch "\" :detached " (if w.detached "true" "false")
       " :dirty " w.dirty " :ignored " w.ignored " :merged " (if w.merged "true" "false") " :lease " w.lease ")")

fn ! findWt! cfg: Cfg unit: String -> (Result Wt String)
  (cond
    ((not (safeUnit? unit)) (err (str "unsafe unit name " unit)))
    (else
      (match (listWt! cfg)
        ((err e) (err e))
        ((ok ws) (match (listHead (filter (fn [(w Wt)] -> Bool (= w.unit unit)) ws))
                   ((some w) (ok w))
                   ((none) (err (str "no worktree for unit " unit))))))))

; (:m :ref FK-WORKTREE :do "add makes branch sh/UNIT at rev (default mainRef) in base/prefixUNIT; an existing path or branch is refused")
fn ! addWt! cfg: Cfg unit: String rev: String -> (Result String String)
  (let [(path (wtPath cfg unit))
        (r (if (stringEmpty? rev) cfg.mainRef rev))]
    (cond
      ((not (safeUnit? unit)) (err (str "unsafe unit name " unit)))
      ((fileExists? path) (err (str "the worktree path exists: " path)))
      (else
        (let [(m (dirCreate cfg.base))
              (a (git! cfg.repo (list "worktree" "add" "-b" (str "sh/" unit) path r)))]
          (if (and (ok? m) (= a.exit 0)) (ok path) (err (str "worktree add failed: " (stringTrim a.out))))))))

; (:m :ref FK-WORKTREE :do "a detached head gets branch rescue/UNIT-short so its commits stay reachable; an existing rescue branch is reused only when it already points at the head")
fn ! rescueBranch! cfg: Cfg w: Wt -> (Result String String)
  (let [(name (str "rescue/" w.unit "-" (optionOr (stringSlice w.head 0 8) w.head)))
        (have (git! cfg.repo (list "rev-parse" "-q" "--verify" (str "refs/heads/" name))))]
    (cond
      ((= have.exit 0) (if (= (stringTrim have.out) w.head) (ok name) (err (str "rescue branch " name " exists at another commit"))))
      (else
        (let [(b (git! cfg.repo (list "branch" name w.head)))]
          (if (= b.exit 0) (ok name) (err (str "rescue branch failed: " (stringTrim b.out))))))))

fn ! archiveDirty! cfg: Cfg w: Wt -> Result String String
  (let [(out (str cfg.archive "/" w.unit "-" (stringFromInt64 (/ (nowNs) 1000000))))
        (mk (dirCreate cfg.archive))
        (df (git! w.path (list "diff" "HEAD" "--binary" (str "--output=" out ".diff"))))
        (un (git! w.path (list "ls-files" "-o" "--exclude-standard" "-z")))
        (names un.out)]
    (cond
      ((or (not (ok? mk)) (!= df.exit 0) (!= un.exit 0)) (err (str "archive failed: " (stringTrim df.out))))
      ((not (fileExists? (str out ".diff"))) (err "archive failed: diff not written"))
      ((stringEmpty? names) (ok out))
      (else
        (match (fileWrite (str out ".untracked.list") names)
          ((err e) (err (str "archive failed: " e)))
          ((ok _)
            (let [(t (run! (list "tar" "-cf" (str out ".untracked.tar") "-C" w.path "--null" "-T" (str out ".untracked.list"))))
                  (rm (run! (list "rm" "-f" (str out ".untracked.list"))))]
              (if (and (= t.exit 0) (fileExists? (str out ".untracked.tar"))) (ok out) (err (str "archive failed: tar exit " t.exit)))))))))

fn kept unit: String reason: String -> String
  (str "(:wtKept :unit " unit " :reason " reason ")")

fn ! dropWt! cfg: Cfg w: Wt force: Bool archived: String rescued: String -> Result String String
  (let [(r (git! cfg.repo (if force (list "worktree" "remove" "--force" w.path) (list "worktree" "remove" w.path))))]
    (if (= r.exit 0)
      (ok (str "(:wtRemoved :unit " w.unit " :dirty " w.dirty " :forced " (if force "true" "false")
               (if (stringEmpty? archived) "" (str " :archive \"" archived "\""))
               (if (stringEmpty? rescued) "" (str " :rescue " rescued)) ")"))
      (err (str "worktree remove failed: " (stringTrim r.out)))))

; (:m :ref FK-WORKTREE :do "remove order: a detached head is rescued to a branch first; a dirty tree is kept unless force, and with force its tracked diff and untracked files are archived and the archive checked before removal; a clean tree whose head is not merged into mainRef is kept unless force; the checkout the repo itself lives in is never a unit path")
fn ! removeWt! cfg: Cfg unit: String force: Bool -> (Result String String)
  (match (findWt! cfg unit)
    ((err e) (err e))
    ((ok w)
      (let [(rescue (if w.detached (rescueBranch! cfg w) (ok "")))]
        (match rescue
          ((err e) (err e))
          ((ok rb)
            (cond
              ((and (> w.dirty 0) (not force)) (ok (str (kept unit "dirty") " :dirty " w.dirty)))
              ((and (not w.merged) (not force)) (ok (kept unit "unmerged")))
              ((> w.dirty 0)
                (match (archiveDirty! cfg w)
                  ((err e) (err e))
                  ((ok a) (dropWt! cfg w force a rb))))
              (else (dropWt! cfg w force "" rb))))))))
