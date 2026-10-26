(module asl-cli/tests/mainSugarTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)
      (asl-parser/reader :a rd)
      (asl-tools/fleet/run :a run)])

; (:m :ref MAIN-SUGAR :do "fn main with no -> is a Unit main that binds args and is effectful, run and built like the full form; a Result it ends on is a type error at its line, and argInt and argStr read arguments by position with a fallback")
fn mainOf src: String -> (Option ast/DefunNode)
  (match (ast/parse src)
    ((err _) (none))
    ((ok forms) (listHead (fold (fn [acc t] (match t ((ast/topDefun d) (if (= d.name "main") (cons d acc) acc)) (_ acc))) (list) forms))))

fn paramText d: ast/DefunNode -> String
  (stringJoin (map (fn [p] (str p.name ":" p.type)) d.params) " ")

fn retOf o: (Option ast/DefunNode) -> String
  (match o ((some d) d.retType) ((none) ""))

fn paramsOf o: (Option ast/DefunNode) -> String
  (match o ((some d) (paramText d)) ((none) ""))

fn lastOf o: (Option ast/DefunNode) -> String
  (match o ((some d) (match (listGet d.body (- (listLength d.body) 1)) ((some e) (rd/sexprHead e)) ((none) ""))) ((none) ""))

fn effectOf o: (Option ast/DefunNode) -> Bool
  (match o ((some d) d.effect) ((none) false))

fn ! testParse -> Bool
  (let [(bare (mainOf "fn main\n  (println \"x\")\n"))
        (banged (mainOf "fn ! main\n  (println \"x\")\n"))
        (named (mainOf "fn main argv: (List String)\n  (println \"x\")\n"))
        (full (mainOf "fn ! main args: (List String) -> (Result Unit String)\n  (ok ())\n"))
        (helper (ast/parse "fn helper x: Int64\n  (println \"x\")\n"))]
    (do (assert (= (retOf bare) "(Result Unit String)") "a main with no -> returns (Result Unit String)")
        (assert (= (lastOf bare) "preludeMainDone") "its last statement is checked as Unit by preludeMainDone")
        (assert (= (paramsOf bare) "args:(List String)") "a main with no parameters binds args")
        (assert (= (effectOf bare) true) "a sugared main is effectful without !")
        (assert (= (retOf banged) "(Result Unit String)") "fn ! main with no -> is sugared too")
        (assert (= (lastOf full) "ok") "the full form keeps its body")
        (assert (= (paramsOf named) "argv:(List String)") "a sugared main keeps the parameters it names")
        (assert (= (retOf full) "(Result Unit String)") "the full form keeps its return type")
        (assert (= (paramsOf full) "args:(List String)") "the full form keeps its parameters")
        (assert (match helper ((ok fs) (listAny? (fn [t] (match t ((ast/topDefun d) (and (= d.name "helper") (= d.retType ":inferredUnit"))) (_ false))) fs)) ((err _) false)) "only main is sugared; another fn with no -> is unchanged")
        true))

fn ! runIn argv: (List String) cwd: String secs: Int64 -> run/Done
  (run/runOneLimited (run/job (cons "/bin/sh" (cons "-c" (cons "exec \"$0\" \"$@\" 2>&1" argv))) cwd (run/childEnv (list))) (run/limits secs 24))

fn sugarSource -> String
  "fn main\n  (println (str \"n=\" (stringFromInt64 (argInt args 0 7)) \" s=\" (argStr args 1 \"d\")))\n"

fn droppedSource -> String
  "fn main\n  (println \"before\")\n  (fileWrite \"/nonexistent-dir/x\" \"y\")\n"

fn ! testCli root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (sugar (str work "/sugar.asl"))
        (dropped (str work "/dropped.asl"))
        (exe (str work "/sugar"))
        (_ (fileWrite sugar (sugarSource)))
        (_ (fileWrite dropped (droppedSource)))
        (plain (runIn (list asl "run" sugar) root 900))
        (given (runIn (list asl "run" sugar "5") root 900))
        (built (runIn (list asl "build" sugar "-o" exe) root 900))
        (exeRan (if (= built.exit 0) (runIn (list exe "9" "x") work 60) built))
        (checked (runIn (list asl "check" sugar) root 900))
        (droppedChecked (runIn (list asl "check" dropped) root 900))]
    (do (assert (= plain.exit 0) (str "asl run takes a sugared main: " plain.out))
        (assert (stringContains? plain.out "n=7 s=d") (str "with no arguments both fallbacks apply: " plain.out))
        (assert (stringContains? given.out "n=5 s=d") (str "argInt reads the first argument: " given.out))
        (assert (= built.exit 0) (str "asl build takes a sugared main: " built.out))
        (assert (= exeRan.out "n=9 s=x\n") (str "the built binary reads both arguments: " exeRan.out))
        (assert (= exeRan.exit 0) "the built Unit main exits 0")
        (assert (= checked.exit 0) (str "asl check passes a sugared main: " checked.out))
        (assert (not (= droppedChecked.exit 0)) (str "a Unit main ending on a Result is rejected, not dropped: " droppedChecked.out))
        (assert (stringContains? droppedChecked.out "dropped.asl:3:") (str "the diagnostic names the line of the Result: " droppedChecked.out))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/mainSugarTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (parsed (testParse))
        (cli (if (ok? made) (testCli root work) false))
        (cleaned (pathRemove work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert parsed "main sugar parses")
        (assert cli "the CLI runs, builds and checks a sugared main")
        (assert (ok? cleaned) "the work directory was removed")
        true))
