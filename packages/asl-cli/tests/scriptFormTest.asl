(module asl-cli/tests/scriptFormTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)
      (asl-tools/fleet/run :a run)])

; (:m :ref IMPLICIT-MODULE :do "a headerless .asl file that defines main or runTests is a script module: the parser gives it a header exporting those entries, and asl run, build, test and check take it like a headed module; a headerless file without an entry stays a fragment and still has no entry")
fn headerOf forms: (List ast/TopForm) -> (Option ast/ModuleNode)
  (listHead (fold (fn [acc t] (match t ((ast/topModule m) (cons m acc)) (_ acc))) (list) forms))

fn exportedOf src: String -> (Option (List String))
  (match (ast/parse src)
    ((err _) (none))
    ((ok forms) (match (headerOf forms) ((some m) (some m.exported)) ((none) (none)))))

fn ! testParse -> Bool
  (do (assert (= (exportedOf "fn ! main args: (List String) -> (Result Unit String)\n  (ok ())\n") (some (list "main"))) "a headerless file with main gets a header exporting main")
      (assert (= (exportedOf "fn ! runTests -> Bool\n  true\n") (some (list "runTests"))) "a headerless file with runTests gets a header exporting runTests")
      (assert (= (exportedOf "fn helper x: Int64 -> Int64\n  (+ x 1)\n") (none)) "a headerless file without an entry gets no header")
      (assert (= (exportedOf "(module m :x [helper] :i [])\n\nfn helper -> Int64\n  1\n\nfn ! main -> (Result Unit String)\n  (ok ())\n") (some (list "helper"))) "an explicit header keeps its own exports")
      true)

fn ! runIn argv: (List String) cwd: String secs: Int64 -> run/Done
  (run/runOneLimited (run/job (cons "/bin/sh" (cons "-c" (cons "exec \"$0\" \"$@\" 2>&1" argv))) cwd (run/childEnv (list))) (run/limits secs 24))

fn helloSource -> String
  "fn twice x: Int64 -> Int64\n  (* x 2)\n\nfn ! main args: (List String) -> (Result Unit String)\n  (do (println (str \"hi \" (stringFromInt64 (twice 21))))\n      (ok ()))\n"

fn suiteSource -> String
  "fn ! runTests -> Bool\n  (do (assert (= (stringLength (stringFromInt64 (procSelf))) (stringLength (stringFromInt64 (procSelf)))) \"a pid prints the same twice\")\n      true)\n"

fn fragmentSource -> String
  "fn helper x: Int64 -> Int64\n  (+ x 1)\n"

fn badSource -> String
  "fn ! main args: (List String) -> (Result Unit String)\n  (do (println (undefinedThing 1))\n      (ok ()))\n"

fn ! testCli root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (hello (str work "/hello.asl"))
        (suite (str work "/suiteTest.asl"))
        (frag (str work "/fragment.asl"))
        (bad (str work "/bad.asl"))
        (exe (str work "/hello"))
        (_ (fileWrite hello (helloSource)))
        (_ (fileWrite suite (suiteSource)))
        (_ (fileWrite frag (fragmentSource)))
        (_ (fileWrite bad (badSource)))
        (ran (runIn (list asl "run" hello) root 900))
        (built (runIn (list asl "build" hello "-o" exe) root 900))
        (exeRan (if (= built.exit 0) (runIn (list exe) work 60) built))
        (tested (runIn (list asl "test" suite) root 900))
        (checked (runIn (list asl "check" hello) root 900))
        (fragRan (runIn (list asl "run" frag) root 900))
        (badChecked (runIn (list asl "check" bad) root 900))]
    (do (assert (= ran.exit 0) (str "asl run takes a headerless script: " ran.out))
        (assert (stringContains? ran.out "hi 42") (str "the script prints through its own helper: " ran.out))
        (assert (= built.exit 0) (str "asl build takes a headerless script: " built.out))
        (assert (= exeRan.out "hi 42\n") (str "the built script prints the same line: " exeRan.out))
        (assert (= tested.exit 0) (str "asl test takes a headerless suite with runTests: " tested.out))
        (assert (= checked.exit 0) (str "asl check passes a headerless script: " checked.out))
        (assert (not (= fragRan.exit 0)) "a headerless file with no entry does not run")
        (assert (stringContains? (str fragRan.out) "ERR_NO_ENTRY") (str "and says it has no entry: " fragRan.out))
        (assert (not (= badChecked.exit 0)) "asl check rejects an unbound symbol in a script")
        (assert (stringContains? (str badChecked.out) "bad.asl:2:") (str "the script diagnostic keeps its source line: " badChecked.out))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/scriptFormTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (parsed (testParse))
        (cli (if (ok? made) (testCli root work) false))
        (cleaned (pathRemove work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert parsed "headerless sources parse to script modules")
        (assert cli "the CLI runs, builds, tests and checks scripts")
        (assert (ok? cleaned) "the work directory was removed")
        true))
