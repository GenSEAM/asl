(module asl-forms/tests/editScopeTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/tests/formsDriver :a fd) (asl-tools/fleet/run :a fr)])

fn scratchDir! tag: String -> String
  (let [(made (str (optionOr (envGet "TMPDIR") "/tmp/") tag "_" (stringFromInt64 (mod (nowNs) 1000000000))))]
    (do (resultOr (dirCreate made) ()) (resultOr (realPath made) made)))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "a repository laid out as git lays it out, without starting git: <base>/main holds the .git directory, <base>/wt is a linked worktree (its .git is a file naming main/.git/worktrees/wt, whose commondir names the shared .git), <base>/other is an unrelated checkout; t.asn exists in all three with the same bytes")
fn layout! base: String body: String -> Bool
  (let [(main (k/joinPath base "main"))
        (wt (k/joinPath base "wt"))
        (other (k/joinPath base "other"))
        (admin (k/joinPath main ".git/worktrees/wt"))]
    (and (ok? (dirCreate (k/joinPath main ".git")))
         (ok? (dirCreate (k/joinPath main ".git/worktrees")))
         (ok? (dirCreate admin))
         (ok? (fileWrite (k/joinPath admin "commondir") "../..\n"))
         (ok? (dirCreate wt))
         (ok? (fileWrite (k/joinPath wt ".git") (str "gitdir: " admin "\n")))
         (ok? (dirCreate other))
         (ok? (dirCreate (k/joinPath other ".git")))
         (ok? (fileWrite (k/joinPath main "t.asn") body))
         (ok? (fileWrite (k/joinPath wt "t.asn") body))
         (ok? (fileWrite (k/joinPath other "t.asn") body))))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "the forms host runs through fleet/run with a 60 s timeout and a descendant limit; no --root is passed, so the workspace comes from the inherited ASL_ROOT and the cwd alone, and the staging store is outside all three checkouts")
fn formsRun! base: String cwd: String envRoot: String payload: String -> fr/Done
  (let [(repo (resultOr (realPath ".") ""))
        (host (fd/formsBin! repo))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ASL_VFS_DIR=" (k/joinPath base "vfs")) (str "ASL_ROOT=" envRoot)))]
    (fr/runOneLimited (fr/job (list host payload) cwd env) (fr/limits 60 16)))

fn editForm old: String new: String -> String
  (str "(:edit :file \"t.asn\" :old \"" old "\" :new \"" new "\") (:flush)")

fn diskText dir: String -> String
  (resultOr (fileReadString (k/joinPath dir "t.asn")) "<unreadable>")

fn body -> String
  "(:row :id a :text \"one\\ntwo\\tthree \\\"q\\\" \\\\n\")\n(:row :id b :text \"keep\\nme\")\n"

fn edited -> String
  "(:row :id a :text \"one\\ntwo\\tthree \\\"q\\\" \\\\n\")\n(:row :id b2 :text \"keep\\nme\")\n"

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "an edit and flush run with the cwd in a linked worktree lands in that worktree although the inherited ASL_ROOT names the main checkout of the same repository; the main checkout keeps every byte and gains no file")
fn testWorktreeCwdBeatsInheritedRoot! -> Bool
  (let [(base (scratchDir! "aslFormsEditScopeWt"))
        (made (layout! base (body)))
        (out (formsRun! base (k/joinPath base "wt") (k/joinPath base "main") (editForm ":id b" ":id b2")))
        (wtAfter (diskText (k/joinPath base "wt")))
        (mainAfter (diskText (k/joinPath base "main")))
        (mainNames (listSort (resultOr (dirList (k/joinPath base "main")) (list))))
        (_ (pathRemove base))]
    (do
      (assert made "scratch repository laid out")
      (assert (stringContains? out.out ":persisted true") (str "the flush persists: " out.out))
      (assert (= wtAfter (edited)) (str "the worktree file carries the edit: " wtAfter))
      (assert (= mainAfter (body)) (str "the main checkout file is byte-equal to before: " mainAfter))
      (assert (= mainNames (list ".git" "t.asn")) (str "the main checkout gained no entry: " (stringJoin mainNames ",")))
      true))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "the same holds from a directory below the worktree top")
fn testWorktreeSubdir! -> Bool
  (let [(base (scratchDir! "aslFormsEditScopeSub"))
        (made (and (layout! base (body)) (ok? (dirCreate (k/joinPath base "wt/deep")))))
        (out (formsRun! base (k/joinPath base "wt/deep") (k/joinPath base "main") (editForm ":id b" ":id b2")))
        (wtAfter (diskText (k/joinPath base "wt")))
        (mainAfter (diskText (k/joinPath base "main")))
        (_ (pathRemove base))]
    (do
      (assert made "scratch repository laid out")
      (assert (= wtAfter (edited)) (str "the worktree file carries the edit: " out.out))
      (assert (= mainAfter (body)) (str "the main checkout file is byte-equal to before: " mainAfter))
      true))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "ASL_ROOT keeps its meaning everywhere else: from an unrelated checkout it selects the named workspace, and from the main checkout it redirects to the worktree it names")
fn testInheritedRootKept! -> Bool
  (let [(base (scratchDir! "aslFormsEditScopeEnv"))
        (made (layout! base (body)))
        (fromOther (formsRun! base (k/joinPath base "other") (k/joinPath base "main") (editForm ":id b" ":id b2")))
        (mainAfter (diskText (k/joinPath base "main")))
        (otherAfter (diskText (k/joinPath base "other")))
        (fromMain (formsRun! base (k/joinPath base "main") (k/joinPath base "wt") (editForm ":id a" ":id a2")))
        (wtAfter (diskText (k/joinPath base "wt")))
        (mainLast (diskText (k/joinPath base "main")))
        (_ (pathRemove base))]
    (do
      (assert made "scratch repository laid out")
      (assert (= mainAfter (edited)) (str "from an unrelated checkout ASL_ROOT selects the workspace: " fromOther.out))
      (assert (= otherAfter (body)) (str "the unrelated checkout is untouched: " otherAfter))
      (assert (stringContains? wtAfter ":id a2") (str "from the main checkout ASL_ROOT redirects to the worktree: " fromMain.out))
      (assert (= mainLast (edited)) (str "the main checkout is not written by the redirected edit: " mainLast))
      true))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "string escapes outside the edited span reach the disk as written: backslash-n, backslash-t, an escaped quote and an escaped backslash are not decoded by the flush")
fn testEscapesRoundTrip! -> Bool
  (let [(base (scratchDir! "aslFormsEditScopeEsc"))
        (made (layout! base (body)))
        (out (formsRun! base (k/joinPath base "wt") (k/joinPath base "wt") (editForm ":id b" ":id b2")))
        (after (diskText (k/joinPath base "wt")))
        (back (formsRun! base (k/joinPath base "wt") (k/joinPath base "wt") (editForm ":id b2" ":id b")))
        (again (diskText (k/joinPath base "wt")))
        (_ (pathRemove base))]
    (do
      (assert made "scratch repository laid out")
      (assert (= after (edited)) (str "only the hunk changed, every escape is as it was: " out.out))
      (assert (= again (body)) (str "the reverse edit restores the file byte-equal: " back.out))
      true))

; (:m :ref ASL-EDIT-SCOPE-ESCAPES :do "ops that take the workspace from the know context follow the same choice: a note written from the linked worktree lands in that worktree's ledger and the main checkout gains no .asl entry")
fn testNoteWriteStaysInWorktree! -> Bool
  (let [(base (scratchDir! "aslFormsEditScopeNote"))
        (made (layout! base (body)))
        (out (formsRun! base (k/joinPath base "wt") (k/joinPath base "main") "(:note :action write :claim \"scopeProbeClaim\")"))
        (wtLedger (resultOr (fileReadString (k/joinPath base "wt/.asl/mem/notes.asn")) ""))
        (mainNames (listSort (resultOr (dirList (k/joinPath base "main")) (list))))
        (_ (pathRemove base))]
    (do
      (assert made "scratch repository laid out")
      (assert (stringContains? out.out ":persisted true") (str "the note write persists: " out.out))
      (assert (stringContains? wtLedger "scopeProbeClaim") (str "the worktree ledger holds the note: " out.out))
      (assert (= mainNames (list ".git" "t.asn")) (str "the main checkout gained no entry: " (stringJoin mainNames ",")))
      true))

fn runTests -> Bool
  (do (testWorktreeCwdBeatsInheritedRoot!) (testWorktreeSubdir!) (testInheritedRootKept!) (testEscapesRoundTrip!) (testNoteWriteStaysInWorktree!) true)
