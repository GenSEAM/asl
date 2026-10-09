(module asl-target-llvm/tests/parRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/parRoute :a pr)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/sysRoute :a rt)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (mt (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn casesSource -> String
  (lines (list
    "(module parCases :x [main] :i [])"
    ""
    "fn ! census -> String"
    "  (let [(me (procSelf))]"
    "    (processRun (str \"ps -A -o ppid= | awk '$1 == \" me \" {n++} END {print n+0}'; if [ -d /proc/\" me \"/fd ]; then ls /proc/\" me \"/fd | wc -l; else lsof -a -p \" me \" -d 0-65535 -F f | awk '/^f/ {n++} END {print n+0}'; fi\")).stdout)"
    ""
    "fn square x: Int64 -> Int64"
    "  (* x x)"
    ""
    "fn ! mapCase n: Int64 w: Int64 -> String"
    "  (let [(before (census))"
    "        (xs (range 0 n))"
    "        (got (parMap square xs w))"
    "        (after (census))]"
    "    (str \"map \" n \" \" w \" \" (listLength got) \" \" (= got (map square xs)) \" \" (if (<= n 7) (str got) \"\") \" clean \" (= before after)))"
    ""
    "fn ! foldCase n: Int64 w: Int64 -> String"
    "  (let [(before (census))"
    "        (xs (range 0 n))"
    "        (got (parFold (fn [(a String) (x Int64)] -> String (str a \".\" x)) (fn [(a String) (b String)] -> String (str a \"|\" b)) \"\" xs w))"
    "        (after (census))]"
    "    (str \"fold \" n \" \" w \" \" (stringLength got) \" \" (if (<= n 7) got (stringSlice got 0 40)) \" clean \" (= before after)))"
    ""
    "fn cases -> (List (Pair Int64 Int64))"
    "  (list (pair 0 1) (pair 0 2) (pair 0 64) (pair 1 1) (pair 1 2) (pair 1 64) (pair 7 1) (pair 7 2) (pair 7 64) (pair 10000 1) (pair 10000 2) (pair 10000 64))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (map (fn [(c (Pair Int64 Int64))] -> Unit (println (mapCase (pairFirst c) (pairSecond c)))) (cases))"
    "      (map (fn [(c (Pair Int64 Int64))] -> Unit (println (foldCase (pairFirst c) (pairSecond c)))) (cases))"
    "      (let [(me (procSelf))]"
    "        (println \"inParent\" (= (parMap (fn [(x Int64)] -> Int64 (procSelf)) (list 1 2 3) 3) (list me me me))))"
    "      (ok 0))"))

fn codecSource -> String
  (lines (list
    "(module parCodec :x [main] :i [])"
    ""
    "fn ! show label: String got: A want: A -> Unit"
    "  (println label (= got want) got)"
    ""
    "fn bits x: Float64 -> (List Int64)"
    "  (let [(b (bytesAlloc 8))]"
    "    (do (bytesSetFloat64 b 0 x)"
    "        (map (fn [(i Int64)] -> Int64 (bytesGet b i)) (range 0 8))))"
    ""
    "fn nanWithPayload k: Int64 -> Float64"
    "  (let [(b (bytesAlloc 8))]"
    "    (do (bytesSet b 0 k) (bytesSet b 6 248) (bytesSet b 7 127)"
    "        (bytesGetFloat64 b 0)))"
    ""
    "schema Deep"
    "  s: String"
    ""
    "schema Inner"
    "  kw: Keyword"
    "  xs: (List Float64)"
    "  deep: Deep"
    ""
    "schema Outer"
    "  name: String"
    "  inner: Inner"
    "  n: Int64"
    ""
    "fn record i: Int64 -> Outer"
    "  (Outer :name (str \"rec\" i) :inner (Inner :kw :inner :xs (list 1.5 (* -2.25 (int64ToFloat64 i))) :deep (Deep :s \"ü\")) :n (- 0 i))"
    ""
    "fn ctor i: Int64 -> (Option (Result (List Int64) String))"
    "  (cond ((= i 0) (none)) ((= i 1) (some (ok (list i 2 3)))) (else (some (err \"bad\"))))"
    ""
    "fn keyword i: Int64 -> Keyword"
    "  (if (= i 0) :alpha (if (= i 1) :beta :gamma))"
    ""
    "fn text i: Int64 -> String"
    "  (str \"héllo wörld 漢字 𝄞 \" i)"
    ""
    "fn bytes i: Int64 -> Bytes"
    "  (let [(b (bytesAlloc (+ i 3)))]"
    "    (do (bytesSet b 0 0) (bytesSet b 1 255) (bytesSet b 2 i) b))"
    ""
    "fn floats i: Int64 -> F64Array"
    "  (f64ArrayGenerate (+ i 2) (fn [(j Int64)] -> Float64 (* 1.25 (int64ToFloat64 (- j i)))))"
    ""
    "fn ints i: Int64 -> I64Array"
    "  (i64ArrayGenerate (+ i 2) (fn [(j Int64)] -> Int64 (if (= j 0) -9223372036854775807 (* j 1000000007))))"
    ""
    "fn bytes8 i: Int64 -> I8Array"
    "  (i8ArrayGenerate (+ i 2) (fn [(j Int64)] -> Int64 (- j 128)))"
    ""
    "fn scalars i: Int64 -> (List Int64)"
    "  (list i 9223372036854775807 -9223372036854775807 0)"
    ""
    "fn f64List a: F64Array -> (List Float64)"
    "  (map (fn [(j Int64)] -> Float64 (f64ArrayGet a j)) (range 0 (f64ArrayLen a)))"
    ""
    "fn i64List a: I64Array -> (List Int64)"
    "  (map (fn [(j Int64)] -> Int64 (i64ArrayGet a j)) (range 0 (i64ArrayLen a)))"
    ""
    "fn i8List a: I8Array -> (List Int64)"
    "  (map (fn [(j Int64)] -> Int64 (i8ArrayGet a j)) (range 0 (i8ArrayLen a)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(xs (list 0 1 2))]"
    "    (do (show \"record\" (parMap record xs 2) (map record xs))"
    "        (show \"ctor\" (parMap ctor xs 3) (map ctor xs))"
    "        (show \"keyword\" (parMap keyword xs 2) (map keyword xs))"
    "        (show \"text\" (parMap text xs 2) (map text xs))"
    "        (show \"bytes\" (map bytesToBase64 (parMap bytes xs 2)) (map bytesToBase64 (map bytes xs)))"
    "        (show \"f64\" (map f64List (parMap floats xs 2))"
    "                    (map f64List (map floats xs)))"
    "        (show \"i64\" (map i64List (parMap ints xs 2))"
    "                    (map i64List (map ints xs)))"
    "        (show \"i8\" (map i8List (parMap bytes8 xs 2))"
    "                   (map i8List (map bytes8 xs)))"
    "        (show \"scalars\" (parMap scalars xs 2) (map scalars xs))"
    "        (show \"negzero\" (map bits (parMap (fn [(i Int64)] -> Float64 (* -0.0 (int64ToFloat64 (+ i 1)))) xs 2)) (map bits (map (fn [(i Int64)] -> Float64 (* -0.0 (int64ToFloat64 (+ i 1)))) xs)))"
    "        (show \"nan\" (map bits (parMap nanWithPayload xs 2)) (map bits (map nanWithPayload xs)))"
    "        (show \"misc\" (parMap (fn [(i Int64)] -> (List (Pair Bool String)) (list (pair (= i 1) \"\") (pair true (str ())))) xs 2) (map (fn [(i Int64)] -> (List (Pair Bool String)) (list (pair (= i 1) \"\") (pair true (str ())))) xs))"
    "        (show \"unit\" (parMap (fn [(i Int64)] -> Unit ()) xs 2) (map (fn [(i Int64)] -> Unit ()) xs))"
    "        (show \"nested\" (parMap (fn [(i Int64)] -> (List (List (List Int64))) (list (list (list i)) (list))) xs 2) (map (fn [(i Int64)] -> (List (List (List Int64))) (list (list (list i)) (list))) xs))"
    "        (ok 0)))"))

fn failSource -> String
  (lines (list
    "(module parFail :x [main] :i [])"
    ""
    "fn ! mark pidFile: String x: Int64 -> Int64"
    "  (do (fileAppend pidFile (str \"pid \" (procSelf) \"\\n\")) x)"
    ""
    "fn ! spin n: Int64 acc: Int64 -> Int64"
    "  (if (= n 0) acc (spin (- n 1) (+ acc (/ n 3))))"
    ""
    "fn ! waitUntil t: Int64 -> Int64"
    "  (if (>= (monotonicNs) t) t (waitUntil t))"
    ""
    "fn ! element mode: String pidFile: String x: Int64 -> Int64"
    "  (let [(_ (mark pidFile x))]"
    "    (cond ((= mode \"stall\") (if (= x 0) (/ 1 x) (do (waitUntil (+ (monotonicNs) 10000000000)) x)))"
    "          ((and (= mode \"trap\") (= x 5)) (/ 1 (- x 5)))"
    "          ((and (= mode \"long\") (= x 5)) (do (trap \"ERR_ARG\" (stringRepeat \"y\" 2000)) x))"
    "          ((and (= mode \"kill\") (= x 5)) (do (procKill (procSelf) \"SIGKILL\") x))"
    "          (else (+ x (/ (spin 3000000 0) 1000000000000)))))"
    ""
    "fn ! run mode: String pidFile: String -> String"
    "  (cond ((or (= mode \"trap\") (= mode \"kill\") (= mode \"stall\")) (str (parMap (fn [(x Int64)] -> Int64 (element mode pidFile x)) (range 0 9) 3)))"
    "        ((= mode \"foldTrap\") (str (parFold (fn [(a Int64) (x Int64)] -> Int64 (+ a (element \"trap\" pidFile x))) (fn [(a Int64) (b Int64)] -> Int64 (- a b)) 0 (range 0 9) 3)))"
    "        ((= mode \"longTrap\") (str (parMap (fn [(x Int64)] -> Int64 (element \"long\" pidFile x)) (range 0 9) 3)))"
    "        ((= mode \"foldLong\") (str (parFold (fn [(a Int64) (x Int64)] -> Int64 (+ a (element \"long\" pidFile x))) (fn [(a Int64) (b Int64)] -> Int64 (- a b)) 0 (range 0 9) 3)))"
    "        ((= mode \"unserializable\") (str (listLength (parMap (fn [(x Int64)] -> (List (fn [Int64] -> Int64)) (if (= (mark pidFile x) 2) (list (fn [(y Int64)] -> Int64 (+ x y))) (list))) (range 0 4) 2))))"
    "        ((= mode \"childBig\") (str (listLength (parMap (fn [(x Int64)] -> String (if (= (mark pidFile x) 1) (stringRepeat \"x\" (- 67108864 8)) \"y\")) (list 0 1) 2))))"
    "        ((= mode \"parentBig\") (str (listLength (parMap (fn [(x Int64)] -> String (if (= (mark pidFile x) 1) (stringRepeat \"x\" (- 67108864 9)) \"y\")) (list 0 1) 2))))"
    "        ((= mode \"fitBig\") (str (map stringLength (parMap (fn [(x Int64)] -> String (if (= (mark pidFile x) 1) (stringRepeat \"x\" (- 67108864 18)) \"y\")) (list 0 1) 2))))"
    "        ((= mode \"big\") (str (map stringLength (parMap (fn [(x Int64)] -> String (stringRepeat \"x\" (* (mark pidFile x) 16777216))) (range 0 3) 3))))"
    "        ((= mode \"slots\") (str (parMap (fn [(x Int64)] -> Int64 (mark pidFile x)) (range 0 3) 0)))"
    "        (else (str \"unknown mode \" mode)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println \"start\")"
    "      (println (run (optionOr (listGet args (- (listLength args) 2)) \"\") (optionOr (listLast args) \"\")))"
    "      (ok 0))"))

fn aritySource -> String
  (lines (list
    "(module parArity :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println \"map2\" (parMap (fn [(x Int64)] -> Int64 (* x 3)) (range 0 20)))"
    "      (println \"fold4\" (parFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 7 (range 0 1000)))"
    "      (println \"fold4 empty\" (parFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 7 (list)))"
    "      (ok 0))"))

fn ! lowered name: String src: String -> (Option ty/SsaModule)
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (mt (lk/lowerSourceWith src preludeText)
          ((err ds) (do (assert false (str name ": lowerSourceWith: " (diagText ds))) (none)))
          ((ok m) (some m)))))

fn ! build work: String name: String hostSrc: String nativeSrc: String -> String
  (let [(_ (assert (ok? (fileWrite (str work "/" name ".asl") hostSrc)) (str name ".asl written")))]
    (mt (lowered name nativeSrc)
      ((none) "")
      ((some m)
        (mt (llvm/emitLlvmProgramFor (hostFacts) m "main")
          ((err ds) (do (assert false (str name ": emitLlvmProgramFor: " (diagText ds))) ""))
          ((ok text) (do (assert (ok? (fileWrite (str work "/" name ".ll") text)) (str name ".ll written")) text))))))

fn ! linkBin work: String name: String -> Bool
  (let [(out (sh (str (clang) " -x ir " work "/" name ".ll -x none " (lib) " -lm -o " work "/" name)))]
    (do (assert (= out.exitCode 0) (str name ": links against libaslrt.a; " out.stderr))
        (= out.exitCode 0)))

fn wrapperDef name: String argc: Int64 -> String
  (str "define internal tailcc %Val @" (ssa/llvmName (str "asl-target-llvm/parallel." name "/" argc)) "(")

fn ! checkIr label: String ll: String used: (List (Pair String Int64)) -> Bool
  (do (assert (not (stringEmpty? ll)) (str label ": IR emitted"))
      (assert (not (stringContains? ll "@asl_rt_builtin_parallel(")) (str label ": no call or declare of asl_rt_builtin_parallel is emitted"))
      (assert (stringContains? ll "\ndeclare i32 @setjmp(ptr) returns_twice\n") (str label ": setjmp is declared returns_twice, so optimised builds keep the worker's catch state across longjmp"))
      (map (fn [(u (Pair String Int64))] -> Bool
             (do (assert (stringContains? ll (wrapperDef (pairFirst u) (pairSecond u))) (str label ": IR defines the " (pairFirst u) "/" (pairSecond u) " wrapper internal")) true))
           used)
      true)

fn ! nmNames bin: String -> (List String)
  (let [(out (sh (str "nm -P " bin)))]
    (do (assert (= out.exitCode 0) (str "nm -P " bin ": " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listHead (stringSplit line " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringSplit out.stdout "\n")))))

fn ! checkSymbols label: String bin: String forbidden: (List String) -> Bool
  (let [(names (nmNames bin))
        (found (filter (fn [(n String)] -> Bool (listContains? forbidden n)) names))]
    (do (assert (> (listLength names) 0) (str label ": nm -P lists symbols"))
        (assert (listEmpty? found) (str label ": no C symbol of " forbidden " is linked: " found))
        true))

fn ! hostError stderr: String path: String -> String
  (let [(prefix (str "FAIL " path ": "))]
    (mt (stringIndexOf stderr prefix)
      ((none) "")
      ((some i) (let [(rest (optionOr (stringSlice stderr (+ i (stringLength prefix)) (stringLength stderr)) ""))]
                  (mt (stringIndexOf rest " (after") ((none) rest) ((some j) (optionOr (stringSlice rest 0 j) "")))))))

fn otherLines text: String -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit text "\n")) "\n")

fn pidsOf text: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (stringSlice l 4 (stringLength l)) ""))
       (filter (fn [(l String)] -> Bool (stringStartsWith? l "pid ")) (stringSplit text "\n")))

fn ! checkParity label: String env: String bin: String src: String args: String -> (Pair ProcessOutput ProcessOutput)
  (let [(native (sh (str env bin " " args)))
        (vm (sh (str env (host) " run " src " " args)))]
    (do (assert (= native.stdout vm.stdout) (str label ": native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout " vm stderr=" (otherLines vm.stderr)))
        (assert (= native.exitCode vm.exitCode) (str label ": native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " (otherLines native.stderr)))
        (assert (= (otherLines native.stderr) (hostError vm.stderr src)) (str label ": native stderr '" (otherLines native.stderr) "' is asl-host run's error '" (hostError vm.stderr src) "'"))
        (pair native vm)))

fn ! pidLines path: String -> (List String)
  (pidsOf (resultOr (fileRead path) ""))

fn ! checkGone label: String pids: (List String) -> Bool
  (let [(alive (filter (fn [(p String)] -> Bool (= (sh (str "kill -0 " p " 2>/dev/null")).exitCode 0)) pids))]
    (do (assert (listEmpty? alive) (str label ": no worker outlives its run: " alive))
        (listEmpty? alive)))

fn cTableNames -> (List String)
  (list "asl_rt_builtin_parallel" "bParMap" "bParFold" "serVal" "mkArray")

fn ! testCases work: String -> Bool
  (let [(ll (build work "parCases" (casesSource) (casesSource)))
        (_ (checkIr "parCases" ll (list (pair "parMap" 3) (pair "parFold" 5))))
        (linked (linkBin work "parCases"))
        (_ (checkSymbols "parCases" (str work "/parCases") (cTableNames)))
        (forked (checkParity "parCases" "" (str work "/parCases") (str work "/parCases.asl") ""))
        (fallback (checkParity "parCases fallback" "ASL_PAR_FORCE_FALLBACK=1 " (str work "/parCases") (str work "/parCases.asl") ""))
        (out (pairFirst forked).stdout)
        (outLines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit out "\n")))]
    (do (assert linked "parCases links")
        (assert (= (listLength outLines) 25) (str "parCases prints 24 cases and inParent: " out))
        (assert (= (listLength (filter (fn [(l String)] -> Bool (stringEndsWith? l " clean true")) outLines)) 24) (str "parCases: every case leaves children and fds as it found them: " out))
        (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "map ")) outLines)) 12) "parCases: 12 parMap cases")
        (assert (listAll? (fn [(l String)] -> Bool (or (not (stringStartsWith? l "map ")) (stringContains? l " true "))) outLines) (str "parCases: every parMap result equals map's: " out))
        (assert (stringContains? out "fold 7 2 15 .0.1.2|.3.4.5.6 clean true") (str "parCases: parFold over 7 with 2 workers combines the chunks in order: " out))
        (assert (stringEndsWith? out "inParent false\n") "parCases: the workers are child processes")
        (assert (stringEndsWith? (pairFirst fallback).stdout "inParent true\n") "parCases fallback: ASL_PAR_FORCE_FALLBACK=1 runs every element in the caller")
        (assert (stringContains? (pairFirst fallback).stdout "fold 7 2 14 .0.1.2.3.4.5.6 clean true") "parCases fallback: the fallback folds in one pass")
        true))

fn ! testCodec work: String -> Bool
  (let [(ll (build work "parCodec" (codecSource) (codecSource)))
        (_ (checkIr "parCodec" ll (list (pair "parMap" 3))))
        (linked (linkBin work "parCodec"))
        (_ (checkSymbols "parCodec" (str work "/parCodec") (list "asl_rt_builtin_parallel" "bParMap" "bParFold" "serVal")))
        (outs (checkParity "parCodec" "" (str work "/parCodec") (str work "/parCodec.asl") ""))
        (outLines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit (pairFirst outs).stdout "\n")))]
    (do (assert linked "parCodec links")
        (assert (= (listLength outLines) 14) (str "parCodec prints 14 kinds: " (pairFirst outs).stdout))
        (assert (listAll? (fn [(l String)] -> Bool (stringContains? l " true ")) outLines) (str "parCodec: every kind equals map's: " (pairFirst outs).stdout))
        true))

fn failModes -> (List (Pair String String))
  (list (pair "trap" "ERR_WORKER_TRAP: parMap element 5: ERR_DIV_ZERO: division by zero")
        (pair "foldTrap" "ERR_WORKER_TRAP: ERR_DIV_ZERO: division by zero")
        (pair "longTrap" (str "ERR_WORKER_TRAP: parMap element 5: ERR_ARG: " (stringRepeat "y" 991)))
        (pair "foldLong" (str "ERR_WORKER_TRAP: ERR_ARG: " (stringRepeat "y" 1010)))
        (pair "kill" "ERR_WORKER_TRAP: worker 1 killed by signal 9")
        (pair "stall" "ERR_WORKER_TRAP: parMap element 0: ERR_DIV_ZERO: division by zero")
        (pair "unserializable" "ERR_WORKER_TRAP: parMap element 2: ERR_NOT_SERIALIZABLE: cannot serialize parMap result across worker process")
        (pair "childBig" "ERR_WORKER_TRAP: parMap element 1: ERR_SERIALIZE_SIZE: parMap worker result exceeds serialization size limit")
        (pair "parentBig" "ERR_SERIALIZE_SIZE: worker 1 response exceeds serialization size limit")
        (pair "fitBig" "")
        (pair "big" "")
        (pair "slots" "ERR_ARG: parMap slots must be positive, got 0"))

fn ! testFail work: String -> Bool
  (let [(ll (build work "parFail" (failSource) (failSource)))
        (_ (checkIr "parFail" ll (list (pair "parMap" 3) (pair "parFold" 5))))
        (linked (linkBin work "parFail"))
        (bin (str work "/parFail"))
        (src (str work "/parFail.asl"))
        (_ (checkSymbols "parFail" bin (cTableNames)))]
    (do (assert linked "parFail links")
        (map (fn [(m (Pair String String))] -> Bool
               (let [(pidFile (str work "/" (pairFirst m) ".pids"))
                     (outs (checkParity (str "parFail " (pairFirst m)) "" bin src (str (pairFirst m) " " pidFile)))
                     (pids (pidLines pidFile))]
                 (do (assert (= (otherLines (pairFirst outs).stderr) (pairSecond m)) (str "parFail " (pairFirst m) ": native error is '" (pairSecond m) "': " (otherLines (pairFirst outs).stderr)))
                     (assert (= (pairFirst outs).exitCode (if (stringEmpty? (pairSecond m)) 0 1)) (str "parFail " (pairFirst m) ": exit " (pairFirst outs).exitCode))
                     (assert (= (listEmpty? pids) (= (pairFirst m) "slots")) (str "parFail " (pairFirst m) ": the elements report their pids (none for slots, which runs none): " pids))
                     (checkGone (str "parFail " (pairFirst m)) pids))))
             (failModes))
        (let [(stallPids (pidLines (str work "/stall.pids")))]
          (assert (<= (listLength stallPids) 6) (str "parFail stall: once worker 0 fails, killOthers sends SIGTERM to workers 1 and 2 during their first 10 s element, so each run marks at most 3 elements (7 each without it): " stallPids)))
        (let [(trapFile (str work "/trapFallback.pids"))
              (trap (checkParity "parFail trap fallback" "ASL_PAR_FORCE_FALLBACK=1 " bin src (str "trap " trapFile)))
              (fold (checkParity "parFail foldTrap fallback" "ASL_PAR_FORCE_FALLBACK=1 " bin src (str "foldTrap " work "/foldFallback.pids")))
              (pids (pidLines trapFile))
              (native (listTake pids 6))
              (vm (listDrop pids 6))]
          (do (assert (= (otherLines (pairFirst trap).stderr) "ERR_WORKER_TRAP: parMap element 5: ERR_DIV_ZERO: division by zero") (str "parFail trap fallback: " (pairFirst trap).stderr))
              (assert (= (otherLines (pairFirst fold).stderr) "ERR_DIV_ZERO: division by zero") (str "parFail foldTrap fallback: " (pairFirst fold).stderr))
              (assert (= (listLength pids) 12) (str "parFail trap fallback: each run reaches elements 0 to 5: " pids))
              (assert (listAll? (fn [(p String)] -> Bool (= (some p) (listHead native))) native) (str "parFail trap fallback: the native run maps every element in the one process: " native))
              (assert (listAll? (fn [(p String)] -> Bool (= (some p) (listHead vm))) vm) (str "parFail trap fallback: asl-host maps every element in the one process: " vm))
              true))))

fn ! testArity work: String -> Bool
  (let [(ll (build work "parArity" (aritySource) (aritySource)))
        (_ (checkIr "parArity" ll (list (pair "parMap" 2) (pair "parFold" 4))))
        (linked (linkBin work "parArity"))
        (outs (checkParity "parArity" "" (str work "/parArity") (str work "/parArity.asl") ""))]
    (do (assert linked "parArity links")
        (assert (stringContains? (pairFirst outs).stdout "fold4 empty 7") (str "parArity: " (pairFirst outs).stdout))
        true))

fn ! testArchive -> Bool
  (let [(out (sh (str "nm -P -A " (lib))))
        (members (filter (fn [(l String)] -> Bool (stringContains? l "[parallel.o]")) (stringSplit out.stdout "\n")))]
    (do (assert (= out.exitCode 0) (str "nm -P -A " (lib) ": " out.stderr))
        (assert (stringContains? out.stdout "[abi.o]") "nm -P -A lists libaslrt.a's members")
        (assert (listEmpty? members) (str "libaslrt.a has no parallel.o member: " (listTake members 3)))
        true))

fn ! testRouteModule work: String -> Bool
  (mt (lowered "plain" "(module plain :x [main] :i [])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (do (println (map (fn [(x Int64)] -> Int64 (+ x 1)) (list 1 2))) (ok 0))\n")
    ((none) false)
    ((some m)
      (let [(routed (pr/routeModule (hostFacts) m))
            (text "declare ptr @aslParWord0(%Val)\ndeclare ptr @aslParWord1(%Val)\n")
            (cut (pr/finishText true (ok text)))
            (unrouted (pr/finishText false (ok text)))
            (plainText (pr/finishText true (ok "define i64 @f() {\n  ret i64 0\n}")))]
        (do (assert (mt routed ((ok r) (and (= r.result m) (listEmpty? r.internal))) ((err _) false)) "routeModule leaves a module without parMap or parFold unchanged")
            (assert (mt cut ((ok _) false) ((err ds) (= (map (fn [(d ty/IrDiag)] -> String d.code) ds) (list "ERR_LLVM_PARROUTE_TEXT")))) "finishText rejects routed text without every helper declaration")
            (assert (= unrouted (ok text)) "finishText leaves the text of a module it did not route unchanged, whatever it holds")
            (assert (pr/routedNames? (list "main" "asl-target-llvm/parallel.serVal")) "routedNames? sees a parallel function among the internal names")
            (refute (pr/routedNames? (list "main" "asl-target-llvm/sysRoute.fdRead")) "routedNames? ignores names other routings made internal")
            (assert (mt plainText ((ok _) false) ((err ds) (= (map (fn [(d ty/IrDiag)] -> String d.code) ds) (list "ERR_LLVM_PARROUTE_TEXT")))) "finishText rejects routed text that declares no helper")
            true))))

fn litSource routed: Bool -> String
  (lines (list
    "(module parLiteral :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println \"declare ptr @aslParWord0(%Val)\")"
    "      (println \"declare i32 @setjmp(ptr)\")"
    "      (println (stringLength \"call ptr @aslParWord0(%Val %v)\"))"
    (if routed "      (println (parMap (fn [(x Int64)] -> String (str \"@aslParWord0(\" x)) (list 1 2) 2))" "      (println \"unrouted\")")
    "      (ok 0))"))

fn ! testLiteral work: String -> Bool
  (do (map (fn [(routed Bool)] -> Bool
             (let [(name (if routed "parLiteralRouted" "parLiteral"))
                   (ll (build work name (litSource routed) (litSource routed)))
                   (_ (assert (not (stringEmpty? ll)) (str name ": IR emitted")))
                   (_ (assert (= (stringContains? ll (wrapperDef "parMap" 3)) routed) (str name ": the parMap wrapper is defined exactly when the program calls parMap")))
                   (_ (assert (= (stringContains? ll "define internal ptr @aslParWord0(%Val %v)") routed) (str name ": the helper definitions are written exactly when the module was routed")))
                   (linked (linkBin work name))
                   (outs (checkParity name "" (str work "/" name) (str work "/" name ".asl") ""))]
               (do (assert linked (str name " links"))
                   (assert (stringStartsWith? (pairFirst outs).stdout "declare ptr @aslParWord0(%Val)\n") (str name ": prints its literals: " (pairFirst outs).stdout))
                   true)))
           (list false true))
      true)

fn wireStandIn -> String
  "wireDump"

fn wireDumpFn f: ty/SsaFunction -> ty/SsaFunction
  (let [(v (mt (listHead f.params) ((some p) p.name) ((none) "")))
        (c (fn [(d String) (n Int64)] -> ty/SsaInstr (ty/ssaInstr d (ty/tyI64) (ty/opConst (ty/constInt n)))))
        (p (fn [(d String) (t ty/SsaTy) (name String) (args (List String))] -> ty/SsaInstr (ty/ssaInstr d t (ty/opPrim name args))))
        (call (fn [(d String) (t ty/SsaTy) (name String) (args (List String))] -> ty/SsaInstr (ty/ssaInstr d t (ty/opCall name args))))]
    (ty/ssaFunction f.name f.captures f.params f.retTy
      (list (ty/ssaBlock "entry" (list)
              (list (c "one" 1) (c "size" 48) (call "sb" (ty/tyPtr) "calloc" (list "one" "size")) (p "sbI" (ty/tyI64) "rawPtrToInt" (list "sb")) (c "z" 0)
                    (call "w" (ty/tyI64) "asl-target-llvm/parallel.serVal" (list "sbI" v "z"))
                    (c "o0" 0) (p "data" (ty/tyI64) "rawLoadI64" (list "sb" "o0")) (c "o8" 8) (p "len" (ty/tyI64) "rawLoadI64" (list "sb" "o8"))
                    (c "o24" 24) (p "err" (ty/tyI64) "rawLoadI64" (list "sb" "o24")) (c "o32" 32) (p "s1" (ty/tyI1) "rawStoreI64" (list "sb" "o32" "err"))
                    (c "o40" 40) (p "s2" (ty/tyI1) "rawStoreI64" (list "sb" "o40" "len")) (p "hdrI" (ty/tyI64) "rawAddI64" (list "sbI" "o32")) (p "hdr" (ty/tyPtr) "rawIntToPtr" (list "hdrI"))
                    (ty/ssaInstr "fd" (ty/tyI32) (ty/opConst (ty/constInt 1))) (c "sixteen" 16) (call "wh" (ty/tyI64) "write" (list "fd" "hdr" "sixteen"))
                    (p "dataP" (ty/tyPtr) "rawIntToPtr" (list "data")) (call "wd" (ty/tyI64) "write" (list "fd" "dataP" "len"))
                    (call "f1" (ty/tyI64) "free" (list "dataP")) (call "f2" (ty/tyI64) "free" (list "sb")) (ty/ssaInstr "u" (ty/tyVal) (ty/opConst (ty/constUnit))))
              (ty/termReturn "u")))))

fn ! testWire work: String -> Bool
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))
        (_ (assert (ok? (fileWrite (str work "/wireCheck.c") (wireCheckSource))) "wireCheck.c written"))
        (cc (sh (str "/usr/bin/cc -std=c11 -D_DEFAULT_SOURCE -D_DARWIN_C_SOURCE -Iasl/host/src " work "/wireCheck.c " (lib) " asl/host/out/libaslhost.a -lm -o " work "/wireCheck")))
        (_ (assert (= cc.exitCode 0) (str "wireCheck compiles over parallel.c: " cc.stderr)))]
    (mt (mt (lk/lowerSourceWith (wireSource) preludeText) ((err ds) (err ds)) ((ok m0) (ar/routeModule m0)))
      ((err ds) (do (assert false (str "parWire: lowerSourceWith and arrayRoute: " (diagText ds))) false))
      ((ok arrays)
        (mt (pr/routeModule (hostFacts) arrays.result)
          ((err ds) (do (assert false (str "parWire: routeModule: " (diagText ds))) false))
          ((ok r)
            (let [(routed r.result)
                  (_ (assert (listAny? (fn [(f ty/SsaFunction)] -> Bool (= f.name (wireStandIn))) routed.functions) "parWire: the wireDump stand-in is lowered"))
                  (withDump (ty/ssaModule routed.name routed.strings routed.types routed.records routed.externs routed.globals
                              (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (if (= f.name (wireStandIn)) (wireDumpFn f) f)) routed.functions)))
                  (text (rt/internalize (ar/finishText (ar/routedNames? arrays.internal) (pr/finishText (pr/routedNames? r.internal) (ssa/emitLlvmProgram withDump "main"))) (listAppend arrays.internal r.internal)))]
              (mt text
                ((err ds) (do (assert false (str "parWire: emit: " (diagText ds))) false))
                ((ok ll)
                  (let [(_ (assert (ok? (fileWrite (str work "/parWire.ll") ll)) "parWire.ll written"))
                        (linked (linkBin work "parWire"))
                        (ran (sh (str work "/parWire > " work "/parWire.frames")))
                        (checked (sh (str work "/wireCheck < " work "/parWire.frames")))]
                    (do (assert linked "parWire links")
                        (assert (= ran.exitCode 0) (str "parWire runs: " ran.stderr))
                        (assert (= checked.exitCode 0) (str "parallel.c takes and re-encodes every native frame byte for byte: " checked.stdout checked.stderr))
                        (assert (= checked.stdout "frames 24 equal\n") (str "wireCheck checks all 24 frames: " checked.stdout))
                        true))))))))))

fn wireSource -> String
  (lines (list
    "(module parWire :x [main] :i [])"
    ""
    "schema Deep"
    "  s: String"
    ""
    "schema Inner"
    "  kw: Keyword"
    "  xs: (List Float64)"
    "  deep: Deep"
    ""
    "schema Outer"
    "  name: String"
    "  inner: Inner"
    "  n: Int64"
    ""
    "fn nanWithPayload k: Int64 -> Float64"
    "  (let [(b (bytesAlloc 8))]"
    "    (do (bytesSet b 0 k) (bytesSet b 6 248) (bytesSet b 7 127)"
    "        (bytesGetFloat64 b 0)))"
    ""
    "fn bytesOf i: Int64 -> Bytes"
    "  (let [(b (bytesAlloc (+ i 3)))]"
    "    (do (bytesSet b 0 0) (bytesSet b 1 255) (bytesSet b 2 i) b))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(n (listLength (parMap (fn [(x Int64)] -> Int64 (* x x)) (list 1 2 3) 2)))]"
    "    (do (wireDump n)"
    "        (wireDump (Outer :name \"rec\" :inner (Inner :kw :inner :xs (list 1.5 -2.25) :deep (Deep :s \"ü\")) :n -7))"
    "        (wireDump (list (Deep :s \"a\") (Deep :s \"b\")))"
    "        (wireDump (none))"
    "        (wireDump (some (ok (list 1 2 3))))"
    "        (wireDump (some (err \"bad\")))"
    "        (wireDump :alpha)"
    "        (wireDump (list :alpha :beta :alpha))"
    "        (wireDump \"héllo wörld 漢字 𝄞\")"
    "        (wireDump \"\")"
    "        (wireDump (bytesOf 2))"
    "        (wireDump (f64ArrayGenerate 3 (fn [(j Int64)] -> Float64 (* 1.25 (int64ToFloat64 j)))))"
    "        (wireDump (i64ArrayGenerate 3 (fn [(j Int64)] -> Int64 (if (= j 0) -9223372036854775807 (* j 1000000007)))))"
    "        (wireDump (i8ArrayGenerate 3 (fn [(j Int64)] -> Int64 (- j 128))))"
    "        (wireDump (list 9223372036854775807 -9223372036854775807 0))"
    "        (wireDump -0.0)"
    "        (wireDump (nanWithPayload 3))"
    "        (wireDump 1.5)"
    "        (wireDump true)"
    "        (wireDump false)"
    "        (wireDump ())"
    "        (wireDump (list))"
    "        (wireDump (list (list (list 1)) (list)))"
    "        (wireDump (pair \"k\" 2))"
    "        (ok 0)))"
    ""
    "fn ! wireDump v: A -> B"
    "  (err \"unlowered\")"))

fn wireCheckSource -> String
  (lines (list
    "#include <stdint.h>"
    "#include <stdio.h>"
    "#include <stdlib.h>"
    "#include <string.h>"
    "#include \"parallel.c\""
    ""
    "void asl_rt_init(void);"
    ""
    "static int readFull(void *out, size_t n) { return fread(out, 1, n, stdin) == n; }"
    ""
    "int main(void) {"
    "  asl_rt_init();"
    "  int64_t count = 0;"
    "  for (;;) {"
    "    int64_t err = 0, len = 0;"
    "    if (fread(&err, 1, 8, stdin) != 8) break;"
    "    if (!readFull(&len, 8)) { printf(\"frame %lld: truncated header\\n\", (long long)count); return 1; }"
    "    if (err != 0) { printf(\"frame %lld: native serVal error %lld\\n\", (long long)count, (long long)err); return 1; }"
    "    if (len < 0 || len > (int64_t)SER_MAX_BYTES) { printf(\"frame %lld: length %lld\\n\", (long long)count, (long long)len); return 1; }"
    "    uint8_t *data = malloc(len ? (size_t)len : 1);"
    "    if (!data) { printf(\"frame %lld: out of memory\\n\", (long long)count); return 1; }"
    "    if (!readFull(data, (size_t)len)) { printf(\"frame %lld: truncated body\\n\", (long long)count); free(data); return 1; }"
    "    DeserCtx d = {data, 0, (size_t)len, 0};"
    "    Val v = deserVal(&d, 0);"
    "    if (d.err || d.pos != (size_t)len) { printf(\"frame %lld: parallel.c deserVal rejects it (err %d at %zu of %lld)\\n\", (long long)count, d.err, d.pos, (long long)len); free(data); return 1; }"
    "    SerBuf b = {0};"
    "    serVal(&b, v, 0);"
    "    if (b.err || b.len != (size_t)len || (len && memcmp(b.data, data, (size_t)len) != 0)) {"
    "      size_t at = 0;"
    "      while (at < b.len && at < (size_t)len && b.data[at] == data[at]) at++;"
    "      printf(\"frame %lld: parallel.c serVal gives %zu bytes, native %lld; first difference at byte %zu\\n\", (long long)count, b.len, (long long)len, at);"
    "      free(b.data); free(data); return 1;"
    "    }"
    "    free(b.data); free(data);"
    "    count++;"
    "  }"
    "  printf(\"frames %lld equal\\n\", (long long)count);"
    "  return 0;"
    "}"))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testArchive)
        (testRouteModule work)
        (testCases work)
        (testCodec work)
        (testFail work)
        (testArity work)
        (testLiteral work)
        (testWire work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
