(module asl-target-llvm/tests/nativeListBytesTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn bigCount -> Int64
  2000

fn fixtureLines -> (List String)
  (list "(module listBytesFixture :x [main] :i [])"
        ""
        "fn add3 a: Int64 b: Int64 c: Int64 -> Int64"
        "  (+ a (+ b c))"
        ""
        "fn sumList xs: (List Int64) acc: Int64 -> Int64"
        "  (mt (listHead xs) ((some h) (sumList (optionOr (listTail xs) (list)) (+ acc h))) ((none) acc))"
        ""
        "fn headOf x: T -> Int64"
        "  (optionOr (listHead x) 0)"
        ""
        "fn tailOf x: T -> (List Int64)"
        "  (optionOr (listTail x) (list))"
        ""
        "fn getOf x: T i: Int64 -> Int64"
        "  (optionOr (listGet x i) 0)"
        ""
        "fn sliceOf x: T -> String"
        "  (optionOr (stringSlice x 0 1) \"\")"
        ""
        "fn direct -> String"
        "  (let [(xs (list 1 2 3))"
        "        (ys (cons 0 xs))"
        "        (b (bytesAlloc 20))"
        "        (s1 (bytesSet b 0 255))"
        "        (s2 (bytesSet b 19 7))"
        "        (f1 (bytesSetFloat64 b 1 2.5))]"
        "    (str (listHead ys) \" \" (listTail ys) \" \" (listEmpty? ys) \" \" (listEmpty? (list)) \" \" (listHead (list)) \" \" (listTail (list)) \" \""
        "         (bytesLength b) \" \" (bytesGet b 0) \" \" (bytesGet b 19) \" \" (bytesGetFloat64 b 1) \" \" (bytesGetFloat64 b 0) \" \" s1 \" \" s2 \" \" f1 \" \" (list)"
        "         \" \" (bytesLength (bytesAlloc 0))))"
        ""
        "fn values -> String"
        "  (let [(c cons) (h listHead) (t listTail) (e listEmpty?) (bl bytesLength) (ba bytesAlloc) (bg bytesGet) (bs bytesSet) (bgf bytesGetFloat64) (bsf bytesSetFloat64)"
        "        (b (ba 16))]"
        "    (str (c 1 (list 2)) \" \" (h (list 1)) \" \" (t (list 1)) \" \" (e (list)) \" \" (bl b) \" \" (bs b 3 9) \" \" (bg b 3) \" \" (bsf b 1 1.5) \" \" (bgf b 1) \" \""
        "         (map listHead (list (list 1) (list))) \" \" (map listEmpty? (list (list) (list 1))) \" \" (map bytesLength (list b))))"
        ""
        "fn fused -> String"
        "  (let [(xs (list 4 5 6))]"
        "    (str (optionOr (listHead xs) 0) \" \" (optionOr (listHead (list)) -1) \" \""
        "         (optionOr (listTail xs) (list)) \" \" (optionOr (listTail (list)) (list 9)) \" \""
        "         (optionOr (listGet xs 2) 0) \" \" (optionOr (listGet xs 3) -1) \" \" (optionOr (listGet xs -1) -2) \" \" (optionOr (listGet (list) 0) -3) \" \""
        "         (optionOr (stringSlice \"hello\" 1 4) \"?\") \" \" (optionOr (stringSlice \"hello\" 1 2) \"?\") \" \" (optionOr (stringSlice \"hello\" 2 2) \"?\") \" \""
        "         (optionOr (stringSlice \"hello\" 3 9) \"?\") \" \" (optionOr (stringSlice \"\" 0 1) \"?\") \" \" (optionOr (stringSlice \"hello\" -1 2) \"?\") \" \""
        "         (mt (listHead xs) ((some h) h) ((none) 0)) \" \" (mt (listHead (list)) ((some h) h) ((none) -1)) \" \""
        "         (mt (listTail xs) ((some r) r) ((none) (list))) \" \" (mt (listTail (list)) ((some r) r) ((none) (list 7))) \" \""
        "         (getOf 5 -1)))"
        ""
        "fn partials -> String"
        "  (let [(p1 (partial add3 1)) (p2 (partial add3 1 2)) (p3 (partial add3 1 2 3)) (q (partial (fn [(a Int64) (b Int64)] -> Int64 (* a b)) 6))]"
        "    (str (p1 2 3) \" \" (p2 3) \" \" (p3) \" \" (q 7) \" \" (map p2 (list 10 20))))"
        ""
        "fn floats -> String"
        "  (let [(b (bytesAlloc 20))"
        "        (s0 (bytesSetFloat64 b 0 -0.0))"
        "        (s1 (bytesSetFloat64 b 1 (floatInf)))]"
        "    (str (bytesGetFloat64 b 0) \" \" (bytesGetFloat64 b 1) \" \" (bytesGet b 7) \" \" (bytesGet b 15) \" \" (bytesGet b 16) \" \" s0 s1))"
        ""
        "fn ! failing op: String -> String"
        "  (let [(b (bytesAlloc 20)) (h listHead) (t listTail) (e listEmpty?) (c cons) (bl bytesLength) (bg bytesGet) (bsf bytesSetFloat64) (bgf bytesGetFloat64)]"
        "    (cond ((= op \"getRange\") (str (bytesGet b 20)))"
        "          ((= op \"getNeg\") (str (bytesGet b -1)))"
        "          ((= op \"setRange\") (str (bytesSet b 20 1)))"
        "          ((= op \"setHigh\") (str (bytesSet b 0 256)))"
        "          ((= op \"setLow\") (str (bytesSet b 0 -1)))"
        "          ((= op \"setRangeHigh\") (str (bytesSet b 20 256)))"
        "          ((= op \"allocNeg\") (str (bytesAlloc -5)))"
        "          ((= op \"allocHuge\") (str (bytesAlloc 9223372036854775807)))"
        "          ((= op \"getF64Past\") (str (bytesGetFloat64 b 2)))"
        "          ((= op \"getF64LenMinus8\") (str (bytesGetFloat64 b 12)))"
        "          ((= op \"getF64LenMinus7\") (str (bytesGetFloat64 b 13)))"
        "          ((= op \"getF64Neg\") (str (bytesGetFloat64 b -1)))"
        "          ((= op \"setF64Past\") (str (bytesSetFloat64 b 2 1.0)))"
        "          ((= op \"setF64LenMinus8\") (str (bytesSetFloat64 b 12 1.0)))"
        "          ((= op \"setF64LenMinus7\") (str (bytesSetFloat64 b 13 1.0)))"
        "          ((= op \"setF64Neg\") (str (bytesSetFloat64 b -1 1.0)))"
        "          ((= op \"setF64Type\") (str (bsf b 0 1)))"
        "          ((= op \"getF64Type\") (str (bgf \"b\" 0)))"
        "          ((= op \"getF64IndexType\") (str (bgf b 0.5)))"
        "          ((= op \"headType\") (str (h 5)))"
        "          ((= op \"tailType\") (str (t \"x\")))"
        "          ((= op \"emptyType\") (str (e 5)))"
        "          ((= op \"consType\") (str (c 1 2)))"
        "          ((= op \"lengthType\") (str (bl 5)))"
        "          ((= op \"getType\") (str (bg 5 0)))"
        "          ((= op \"headOrType\") (str (headOf 5)))"
        "          ((= op \"tailOrType\") (str (tailOf \"x\")))"
        "          ((= op \"getOrType\") (str (getOf 5 0)))"
        "          ((= op \"sliceOrType\") (str (sliceOf 5)))"
        "          ((= op \"partialNone\") (str (partial)))"
        "          ((= op \"partialOver\") (str ((partial add3 1 2) 3 4)))"
        "          (else \"no such case\")))"
        ""
        "fn ! main args: (List String) -> (Result Int64 String)"
        "  (let [(op (optionOr (listHead args) \"\"))]"
        "    (do (println (cond ((= op \"direct\") (direct))"
        "                       ((= op \"values\") (values))"
        "                       ((= op \"fused\") (fused))"
        "                       ((= op \"partials\") (partials))"
        "                       ((= op \"floats\") (floats))"
        "                       ((= op \"big\") (stringFromInt64 (sumList (bigList) 0)))"
        "                       (else (failing op))))"
        "        (ok 0)))")

fn fixtureSrc -> String
  (str (stringJoin (fixtureLines) "\n") "\n\nfn bigList -> (List Int64)\n  (list "
       (stringJoin (map stringFromInt64 (range 0 (bigCount))) " ") ")\n")

fn deletedEntries -> (List String)
  (list "cons" "listHead" "listTail" "listEmpty" "bytesLength" "bytesAlloc" "bytesGet" "bytesSet"
        "listHeadOr" "listTailOr" "listGetOr" "stringSliceOr" "listFirst" "listRest")

fn groupNames -> (List (Pair String String))
  (list (pair "list" "list") (pair "listTail" "listTail") (pair "listHead" "listHead") (pair "listEmpty?" "listEmpty$3F") (pair "cons" "cons")
        (pair "bytesLength" "bytesLength") (pair "bytesAlloc" "bytesAlloc") (pair "bytesGet" "bytesGet") (pair "bytesSet" "bytesSet")
        (pair "bytesGetFloat64" "bytesGetFloat64") (pair "bytesSetFloat64" "bytesSetFloat64") (pair "partial" "partial"))

fn helperCalls -> (List String)
  (list "@listrt.headOr(" "@listrt.tailOr(" "@listrt.getOr(" "@listrt.sliceOr(" "@listrt.first(" "@listrt.rest(" "@listrt.cell("
        "@listrt.partialNone(" "@bytesrt.alloc(" "@bytesrt.getFloat64(" "@bytesrt.setFloat64(")

fn valueCases -> (List String)
  (list "direct" "values" "fused" "partials" "floats" "big")

fn failingCases -> (List String)
  (list "getRange" "getNeg" "setRange" "setHigh" "setLow" "setRangeHigh" "allocNeg" "allocHuge"
        "getF64Past" "getF64LenMinus8" "getF64LenMinus7" "getF64Neg" "setF64Past" "setF64LenMinus8" "setF64LenMinus7" "setF64Neg"
        "setF64Type" "getF64Type" "getF64IndexType" "headType" "tailType" "emptyType" "consType" "lengthType" "getType"
        "headOrType" "tailOrType" "getOrType" "sliceOrType" "partialNone")

fn occurrences text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

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
    (refute (listAny? (fn [(d String)] -> Bool (stringContains? d "@asl_rt_list(")) (llvm/runtimeDecls)) "runtimeDecls declares no asl_rt_list")
    true)

fn sourceDirs -> (List (Pair String (List String)))
  (list (pair "asl/packages/asl-target-llvm/src" (list ".asl"))
        (pair "asl/packages/asl-target-llvm/tests" (list ".asl"))
        (pair "asl/host/src" (list ".c" ".h")))

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
                         ((ok text) (listAppend acc (map (fn [(n String)] -> String (str f ": asl_rt_b_" n))
                                                         (filter (fn [(n String)] -> Bool (stringContains? text (str "asl_rt_b_" n))) (deletedEntries)))))))
                     (list) files))]
    (do
      (assert (> (listLength files) 60) (str "scans the package and the host runtime, got " (listLength files) " files"))
      (assert (listAny? (fn [(f String)] -> Bool (stringEndsWith? f "/abi.c")) files) "scans asl/host/src/abi.c")
      (assert (listEmpty? stale) (str "no source names a deleted entry; stale: " (stringJoin stale "; ")))
      true))

fn ! testIr dir: String code: String -> Bool
  (let [(ll (str dir "/listBytesFixture.ll"))]
    (do
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@asl_rt_b_" n "(")) (str "the IR neither declares nor calls asl_rt_b_" n))
                 true))
           (deletedEntries))
      (refute (stringContains? code "@asl_rt_list(") "the IR neither declares nor calls asl_rt_list")
      (map (fn [(p (Pair String String))] -> Bool
             (do (refute (stringContains? code (str "@asl_rt_builtin(ptr @name." (pairSecond p) ", i64 ")) (str "no asl_rt_builtin call names " (pairFirst p)))
                 true))
           (groupNames))
      (map (fn [(h String)] -> Bool
             (do (assert (stringContains? code (str "call %Val " h)) (str "the IR calls " h))
                 true))
           (helperCalls))
      (assert (stringContains? code "call void @ctorIdInit.partial()") "partial resolves the runtime's partial keyword for its Ctor")
      (refute (stringContains? code (str "alloca [" (bigCount) " x %Val]")) "the big literal has no argument array")
      (assert (>= (occurrences code "@listrt.cell(") (bigCount)) (str "the big literal is a chain of " (bigCount) " @listrt.cell conses"))
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (mt (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (processRun (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str "opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn valueSource name: String -> String
  (stringJoin (list "(module valueFixture :x [main] :i [])" ""
                    "fn ! main args: (List String) -> (Result Int64 String)"
                    (str "  (let [(f " name ")] (do (println (str (f 1))) (ok 0)))")) "\n")

fn ! testValuesRejected dir: String -> Bool
  (do
    (map (fn [(name String)] -> Bool
           (let [(src (str dir "/" name "Value.asl"))]
             (do (assert (ok? (fileWrite src (valueSource name))) (str "fileWrite " src))
                 (mt (compiled src)
                   ((ok _) (do (assert false (str name " as a value compiled")) true))
                   ((err e) (do (assert (stringContains? e (str "ERR_LOWER_UNKNOWN_SYMBOL")) (str name " as a value: " e))
                                (assert (stringContains? e (str "'" name "'")) (str name " as a value names it: " e))
                                true))))))
         (list "list" "partial"))
    true)

fn ! nativeExe dir: String -> String
  (let [(exe (str dir "/listBytesFixture"))
        (linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " dir "/listBytesFixture.ll -x none asl/host/out/libaslrt.a -lm -o " exe)))]
    (do (assert (= linked.exitCode 0) (str "listBytesFixture links against libaslrt.a: " linked.stderr))
        exe))

fn ! testValueParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (processRun (str (host) " run " src " " op)))]
    (do
      (assert (= interp.exitCode 0) (str op ": asl-host run exit " interp.exitCode "; stderr " interp.stderr))
      (assert (= native.exitCode 0) (str op ": native exit " native.exitCode "; stderr " native.stderr))
      (assert (= native.stdout interp.stdout) (str op ": native prints " native.stdout " and asl-host run " interp.stdout))
      (assert (= native.stderr "") (str op ": native stderr empty, got " native.stderr))
      true))

fn ! testFailingParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (processRun (str (host) " run " src " " op)))
        (line (stringReplace native.stderr "\n" ""))]
    (do
      (assert (= native.exitCode 1) (str op ": native exit " native.exitCode ", want 1; stderr " native.stderr))
      (assert (= native.exitCode interp.exitCode) (str op ": native exit equals asl-host run exit " interp.exitCode))
      (assert (stringStartsWith? line "ERR_") (str op ": native stderr is one error line: " native.stderr))
      (assert (= native.stderr (str line "\n")) (str op ": native stderr is a single line: " native.stderr))
      (assert (stringContains? interp.stderr (str ": " line " (after")) (str op ": asl-host run reports " line "; it reported " interp.stderr))
      (assert (= native.stdout interp.stdout) (str op ": native stdout equals asl-host run stdout"))
      true))

fn ! testOverApplied exe: String src: String -> Bool
  (let [(native (processRun (str exe " partialOver")))
        (interp (processRun (str (host) " run " src " partialOver")))]
    (do
      (assert (= native.exitCode 1) (str "partialOver: native exit " native.exitCode))
      (assert (= interp.exitCode 1) (str "partialOver: asl-host run exit " interp.exitCode))
      (assert (= native.stderr "ERR_ARITY: add3 expects 3 argument(s), got 4\n") (str "partialOver: native reports " native.stderr))
      (assert (stringContains? interp.stderr ": ERR_ARITY: add3 expects 3 argument(s), got 4 (after") (str "partialOver: asl-host run reports " interp.stderr))
      true))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (src (str dir "/listBytesFixture.asl"))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testRuntimeDecls)
      (testStaleNames)
      (testValuesRejected dir)
      (assert (ok? (fileWrite src (fixtureSrc))) (str "fileWrite " src))
      (mt (compiled src)
        ((err e) (do (assert false (str "listBytesFixture links and emits: " e)) true))
        ((ok code)
          (do
            (testIr dir code)
            (let [(exe (nativeExe dir))]
              (do
                (map (fn [(op String)] -> Bool (testValueParity exe src op)) (valueCases))
                (map (fn [(op String)] -> Bool (testFailingParity exe src op)) (failingCases))
                (testOverApplied exe src))))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
