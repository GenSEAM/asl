(module asl-tools/coord/tests/gateWidenTest
  :x [runTests]
  :i [(asl-tools/coord/gateWiden :a gw)])

; (:m :ref CONDUCTOR-GATE-WIDEN :do "pure coverage of the gate-widen planner over an in-memory fixture of six (path, text) pairs: one owned module, an alias importer, a bare importer, the suite, a test file of another module, and an unrelated file; no file IO in the pure fns")

fn fixture -> (List (Pair String String))
  (list
    (pair "asl/tools/coord/gateWiden.asl"
          "(module asl-tools/coord/gateWiden\n  :x [moduleNameOf importsOf]\n  :i [])")
    (pair "asl/tools/coord/gateGuard.asl"
          "(module asl-tools/coord/gateGuard\n  :x [moduleName]\n  :i [(asl-tools/coord/gateWiden :a gw)])")
    (pair "asl/tools/coord/tests/gateWidenTest.asl"
          "(module asl-tools/coord/tests/gateWidenTest\n  :x [runTests]\n  :i [asl-tools/coord/gateWiden])")
    (pair "asl/tools/coord/tests/gateGuardTest.asl"
          "(module asl-tools/coord/tests/gateGuardTest\n  :x [runTests]\n  :i [(asl-tools/coord/gateGuard :a gg)])")
    (pair "asl/tools/coord/brief.asl"
          "(module asl-tools/coord/brief\n  :x [main]\n  :i [(asl/fleet/run :a fr)])")
    (pair "other/pkg/thing.asl"
          "(module other/pkg/thing\n  :x [main]\n  :i [asl-tools/coord/gateWiden])"))

fn owned -> (List String)
  (list "asl/tools/coord/gateWiden.asl")

fn ! testModuleNameOf -> Bool
  (do (assert (= (gw/moduleNameOf "(module asl-tools/coord/gateWiden\n  :i [])") "asl-tools/coord/gateWiden") "module name read from the header")
      (assert (= (gw/moduleNameOf "no header") "") "no header, no name")
      true)

fn ! testImportsOf -> Bool
  (do (assert (= (gw/importsOf "(module a/b\n  :i [(x/y :a z) (p/q)])") (list "x/y" "p/q")) "alias and plain forms both read")
      (assert (= (gw/importsOf "(module a/b\n  :i [m/n])") (list "m/n")) "a bare name in :i counts")
      (assert (= (gw/importsOf "(module a/b\n  :i [])") (list)) "an empty :i yields none")
      (assert (= (gw/importsOf "(module a/b\n  :x [main])") (list)) "no :i vector yields none")
      true)

fn ! testImportersOf -> Bool
  (let [(got (gw/importersOf (owned) (fixture)))]
    (do (assert (= got (list "asl/tools/coord/gateGuard.asl" "asl/tools/coord/tests/gateWidenTest.asl" "other/pkg/thing.asl")) "exactly the three importers, in input order")
        (assert (not (listContains? got "asl/tools/coord/gateWiden.asl")) "the owned file itself is left out")
        (assert (not (listContains? got "asl/tools/coord/brief.asl")) "an unrelated file is not an importer")
        true))

fn ! testSuitesOf -> Bool
  (do (assert (= (gw/suitesOf (owned) (fixture)) (list "asl/tools/coord/tests/gateWidenTest.asl")) "exactly the one suite under the owned package's tests/")
      (assert (not (listContains? (gw/suitesOf (owned) (fixture)) "asl/tools/coord/tests/gateGuardTest.asl")) "a test file importing another module is no suite")
      (assert (not (listContains? (gw/suitesOf (owned) (fixture)) "other/pkg/thing.asl")) "an importer outside the package is no suite")
      true)

fn ! testWidenedGate -> Bool
  (do (assert (= (gw/widenedGate (list "./bin/asl test asl/tools/coord/tests/gateWidenTest.asl") (owned) (fixture))
                 (list "./bin/asl check asl/tools/coord/gateGuard.asl"
                       "./bin/asl check asl/tools/coord/tests/gateWidenTest.asl"
                       "./bin/asl check other/pkg/thing.asl"
                       "./bin/asl test asl/tools/coord/tests/gateWidenTest.asl"))
              "declared, suites and importers deduplicated and sorted")
      (assert (= (gw/widenedGate (list "./bin/asl check asl/tools/coord/gateWiden.asl") (owned) (fixture))
                 (list "./bin/asl check asl/tools/coord/gateGuard.asl"
                       "./bin/asl check asl/tools/coord/gateWiden.asl"
                       "./bin/asl check asl/tools/coord/tests/gateWidenTest.asl"
                       "./bin/asl check other/pkg/thing.asl"
                       "./bin/asl test asl/tools/coord/tests/gateWidenTest.asl"))
              "a fresh declared command joins the sorted list")
      true)

fn ! runTests -> Bool
  (do (assert (testModuleNameOf) "moduleNameOf")
      (assert (testImportsOf) "importsOf")
      (assert (testImportersOf) "importersOf")
      (assert (testSuitesOf) "suitesOf")
      (assert (testWidenedGate) "widenedGate")
      true)
