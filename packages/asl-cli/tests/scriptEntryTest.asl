(module asl-cli/tests/scriptEntryTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run)])

; (:m :ref SCRIPT-ENTRY :do "behaviour of sugared mains and script entry through the CLI: an err statement before the last exits 1 with its locus, the last statement's Unit check names the statement, a main parameter that is not the argument list and a second definition of a name are errors at their own line, tailrec entries are found, and inline text leaves no staged file")
fn ! sh argv: (List String) cwd: String secs: Int64 -> run/ProcOut
  (run/runGuarded argv cwd (run/childEnv (list)) (run/limits secs 24))

fn out r: run/ProcOut -> String
  (str r.stdout r.stderr)

fn ! put! dir: String name: String text: String -> String
  (let [(path (str dir "/" name)) (_ (fileWrite path text))] path)

fn inlineCode -> String
  "(println (str \"inline \" (argStr args 0 \"-\")))"

fn ! stagedLeft! root: String code: String -> Bool
  (let [(tail (str "x" (optionOr (stringSlice (bytesSha256 (stringToBytes code)) 0 16) "") ".asl"))]
    (match (dirList (str root "/.asl/cache/nativeTest/outside"))
      ((ok names) (listAny? (fn [(n String)] -> Bool (and (stringStartsWith? n "inline") (stringEndsWith? n tail))) names))
      ((err _) false)))

fn ! testMain root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (mid (put! work "mid.asl" "fn main\n  (println \"before\")\n  (fileReadString \"/nonexistent\")\n  (println \"after\")\n"))
        (headed (put! work "headed.asl" "(module headed\n  :x [main]\n  :i [(asl-parser/reader :a rd)])\n\nfn main\n  (println (rd/renderSexpr (rd/makeAtom \"hi\")))\n  (fileReadString \"/nonexistent\")\n  (println \"after\")\n"))
        (fine (put! work "fine.asl" "fn main\n  (println \"one\")\n  (let [s (fileReadString \"/etc/hosts\")] (println (str (ok? s))))\n  (println \"two\")\n"))
        (last (put! work "last.asl" "fn main\n  (println \"a\")\n  (fileReadString \"/nonexistent\")\n"))
        (midRun (sh (list asl "run" mid) root 900))
        (headedRun (sh (list asl "run" headed) root 900))
        (fineRun (sh (list asl "run" fine) root 900))
        (lastCheck (sh (list asl "check" last) root 900))]
    (do (assert (= midRun.exitCode 1) (str "an err statement before the last exits 1: " (out midRun)))
        (assert (= midRun.stdout "before\n") (str "and stops main before the statements after it: " midRun.stdout))
        (assert (stringContains? midRun.stderr "(:err :form 2 :line 3 :msg \"notFound: /nonexistent") (str "with one line naming the statement and its line: " midRun.stderr))
        (assert (= headedRun.exitCode 1) (str "a sugared main in a module with a header exits the same way: " (out headedRun)))
        (assert (and (= headedRun.stdout "hi\n") (stringContains? headedRun.stderr "(:err :form 2 :line 7 ")) (str "its imports resolve and the locus is its own: " (out headedRun)))
        (assert (and (= fineRun.exitCode 0) (= fineRun.stdout "one\ntrue\ntwo\n")) (str "statements that do not fail run in order and exit 0: " (out fineRun)))
        (assert (stringContains? (out lastCheck) "last.asl:3:3: ERR_TYPE_MISMATCH the last statement of main: expected Unit, found (Result String String)") (str "a Result last statement is a type error at its line: " (out lastCheck)))
        (refute (stringContains? (out lastCheck) "preludeMainDone") (str "the diagnostic does not name the internal hook: " (out lastCheck)))
        true))

fn ! testRejects root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (param (put! work "param.asl" "fn ! main n: Int64\n  (println \"x\")\n"))
        (named (put! work "named.asl" "fn main argv: (List String)\n  (println (argStr argv 0 \"none\"))\n"))
        (dup (put! work "dup.asl" "fn helper -> Int64\n  1\n\nfn helper -> Int64\n  2\n\nfn main\n  (println (str (helper)))\n"))
        (dupType (put! work "dupType.asl" "(schema Point (:f x Int64))\n\n(schema Point (:f y Int64))\n\nfn main\n  (println \"p\")\n"))
        (paramCheck (sh (list asl "check" param) root 900))
        (namedRun (sh (list asl "run" named "given") root 900))
        (dupCheck (sh (list asl "check" dup) root 900))
        (dupTypeCheck (sh (list asl "check" dupType) root 900))]
    (do (assert (!= paramCheck.exitCode 0) "a sugared main with a non-list parameter does not check")
        (assert (stringContains? (out paramCheck) "param.asl:1:11: parse ERR_MAIN_PARAM") (str "the error stands at the parameter: " (out paramCheck)))
        (assert (stringContains? (out paramCheck) "found n: Int64") (str "and names it: " (out paramCheck)))
        (assert (= namedRun.stdout "given\n") (str "a sugared main naming its (List String) parameter still runs: " (out namedRun)))
        (assert (!= dupCheck.exitCode 0) "a second fn with the same name does not check")
        (assert (stringContains? (out dupCheck) "dup.asl:4:1: parse ERR_DUPLICATE_DEF fn helper is already defined in this module") (str "the error stands at the second definition: " (out dupCheck)))
        (assert (stringContains? (out dupTypeCheck) "dupType.asl:3:1: parse ERR_DUPLICATE_DEF type Point") (str "a second schema with the same name too: " (out dupTypeCheck)))
        true))

fn ! testEntries root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (tailMain (put! work "tailMain.asl" "fn tailrec main\n  (println \"tail main\")\n"))
        (tailTests (put! work "tailTests.asl" "fn tailrec runTests -> Bool\n  (do (assert (= (listLength (stringSplit \"a b\" \" \")) 2) \"splits\") true)\n"))
        (mainRun (sh (list asl tailMain) root 900))
        (testsRun (sh (list asl tailTests) root 900))
        (inline (sh (list asl "-e" (inlineCode) "ia") work 900))
        (stdinCode "(println (str \"piped \" (argStr args 0 \"-\")))")
        (piped (sh (list "/bin/sh" "-c" (str "printf '%s\\n' '" stdinCode "' | exec \"$0\" - pa") asl) work 900))]
    (do (assert (= mainRun.stdout "tail main\n") (str "asl FILE runs a tailrec main: " (out mainRun)))
        (assert (and (= testsRun.exitCode 0) (stringContains? (out testsRun) "1 assertion(s) executed")) (str "asl FILE runs a tailrec runTests as tests when there is no main: " (out testsRun)))
        (assert (= inline.stdout "inline ia\n") (str "asl -e runs its text with arguments: " (out inline)))
        (assert (= piped.stdout "piped pa\n") (str "asl - runs script text from stdin with arguments: " (out piped)))
        (refute (stagedLeft! root (inlineCode)) "asl -e leaves no staged file behind")
        (refute (stagedLeft! root (str stdinCode "\n")) "asl - leaves no staged file behind")
        true))

fn ! testFixRound root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (_ (put! work "strparen.asl" "fn runTests -> Bool\n  (let [(s \"first\n(second)\")] (do (assert (stringContains? s \"second\") \"has the second line\") true))\n"))
        (_ (put! work "badtool" "#!/usr/bin/env asl\n(println undefinedTool)\n"))
        (strRun (sh (list asl "./strparen.asl") work 900))
        (inlineBad (sh (list asl "-e" "(println undefinedInline)") work 900))
        (unclosed (sh (list asl "-e" "(println 1)\n(println 2") work 900))
        (piped (sh (list "/bin/sh" "-c" "printf '%s\\n' '(println undefinedPiped)' | exec \"$0\" -" asl) work 900))
        (tool (sh (list asl "./badtool") work 900))]
    (do (assert (and (= strRun.exitCode 0) (stringContains? (out strRun) "1 assertion(s) executed")) (str "a column-0 paren inside a string does not make a runTests file a program: " (out strRun)))
        (assert (and (stringStartsWith? inlineBad.stderr "FAIL -e: ") (stringContains? inlineBad.stderr "undefinedInline")) (str "an -e failure names -e: " inlineBad.stderr))
        (assert (and (stringContains? unclosed.stderr "FAIL -e: -e:2:1: ") (stringContains? unclosed.stderr "unclosed delimiter")) (str "an unclosed -e names -e and the line: " unclosed.stderr))
        (assert (and (stringStartsWith? piped.stderr "FAIL -: ") (stringContains? piped.stderr "undefinedPiped")) (str "a - failure names -: " piped.stderr))
        (assert (and (stringStartsWith? tool.stderr "FAIL badtool: ") (stringContains? tool.stderr "undefinedTool")) (str "a shebang file failure names the file: " tool.stderr))
        (refute (stringContains? (str inlineBad.stderr unclosed.stderr piped.stderr tool.stderr) "outside/inline") "no failure names the staged file")
        true))

fn ! testChecked root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (away (str "/tmp/aslScriptCheck." (stringFromInt64 (procSelf))))
        (_ (dirCreate away))
        (bad "(println \"before\")\n(println (str (ok? 3)))\n")
        (_ (put! away "topused.asl" bad))
        (_ (put! work "topused.asl" bad))
        (_ (put! away "fine.asl" "(println \"one\")\n(println (str (+ 1 2)))\n"))
        (_ (put! away "badTest.asl" "fn runTests -> Bool\n  (ok? 3)\n"))
        (outside (sh (list asl "./topused.asl") away 900))
        (inside (sh (list asl "./topused.asl") work 900))
        (inline (sh (list asl "-e" bad) away 900))
        (piped (sh (list "/bin/sh" "-c" "printf '(println 1)\\n(ok? 3)\\n' | exec \"$0\" -" asl) away 900))
        (fine (sh (list asl "./fine.asl") away 900))
        (vdir (str work "/verdicts"))
        (_ (dirCreate vdir))
        (cacheEnv (run/childEnv (list (str "ASL_CHECK_CACHE=" vdir))))
        (again1 (run/runGuarded (list asl "-e" bad) away cacheEnv (run/limits 900 24)))
        (again2 (run/runGuarded (list asl "-e" bad) away cacheEnv (run/limits 900 24)))
        (verdicts (match (dirList vdir) ((ok names) (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) names))) ((err _) -1)))
        (tested (sh (list asl "test" (str away "/badTest.asl")) away 900))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str away "/" n)))) (list "topused.asl" "fine.asl" "badTest.asl")))
        (_ (pathRemove away))]
    (do (assert (= outside.exitCode 1) (str "a script outside the workspace that check rejects exits 1: " (out outside)))
        (assert (= outside.stdout "") (str "before any output: " outside.stdout))
        (assert (stringContains? outside.stderr "FAIL ./topused.asl: ./topused.asl:2:1: ERR_TYPE_MISMATCH argument to ok?") (str "with the check diagnostic under the name the user gave: " outside.stderr))
        (assert (and (= inside.exitCode 1) (= inside.stdout "")) (str "a rejected script inside the workspace does not run either: " (out inside)))
        (assert (and (= inline.exitCode 1) (= inline.stdout "")) (str "asl -e with a type error exits 1 before output: " (out inline)))
        (assert (stringContains? inline.stderr "FAIL -e: -e:2:1: ERR_TYPE_MISMATCH argument to ok?") (str "naming -e and the line: " inline.stderr))
        (assert (and (= piped.exitCode 1) (stringContains? piped.stderr "-:2:1: ERR_TYPE_MISMATCH")) (str "asl - with a type error is rejected the same way: " (out piped)))
        (assert (= piped.stdout "") (str "and prints nothing first: " piped.stdout))
        (assert (and (= again2.exitCode 1) (= again2.stderr again1.stderr)) (str "a rerun of the same -e text replays the same rejection: " again2.stderr))
        (assert (= verdicts 1) (str "and both runs share one cached verdict, not one per staged name: " verdicts))
        (assert (and (= fine.exitCode 0) (= fine.stdout "one\n3\n")) (str "a valid script outside the workspace still runs: " (out fine)))
        (assert (and (!= tested.exitCode 0) (stringContains? (out tested) "ERR_TYPE_MISMATCH")) (str "asl test rejects an outside suite that check rejects: " (out tested)))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/scriptEntryTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (mains (if (ok? made) (testMain root work) false))
        (rejects (if (ok? made) (testRejects root work) false))
        (entries (if (ok? made) (testEntries root work) false))
        (checked (if (ok? made) (testChecked root work) false))
        (fixes (if (ok? made) (testFixRound root work) false))
        (cleaned (run/runGuarded (list "/bin/rm" "-rf" work) root (run/childEnv (list)) (run/limits 60 4)))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert mains "sugared mains exit on an err statement and name their last statement")
        (assert rejects "bad main parameters and duplicate definitions are rejected at their line")
        (assert entries "tailrec entries and inline text run")
        (assert checked "run, -e and - type-check before building, as asl check does")
        (assert fixes "a string paren keeps a test a test, and inline failures name what the user typed")
        (assert (= cleaned.exitCode 0) "the work directory was removed")
        true))
