(module asl-target-llvm/tests/nativeTrapTest
  :x [runTests]
  :i [(asl-target-llvm :a llvm)
      (asl-parser/ast :a a)])

fn host -> String
  "asl/host/out/asl-host"

fn asl1 -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn runtimeLib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn removedSymbols -> (List String)
  (list "@asl_rt_trap(" "@asl_rt_type_trap(" "@asl_rt_int_trap(" "@asl_rt_exit_code(" "@asl_rt_b_trap(")

fn removedNames -> (List String)
  (map (fn [(s String)] -> String (stringReplace (stringReplace s "@" "") "(" "")) (removedSymbols))

fn packageDirs -> (List String)
  (list "asl/packages/asl-target-llvm/src" "asl/packages/asl-target-llvm/tests")

fn ! packageFiles -> (List String)
  (fold (fn [(acc (List String)) (dir String)] -> (List String)
          (mt (dirList dir)
            ((err _) acc)
            ((ok names) (listAppend acc (map (fn [(n String)] -> String (str dir "/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) names))))))
        (list) (packageDirs))

fn ! parsed path: String -> (Result (List a/TopForm) String)
  (mt (fileRead path)
    ((err e) (err (str path ": unreadable: " e)))
    ((ok src) (mt (a/parse src)
                ((err pe) (err (str path ":" pe.line ":" pe.col ": " pe.msg)))
                ((ok forms) (ok forms)))))

fn ledgerPath -> String
  "asl/packages/asl-target-llvm/doc.asn"

fn rowDoc line: String -> (List (Pair String String))
  (if (stringStartsWith? line "(:doc :symbol \"asl/packages/asl-target-llvm/")
    (let [(parts (stringSplit line " :text \""))
          (symbol (optionOr (listGet parts 0) ""))
          (text (optionOr (listGet parts 1) ""))]
      (list (pair symbol (optionOr (stringSlice text 0 (- (stringLength text) 2)) ""))))
    (list))

fn ! ledgerDocs -> (List (Pair String String))
  (mt (fileReadString (ledgerPath))
    ((err _) (list))
    ((ok t) (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String)) (listAppend acc (rowDoc line))) (list) (stringSplit t "\n"))))

fn ! parseFailures path: String -> (List String)
  (mt (parsed path) ((err e) (list e)) ((ok _) (list)))

fn staleDocs docs: (List (Pair String String)) -> (List String)
  (map (fn [(d (Pair String String))] -> String (pairFirst d))
       (filter (fn [(d (Pair String String))] -> Bool (not (listEmpty? (filter (fn [(n String)] -> Bool (stringContains? (pairSecond d) n)) (removedNames))))) docs))

fn ! testDocs -> Bool
  (let [(files (packageFiles))
        (docs (ledgerDocs))
        (stale (staleDocs docs))
        (failures (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (parseFailures p))) (list) files))]
    (do
      (assert (listEmpty? failures) (str "docs: every file parses; " (stringJoin failures "; ")))
      (assert (> (listLength files) 30) (str "docs: scans the package's src and tests, got " (listLength files) " files"))
      (assert (> (listLength (filter (fn [(d (Pair String String))] -> Bool (> (stringLength (pairSecond d)) 2)) docs)) 500) (str "docs: reads the package's doc.asn rows, got " (listLength docs)))
      (assert (listEmpty? stale) (str "docs: no doc names a removed abi.c entry; stale: " (stringJoin stale "; ")))
      true))

fn removedIn ir: String -> (List String)
  (filter (fn [(s String)] -> Bool (stringContains? ir s)) (removedSymbols))

fn program name: String mainType: String body: String -> String
  (stringJoin (list (str "(module " name " :x [main] :i [])")
                    ""
                    (str "fn ! main -> " mainType)
                    (str "  " body)) "\n")

fn one -> String
  "(stringLength \"a\")"

fn cases -> (List (Pair String String))
  (list
    (pair "addOver" (program "addOver" "(Result Int64 String)" (str "(ok (+ 9223372036854775807 " (one) "))")))
    (pair "subOver" (program "subOver" "(Result Int64 String)" (str "(ok (- -9223372036854775808 " (one) "))")))
    (pair "mulOver" (program "mulOver" "(Result Int64 String)" (str "(ok (* 9223372036854775807 (+ " (one) " 1)))")))
    (pair "divOver" (program "divOver" "(Result Int64 String)" (str "(ok (/ -9223372036854775808 (- 0 " (one) ")))")))
    (pair "divZero" (program "divZero" "(Result Int64 String)" (str "(ok (/ 7 (- " (one) " 1)))")))
    (pair "modZero" (program "modZero" "(Result Int64 String)" (str "(ok (mod 7 (- " (one) " 1)))")))
    (pair "trapCode" (program "trapCode" "(Result Int64 String)" "(trap \"ERR_RANGE\" \"chosen message\")"))
    (pair "trapUnknown" (program "trapUnknown" "(Result Int64 String)" "(trap \"ERR_NOT_A_CODE\" \"m\")"))
    (pair "trapBlocked" (program "trapBlocked" "(Result Int64 String)" "(trap \"ERR_INTERNAL\" \"m\")"))
    (pair "trapNewline" (program "trapNewline" "(Result Int64 String)" "(trap \"ERR_RANGE\" \"two\\nlines\")"))
    (pair "ok3" (program "ok3" "(Result Int64 String)" "(ok 3)"))
    (pair "ok256" (program "ok256" "(Result Int64 String)" "(ok 256)"))
    (pair "okNegative" (program "okNegative" "(Result Int64 String)" (str "(ok (- 0 " (one) "))")))
    (pair "okString" (program "okString" "(Result String String)" "(ok \"s\")"))
    (pair "errString" (program "errString" "(Result Int64 String)" "(err \"e\")"))
    (pair "assertMessage" (program "assertMessage" "(Result Int64 String)" (str "(do (assert (= " (one) " 1) \"first holds\") (assert (= " (one) " 2) \"second fails\") (ok 0))")))
    (pair "assertBare" (program "assertBare" "(Result Int64 String)" (str "(do (assert (= " (one) " 2)) (ok 0))")))
    (pair "assertRecord" (program "assertRecord" "(Result Int64 String)" (str "(do (assert (= " (one) " 2) [[[[[[[[[[\"deep\"]]]]]]]]]]) (ok 0))")))
    (pair "refuteMessage" (program "refuteMessage" "(Result Int64 String)" (str "(do (refute (= " (one) " 2) \"holds\") (refute (= " (one) " 1) \"was true\") (ok 0))")))
    (pair "refuteBare" (program "refuteBare" "(Result Int64 String)" (str "(do (refute (= " (one) " 1)) (ok 0))")))
    (pair "ordering" (program "ordering" "(Result Int64 String)" (str "(do (println \"before one\") (print \"before two\") (ok (+ 9223372036854775807 " (one) ")))")))
    (pair "parallelRaise" (program "parallelRaise" "(Result Int64 String)" "(ok (listLength (parMap (fn [(x Int64)] -> Int64 (+ x 9223372036854775806)) (list 1 2 3) 1)))"))
    (pair "parallelFork" (program "parallelFork" "(Result Int64 String)" "(ok (listLength (parMap (fn [(x Int64)] -> Int64 (+ x 9223372036854775806)) (list 1 2 3) 2)))"))
    (pair "initAssert" (stringJoin (list "(module initAssert :x [main] :i [])"
                                         ""
                                         "(println \"init runs\")"
                                         "(assert (= (stringLength \"ab\") 2) \"init holds\")"
                                         "(assert (= (stringLength \"ab\") 3) \"init fails\")"
                                         ""
                                         "fn ! main -> (Result Int64 String)"
                                         "  (ok 0)") "\n"))
    (pair "mixedRaise" (stringJoin (list "(module mixedRaise :x [main] :i [])"
                                         ""
                                         "fn ! pause n: Int64 -> Int64"
                                         "  (do (sleepMs n) n)"
                                         ""
                                         "fn ! main args: (List String) -> (Result Int64 String)"
                                         "  (if (= (mt (listHead args) ((some a) a) ((none) \"\")) \"c\")"
                                         "    (ok (pause (- 0 (stringLength \"a\"))))"
                                         "    (ok (+ 9223372036854775807 (stringLength \"a\"))))") "\n")))

fn uncheckedCases -> (List (Pair String String))
  (list
    (pair "notBool" (stringJoin (list "(module notBool :x [main] :i [])"
                                      ""
                                      "fn pick x: a -> Int64"
                                      "  (if x 1 2)"
                                      ""
                                      "fn ! main -> (Result Int64 String)"
                                      "  (ok (pick (stringLength \"a\")))") "\n"))
    (pair "noMatch" (stringJoin (list "(module noMatch :x [main] :i [])"
                                      ""
                                      "(enum Tri (:c one [] \"One\") (:c two [] \"Two\") (:c three [] \"Three\"))"
                                      ""
                                      "fn pick t: Tri -> Int64"
                                      "  (mt t ((one) 1) ((two) 2))"
                                      ""
                                      "fn ! main -> (Result Int64 String)"
                                      "  (ok (pick (if (= (stringLength \"a\") 1) (three) (one))))") "\n")))

fn failLine out: ProcessOutput src: String -> String
  (let [(prefix (str "FAIL " src ": "))
        (line (fold (fn [(acc String) (l String)] -> String (if (stringStartsWith? l prefix) l acc)) "" (stringSplit out.stderr "\n")))
        (rest (optionOr (stringSlice line (stringLength prefix) (stringLength line)) ""))]
    (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest " (after ") (stringLength rest))) rest))

fn failAsserts out: ProcessOutput src: String -> String
  (let [(prefix (str "FAIL " src ": "))
        (line (fold (fn [(acc String) (l String)] -> String (if (stringStartsWith? l prefix) l acc)) "" (stringSplit out.stderr "\n")))
        (from (optionOr (stringIndexOf line " (after ") (stringLength line)))
        (tail (optionOr (stringSlice line (+ from 8) (stringLength line)) ""))]
    (optionOr (stringSlice tail 0 (optionOr (stringIndexOf tail " asserts)") 0)) ""))

fn expectedStderr hosted: ProcessOutput src: String -> String
  (let [(line (failLine hosted src))] (if (stringEmpty? line) hosted.stderr (str line "\n")))

fn ! compare label: String bin: String src: String args: String -> Bool
  (let [(hosted (sh (str (host) " run " src args)))
        (native (sh (str bin args)))]
    (do
      (assert (= native.exitCode hosted.exitCode) (str label ": exit equals asl-host; native " native.exitCode " host " hosted.exitCode " stderr " native.stderr))
      (assert (= native.stdout hosted.stdout) (str label ": stdout equals asl-host; native " native.stdout " host " hosted.stdout))
      (assert (= native.stderr (expectedStderr hosted src)) (str label ": stderr equals asl-host's error line; native " native.stderr " host " hosted.stderr))
      true))

fn ! buildChecked work: String name: String text: String -> String
  (let [(src (str work "/" name ".asl")) (ll (str work "/" name ".ll")) (bin (str work "/" name))]
    (do
      (assert (ok? (fileWrite src text)) (str name ": writes source"))
      (let [(built (sh (str (host) " run " (asl1) " build " src " -o " ll)))]
        (assert (= built.exitCode 0) (str name ": asl1 builds; stderr " built.stderr)))
      (linkChecked name ll bin)
      bin))

fn ! buildUnchecked work: String name: String text: String -> String
  (let [(src (str work "/" name ".asl")) (ll (str work "/" name ".ll")) (bin (str work "/" name))]
    (do
      (assert (ok? (fileWrite src text)) (str name ": writes source"))
      (mt (llvm/emitLlvmSource text "main")
        ((ok code) (assert (ok? (fileWrite ll code)) (str name ": writes IR")))
        ((err _) (assert false (str name ": emitLlvmSource lowers it"))))
      (linkChecked name ll bin)
      bin))

fn ! linkChecked name: String ll: String bin: String -> Bool
  (let [(ir (mt (fileReadString ll) ((ok t) t) ((err _) "")))]
    (do
      (assert (stringContains? ir "define i32 @main(") (str name ": IR defines @main"))
      (assert (listEmpty? (removedIn ir)) (str name ": IR declares or calls no removed abi.c entry; found " (stringJoin (removedIn ir) " ")))
      (let [(linked (sh (str (clang) " -x ir " ll " -x none " (runtimeLib) " -lm -o " bin)))]
        (assert (= linked.exitCode 0) (str name ": clang links; stderr " linked.stderr)))
      true))

fn ! testCases work: String -> Bool
  (do
    (map (fn [(c (Pair String String))] -> Bool
           (compare (pairFirst c) (buildChecked work (pairFirst c) (pairSecond c)) (str work "/" (pairFirst c) ".asl") ""))
         (filter (fn [(c (Pair String String))] -> Bool (!= (pairFirst c) "mixedRaise")) (cases)))
    (map (fn [(c (Pair String String))] -> Bool
           (compare (pairFirst c) (buildUnchecked work (pairFirst c) (pairSecond c)) (str work "/" (pairFirst c) ".asl") ""))
         (uncheckedCases))
    true)

fn irConstants ir: String -> (List String)
  (fold (fn [(acc (List String)) (l String)] -> (List String)
          (mt (stringIndexOf l " x i8] c\"")
            ((none) acc)
            ((some at) (let [(body (optionOr (stringSlice l (+ at 9) (stringLength l)) ""))
                             (text (optionOr (stringSlice body 0 (optionOr (stringIndexOf body "\"") (stringLength body))) ""))]
                         (listAppend acc (list (stringReplace (stringReplace (stringReplace (stringReplace text "\\00" "") "\\0A" "\n") "\\22" "\"") "\\5C" "\\")))))))
        (list) (stringSplit ir "\n"))

fn specRest p: String -> String
  (mt (stringSlice p 0 1)
    ((none) "")
    ((some c) (if (stringContains? "0123456789.-+ #lhzjtL" c)
                (specRest (optionOr (stringSlice p 1 (stringLength p)) ""))
                (optionOr (stringSlice p 1 (stringLength p)) ""))))

fn formatPieces c: String -> (List String)
  (let [(parts (stringSplit c "%"))]
    (listAppend (list (optionOr (listHead parts) ""))
                (map (fn [(p String)] -> String (specRest p)) (optionOr (listTail parts) (list)))))

fn fitsFormat line: String c: String -> Bool
  (or (fitsText line c) (fitsText (optionOr (stringSlice line (+ 2 (optionOr (stringIndexOf line ": ") (stringLength line))) (stringLength line)) "") c))

fn fitsText line: String c: String -> Bool
  (let [(pieces (formatPieces (stringReplace c "\n" "")))
        (literal (fold (fn [(n Int64) (p String)] -> Int64 (+ n (stringLength p))) 0 pieces))
        (first (optionOr (listHead pieces) ""))
        (rest (optionOr (listTail pieces) (list)))
        (last (fold (fn [(acc String) (p String)] -> String p) first rest))
        (walked (fold (fn [(at Int64) (p String)] -> Int64
                        (if (< at 0) at
                            (mt (stringSlice line at (stringLength line))
                              ((none) -1)
                              ((some tail) (mt (stringIndexOf tail p) ((none) -1) ((some i) (+ at (+ i (stringLength p)))))))))
                      (stringLength first) rest))]
    (and (>= literal 6)
         (stringStartsWith? line first)
         (>= walked 0)
         (stringEndsWith? line last)
         (if (listEmpty? rest) (= line first) true)))

fn ! testMixed work: String -> Bool
  (let [(bin (buildChecked work "mixedRaise" (optionOr (mapGet (mapFromPairs (cases)) "mixedRaise") "")))
        (src (str work "/mixedRaise.asl"))
        (ir (mt (fileReadString (str work "/mixedRaise.ll")) ((ok t) t) ((err _) "")))
        (hostC (sh (str (host) " run " src " c")))
        (line (failLine hostC src))
        (formats (irConstants ir))]
    (do
      (assert (> (stringLength line) 12) (str "mixedRaise c: asl-host reports an error line; got " hostC.stderr))
      (assert (> (listLength formats) 20) (str "mixedRaise c: reads the emitted IR's string constants, got " (listLength formats)))
      (assert (fitsFormat "ERR_RANGE: bytesGet: slot 5 outside 2 bytes" "%s: slot %lld outside %zu bytes") "mixedRaise c: fitsFormat matches a format across its conversions")
      (refute (fitsFormat line "%s: %s\n") "mixedRaise c: fitsFormat ignores a format with no raise site's words")
      (assert (and (listContains? formats "sleepMs: ") (listContains? formats " is negative")) (str "mixedRaise c: the IR holds the routed sleepMs's pieces of '" line "', so native code raised it"))
      (refute (stringContains? ir "@asl_rt_builtin(") "mixedRaise c: the IR calls no asl_rt_builtin")
      (assert (stringContains? hostC.stderr "ERR_RANGE: sleepMs: -1 is negative") (str "mixedRaise c: asl-host fails sleepMs of -1 with ERR_RANGE; got " hostC.stderr))
      (compare "mixedRaise c" bin src " c")
      (compare "mixedRaise native" bin src " n")
      true))

fn ! testOrdering work: String -> Bool
  (let [(src (str work "/ordering.asl"))
        (hosted (sh (str (host) " run " src)))
        (merged (sh (str work "/ordering 2>&1")))]
    (do
      (assert (= hosted.stdout "before one\nbefore two") (str "ordering: asl-host prints both lines; got " hosted.stdout))
      (assert (= merged.stdout (str hosted.stdout (failLine hosted src) "\n")) (str "ordering: native stdout then the error line; got " merged.stdout))
      true))

fn countedSource -> String
  (stringJoin (list "(module counted :x [main runTests] :i [])"
                    ""
                    "fn ! runTests -> Bool"
                    "  (do (assert (= (stringLength \"ab\") 2) \"a\") (assert (< 1 (stringLength \"ab\"))) (refute (= 0 (stringLength \"ab\")) \"r\")"
                    "      (assert (!= (stringLength \"ab\") 3)) (refute (= 1 (stringLength \"ab\"))) true)"
                    ""
                    "fn ! main -> (Result Int64 String)"
                    "  (if (runTests) (ok 0) (err \"failed\"))") "\n")

fn ! testReport work: String -> Bool
  (let [(bin (buildChecked work "counted" (countedSource)))
        (src (str work "/counted.asl"))
        (tested (sh (str (host) " test " src)))
        (wantLine (str (optionOr (stringSlice tested.stdout (+ (stringLength src) 2) (optionOr (stringIndexOf tested.stdout " (") 0)) "") "\n"))
        (reported (sh (str "ASL_ASSERT_REPORT=1 " bin)))
        (silent (sh bin))
        (failSrc (str work "/assertMessage.asl"))
        (failHost (sh (str (host) " run " failSrc)))
        (failReported (sh (str "ASL_ASSERT_REPORT=1 " work "/assertMessage")))]
    (do
      (assert (= tested.exitCode 0) (str "counted: asl-host test passes; stderr " tested.stderr))
      (assert (= wantLine "3 assertion(s) executed, 2 refutation(s) executed\n") (str "counted: asl-host test counts 3 and 2; got " tested.stdout))
      (assert (= reported.exitCode 0) (str "counted: native passes; stderr " reported.stderr))
      (assert (= reported.stderr wantLine) (str "counted: native report equals asl-host test's counts; got " reported.stderr))
      (assert (= silent.stderr "") (str "counted: no report without ASL_ASSERT_REPORT; got " silent.stderr))
      (assert (= failReported.stderr
                 (str (failLine failHost failSrc) "\n" (failAsserts failHost failSrc) " assertion(s) executed, 0 refutation(s) executed\n"))
              (str "assertMessage: report after the error counts asl-host's (after N asserts); got " failReported.stderr " host " failHost.stderr))
      true))

fn ! testRawTraps work: String -> Bool
  (do
    (map (fn [(fixture (Pair String String))] -> Bool
           (let [(name (pairFirst fixture)) (ll (str work "/" (pairFirst fixture) ".ll")) (bin (str work "/" (pairFirst fixture)))
                 (emitted (sh (str (host) " run asl/packages/asl-target-llvm/tests/irE2eTest.asl trap:" name " > " ll)))
                 (ir (mt (fileReadString ll) ((ok t) t) ((err _) "")))
                 (linked (sh (str (clang) " -x ir " ll " -lm -o " bin)))
                 (out (sh bin))]
             (do
               (assert (= emitted.exitCode 0) (str name ": irE2eTest emits it; stderr " emitted.stderr))
               (assert (listEmpty? (removedIn ir)) (str name ": IR declares or calls no removed abi.c entry; found " (stringJoin (removedIn ir) " ")))
               (assert (= linked.exitCode 0) (str name ": links without the runtime; stderr " linked.stderr))
               (assert (= out.exitCode 1) (str name ": exit 1, got " out.exitCode))
               (assert (= out.stderr (pairSecond fixture)) (str name ": stderr " out.stderr))
               true)))
         (list (pair "narrowOver" "ERR_INT_OVERFLOW: Int narrow leaves int32\n")
               (pair "floatHuge" "ERR_INT_OVERFLOW: Float to Int leaves int64\n")
               (pair "floatNan" "ERR_INT_OVERFLOW: Float to Int leaves int64\n")))
    true)

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "nativeTrap: makes work directory")
      (testCases work)
      (testMixed work)
      (testOrdering work)
      (testReport work)
      (testRawTraps work)
      (testDocs)
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "nativeTrap: removes work directory")
      true))
