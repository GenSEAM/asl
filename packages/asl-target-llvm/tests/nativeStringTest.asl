(module asl-target-llvm/tests/nativeStringTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): testValueParity/testFailingParity used asl-host as a live parity oracle for the hand-built native binary over stringFixture, keyed by op. Every op is fixed, so the oracle is replaced by a recordedCase table, captured once from the leftover asl-host binary before HL-DELETE removed it, covering all of valueCases and failingCases; native build/link/run logic is unchanged. Also fixed the same pre-existing sourceDirs/asl-host-src gap already fixed in nativeOpsTest.asl")

(schema Recorded
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn fixtureLines -> (List String)
  (list "(module stringFixture :x [main] :i [])"
        ""
        "fn lengthOf x: T -> Int64"
        "  (stringLength x)"
        ""
        "fn concatOf x: T y: T -> String"
        "  (stringConcat x y)"
        ""
        "fn sliceOf x: T from: T to: T -> (Option String)"
        "  (stringSlice x from to)"
        ""
        "fn fromIntOf x: T -> String"
        "  (stringFromInt64 x)"
        ""
        "fn startsOf x: T y: T -> Bool"
        "  (stringStartsWith? x y)"
        ""
        "fn containsOf x: T y: T -> Bool"
        "  (stringContains? x y)"
        ""
        "fn bytesOf x: T -> Bytes"
        "  (stringToBytes x)"
        ""
        "fn idOf x: T -> T"
        "  x"
        ""
        "fn sliceAcross x: T from: T c: Bool -> String"
        "  (let [(s (idOf x))] (if c (str (stringSlice s from 1)) \"no\"))"
        ""
        "fn doubled s: String n: Int64 -> String"
        "  (if (= n 0) s (doubled (stringConcat s s) (- n 1)))"
        ""
        "fn empties -> String"
        "  (str (stringLength \"\") \" \" (stringConcat \"\" \"\") \"|\" (stringSlice \"\" 0 0) \" \" (stringSlice \"\" 0 1) \" \""
        "       (stringStartsWith? \"\" \"\") \" \" (stringContains? \"\" \"\") \" \" (stringStartsWith? \"\" \"a\") \" \" (stringContains? \"\" \"a\") \" \""
        "       (bytesLength (stringToBytes \"\")) \" \" (stringFromInt64 0) \" \" (stringConcat \"x\" \"\") (stringConcat \"\" \"y\"))"
        ""
        "fn utf8 -> String"
        "  (let [(s \"h\\xc3\\xa9llo w\\xc3\\xb6rld \\xe2\\x9c\\x93\") (b (stringToBytes s))]"
        "    (str (stringLength s) \" \" (stringSlice s 1 2) \" \" (stringSlice s 1 3) \" \" (stringSlice s 2 3) \" \" (stringSlice s 14 16) \" \" (stringSlice s 14 17) \" \""
        "         (stringConcat (optionOr (stringSlice s 0 2) \"\") (optionOr (stringSlice s 2 17) \"\")) \" \" (stringLength (stringConcat s s)) \" \""
        "         (stringContains? s \"w\\xc3\\xb6r\") \" \" (stringContains? s \"\\xb6\") \" \" (stringStartsWith? s \"h\\xc3\") \" \" (stringStartsWith? s \"\\xc3\") \" \""
        "         (bytesLength b) \" \" (bytesGet b 1) \" \" (bytesGet b 2) \" \" (bytesGet b 16) \" \" b))"
        ""
        "fn bounds -> String"
        "  (let [(s \"abcdef\")]"
        "    (str (stringSlice s 3 1) \" \" (stringSlice s -1 2) \" \" (stringSlice s 0 -1) \" \" (stringSlice s -5 -2) \" \" (stringSlice s 2 99) \" \""
        "         (stringSlice s 6 6) \" \" (stringSlice s 7 7) \" \" (stringSlice s 0 6) \" \" (stringSlice s 3 3) \" \" (stringSlice s 2 9223372036854775807) \" \""
        "         (stringSlice s 9223372036854775807 9223372036854775807) \" \" (stringSlice s (- -9223372036854775807 1) 1)))"
        ""
        "fn ints -> String"
        "  (str (stringFromInt64 0) \" \" (stringFromInt64 -1) \" \" (stringFromInt64 (- -9223372036854775807 1)) \" \" (stringFromInt64 9223372036854775807) \" \""
        "       (stringFromInt64 1234567890) \" \" (stringFromInt64 -10) \" \" (stringFromInt64 9))"
        ""
        "fn needles -> String"
        "  (str (stringStartsWith? \"abc\" \"\") \" \" (stringContains? \"abc\" \"\") \" \" (stringStartsWith? \"abc\" \"abcd\") \" \" (stringContains? \"abc\" \"abcd\") \" \""
        "       (stringStartsWith? \"abc\" \"abc\") \" \" (stringContains? \"abc\" \"abc\") \" \" (stringContains? \"abcabd\" \"abd\") \" \" (stringContains? \"aaab\" \"aab\") \" \""
        "       (stringStartsWith? \"abc\" \"b\") \" \" (stringContains? \"abc\" \"c\") \" \" (stringContains? \"abc\" \"x\") \" \" (stringContains? \"ab\" \"abc\") \" \""
        "       (stringStartsWith? \"ab\" \"abc\") \" \" (stringContains? \"a\\x00b\" \"\\x00b\") \" \" (stringStartsWith? \"a\\x00b\" \"a\\x00c\"))"
        ""
        "fn big -> String"
        "  (let [(a (doubled \"a\" 20)) (b (doubled \"b\" 20)) (ab (stringConcat a b))]"
        "    (str (stringLength a) \" \" (stringLength b) \" \" (stringLength ab) \" \" (stringSlice ab 1048574 1048578) \" \" (stringStartsWith? ab a) \" \""
        "         (stringStartsWith? ab b) \" \" (stringContains? ab \"ab\") \" \" (stringContains? ab \"ba\") \" \" (= (stringConcat a b) ab) \" \" (bytesLength (stringToBytes ab))))"
        ""
        "fn values -> String"
        "  (let [(ln stringLength) (cc stringConcat) (sl stringSlice) (fi stringFromInt64) (sw stringStartsWith?) (ct stringContains?) (tb stringToBytes)]"
        "    (str (ln \"abc\") \" \" (cc \"ab\" \"cd\") \" \" (sl \"abcdef\" 1 3) \" \" (sl \"abc\" 2 1) \" \" (fi -42) \" \" (sw \"abc\" \"ab\") \" \" (ct \"abc\" \"bc\") \" \""
        "         (bytesLength (tb \"xyz\")) \" \" (map stringLength (list \"\" \"a\" \"ab\")) \" \" (map stringFromInt64 (list 1 -2)) \" \""
        "         (fold stringConcat \"\" (list \"x\" \"y\" \"z\")) \" \" (map stringToBytes (list \"q\"))))"
        ""
        "fn ! failing op: String -> String"
        "  (let [(ln stringLength) (cc stringConcat) (sl stringSlice) (fi stringFromInt64) (sw stringStartsWith?) (ct stringContains?) (tb stringToBytes)]"
        "    (cond ((= op \"lengthValue\") (str (ln 5)))"
        "          ((= op \"lengthParam\") (str (lengthOf 1.5)))"
        "          ((= op \"concatFirst\") (cc 5 \"a\"))"
        "          ((= op \"concatSecond\") (cc \"a\" true))"
        "          ((= op \"concatParam\") (concatOf 1 2))"
        "          ((= op \"sliceText\") (str (sl 5 0 1)))"
        "          ((= op \"sliceFrom\") (str (sl \"abc\" \"x\" 1)))"
        "          ((= op \"sliceTo\") (str (sl \"abc\" 0 1.5)))"
        "          ((= op \"sliceTextAndFrom\") (str (sl 5 \"x\" 1)))"
        "          ((= op \"sliceTextAndTo\") (str (sl (list) 0 \"y\")))"
        "          ((= op \"sliceParam\") (str (sliceOf \"abc\" 0 \"z\")))"
        "          ((= op \"sliceAcrossBlocks\") (sliceAcross 5 \"q\" true))"
        "          ((= op \"fromIntText\") (fi \"x\"))"
        "          ((= op \"fromIntFloat\") (fi 1.5))"
        "          ((= op \"fromIntParam\") (fromIntOf \"q\"))"
        "          ((= op \"startsFirst\") (str (sw 5 \"a\")))"
        "          ((= op \"startsSecond\") (str (sw \"a\" 5)))"
        "          ((= op \"startsParam\") (str (startsOf \"a\" (list))))"
        "          ((= op \"containsFirst\") (str (ct 5 \"a\")))"
        "          ((= op \"containsSecond\") (str (ct \"a\" (list 1))))"
        "          ((= op \"containsParam\") (str (containsOf 1.5 \"a\")))"
        "          ((= op \"toBytesValue\") (str (tb 5)))"
        "          ((= op \"toBytesParam\") (str (bytesOf 2.5)))"
        "          (else \"no such case\")))"
        ""
        "fn ! main args: (List String) -> (Result Int64 String)"
        "  (let [(op (optionOr (listHead args) \"\"))]"
        "    (do (println (cond ((= op \"empties\") (empties))"
        "                       ((= op \"utf8\") (utf8))"
        "                       ((= op \"bounds\") (bounds))"
        "                       ((= op \"ints\") (ints))"
        "                       ((= op \"needles\") (needles))"
        "                       ((= op \"big\") (big))"
        "                       ((= op \"values\") (values))"
        "                       (else (failing op))))"
        "        (ok 0)))")

fn fixtureSrc -> String
  (str (stringJoin (fixtureLines) "\n") "\n")

fn deletedEntries -> (List String)
  (list "stringConcat" "stringLength" "stringSlice" "stringFromInt64" "stringStartsWith" "stringContains" "stringToBytes")

fn groupNames -> (List (Pair String String))
  (list (pair "stringLength" "stringLength") (pair "stringConcat" "stringConcat") (pair "stringSlice" "stringSlice") (pair "stringFromInt64" "stringFromInt64")
        (pair "stringStartsWith?" "stringStartsWith$3F") (pair "stringContains?" "stringContains$3F") (pair "stringToBytes" "stringToBytes"))

fn helperCalls -> (List String)
  (list "call i64 @strrt.length(" "call %Val @strrt.concat(" "call %Val @strrt.slice(" "call %Val @asl_rt_format_i64("
        "call i1 @strrt.startsWith(" "call i1 @strrt.contains(" "call %Val @strrt.toBytes(")

fn valueCases -> (List String)
  (list "empties" "utf8" "bounds" "ints" "needles" "big" "values")

fn failingCases -> (List String)
  (list "lengthValue" "lengthParam" "concatFirst" "concatSecond" "concatParam" "sliceText" "sliceFrom" "sliceTo" "sliceTextAndFrom" "sliceTextAndTo" "sliceParam" "sliceAcrossBlocks"
        "fromIntText" "fromIntFloat" "fromIntParam" "startsFirst" "startsSecond" "startsParam" "containsFirst" "containsSecond" "containsParam"
        "toBytesValue" "toBytesParam")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiled path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (processRun (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listHead known)
      ((some o) (some o))
      ((none) (if (= (processRun "command -v opt >/dev/null 2>&1").exitCode 0) (some "opt") (none)))))

fn ! testRuntimeDecls -> Bool
  (do
    (map (fn [(n String)] -> Bool
           (do (refute (listAny? (fn [(d String)] -> Bool (stringContains? d (str "@asl_rt_b_" n "("))) (llvm/runtimeDecls))
                       (str "runtimeDecls declares no asl_rt_b_" n))
               true))
         (deletedEntries))
    true)

fn ! testArchive -> Bool
  (let [(listed (processRun "nm asl/host/out/libaslrt.a"))]
    (do
      (assert (= listed.exitCode 0) (str "nm lists libaslrt.a: " listed.stderr))
      (assert (stringContains? listed.stdout "asl_rt_init") "nm output holds the entries libaslrt.a keeps")
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? listed.stdout (str "asl_rt_b_" n "\n")) (str "libaslrt.a defines no asl_rt_b_" n))
                 true))
           (deletedEntries))
      true))

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): dropped the asl/host/src dir, which HL-DELETE removed entirely; see nativeOpsTest.asl's identical fix")
fn sourceDirs -> (List (Pair String (List String)))
  (list (pair "asl/packages/asl-target-llvm/src" (list ".asl"))
        (pair "asl/packages/asl-target-llvm/tests" (list ".asl")))

fn ! sourceFiles -> (List String)
  (fold (fn [(acc (List String)) (d (Pair String (List String)))] -> (List String)
          (mt (dirList (pairFirst d))
            ((err e) (do (assert false (str "lists " (pairFirst d) ": " e)) acc))
            ((ok names) (listAppend acc (map (fn [(n String)] -> String (str (pairFirst d) "/" n))
                                             (filter (fn [(n String)] -> Bool (listAny? (fn [(s String)] -> Bool (stringEndsWith? n s)) (pairSecond d))) names))))))
        (list) (sourceDirs))

fn ! testStaleNames -> Bool
  (let [(files (sourceFiles))
        (stale (fold (fn [(acc (List String)) (f String)] -> (List String)
                       (mt (fileReadString f)
                         ((err e) (do (assert false (str "reads " f ": " e)) acc))
                         ((ok text) (listAppend acc (map (fn [(n String)] -> String (str f ": " n))
                                                         (filter (fn [(n String)] -> Bool (or (stringContains? text (str "asl_rt_b_" n))
                                                                                             (or (stringContains? text (str "ENTRY1(" n ","))
                                                                                                 (or (stringContains? text (str "ENTRY2(" n ","))
                                                                                                     (stringContains? text (str "ENTRY3(" n ","))))))
                                                                 (deletedEntries)))))))
                     (list) files))]
    (do
      (assert (> (listLength files) 60) (str "scans the package and the host runtime, got " (listLength files) " files"))
      (assert (listAny? (fn [(f String)] -> Bool (stringEndsWith? f "/rtAbi.asl")) files) "scans asl-target-llvm/src/rtAbi.asl (RT-ABI ported abi.c's builtins here; abi.c itself is gone)")
      (assert (listEmpty? stale) (str "no source names a deleted entry; stale: " (stringJoin stale "; ")))
      true))

fn ! testIr dir: String code: String -> Bool
  (let [(ll (str dir "/stringFixture.ll"))]
    (do
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@asl_rt_b_" n "(")) (str "the IR neither declares nor calls asl_rt_b_" n))
                 true))
           (deletedEntries))
      (map (fn [(p (Pair String String))] -> Bool
             (do (refute (stringContains? code (str "(ptr @name." (pairSecond p) ", i64 ")) (str "no asl_rt_builtin call names " (pairFirst p)))
                 true))
           (groupNames))
      (map (fn [(h String)] -> Bool
             (do (assert (stringContains? code h) (str "the IR makes " h))
                 true))
           (helperCalls))
      (assert (stringContains? code "call void @mathrt.want(ptr @.strrt.who.stringSlice, i32 2,") "an Int operand of stringSlice fails with stringSlice's want text")
      (assert (stringContains? code "call void @mathrt.want(ptr @.strrt.who.stringFromInt64, i32 2,") "an Int operand of stringFromInt64 fails with its want text")
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (mt (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (processRun (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str "opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn ! nativeExe dir: String -> String
  (let [(exe (str dir "/stringFixture"))
        (linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " dir "/stringFixture.ll -x none asl/host/out/libaslrt.a -lm -o " exe)))]
    (do (assert (= linked.exitCode 0) (str "stringFixture links against libaslrt.a: " linked.stderr))
        exe))

fn recordedCase op: String -> Recorded
  (cond
    ((= op "big") (Recorded :exitCode 0 :stdout "1048576 1048576 2097152 (some \"aabb\") true false true false true 2097152\n" :stderr ""))
    ((= op "bounds") (Recorded :exitCode 0 :stdout "(none) (none) (none) (none) (none) (some \"\") (none) (some \"abcdef\") (some \"\") (none) (none) (none)\n" :stderr ""))
    ((= op "concatFirst") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringConcat expects String, got Int (after 0 asserts)\n"))
    ((= op "concatParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringConcat expects String, got Int (after 0 asserts)\n"))
    ((= op "concatSecond") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringConcat expects String, got Bool (after 0 asserts)\n"))
    ((= op "containsFirst") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringContains? expects String, got Int (after 0 asserts)\n"))
    ((= op "containsParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringContains? expects String, got Float (after 0 asserts)\n"))
    ((= op "containsSecond") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringContains? expects String, got List (after 0 asserts)\n"))
    ((= op "empties") (Recorded :exitCode 0 :stdout "0 |(some \"\") (none) true true false false 0 0 xy\n" :stderr ""))
    ((= op "fromIntFloat") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringFromInt64 expects Int, got Float (after 0 asserts)\n"))
    ((= op "fromIntParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringFromInt64 expects Int, got String (after 0 asserts)\n"))
    ((= op "fromIntText") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringFromInt64 expects Int, got String (after 0 asserts)\n"))
    ((= op "ints") (Recorded :exitCode 0 :stdout "0 -1 -9223372036854775808 9223372036854775807 1234567890 -10 9\n" :stderr ""))
    ((= op "lengthParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringLength expects String, got Float (after 0 asserts)\n"))
    ((= op "lengthValue") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringLength expects String, got Int (after 0 asserts)\n"))
    ((= op "needles") (Recorded :exitCode 0 :stdout "true true false false true true true true false true false false false true false\n" :stderr ""))
    ((= op "sliceAcrossBlocks") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects String, got Int (after 0 asserts)\n"))
    ((= op "sliceFrom") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects Int, got String (after 0 asserts)\n"))
    ((= op "sliceParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects Int, got String (after 0 asserts)\n"))
    ((= op "sliceText") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects String, got Int (after 0 asserts)\n"))
    ((= op "sliceTextAndFrom") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects String, got Int (after 0 asserts)\n"))
    ((= op "sliceTextAndTo") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects String, got List (after 0 asserts)\n"))
    ((= op "sliceTo") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringSlice expects Int, got Float (after 0 asserts)\n"))
    ((= op "startsFirst") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringStartsWith? expects String, got Int (after 0 asserts)\n"))
    ((= op "startsParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringStartsWith? expects String, got List (after 0 asserts)\n"))
    ((= op "startsSecond") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringStartsWith? expects String, got Int (after 0 asserts)\n"))
    ((= op "toBytesParam") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringToBytes expects String, got Float (after 0 asserts)\n"))
    ((= op "toBytesValue") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/strCap/stringFixture.asl: ERR_TYPE: stringToBytes expects String, got Int (after 0 asserts)\n"))
    ((= op "utf8") (Recorded :exitCode 0 :stdout "17 (some \"\xc3\") (some \"\xc3\xa9\") (some \"\xa9\") (some \"\xe2\x9c\") (some \"\xe2\x9c\x93\") h\xc3\xa9llo w\xc3\xb6rld \xe2\x9c\x93 34 true true true false 17 195 169 147 #<Bytes>\n" :stderr ""))
    ((= op "values") (Recorded :exitCode 0 :stdout "3 abcd (some \"bc\") (none) -42 true true 3 (0 1 2) (\"1\" \"-2\") xyz (#<Bytes>)\n" :stderr ""))
    (else (Recorded :exitCode -1 :stdout "" :stderr (str "no recorded case: " op))))
fn ! testValueParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (recordedCase op))]
    (do
      (assert (= interp.exitCode 0) (str op ": the recorded asl-host exit " interp.exitCode "; stderr " interp.stderr))
      (assert (= native.exitCode 0) (str op ": native exit " native.exitCode "; stderr " native.stderr))
      (assert (> (stringLength interp.stdout) 1) (str op ": the recorded asl-host run prints the group"))
      (assert (= native.stdout interp.stdout) (str op ": native prints " native.stdout " and the recorded asl-host run " interp.stdout))
      (assert (= native.stderr "") (str op ": native stderr empty, got " native.stderr))
      true))

fn ! testFailingParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (recordedCase op))
        (line (stringReplace native.stderr "\n" ""))]
    (do
      (assert (= native.exitCode 1) (str op ": native exit " native.exitCode ", want 1; stderr " native.stderr))
      (assert (= native.exitCode interp.exitCode) (str op ": native exit equals the recorded asl-host exit " interp.exitCode))
      (assert (stringStartsWith? line "ERR_TYPE: string") (str op ": native stderr is one string builtin's ERR_TYPE line: " native.stderr))
      (assert (= native.stderr (str line "\n")) (str op ": native stderr is a single line: " native.stderr))
      (assert (stringContains? interp.stderr (str ": " line " (after")) (str op ": the recorded asl-host run reports " line "; it reported " interp.stderr))
      (assert (= native.stdout interp.stdout) (str op ": native stdout equals the recorded asl-host run stdout"))
      true))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (src (str dir "/stringFixture.asl"))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testRuntimeDecls)
      (testArchive)
      (testStaleNames)
      (assert (ok? (fileWrite src (fixtureSrc))) (str "fileWrite " src))
      (mt (compiled src)
        ((err e) (do (assert false (str "stringFixture links and emits: " e)) true))
        ((ok code)
          (do
            (testIr dir code)
            (let [(exe (nativeExe dir))]
              (do
                (map (fn [(op String)] -> Bool (testValueParity exe src op)) (valueCases))
                (map (fn [(op String)] -> Bool (testFailingParity exe src op)) (failingCases))
                true)))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
