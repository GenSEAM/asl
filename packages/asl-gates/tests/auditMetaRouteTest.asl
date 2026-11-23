(module asl-gates/tests/auditMetaRouteTest
  :x [runTests]
  :i [(asl-gates/auditGates :a ag) (asl-tools/fleet/run :a fr)])

fn sh! cmd: String -> fr/Done
  (fr/runShell! cmd "." (fr/childEnv (list)) (fr/defaultLimits))

fn copyFile! src: String dst: String -> Bool
  (match (fileReadString src)
    ((err _) false)
    ((ok t) (ok? (fileWrite dst t))))

fn ! runTests -> Bool
  (let [(made (sh! "mktemp -d"))
        (dir (stringTrim made.out))
        (fixture (str dir "/fixture.py"))
        (metaDst (str dir "/asl/grammar/meta.asn"))
        (baseDst (str dir "/scripts/audit/metaBaseline.asn"))
        (body (str "# (:m :effect pure)\n"
                   "def good():\n"
                   "    pass\n"
                   "# (:m :effect disk)\n"
                   "def bad():\n"
                   "    pass\n"))
        (base (str "(:metaBaseline (:file :path \"" fixture "\" :plain 4))\n"))
        (madeDirs (sh! (str "mkdir -p '" dir "/asl/grammar' '" dir "/scripts/audit' '" dir "/tests' '" dir "/.asl/mem/decisions'")))]
    (do
      (assert (= made.exit 0) "a private fixture directory is made")
      (assert (= madeDirs.exit 0) "the fixture tree is made")
      (assert (copyFile! "asl/grammar/meta.asn" metaDst) "meta.asn copied")
      (assert (ok? (fileWrite fixture body)) "fixture written")
      (assert (ok? (fileWrite baseDst base)) "baseline written")
      (let [(check (ag/coreCheck! dir "core" (list "audit" "meta" fixture)))]
        (do
          (assert (= check.id "meta") "the meta subcommand reports the meta check")
          (assert (!= check.err "ERR_CORE_FAILED") "bin/asl-core is not spawned for meta")
          (assert (match check.n ((some n) (= n 1)) ((none) false)) "one invalid (:m) comment is counted")
          (assert (= (sh! (str "rm -rf '" dir "'")).exit 0) "the fixture directory is removed")
          true))))
