(module asl-tools/vcs/vcs
  :x [VcsReceipt head! status! diff! stage! commit! commitWith! branch! mergeFf! log! isAncestor! receiptOf restore! applyPatch! worktreeAdd! worktreeRemove!]
  :i [(asl-tools/vcs/git :a g) (asl-tools/coord/commitGuard :a cg)])

; (:m :ref VCS-LAYER-CORE :do "the backend-neutral version-control API: every op takes a repo root and answers an ASN receipt line; the git backend is vcs/git.asl, the only file that spawns git, so a different backend replaces that one file; commit lands exactly the blobs the guard judged and refuses when commitGuard blocks or leaves a file unchecked")
(schema VcsReceipt
  (:f code Int64)
  (:f text String))

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn receiptOf op: String code: Int64 body: String -> VcsReceipt
  (VcsReceipt :code code :text (str "(:vcs :op :" op " :status :" (if (= code 0) "ok" "failed") body ")"))

fn outReceipt op: String o: g/Out -> VcsReceipt
  (receiptOf op (if (= o.exit 0) 0 1) (str " :exit " (stringFromInt64 o.exit) " :out \"" (esc (g/clean o.out)) "\""))

fn ! head! repo: String -> VcsReceipt
  (outReceipt "head" (g/head! repo))

fn ! status! repo: String paths: (List String) -> VcsReceipt
  (let [(bad (badPaths! repo paths))]
    (if (listEmpty? bad)
      (outReceipt "status" (g/changes! repo paths))
      (refused "status" (str "path not accepted: " (stringJoin bad ",")))))

fn ! diff! repo: String base: String headRef: String paths: (List String) -> VcsReceipt
  (let [(bad (badPaths! repo paths))]
    (if (listEmpty? bad)
      (outReceipt "diff" (g/diff! repo base headRef paths))
      (refused "diff" (str "path not accepted: " (stringJoin bad ",")))))

; (:m :do "paths the layer will not pass on: pathspec-shaped, escaping, .git, or a directory")
fn ! badPaths! repo: String paths: (List String) -> (List String)
  (filter (fn [(p String)] -> Bool (or (not (g/pathOk? p)) (g/isDirPath? repo p))) paths)

fn refused op: String why: String -> VcsReceipt
  (VcsReceipt :code 1 :text (str "(:vcs :op :" op " :status :refused :why \"" (esc why) "\")"))

; (:m :do "stage exactly the named paths in the shared index; an empty list, a pathspec-shaped path or a directory is refused and nothing is staged")
fn ! stage! repo: String paths: (List String) -> VcsReceipt
  (cond
    ((listEmpty? paths) (refused "stage" "no paths named"))
    ((not (listEmpty? (badPaths! repo paths))) (refused "stage" (str "path not accepted: " (stringJoin (badPaths! repo paths) ","))))
    (else (outReceipt "stage" (g/stageNamed! repo paths))))

; (:m :do "commit exactly paths: refuse an empty list or an unaccepted path, build a private index from HEAD plus the named paths (the shared index and the guard's view never differ from what lands), run commitGuard on that index in process, refuse on a block or a partial check (mode commit) or record and go on (mode warn), then commit-tree and update-ref against the recorded HEAD; the receipt carries :sha and the guard receipt, a refusal leaves the shared index as it was")
fn ! commit! repo: String aslRoot: String paths: (List String) msg: String mode: String -> VcsReceipt
  (commitWith! repo aslRoot "" paths msg mode)

; (:m :ref WORKTREE-COLD-CACHE :do "commit! whose guard checks run by toolRoot's bin/asl (a warm tree) with cwd and ASL_ROOT of aslRoot; empty toolRoot is commit!")
fn ! commitWith! repo: String aslRoot: String toolRoot: String paths: (List String) msg: String mode: String -> VcsReceipt
  (cond
    ((listEmpty? paths) (refused "commit" "no paths named"))
    ((not (listEmpty? (badPaths! repo paths))) (refused "commit" (str "path not accepted: " (stringJoin (badPaths! repo paths) ","))))
    ((not (listEmpty? (g/peerStaged! repo paths))) (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :refused :peerStaged (" (stringJoin (map (fn [(p String)] -> String (str "\"" (esc p) "\"")) (g/peerStaged! repo paths)) " ") ") :why \"the shared index holds a staged blob for a named path that differs from HEAD and the working file\")")))
    (else
      (let [(tx (g/prepare! repo paths))]
        (if (not tx.ok)
          (let [(_ (g/discard! tx))] (refused "commit" tx.why))
          (let [(j (cg/guardIndexWith! repo aslRoot toolRoot paths msg (= mode "warn") tx.index))]
            (if (= j.code 1)
              (let [(_ (g/discard! tx))] (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :refused :guard " j.text ")")))
              (let [(c (g/finish! repo tx msg paths))
                    (_ (g/discard! tx))]
                (if (and (!= c.exit 0) (!= c.exit 2))
                  (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :failed :why \"" (esc (g/clean c.out)) "\")"))
                  (let [(sha (g/clean c.out))
                        (warned (and (= mode "warn") (not (listEmpty? j.rows))))
                        (stale (= c.exit 2))
                        (rec (if warned (cg/recordText! repo (str "(:vcs :op :commit :sha " sha " :aslRoot \"" (esc aslRoot) "\" :guard " j.text ")")) ""))
                        (status (cond (warned "warned") (stale "partial") (else "done")))]
                    (VcsReceipt :code 0 :text (str "(:vcs :op :commit :status :" status " :aslRoot \"" (esc aslRoot) "\"" (if stale " :indexStale true" "") " :sha " sha rec " :guard " j.text ")")))))))))))

fn ! branch! repo: String name: String base: String -> VcsReceipt
  (outReceipt "branch" (g/branchCreate! repo name base))

fn ! mergeFf! repo: String source: String -> VcsReceipt
  (outReceipt "mergeFf" (g/mergeFf! repo source))

fn ! restore! repo: String rev: String paths: (List String) -> VcsReceipt
  (outReceipt "restore" (g/restoreTree! repo rev paths))

fn ! applyPatch! repo: String patch: String reverse: Bool -> VcsReceipt
  (outReceipt "applyPatch" (g/applyPatch! repo patch reverse))

fn ! worktreeAdd! repo: String path: String sha: String -> VcsReceipt
  (outReceipt "worktreeAdd" (g/worktreeAdd! repo path sha))

fn ! worktreeRemove! repo: String path: String -> VcsReceipt
  (outReceipt "worktreeRemove" (g/worktreeRemove! repo path))

fn ! log! repo: String range: String paths: (List String) fmt: String -> VcsReceipt
  (let [(bad (badPaths! repo paths))]
    (if (listEmpty? bad)
      (outReceipt "log" (g/log! repo range paths fmt))
      (refused "log" (str "path not accepted: " (stringJoin bad ",")))))

fn ! isAncestor! repo: String a: String b: String -> (Result Bool String)
  (g/isAncestor! repo a b)
