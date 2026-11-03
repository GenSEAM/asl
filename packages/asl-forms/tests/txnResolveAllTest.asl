(module asl-forms/tests/txnResolveAllTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/tests/formsDriver :a fd) (asl-tools/fleet/run :a fr)])

fn scratchDir! tag: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp/") tag "_" (stringFromInt64 (mod (nowNs) 1000000000)))

; (:m :ref NOSELFHOST-RED-20261031 :do "the forms host runs through fleet/run with a 60 s timeout and a descendant limit, so a hung or forking child is killed with its tree")
fn txnRun! root: String payload: String -> fr/Done
  (let [(repo (resultOr (realPath ".") ""))
        (host (fd/formsBin! repo))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ASL_VFS_DIR=" (k/joinPath root ".asl/vfs"))))]
    (fr/runOneLimited (fr/job (list host "--root" root payload) repo env) (fr/limits 60 16)))

fn libText -> String
  "(module tmp/lib :x [one])\\nfn one -> Int64\\n  1\\n"

fn useText missing: String -> String
  (str "(module tmp/useTest :x [runTests] :i [(tmp/" missing " :a l)])\\nfn runTests -> Bool\\n  (= (l/one) 1)\\n")

fn txnForm lib: String use: String -> String
  (str "(:txn :owns (\"tmp/src/lib.asl\" \"tmp/src/useTest.asl\")"
       " (:write :file \"tmp/src/useTest.asl\" :content \"" use "\")"
       " (:write :file \"tmp/src/lib.asl\" :content \"" lib "\"))")

fn ! setupPkg! root: String -> Result Unit String
  (match (dirCreate (k/joinPath root "tmp/src"))
    ((err e) (err e))
    ((ok _) (fileWrite (k/joinPath root "tmp/.asl.config.asn") "(:aslConfig\n  :workspace \"tmp\"\n  :version \"0.1.0\")\n")))

fn exists? root: String rel: String -> Bool
  (fileExists? (k/joinPath root rel))

fn testTestThenSource! -> Bool
  (let [(root (scratchDir! "aslFormsTxnResolveAll"))
        (made (setupPkg! root))
        (out (txnRun! root (txnForm (libText) (useText "lib"))))
        (both (and (exists? root "tmp/src/lib.asl") (exists? root "tmp/src/useTest.asl")))
        (_ (pathRemove root))]
    (do
      (assert (ok? made) "scratch workspace created")
      (assert (stringContains? out.out ":status \"ok\"") (str "a txn staging the test before the module it imports commits: " out.out))
      (assert both (str "both files are flushed: " out.out))
      true))

fn testUnresolvedStillAborts! -> Bool
  (let [(root (scratchDir! "aslFormsTxnUnresolved"))
        (made (setupPkg! root))
        (out (txnRun! root (txnForm (libText) (useText "nope"))))
        (any (or (exists? root "tmp/src/lib.asl") (exists? root "tmp/src/useTest.asl")))
        (_ (pathRemove root))]
    (do
      (assert (ok? made) "scratch workspace created")
      (assert (stringContains? out.out "ERR_TXN_ABORTED") (str "an import no staged item provides aborts the txn: " out.out))
      (assert (not any) "an aborted txn leaves neither file")
      true))

fn ! runTests -> Bool
  (do
    (assert (testTestThenSource!) "test-then-source txn commits")
    (assert (testUnresolvedStillAborts!) "an unresolved import still aborts after all items are staged")
    true)
