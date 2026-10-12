(module asl-target-llvm/tests/coreTableGoneTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn runtime -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn tableRows text: String -> (List (Pair String Int64))
  (mt (stringIndexOf text "const Builtin coreBuiltins[] = {")
    ((none) (list))
    ((some start)
      (let [(body (optionOr (stringSlice text start (stringLength text)) ""))
            (table (optionOr (stringSlice body 0 (optionOr (stringIndexOf body "};") 0)) ""))]
        (map (fn [(p String)] -> (Pair String Int64)
               (pair (optionOr (listHead (stringSplit p "\"")) "")
                     (optionOr (stringToInt64 (optionOr (listGet (stringSplit p ", ") 2) "")) -9)))
             (listDrop (stringSplit table "{\"") 1)))))

fn cases -> (List (List String))
  (list (list "list" "1 2" "%%") (list "listTail" "(list 1 2)" "%%") (list "listHead" "(list 1 2)" "%%") (list "listEmpty?" "(list)" "%%")
        (list "cons" "0 (list 1)" "%%") (list "str" "\"a\" 1 2.5 :k" "%%") (list "stringLength" "\"abc\"" "%%") (list "stringConcat" "\"ab\" \"cd\"" "%%")
        (list "stringSlice" "\"abcd\" 1 3" "%%") (list "stringFromInt64" "-42" "%%") (list "stringFromFloat64" "1.5" "%%") (list "stringToFloat64" "\"2.25\"" "%%")
        (list "int64ToFloat64" "3" "%%") (list "float64ToInt64" "3.7" "%%") (list "floor" "2.5" "%%") (list "ceil" "2.5" "%%") (list "round" "2.5" "%%")
        (list "clamp" "0.0 3.0 5.0" "%%") (list "pow" "2.0 10.0" "%%") (list "exp" "1.0" "%%") (list "log" "2.0" "%%") (list "log2" "8.0" "%%") (list "log10" "1000.0" "%%")
        (list "sqrt" "2.0" "%%") (list "sin" "1.0" "%%") (list "cos" "1.0" "%%") (list "tan" "1.0" "%%") (list "atan2" "1.0 2.0" "%%")
        (list "fileWrite" "(str dir \"/w\") \"hello\"" "%%") (list "fileReadBytes" "(str dir \"/w\")" "(mt %% ((ok b) (list (bytesLength b) (bytesGet b 1))) ((err e) (list)))") (list "fileReadString" "(str dir \"/w\")" "%%")
        (list "realPath" "dir" "(ok? %%)") (list "zstdDecompress" "(stringToBytes \"x\")" "%%") (list "bytesSha256" "(stringToBytes \"abc\")" "%%")
        (list "bytesLength" "(stringToBytes \"abc\")" "%%") (list "stringStartsWith?" "\"abc\" \"ab\"" "%%") (list "stringContains?" "\"abc\" \"bc\"" "%%")
        (list "partial" "stringConcat \"a\"" "(%% \"b\")") (list "abs" "-3" "%%") (list "min" "1 2" "%%") (list "max" "1 2" "%%") (list "<<" "1 62" "%%") (list ">>" "-16 2" "%%")
        (list "trap" "\"ERR_RANGE\" \"boom\"" "%%") (list "print" "\"p\" 1" "%%") (list "println" "\"q\" 2" "%%") (list "eprintln" "\"e\" 3" "%%")
        (list "dirList" "dir" "%%") (list "fileStat" "(str dir \"/w\")" "(mt %% ((ok s) (list s.isFile s.isDir s.size)) ((err e) (list)))")
        (list "fileReadRange" "(str dir \"/w\") 1 3" "(mt %% ((ok b) (list (bytesLength b) (bytesGet b 0))) ((err e) (list)))") (list "processRun" "\"echo hi\"" "%%") (list "nowNs" "" "(> %% 0)") (list "monotonicNs" "" "(> %% 0)")
        (list "sleepMs" "1" "%%") (list "envGet" "\"HOME\"" "%%") (list "getHomeDir" "" "%%") (list "processSpawn" "\"echo s\"" "(ok? %%)")
        (list "processWait" "(optionOr (resultToOption (processSpawn \"echo w\")) 0) 5000" "%%") (list "fileCreateExclusive" "(str dir \"/x\") \"data\"" "(ok? %%)")
        (list "dirCreate" "(str dir \"/d\")" "(ok? %%)") (list "pathRemove" "(str dir \"/d\")" "(ok? %%)") (list "pathRename" "(str dir \"/x\") (str dir \"/y\")" "(ok? %%)")
        (list "fileChmod" "(str dir \"/w\") 420" "%%") (list "fileFsync" "(str dir \"/w\")" "%%") (list "pathSymlink" "\"w\" (str dir \"/l\")" "(ok? %%)")
        (list "fileReadlink" "(str dir \"/l\")" "%%") (list "fileLstat" "(str dir \"/l\")" "(ok? %%)") (list "fileUtime" "(str dir \"/w\") 1000000000000000000" "%%")
        (list "bytesAlloc" "3" "(bytesLength %%)") (list "bytesGet" "(stringToBytes \"abc\") 1" "%%") (list "bytesSet" "(bytesAlloc 2) 0 7" "%%")
        (list "bytesGetFloat64" "(bytesAlloc 8) 0" "%%") (list "bytesSetFloat64" "(bytesAlloc 8) 0 1.5" "%%") (list "stringToBytes" "\"ab\"" "(bytesGet %% 1)"))

fn caseName c: (List String) -> String
  (optionOr (listGet c 0) "")

fn caseField c: (List String) k: Int64 -> String
  (optionOr (listGet c k) "")

fn arityOf rows: (List (Pair String Int64)) name: String -> Int64
  (optionOr (mapGet (mapFromPairs rows) name) -9)

fn callText head: String operands: String -> String
  (if (stringEmpty? operands) (str "(" head ")") (str "(" head " " operands ")"))

fn caseFns rows: (List (Pair String Int64)) k: Int64 c: (List String) -> String
  (let [(name (caseName c)) (view (caseField c 2)) (operands (caseField c 1))]
    (str "fn ! d" k " dir: String -> T\n  " (stringReplace view "%%" (callText name operands)) "\n\n"
         (if (< (arityOf rows name) 0)
           ""
           (str "fn ! v" k " dir: String -> T\n  (let [(f " name ")] " (stringReplace view "%%" (callText "f" operands)) ")\n\n"))))

fn fixtureSrc rows: (List (Pair String Int64)) -> String
  (let [(numbered (enumerate (cases)))
        (shown (filter (fn [(p (Pair Int64 (List String)))] -> Bool (!= (caseName (pairSecond p)) "trap")) numbered))
        (trapK (fold (fn [(acc Int64) (p (Pair Int64 (List String)))] -> Int64 (if (= (caseName (pairSecond p)) "trap") (pairFirst p) acc)) -1 numbered))]
    (str "(module coreTable :x [main] :i [])\n\n"
         (stringJoin (map (fn [(p (Pair Int64 (List String)))] -> String (caseFns rows (pairFirst p) (pairSecond p))) numbered) "")
         "fn ! all dir: String -> Int64\n  (do\n"
         (stringJoin (map (fn [(p (Pair Int64 (List String)))] -> String
                            (let [(k (pairFirst p)) (name (caseName (pairSecond p)))]
                              (str "    (println \"" name "\" (d" k " dir)" (if (< (arityOf rows name) 0) "" (str " (v" k " dir)")) ")\n")))
                          shown) "")
         "    0)\n\n"
         "fn ! main args: (List String) -> (Result Int64 String)\n"
         "  (let [(op (optionOr (listGet args 0) \"\")) (dir (optionOr (listGet args 1) \".\"))]\n"
         "    (cond ((= op \"all\") (ok (all dir)))\n"
         "          ((= op \"trap\") (do (d" trapK " dir) (ok 1)))\n"
         "          ((= op \"trapValue\") (do (v" trapK " dir) (ok 1)))\n"
         "          (else (err (str \"no such op \" op)))))\n"))

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiled path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listHead known)
      ((some o) (some o))
      ((none) (if (= (sh "command -v opt >/dev/null 2>&1").exitCode 0) (some "opt") (none)))))

fn ! testTable rows: (List (Pair String Int64)) -> Bool
  (do (assert (> (listLength rows) 70) (str "prelude.c's coreBuiltins initializer yields its rows, got " (listLength rows)))
      (assert (= (listSort (map pairFirst rows)) (listSort (map caseName (cases)))) (str "the cases name prelude.c's coreBuiltins: " (stringJoin (map pairFirst rows) " ")))
      (assert (= (listLength (cases)) (listLength rows)) "one case per coreBuiltins row")
      true)

fn ! testIr dir: String code: String -> Bool
  (let [(ll (str dir "/coreTable.ll"))]
    (do
      (refute (listAny? (fn [(d String)] -> Bool (stringContains? d "@asl_rt_builtin(")) (llvm/runtimeDecls)) "runtimeDecls declares no asl_rt_builtin")
      (refute (stringContains? code "@asl_rt_builtin(") "the fixture IR neither declares nor calls asl_rt_builtin")
      (refute (stringContains? code "@asl_rt_b_") "the fixture IR calls no asl_rt_b_ ENTRY wrapper")
      (assert (stringContains? code "call %Val @mathrt.shiftLeft(") "<< calls its @mathrt helper")
      (assert (stringContains? code "define internal %Val @mkBytes(") "mkBytes is the module's own IR, not prelude.c's")
      (refute (stringContains? code "declare %Val @mkBytes(") "the module declares no prelude.c mkBytes")
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (mt (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (sh (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str "opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn ! nativeExe dir: String -> String
  (let [(exe (str dir "/coreTable"))
        (linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " dir "/coreTable.ll -x none " (runtime) " -lm -o " exe)))]
    (do (assert (= linked.exitCode 0) (str "the fixture links against libaslrt.a alone: " linked.stderr))
        exe))

fn ! freshDir root: String name: String -> String
  (let [(d (str root "/" name))]
    (do (assert (= (sh (str "mkdir " d)).exitCode 0) (str "mkdir " d)) d))

fn ! testRunParity exe: String src: String root: String -> Bool
  (let [(native (sh (str exe " all " (freshDir root "native"))))
        (again (sh (str exe " all " (freshDir root "nativeAgain"))))
        (nLines (stringLines native.stdout))
        (againLines (stringLines again.stdout))]
    (do
      (assert (= again.exitCode 0) (str "a second native all run exits 0; stderr " again.stderr))
      (assert (= native.exitCode 0) (str "native all exits 0; stderr " native.stderr))
      (assert (= (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) nLines)) (listLength (cases)))
              (str "native prints one line per case but trap, and println's own line, got " (listLength nLines)))
      (map (fn [(p (Pair String String))] -> Bool
             (do (assert (= (pairFirst p) (pairSecond p)) (str "native prints " (pairFirst p) " on one run and " (pairSecond p) " on another")) true))
           (zip nLines againLines))
      (assert (= native.stdout again.stdout) "native stdout is deterministic across runs")
      (assert (= native.stderr "e 3\n") (str "native stderr holds eprintln's line, got " native.stderr))
      (assert (= native.stderr again.stderr) (str "native stderr is deterministic across runs: " native.stderr " vs " again.stderr))
      true))

fn ! testTrapParity exe: String src: String op: String -> Bool
  (let [(native (sh (str exe " " op)))
        (again (sh (str exe " " op)))
        (line (stringReplace native.stderr "\n" ""))]
    (do
      (assert (= native.exitCode 1) (str op ": native exit " native.exitCode ", want 1; stderr " native.stderr))
      (assert (= native.exitCode again.exitCode) (str op ": native exit is deterministic across runs: " again.exitCode))
      (assert (= line "ERR_RANGE: boom") (str op ": native stderr is trap's line: " native.stderr))
      (assert (= native.stderr again.stderr) (str op ": native stderr is deterministic across runs: " native.stderr " vs " again.stderr))
      (assert (= native.stdout again.stdout) (str op ": native stdout is deterministic across runs"))
      true))

fn ! testVariadicValues root: String rows: (List (Pair String Int64)) -> Bool
  (do
    (map (fn [(r (Pair String Int64))] -> Bool
           (let [(src (str root "/variadic" (stringLength (pairFirst r)) (pairFirst r) ".asl"))]
             (do (assert (ok? (fileWrite src (str "(module variadicValue :x [main] :i [])\n\nfn main -> T\n  (let [(f " (pairFirst r) ")] (f 1))\n")))
                         (str "fileWrite " src))
                 (mt (compiled src)
                   ((ok code) (do (assert false (str (pairFirst r) " as a value emits IR: " (optionOr (stringSlice code 0 200) code))) true))
                   ((err e) (do (assert (stringContains? e (str "'" (pairFirst r) "'")) (str (pairFirst r) " as a value fails at build time naming it: " e)) true))))))
         (filter (fn [(r (Pair String Int64))] -> Bool (< (pairSecond r) 0)) rows))
    true)

fn memberOf line: String -> String
  (let [(open (optionOr (stringIndexOf line "[") -1)) (close (optionOr (stringIndexOf line "]") -1))]
    (if (and (>= open 0) (> close open)) (optionOr (stringSlice line (+ open 1) close) "") ""))

fn symbolOf line: String -> String
  (let [(fields (stringSplit (stringTrim (optionOr (listGet (stringSplit line "]: ") 1) "")) " "))
        (name (optionOr (listHead fields) ""))]
    (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name))

fn kindOf line: String -> String
  (optionOr (listGet (stringSplit (stringTrim (optionOr (listGet (stringSplit line "]: ") 1) "")) " ") 1) "")

fn ! archiveLines path: String -> (List String)
  (let [(listed (sh (str "nm -A -P " path)))]
    (do (assert (= listed.exitCode 0) (str "nm -A -P " path ": " listed.stderr))
        (filter (fn [(l String)] -> Bool (not (stringEmpty? (memberOf l)))) (stringLines listed.stdout))))

fn definedIn lines: (List String) member: String -> (List String)
  (map symbolOf (filter (fn [(l String)] -> Bool (and (= (memberOf l) member) (and (!= (kindOf l) "U") (not (stringEmpty? (kindOf l)))))) lines))

fn ! testArchive -> Bool
  (let [(rt (archiveLines (runtime)))
        (hostLines (archiveLines "asl/host/out/libaslhost.a"))
        (gone (listAppend (definedIn hostLines "prelude.o") (definedIn hostLines "zstd.o")))
        (members (fold (fn [(acc (List String)) (l String)] -> (List String) (if (listContains? acc (memberOf l)) acc (listAppend acc (list (memberOf l))))) (list) rt))
        (defined (filter (fn [(l String)] -> Bool (and (!= (kindOf l) "U") (not (stringEmpty? (kindOf l))))) rt))
        (refs (filter (fn [(l String)] -> Bool (and (= (kindOf l) "U") (listContains? gone (symbolOf l)))) rt))]
    (do
      (assert (> (listLength gone) 20) (str "libaslhost.a's prelude.o and zstd.o define their symbols, got " (listLength gone)))
      (assert (listContains? gone "coreBuiltins") "libaslhost.a's prelude.o defines coreBuiltins")
      (assert (listContains? members "rtAbi.o") (str "libaslrt.a holds rtAbi.o (abi.c ported to asl-target-llvm/rtAbi.asl, RT-ABI): " (stringJoin members " ")))
      (refute (listContains? members "prelude.o") (str "libaslrt.a holds no prelude.o: " (stringJoin members " ")))
      (refute (listContains? members "zstd.o") (str "libaslrt.a holds no zstd.o: " (stringJoin members " ")))
      (map (fn [(s String)] -> Bool
             (do (refute (listAny? (fn [(l String)] -> Bool (= (symbolOf l) s)) defined) (str "libaslrt.a defines no " s)) true))
           (list "coreBuiltins" "asl_rt_builtin" "bFileStat" "zstdDecompress"))
      (map (fn [(s String)] -> Bool
             (do (refute (listAny? (fn [(l String)] -> Bool (= (symbolOf l) s)) defined) (str "no libaslrt.a member defines " s " (strFloor.c is libaslhost.a's alone since RT-FLOOR)")) true))
           (list "bStringConcat" "bStringLength" "bStringSlice"))
      (assert (listEmpty? refs)
              (str "no libaslrt.a member refers to prelude.o or zstd.o (hostVerbLink.o, whose builtin chain did, left in NX4): " (stringJoin (map (fn [(l String)] -> String (str (memberOf l) " " (symbolOf l))) refs) "; ")))
      true))

fn ! testUnsupported root: String -> Bool
  (let [(src (str root "/unsupported.asl"))]
    (do
      (assert (ok? (fileWrite src "(module unsupported :x [main] :i [])\n\nfn main -> T\n  (fileReadString \"x\")\n")) (str "fileWrite " src))
      (mt (lk/linkEntry! src)
        ((err ds) (do (assert false (str "unsupported.asl links: " (formatDiags ds))) true))
        ((ok m) (mt (llvm/emitLlvmProgram m (str m.name ".main"))
                  ((ok code) (do (assert false (str "fileReadString without its route emits IR: " (optionOr (stringSlice code 0 200) code))) true))
                  ((err ds) (do (assert (listAny? (fn [(d irTy/IrDiag)] -> Bool (and (= d.code "ERR_LOWER_UNSUPPORTED") (stringContains? d.message "'fileReadString'"))) ds)
                                        (str "fileReadString without its route is ERR_LOWER_UNSUPPORTED naming it: " (formatDiags ds)))
                                true)))))
      (let [(fn1 (irTy/ssaFunction "named.main" (list) (list) (irTy/tyVal)
                   (list (irTy/ssaBlock "entry" (list) (list (irTy/ssaInstr "r" (irTy/tyVal) (irTy/opBuiltin "noNativeBuiltin" (list)))) (irTy/termReturn "r")))))
            (m (irTy/ssaModule "named" (list) (list) (list) (list) (list) (list fn1)))]
        (mt (llvm/emitLlvmModule m)
          ((ok code) (do (assert false "a builtin no table holds emits IR") true))
          ((err ds) (do (assert (listAny? (fn [(d irTy/IrDiag)] -> Bool (and (= d.code "ERR_LOWER_UNSUPPORTED") (and (stringContains? d.message "'noNativeBuiltin'") (= d.locus "named.main")))) ds)
                                (str "noNativeBuiltin is ERR_LOWER_UNSUPPORTED in named.main: " (formatDiags ds)))
                        true))))
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (root (stringReplace made.stdout "\n" ""))
        (src (str root "/coreTable.asl"))
        (rows (mt (fileReadString "asl/host/src/prelude.c") ((ok t) (tableRows t)) ((err e) (do (assert false (str "reads prelude.c: " e)) (list)))))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testTable rows)
      (testArchive)
      (assert (ok? (fileWrite src (fixtureSrc rows))) (str "fileWrite " src))
      (mt (compiled src)
        ((err e) (do (assert false (str "the core builtin fixture links and emits: " e)) true))
        ((ok code)
          (do
            (testIr root code)
            (let [(exe (nativeExe root))]
              (do
                (testRunParity exe src root)
                (testTrapParity exe src "trap")
                (testTrapParity exe src "trapValue")
                true)))))
      (testVariadicValues root rows)
      (testUnsupported root)
      (assert (= (sh (str "rm -rf " root)).exitCode 0) "work directory removed")
      true))
