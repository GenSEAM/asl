(module asl-compiler/tests/asl1Test
  :x [runTests]
  :i [(asl-checker/resolve :a r)])

fn host -> String
  "asl/host/out/asl-host"

fn asl1 -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn fibPath -> String
  "tests/conformance/bootstrap/fibProgram.asl"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! driver args: String -> ProcessOutput
  (sh (str (host) " run " (asl1) " " args))

fn ! testBuildFib work: String -> Bool
  (let [(built (driver (str "build " (fibPath) " -o " work "/fib.ll")))]
    (do (assert (= built.exitCode 0) (str "asl1 build fibProgram exits 0, got " built.exitCode "; stderr: " built.stderr))
        (assert (= built.stderr "") (str "asl1 build fibProgram prints no diagnostics: " built.stderr))
        (let [(linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " work "/fib.ll -x none asl/host/out/libaslrt.a -lm -o " work "/fib")))]
          (assert (= linked.exitCode 0) (str "clang links the .ll asl1 wrote: " linked.stderr)))
        (let [(ran (sh (str work "/fib")))]
          (assert (= ran.exitCode 42) (str "native fibProgram exits 42, got " ran.exitCode)))
        true))

fn argsSource -> String
  "(module argsProgram :x [main] :i [])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (if (listEmpty? args) (err \"no arguments\") (ok (+ 40 (listLength args))))\n"

fn ! testArgsMain work: String -> Bool
  (let [(src (str work "/argsProgram.asl"))
        (written (fileWrite src (argsSource)))
        (built (driver (str "build " src " -o " work "/args.ll")))
        (linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " work "/args.ll -x none asl/host/out/libaslrt.a -lm -o " work "/args")))
        (hostRun (sh (str (host) " run " src " a b")))
        (nativeRun (sh (str work "/args a b")))
        (nativeErr (sh (str work "/args")))]
    (do (assert (ok? written) "argsProgram fixture written")
        (assert (= built.exitCode 0) (str "asl1 builds a main taking the argument list: " built.stderr))
        (assert (= linked.exitCode 0) (str "clang links argsProgram: " linked.stderr))
        (assert (= hostRun.exitCode 42) (str "asl-host run argsProgram a b exits 42, got " hostRun.exitCode))
        (assert (= nativeRun.exitCode 42) (str "native argsProgram a b exits 42 like asl-host run, got " nativeRun.exitCode))
        (assert (= nativeErr.exitCode 1) (str "native argsProgram with no arguments exits 1, got " nativeErr.exitCode))
        (assert (= nativeErr.stderr "ERR_MAIN_FAILED: main returned (err \"no arguments\"), not (ok ...)\n") (str "native (err ...) from main is reported: " nativeErr.stderr))
        true))

fn ! testCheck work: String -> Bool
  (let [(bad (str work "/bad.asl"))
        (written (fileWrite bad "(module bad :x [f] :i [])\n\nfn f -> Int64\n  (undefinedThing 1)\n"))
        (noDoc (str work "/noDoc.asl"))
        (noDocWritten (fileWrite noDoc "(module noDoc :x [main])\n\nfn ! main -> (Result Unit IoError)\n  (ok ())\n"))
        (good (driver (str "check " (fibPath))))
        (checked (driver (str "check " bad)))
        (built (driver (str "build " bad " -o " work "/bad.ll")))
        (noDocChecked (driver (str "check " noDoc)))]
    (do (assert (ok? written) "bad.asl fixture written")
        (assert (ok? noDocWritten) "noDoc.asl fixture written")
        (assert (= good.exitCode 0) (str "asl1 check fibProgram exits 0; stderr: " good.stderr))
        (assert (= checked.exitCode 1) (str "asl1 check on an unbound symbol exits 1, got " checked.exitCode))
        (assert (stringContains? checked.stderr (str bad ":4:4: [ERR_UNKNOWN_SYMBOL] unbound symbol: undefinedThing\n")) (str "asl1 check prints the checker diagnostic: " checked.stderr))
        (assert (= built.exitCode 1) (str "asl1 build on an unbound symbol exits 1, got " built.exitCode))
        (assert (stringContains? built.stderr "[rule-2] undefinedThing is not defined") (str "asl1 build prints the checker diagnostic: " built.stderr))
        (assert (err? (fileRead (str work "/bad.ll"))) "asl1 build writes no .ll when there are diagnostics")
        (assert (= noDocChecked.exitCode 0) (str "XPLATDOC: asl1 check exits 0 on an exported main with no :doc (rule-8 is a warning), got " (stringFromInt64 noDocChecked.exitCode) "; stderr: " noDocChecked.stderr))
        true))

fn ! testCheckLikeHost work: String -> Bool
  (let [(lint (str work "/lint.asl"))
        (written (fileWrite lint "(module lint :x [f runTests] :i [])\n\nfn f x: Any -> Int64\n  1\n"))
        (hostChecked (sh (str (host) " check " lint)))
        (checked (driver (str "check " lint)))]
    (do (assert (ok? written) "lint.asl fixture written")
        (assert (= hostChecked.exitCode 0) (str "asl-host check accepts an exported-but-undefined name and an Any parameter: " hostChecked.stdout hostChecked.stderr))
        (assert (= checked.exitCode hostChecked.exitCode) (str "HL-CHECK-UNIFY: asl1 check runs checkFile!, so it drops the lint rows (exported-but-undefined rule-2, rule-10 Any) the host never reports; exit " (stringFromInt64 checked.exitCode) ": " checked.stderr))
        (assert (= checked.stderr "") (str "asl1 check prints no diagnostic on the lint fixture: " checked.stderr))
        true))

fn ! testDeps -> Bool
  (let [(entry "asl/packages/asl-gates/tests/polarityTest.asl")
        (out (driver (str "deps " entry)))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines out.stdout)))
        (missing (driver "deps asl/packages/asl-compiler/tests/noSuchEntry.asl"))]
    (do (assert (= out.exitCode 0) (str "asl1 deps exits 0: " out.stderr))
        (assert (listContains? (map (fn [(l String)] -> Bool (stringEndsWith? l "asl/packages/asl-gates/src/polarity.asl")) lines) true) (str "the closure holds the imported polarity module: " out.stdout))
        (assert (listContains? (map (fn [(l String)] -> Bool (stringEndsWith? l "asl/packages/asl-parser/src/lexer.asl")) lines) true) "and the lexer polarity imports in turn")
        (refute (listContains? (map (fn [(l String)] -> Bool (stringEndsWith? l "/polarityTest.asl")) lines) true) "the entry itself is not listed")
        (assert (= lines (listSort lines)) "the paths are sorted")
        (assert (listEmpty? (filter (fn [(l String)] -> Bool (stringStartsWith? l "/")) lines)) "every path is root-relative, not absolute")
        (assert (= missing.exitCode 1) (str "asl1 deps on a missing entry exits 1, got " missing.exitCode))
        (assert (stringContains? missing.stderr "[ERR_IO] cannot read the entry") (str "and names the error: " missing.stderr))
        true))

fn ! testDepsFullClosure -> Bool
  (let [(entry (asl1))
        (out (driver (str "deps " entry)))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines out.stdout)))
        (cl (r/loadModuleClosure! entry true))
        (closureCount (listLength (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys cl.deps))))]
    (do (assert (= out.exitCode 0) (str "asl1 deps on asl1.asl itself exits 0: " out.stderr))
        (assert (listContains? (map (fn [(l String)] -> Bool (stringContains? l "asl-checker/")) lines) true) (str "asl1.asl's own closure holds an asl-checker module: " out.stdout))
        (assert (listContains? (map (fn [(l String)] -> Bool (stringContains? l "asl-parser/")) lines) true) "and an asl-parser module")
        (assert (listEmpty? (filter (fn [(l String)] -> Bool (stringStartsWith? l "/")) lines)) "every path is root-relative, not absolute")
        (assert (= (listLength lines) closureCount) (str "deps lists every module of the real closure: printed " (stringFromInt64 (listLength lines)) ", loadModuleClosure! found " (stringFromInt64 closureCount)))
        true))

fn ! testUsage -> Bool
  (let [(none (driver ""))
        (noOut (driver (str "build " (fibPath))))
        (unknown (driver (str "run " (fibPath))))
        (depsBare (driver "deps"))]
    (do (map (fn [(out ProcessOutput)] -> Bool
               (do (assert (= out.exitCode 2) (str "a malformed command line exits 2, got " out.exitCode "; stderr: " out.stderr))
                   (assert (= out.stderr "usage: asl1 build ENTRY -o OUT.ll | asl1 check ENTRY | asl1 deps ENTRY\n") (str "the usage line on stderr: " out.stderr))
                   true))
             (list none noOut unknown depsBare))
        true))

fn charAt s: String i: Int64 -> String
  (mt (stringSlice s i (+ i 1)) ((some c) c) ((none) ""))

fn letterOrUnderscore? ch: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" ch)

fn scanCallFieldChain src: String i: Int64 n: Int64 -> Bool
  (if (>= (+ i 2) n)
    false
    (if (and (= (charAt src i) ")") (and (= (charAt src (+ i 1)) ".") (letterOrUnderscore? (charAt src (+ i 2)))))
      true
      (scanCallFieldChain src (+ i 1) n)))

fn ! testNoCallResultFieldChain -> Bool
  (mt (fileReadString (asl1))
    ((err e) (do (assert false (str "cannot read " (asl1) ": " e)) false))
    ((ok src) (do (assert (not (scanCallFieldChain src 0 (stringLength src))) (str (asl1) " must bind a call's result with let before taking a .field off it (NATIVE-ASL1-FALLBACK via a stale native compiler otherwise)"))
                  true)))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (testBuildFib work) "testBuildFib")
        (assert (testArgsMain work) "testArgsMain")
        (assert (testCheck work) "testCheck")
        (assert (testCheckLikeHost work) "testCheckLikeHost")
        (assert (testDeps) "testDeps")
        (assert (testDepsFullClosure) "testDepsFullClosure")
        (assert (testUsage) "testUsage")
        (assert (testNoCallResultFieldChain) "testNoCallResultFieldChain")
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
