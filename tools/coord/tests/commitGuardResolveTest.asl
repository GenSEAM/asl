(module asl/tools/coord/tests/commitGuardResolveTest
  :x [runTests]
  :i [(asl-tools/coord/commitGuard :a cg) (asl-tools/fleet/run :a fr)])

; (:m :ref COMMIT-GUARD-PKG-RESOLVE :do "the guard checks a staged file in its own package and workspace: two packages each declare a wire module, so the short import (wire :a wire) is ambiguous repo-wide and unique in pkgA; a staged edit of pkgA/src/config.asl passes as a plain asl check there does; a real unresolved import and an ill-typed staged half still block; a well-typed staged half with an ill-typed working copy passes; an import of a module present only in the working tree (never staged) blocks, since the commit would not carry it")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuardResolveTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> Bool
  (= (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).exit 0)

fn msg -> String
  "(:c :a fixture :do \"edit config\" :g \"gate\" :ev (COMMIT-GUARD-PKG-RESOLVE))"

fn wireOf pkg: String n: String -> String
  (str "(module " pkg "/wire\n  :x [w]\n  :i [])\n\nfn w -> Int64\n  " n "\n")

fn manifestOf pkg: String mods: String -> String
  (str "(:package " pkg "\n  :version \"0.1.0\"\n  :dependencies ()\n  :modules (" mods "))\n")

fn configWith imp: String body: String -> String
  (str "(module pkgA/config\n  :x [c]\n  :i [" imp "])\n\nfn c -> Int64\n  " body "\n")

fn goodConfig -> String
  (configWith "(wire :a wire)" "(+ 1 (wire/w))")

; (:m :do "a workspace repo with pkgA and pkgB, each holding a wire module, and pkgA/src/config.asl importing (wire :a wire), all committed")
fn ! workspace base: String name: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/scripts/audit") (str dir "/pkgA/src") (str dir "/pkgB/src"))).exit 0) (str name ": dirs"))
        (assert (git dir (list "init" "-q" "-b" "main")) (str name ": init"))
        (assert (put (str dir "/.asl.config.asn") "(:aslConfig\n  :workspace \"t\"\n  :root true\n)\n") (str name ": root config"))
        (assert (put (str dir "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1\n)\n") (str name ": baseline"))
        (assert (put (str dir "/pkgA/manifest.asn") (manifestOf "pkgA" "\"pkgA/wire\" \"pkgA/config\"")) (str name ": pkgA manifest"))
        (assert (put (str dir "/pkgB/manifest.asn") (manifestOf "pkgB" "\"pkgB/wire\"")) (str name ": pkgB manifest"))
        (assert (put (str dir "/pkgA/src/wire.asl") (wireOf "pkgA" "1")) (str name ": pkgA wire"))
        (assert (put (str dir "/pkgB/src/wire.asl") (wireOf "pkgB" "2")) (str name ": pkgB wire"))
        (assert (put (str dir "/pkgA/src/config.asl") (configWith "(wire :a wire)" "(wire/w)")) (str name ": config"))
        (assert (git dir (list "add" "-A")) (str name ": add"))
        (assert (git dir (list "commit" "-q" "-m" "base")) (str name ": commit"))
        dir))

fn ! staged! dir: String text: String -> Bool
  (and (put (str dir "/pkgA/src/config.asl") text) (git dir (list "add" "pkgA/src/config.asl")))

fn ! judge root: String dir: String -> cg/Receipt
  (cg/guard! dir root (list) (msg) false)

fn checkRow? r: cg/Receipt -> Bool
  (listAny? (fn [(h cg/Hit)] -> Bool (and (= h.rule "check") h.block)) r.rows)

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))
        (_0 (sh "." (list "mkdir" "-p" base)))
        (amb (workspace base "amb"))
        (_a (assert (staged! amb (goodConfig)) "amb: staged edit"))
        (plain (fr/runOneLimited (fr/job (list (str root "/bin/asl") "check" "pkgA/src/config.asl") amb (fr/childEnv (list (str "ASL_ROOT=" amb)))) (fr/limits 120 16)))
        (rAmb (judge root amb))
        (miss (workspace base "miss"))
        (_b (assert (staged! miss (configWith "(nope/gone :a g)" "(g/w)")) "miss: staged edit"))
        (rMiss (judge root miss))
        (half (workspace base "half"))
        (_c (assert (staged! half (goodConfig)) "half: good staged half"))
        (_d (assert (put (str half "/pkgA/src/config.asl") (configWith "(wire :a wire)" "\"not an int\"")) "half: ill-typed working copy"))
        (rHalf (judge root half))
        (badHalf (workspace base "badHalf"))
        (_e (assert (staged! badHalf (configWith "(wire :a wire)" "\"not an int\"")) "badHalf: ill-typed staged half"))
        (_f (assert (put (str badHalf "/pkgA/src/config.asl") (goodConfig)) "badHalf: good working copy"))
        (rBad (judge root badHalf))
        (unst (workspace base "unstaged"))
        (_g (assert (put (str unst "/pkgA/src/extra.asl") "(module pkgA/extra\n  :x [e]\n  :i [])\n\nfn e -> Int64\n  3\n") "unstaged: module only in the working tree"))
        (_h (assert (staged! unst (configWith "(wire :a wire) (pkgA/extra :a extra)" "(+ (extra/e) (wire/w))")) "unstaged: importer staged"))
        (rUnst (judge root unst))]
    (do
      (assert (and (= plain.exit 0) (stringContains? plain.out "ok ")) (str "control: a plain asl check of the staged file in its workspace passes: " plain.out))
      (assert (and (= rAmb.code 0) (not (checkRow? rAmb))) (str "a short import unique in its package is resolved there, not ambiguous repo-wide: " rAmb.text))
      (assert (= rAmb.status "ok") (str "and the receipt is ok: " rAmb.text))
      (assert (and (= rMiss.code 1) (checkRow? rMiss)) (str "a real unresolved import still blocks: " rMiss.text))
      (assert (stringContains? rMiss.text "ERR_UNRESOLVED_IMPORT") "naming the unresolved import")
      (assert (and (= rHalf.code 0) (not (checkRow? rHalf))) (str "a well-typed staged half passes although the working copy is ill-typed: " rHalf.text))
      (assert (and (= rBad.code 1) (checkRow? rBad)) (str "an ill-typed staged half blocks although the working copy is fine: " rBad.text))
      (assert (and (= rUnst.code 1) (checkRow? rUnst)) (str "an import of a module that is only in the working tree blocks, the commit would not carry it: " rUnst.text))
      (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
      true))
