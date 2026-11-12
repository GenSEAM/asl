(module aslAgent/tests/journalResumeAppliedTest
  :x [runTests]
  :i [(aslAgent/journal :a j) (asl-tools/vcs/git :a vg)])

; (:m :ref APPLYPATCH-SOFT-ERR :do "resumeApplied over each outcome of applyPatchChecked!: a git that did not run to its end stays err, a refused patch is ok with the label and the git message, an applied patch file is removed and named relative to the root")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/journalResumeAppliedTest-" (stringFromInt64 (procSelf)))

fn errOf r: (Result (Pair j/Written (Pair (Option String) (Option String))) String) -> String
  (match r ((ok _) "<ok>") ((err e) e))

fn appliedOf r: (Result (Pair j/Written (Pair (Option String) (Option String))) String) -> String
  (match r ((ok p) (optionOr (pairFirst (pairSecond p)) "<none>")) ((err e) (str "<err " e ">")))

fn messageOf r: (Result (Pair j/Written (Pair (Option String) (Option String))) String) -> String
  (match r ((ok p) (optionOr (pairSecond (pairSecond p)) "<none>")) ((err e) (str "<err " e ">")))

fn ! runTests -> Bool
  (let [(dir (scratch))
        (patch (str dir "/s1.patch"))
        (made (ok? (dirCreate dir)))
        (w (ok? (fileWrite patch "p\n")))
        (wr (j/newWritten dir none))
        (late (j/resumeApplied wr dir patch "apply s1.patch" (err "git timeout exit 124: o")))
        (refused (j/resumeApplied wr dir patch "apply s1.patch" (ok (vg/Out :exit 1 :out "  error: patch does not apply\n"))))
        (kept (fileExists? patch))
        (applied (j/resumeApplied wr dir patch "apply s1.patch" (ok (vg/Out :exit 0 :out ""))))
        (gone (not (fileExists? patch)))
        (_ (pathRemove dir))]
    (do (assert (and made w) "a temp root with a patch file")
        (assert (= (errOf late) "git timeout exit 124: o") (str "a git that did not run to its end stays err: " (errOf late)))
        (assert (= (messageOf refused) "apply s1.patch: error: patch does not apply") (str "a refused patch is ok with the git message: " (messageOf refused)))
        (assert (and (= (appliedOf refused) "<none>") kept) "and the refused patch file is kept")
        (assert (and (= (appliedOf applied) "s1.patch") gone) (str "an applied patch is named and removed: " (appliedOf applied)))
        true))
