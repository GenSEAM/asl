(module asl-cli/tests/topLevelTest
  :x [runTests]
  :i [(asl-parser/ast :a ast)
      (asl-parser/astPrinter :a pr)
      (asl-tools/fleet/run :a run)])

; (:m :ref TOP-LEVEL-CODE :do "a headerless file's column-0 code forms are its entry, run in order like a shell or python script: a statement that checks as (err e) stops the script with one (:err :form N :line L :msg e) line on stderr and exit 1, a top-level let binds the ok value for the forms after it, (use path) imports a module by its path; the file runs through asl run, as a bare asl FILE, as ./FILE through its #! line, and inline through asl -e and asl -; a program holds at most one such module and none may be imported")
fn headerOf forms: (List ast/TopForm) -> (Option ast/ModuleNode)
  (listHead (fold (fn [acc t] (match t ((ast/topModule m) (cons m acc)) (_ acc))) (list) forms))

fn mainOf forms: (List ast/TopForm) -> (Option ast/DefunNode)
  (listHead (fold (fn [acc t] (match t ((ast/topDefun d) (if (= d.name "main") (cons d acc) acc)) (_ acc))) (list) forms))

fn parsedHeader src: String -> (Option ast/ModuleNode)
  (match (ast/parse src) ((err _) (none)) ((ok forms) (headerOf forms)))

fn parsedMain src: String -> (Option ast/DefunNode)
  (match (ast/parse src) ((err _) (none)) ((ok forms) (mainOf forms)))

fn parseError src: String -> String
  (match (ast/parse src) ((err e) e.msg) ((ok _) ""))

fn printed src: String -> String
  (match (ast/parse src) ((err e) e.msg) ((ok forms) (stringJoin (map pr/printTopForm forms) "\n\n")))

fn ! testParse -> Bool
  (let [(code "fn twice x: Int64 -> Int64\n  (* 2 x)\n\n(println (str (twice 2)))\n(let [n (twice 3)])\n(println (str n))\n")
        (header (parsedHeader code))
        (main (parsedMain code))]
    (do (assert (= (optionMap (fn [(m ast/ModuleNode)] -> (List String) m.exported) header) (some (list "main"))) "a headerless file with top-level code exports main")
        (assert (= (optionMap (fn [(d ast/DefunNode)] -> String d.retType) main) (some "(Result Int64 String)")) "its main returns an exit code or an error")
        (assert (= (optionMap (fn [(d ast/DefunNode)] -> Bool d.effect) main) (some true)) "its main is effectful")
        (assert (= (optionMap (fn [(d ast/DefunNode)] -> String d.docstring) main) (some (ast/scriptMainDoc))) "its main is marked as top-level code")
        (assert (= (optionMap (fn [(d ast/DefunNode)] -> (List String) (map (fn [(p ast/Param)] -> String p.name) d.params)) main) (some (list "args"))) "its main binds args")
        (assert (= (optionMap (fn [(m ast/ModuleNode)] -> (List String) m.exported) (parsedHeader "#!/usr/bin/env asl\n(println \"x\")\n")) (some (list "main"))) "a #! first line is skipped")
        (assert (= (optionMap (fn [(m ast/ModuleNode)] -> (List (Pair String String)) m.imports) (parsedHeader "(use asl-parser/reader)\n(println \"x\")\n")) (some (list (pair "asl-parser/reader" "reader")))) "(use path) imports the module aliased by its last segment")
        (assert (stringContains? (parseError "(println \"x\")\nfn main\n  (println \"y\")\n") "ERR_SCRIPT_MAIN") "top-level code and fn main in one file is an error")
        (assert (= (parsedHeader "(:package \"p\" :version \"1\")\n") (none)) "a keyword-headed data form is not code")
        (assert (and (stringContains? (printed code) "(let [n (twice 3)])\n(println (str n))") (not (stringContains? (printed code) "preludeScriptStep"))) (str "a script prints back as its top-level code: " (printed code)))
        (assert (= (optionMap (fn [(m ast/ModuleNode)] -> (List String) m.exported) (parsedHeader (printed code))) (some (list "main"))) "and the printed script reparses to a script")
        true))

fn ! sh argv: (List String) cwd: String env: (List String) secs: Int64 -> run/ProcOut
  (run/runGuarded argv cwd (run/childEnv env) (run/limits secs 24))

fn badSource -> String
  "#!/usr/bin/env asl\n(println \"a\")\n(println (+ 1 \"x\"))\n(println (noSuchFunction 3))\n"

fn unwrapSource -> String
  "(let [s (fileReadString \"/etc/hosts\")])\n(println (str (+ (stringLength s) 1)))\n"

fn ! testCli root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (fx (str root "/asl/packages/asl-cli/tests/fixtures/scripts"))
        (bad (str work "/bad.asl"))
        (unwrap (str work "/unwrap.asl"))
        (bin (str work "/bin"))
        (_ (fileWrite bad (badSource)))
        (_ (fileWrite unwrap (unwrapSource)))
        (data (str work "/data.txt"))
        (_ (fileWrite data "hello\n"))
        (_ (dirCreate bin))
        (_ (pathSymlink asl (str bin "/asl")))
        (path (str "PATH=" bin ":" (optionOr (envGet "PATH") "/usr/bin:/bin")))
        (ran (sh (list asl "run" (str fx "/greet.asl") "bob" data) root (list) 900))
        (bare (sh (list asl (str fx "/greet.asl") "ann") root (list) 900))
        (shebang (sh (list "./greet.asl" "cy" data) fx (list path) 900))
        (inline (sh (list asl "-e" "(println (str \"e \" (argStr args 0 \"-\")))" "xa") work (list) 900))
        (stdin (sh (list "/bin/sh" "-c" "printf '%s\\n' '(println (str \"in \" (argStr args 0 \"-\")))' | exec \"$0\" - ya" asl) work (list) 900))
        (used (sh (list asl "run" (str fx "/useLib.asl")) root (list) 900))
        (two (sh (list asl "run" (str fx "/twoEntry.asl")) root (list) 900))
        (lib (sh (list asl "run" (str fx "/importsScript.asl")) root (list) 900))
        (badChecked (sh (list asl "check" bad) root (list) 900))
        (unwrapChecked (sh (list asl "check" unwrap) root (list) 900))]
    (do (assert (= ran.exitCode 0) (str "asl run takes a script with top-level code: " ran.stdout ran.stderr))
        (assert (= ran.stdout "BOB!\nread 6\nafter\n") (str "its forms run in order, fns visible, the ok value bound: " ran.stdout))
        (assert (= bare.exitCode 1) (str "an (err ...) statement exits 1: " bare.stdout bare.stderr))
        (assert (= bare.stdout "ANN!\n") (str "and stops the script before the forms after it: " bare.stdout))
        (assert (stringContains? bare.stderr "(:err :form 2 :line 6 :msg \"notFound: /nonexistent") (str "with one ASN line naming the form and its line: " bare.stderr))
        (assert (= shebang.exitCode 0) (str "./FILE runs through its #! line: " shebang.stdout shebang.stderr))
        (assert (= shebang.stdout "CY!\nread 6\nafter\n") (str "with its arguments: " shebang.stdout))
        (assert (= inline.stdout "e xa\n") (str "asl -e runs inline code with arguments: " inline.stdout inline.stderr))
        (assert (= stdin.stdout "in ya\n") (str "asl - runs code from stdin with arguments: " stdin.stdout stdin.stderr))
        (assert (= used.stdout "twice 8\n") (str "(use path) imports a module into a script: " used.stdout used.stderr))
        (assert (!= two.exitCode 0) "two modules with top-level code do not run")
        (assert (and (stringContains? (str two.stdout two.stderr) "ERR_MULTIPLE_ENTRY") (and (stringContains? (str two.stdout two.stderr) "helper.asl") (stringContains? (str two.stdout two.stderr) "twoEntry.asl"))) (str "ERR_MULTIPLE_ENTRY names both files: " two.stdout two.stderr))
        (assert (!= lib.exitCode 0) "a module importing a script does not run")
        (assert (stringContains? (str lib.stdout lib.stderr) "ERR_TOPLEVEL_IN_LIBRARY") (str "importing a script is ERR_TOPLEVEL_IN_LIBRARY: " lib.stdout lib.stderr))
        (assert (and (stringContains? (str badChecked.stdout badChecked.stderr) "bad.asl:3:1:") (stringContains? (str badChecked.stdout badChecked.stderr) "bad.asl:4:1:")) (str "each diagnostic stands at its own statement, past the #! line: " badChecked.stdout))
        (assert (= unwrapChecked.exitCode 0) (str "a Result statement bound by let checks as its ok type: " unwrapChecked.stdout))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/topLevelTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (parsed (testParse))
        (cli (if (ok? made) (testCli root work) false))
        (cleaned (run/runGuarded (list "/bin/rm" "-rf" work) root (run/childEnv (list)) (run/limits 60 4)))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert parsed "top-level code parses to a script main")
        (assert cli "scripts run through asl run, bare asl FILE, ./FILE, asl -e and asl -")
        (assert (= cleaned.exitCode 0) "the work directory was removed")
        true))
