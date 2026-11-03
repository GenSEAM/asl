(module asl-target-sh/tests/stepCloneTest
  :x [runTests]
  :i [(asl-target-sh/distrib :a dist)])

; (:m :ref COVERAGE-RATCHET-RED :do "stepClone! decides where the installer's entry comes from when no local checkout gave one: an entry already chosen stays, otherwise the clone under HOME/.asl/repo (a dry run only says what it would run) is searched for an entry and falls back to the portable entry a checkout can emit or to bin/asl in a dry run")
fn instFor home: String entry: String dry: Bool -> dist/Inst
  (dist/Inst :tree "" :from "pipe" :tty "" :os "linux" :arch "x86_64" :home home :installDir (str home "/.asl/bin") :dry dry :autoYes true
             :filter "" :skip false :purge false :force false :sourceDir "" :entry entry :prebuilt false :links (list) :answeredOps "")

fn ! makeDirs! base: String parts: (List String) -> String
  (fold (fn [(acc String) (p String)] -> String
          (let [(next (str acc "/" p))
                (_ (dirCreate next))]
            next))
        base parts)

fn ! entryOf r: dist/Step -> String
  (match r ((dist/go s) s.entry) ((dist/stop _) "stopped"))

fn ! sourceOf r: dist/Step -> String
  (match r ((dist/go s) s.sourceDir) ((dist/stop _) "stopped"))

fn ! testStepClone -> Bool
  (let [(home (str (optionOr (envGet "TMPDIR") "/tmp") "/stepCloneTest." (stringFromInt64 (procSelf))))
        (_ (pathRemove home))
        (_ (dirCreate home))
        (clone (str home "/.asl/repo"))
        (kept (dist/stepClone! (instFor home "/chosen/asl" false)))
        (bare (dist/stepClone! (instFor home "" true)))
        (_ (makeDirs! home (list ".asl" "repo" ".git")))
        (pulled (dist/stepClone! (instFor home "" true)))
        (_ (makeDirs! clone (list "packages" "asl-cli" "src")))
        (_ (makeDirs! clone (list "packages" "asl-target-sh" "src")))
        (_ (fileWrite (str clone "/packages/asl-cli/src/main.asl") "(module main :x [] :i [])\n"))
        (_ (fileWrite (str clone "/packages/asl-target-sh/src/distrib.asl") "(module distrib :x [] :i [])\n"))
        (emitted (dist/stepClone! (instFor home "" true)))
        (_ (pathRemove home))]
    (do (assert (= (entryOf kept) "/chosen/asl") "an entry already chosen is kept and nothing is cloned")
        (assert (= (sourceOf kept) "") "a kept entry leaves the source directory alone")
        (assert (= (entryOf bare) (str clone "/bin/asl")) "a dry run with an empty clone assumes bin/asl in the clone")
        (assert (= (sourceOf bare) clone) "the clone is the source directory")
        (assert (= (entryOf pulled) (str clone "/bin/asl")) "a dry run over an existing clone plans a pull and ends at the same entry")
        (assert (= (entryOf emitted) (str clone "/host/out/asl")) "a clone that carries the CLI and installer sources gets the portable entry")
        (assert (= (sourceOf emitted) clone) "the portable entry is built from the clone")
        true))

fn ! runTests -> Bool
  (do (testStepClone) true)
