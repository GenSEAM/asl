(module asl-gates/tests/noteMigrationTest
  :x [runTests]
  :i [(asl-gates/docExtract :a dx) (tools/fleet/run :a run)])

fn migrationCommit -> String
  "1885f75cd"

(schema Captured
  (:f exitCode Int64)
  (:f stdout String))

fn ! git! args: String -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (outPath (str (optionOr (envGet "TMPDIR") "/tmp") "/noteMigrationTest." (monotonicNs) ".out"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "cd '" root "' && git " args " > " outPath " 2>/dev/null")) root
                                         (run/childEnv (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")))))
                                 (run/limits 120 8)))
        (outText (resultOr (fileReadString outPath) ""))
        (_ (pathRemove outPath))]
    (Captured :exitCode done.exit :stdout outText))

fn ! changedPaths! -> (List String)
  (let [(r (git! (str "diff --name-only " (migrationCommit) "^.." (migrationCommit))))]
    (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit (stringTrim r.stdout) "\n")))

fn ! oldTextOf! path: String -> (Option String)
  (let [(r (git! (str "show " (migrationCommit) "^:" path)))]
    (if (= r.exitCode 0) (some r.stdout) (none)))

fn escRow s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn ! fileTextOr! path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err _) ""))

; (:m :ref DEADPKG-LEFT :do "asl-agent's package was deleted (DEAD-PACKAGES); its doc.asn, the ledger dx/ledgerPathFor would still point this migration's 9 pinned files at, moved verbatim to .asl/mem/docs/retiredNotes.asn so the package directory could go away entirely while the pinned note texts stay findable")
fn retiredLedgerOverride path: String -> (Option String)
  (if (stringStartsWith? path "asl/packages/asl-agent/") (some ".asl/mem/docs/retiredNotes.asn") (none))

fn ledgerPathForMigration path: String -> String
  (optionOr (retiredLedgerOverride path) (dx/ledgerPathFor path))

fn allNotesPresent! cs: (List dx/NoteCandidate) ledgerText: String path: String -> Bool
  (mt (listHead cs)
    ((none) true)
    ((some c)
      (do (assert (stringContains? ledgerText (escRow c.text))
                  (str path ": note text for " c.symbol " must appear in " (ledgerPathForMigration path)))
          (allNotesPresent! (optionOr (listTail cs) (list)) ledgerText path))))

fn ! checkPathNotes! path: String -> Bool
  (mt (oldTextOf! path)
    ((none) (do (assert false (str "git show " (migrationCommit) "^:" path " failed")) false))
    ((some oldText)
      (let [(cs (dx/noteScanAll path oldText)) (ledgerText (fileTextOr! (ledgerPathForMigration path)))]
        (allNotesPresent! cs ledgerText path))))

fn ! checkAllPaths! paths: (List String) -> Bool
  (mt (listHead paths)
    ((none) true)
    ((some p) (and (checkPathNotes! p) (checkAllPaths! (optionOr (listTail paths) (list))))))

fn ! testAllRemovedNotesPreserved! -> Bool
  (let [(paths (changedPaths!))]
    (do (assert (= (listLength paths) 143) (str "the " (migrationCommit) " note-retirement sweep touched 143 files, got " (stringFromInt64 (listLength paths))))
        (checkAllPaths! paths)))

fn ! runTests -> Bool
  (do
    (assert (testAllRemovedNotesPreserved!) "testAllRemovedNotesPreserved!")
    true)
