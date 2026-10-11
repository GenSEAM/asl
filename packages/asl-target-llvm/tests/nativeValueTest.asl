(module asl-target-llvm/tests/nativeValueTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-ir/lower :a low) (asl-target-llvm :a llvm) (asl-target-llvm/ssa :a ssa)])

fn host -> String
  "asl/host/out/asl-host"

fn runtime -> String
  "asl/host/out/libaslrt.a"

fn cap -> String
  "ASL_GC_MAX_MIB=8 "

fn valueNames -> (List String)
  (list "intern" "aslError" "valPrint" "mkStr" "floatRepr")

fn manyCount -> Int64
  100000

fn chunkSize -> Int64
  1000

fn appSource -> String
  (str (stringJoin (list
    "(module valfx/app :x [main] :i [(valfx/other :a o)])"
    ""
    "(schema Pt (:f x Int64) (:f y T))"
    ""
    "(enum Shape (:c dot [] \"No size\") (:c sq [(s Int64)] \"Square\"))"
    ""
    "fn idOf x: T -> T"
    "  x"
    ""
    "fn grow acc: (List Int64) i: Int64 -> (List Int64)"
    "  (if (= i 0) acc (grow (cons i acc) (- i 1)))"
    ""
    "fn lengths xs: (List String) -> Int64"
    "  (fold (fn [(acc Int64) (s String)] -> Int64 (+ acc (stringLength s))) 0 xs)"
    ""
    "fn argsText args: (List String) -> String"
    "  (if (> (listLength args) 20)"
    "    (str (listLength args) \" \" (lengths args) \" \" (optionOr (listHead args) \"\") \" \" (optionOr (listGet args (- (listLength args) 1)) \"\"))"
    "    (str (listLength args) \" \" (lengths args) \" [\" (stringJoin args \"|\") \"]\"))"
    ""
    "fn run op: String args: (List String) -> T"
    "  (cond ((= op \"kw\") (idOf (str (= :alpha (o/alpha)) \" \" (o/isAlpha :alpha) \" \" (= :beta (o/alpha)) \" \" (< :alpha (o/beta)) \" \" (> :alpha (o/beta)) \" \" (o/alpha) \" \" (list :alpha (o/beta) :gamma))))"
    "        ((= op \"kwFresh\") (idOf (str (o/fresh) \" \" (= (o/fresh) :onlyInOther) \" \" (o/isAlpha (idOf :alpha)))))"
    "        ((= op \"ctor\") (idOf (str (o/thin) \" \" (sq 3) \" \" dot \" \" (= (sq 3) (idOf (sq 3))) \" \" (= (o/thin) (idOf (sq 7))))))"
    "        ((= op \"field\") (idOf (str (Pt :x 1 :y :alpha) \" \" (o/point).y \" \" (= (o/point).y :beta) \" \" (o/point))))"
    "        ((= op \"field2\") (idOf (idOf (Pt :x 1 :y 2)).z))"
    "        ((= op \"argv\") (idOf (argsText args)))"
    "        ((= op \"oom\") (idOf (listLength (grow (list) 1000000))))"
    "        ((= op \"fits\") (idOf (listLength (grow (list) 1000))))"
    "        (else (idOf (str \"no such case \" op))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str (if (listEmpty? args) (argsText args) (run (optionOr (listHead args) \"\") (optionOr (listTail args) (list))))))"
    "      (ok 0))") "\n") "\n")

fn otherSource -> String
  (str (stringJoin (list
    "(module valfx/other :x [alpha beta fresh isAlpha thin point] :i [])"
    ""
    "(schema Pt (:f x Int64) (:f y T))"
    ""
    "(enum Thin (:c sq [(s Int64)] \"One-field box named as valfx/app's square\"))"
    ""
    "fn alpha -> T"
    "  :alpha"
    ""
    "fn beta -> T"
    "  :beta"
    ""
    "fn fresh -> T"
    "  :onlyInOther"
    ""
    "fn isAlpha k: T -> Bool"
    "  (= k :alpha)"
    ""
    "fn thin -> Thin"
    "  (sq 7)"
    ""
    "fn point -> Pt"
    "  (Pt :x 2 :y :beta)") "\n") "\n")

fn chunkSource c: Int64 -> String
  (str "fn chunk" c " -> (List T)\n  (list "
       (stringJoin (map (fn [(i Int64)] -> String (str ":w" (+ (* c (chunkSize)) i))) (range 0 (chunkSize))) " ")
       ")\n\n")

fn manySource -> String
  (let [(chunks (/ (manyCount) (chunkSize)))]
    (str "(module valfx/many :x [main] :i [(valfx/manyOther :a mo)])\n\n"
         (stringJoin (map (fn [(c Int64)] -> String (chunkSource c)) (range 0 chunks)) "")
         "fn all -> (List T)\n  "
         (stringJoin (map (fn [(c Int64)] -> String (if (= c (- chunks 1)) (str "(chunk" c ")") (str "(listAppend (chunk" c ") "))) (range 0 chunks)) "")
         (stringJoin (map (fn [(c Int64)] -> String ")") (range 1 chunks)) "")
         "\n\n"
         "fn countEq xs: (List T) k: T -> Int64\n  (fold (fn [(acc Int64) (x T)] -> Int64 (if (= x k) (+ acc 1) acc)) 0 xs)\n\n"
         "fn ! main args: (List String) -> (Result Int64 String)\n"
         "  (let [(ks (all))]\n"
         "    (do (println (str (listLength ks) \" \" (optionOr (listGet ks 0) :none) \" \" (optionOr (listGet ks 99999) :none) \" \" (optionOr (listGet ks 54321) :none)))\n"
         "        (println (str (countEq ks :w777) \" \" (countEq ks :w99999) \" \" (countEq ks (mo/far)) \" \" (= (optionOr (listGet ks 54321) :none) (mo/far))))\n"
         "        (println (str (< :w100 :w99) \" \" (< :w99998 :w99999) \" \" (= :w0 :w1) \" \" (mo/far)))\n"
         "        (ok 0)))\n"))

fn manyOtherSource -> String
  "(module valfx/manyOther :x [far] :i [])\n\nfn far -> T\n  :w54321\n"

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiled path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn memberName line: String -> String
  (let [(head (optionOr (stringSlice line 0 (- (stringLength line) 1)) line))]
    (mt (stringIndexOf head "[")
      ((none) head)
      ((some at) (optionOr (stringSlice head (+ at 1) (optionOr (stringIndexOf head "]") (stringLength head))) head))))

fn archiveMembers text: String -> (List String)
  (map (fn [(l String)] -> String (memberName l))
       (filter (fn [(l String)] -> Bool (and (= (stringSlice l (- (stringLength l) 1) (stringLength l)) (some ":")) (not (stringContains? l " ")))) (stringSplit text "\n")))

fn symbolNames text: String -> (List String)
  (map (fn [(l String)] -> String
         (let [(name (optionOr (listHead (stringSplit l " ")) ""))]
           (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
       (filter (fn [(l String)] -> Bool (stringContains? l " ")) (stringSplit text "\n")))

fn ! testArchive -> Bool
  (let [(listed (sh (str "nm -P " (runtime))))
        (members (archiveMembers listed.stdout))]
    (do
      (assert (= listed.exitCode 0) (str "nm -P lists libaslrt.a: " listed.stderr))
      (map (fn [(m String)] -> Bool (do (assert (listContains? members m) (str "libaslrt.a has member " m "; members " (stringJoin members " "))) true))
           (list "rtAbi.o" "gcAsl.o" "rtFloor.o"))
      (map (fn [(m String)] -> Bool (do (refute (listContains? members m) (str "libaslrt.a has no member " m "; members " (stringJoin members " "))) true))
           (list "abi.o" "value.o" "float.o" "gc.o"))
      true))

fn ! testSymbols exe: String -> Bool
  (let [(listed (sh (str "nm -P " exe)))
        (names (symbolNames listed.stdout))]
    (do
      (assert (= listed.exitCode 0) (str "nm -P lists " exe ": " listed.stderr))
      (assert (listContains? names "main") (str exe ": nm -P lists main"))
      (assert (listContains? names "valrt.intern") (str exe ": nm -P lists the IR intern table's valrt.intern"))
      (map (fn [(n String)] -> Bool (do (refute (listContains? names n) (str exe ": no symbol " n)) true)) (valueNames))
      true))

fn ! build dir: String name: String -> String
  (let [(exe (str dir "/" name))]
    (mt (compiled (str exe ".asl"))
      ((err e) (do (assert false (str name " links and emits: " e)) exe))
      ((ok code)
        (do
          (assert (ok? (fileWrite (str exe ".ll") code)) (str "fileWrite " exe ".ll"))
          (assert (stringContains? code "@valrt.intern(") (str name ": the IR interns through @valrt.intern"))
          (let [(linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " exe ".ll -x none " (runtime) " -lm -o " exe)))]
            (do (assert (= linked.exitCode 0) (str name " links against libaslrt.a: " linked.stderr))
                exe))))))

fn hostErrorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn ! testParity env: String exe: String src: String args: String want: String -> Bool
  (let [(native (sh (str env exe " " args)))
        (interp (sh (str env (host) " run " src " " args)))
        (label (if (> (stringLength args) 60) (str (optionOr (stringSlice args 0 60) "") "...") args))]
    (do
      (assert (= native.exitCode interp.exitCode) (str label ": native exit " native.exitCode " equals asl-host run exit " interp.exitCode "; native stderr " native.stderr "; asl-host stderr " interp.stderr))
      (assert (= native.stdout interp.stdout) (str label ": native prints " native.stdout " and asl-host run " interp.stdout))
      (refute (stringContains? interp.stdout "no such case") (str label ": the fixture knows the case"))
      (if (= interp.exitCode 0)
        (do (assert (stringContains? native.stdout want) (str label ": native prints " want "; got " native.stdout))
            (assert (= native.stderr "") (str label ": native stderr empty, got " native.stderr)))
        (do (assert (stringStartsWith? (hostErrorLine interp) want) (str label ": asl-host run fails with " want "; got " interp.stderr))
            (assert (= native.stderr (str (hostErrorLine interp) "\n")) (str label ": native stderr is asl-host's error line " (hostErrorLine interp) "; got " native.stderr))))
      true))

fn manyArgs -> String
  (stringJoin (map (fn [(i Int64)] -> String (str "a" i)) (range 0 10000)) " ")

fn ! testFixture dir: String -> Bool
  (let [(src (str dir "/valfx/app.asl"))]
    (do
      (assert (ok? (fileWrite src (appSource))) (str "fileWrite " src))
      (assert (ok? (fileWrite (str dir "/valfx/other.asl") (otherSource))) "fileWrite valfx/other.asl")
      (let [(exe (build dir "valfx/app"))]
        (do
          (testSymbols exe)
          (testParity "" exe src "kw" "true true false true false :alpha (:alpha :beta :gamma)")
          (testParity "" exe src "kwFresh" ":onlyInOther true true")
          (testParity "" exe src "ctor" "true")
          (testParity "" exe src "field" ":beta true")
          (testParity "" exe src "field2" "ERR_")
          (testParity "" exe src "" "0 0 []")
          (testParity "" exe src "argv" "0 0 []")
          (testParity "" exe src "argv '' 'héllo' '日本語' '𐍈' 'a b'" "5 ")
          (testParity "" exe src (str "argv " (manyArgs)) "10000 48890 a0 a9999")
          (testParity (cap) exe src "fits" "1000")
          (testParity (cap) exe src "oom" "ERR_OOM: ")
          true))))

fn ! testMany dir: String -> Bool
  (let [(src (str dir "/valfx/many.asl"))]
    (do
      (assert (ok? (fileWrite src (manySource))) (str "fileWrite " src))
      (assert (ok? (fileWrite (str dir "/valfx/manyOther.asl") (manyOtherSource))) "fileWrite valfx/manyOther.asl")
      (let [(exe (build dir "valfx/many"))]
        (do
          (testSymbols exe)
          (testParity "" exe src "" "100000 :w0 :w99999 :w54321\n1 1 1 true\ntrue true false :w54321\n")
          true))))

fn hostLib -> String
  "asl/host/out/libaslhost.a"

fn unroutedSource -> String
  (str (stringJoin (list
    "(module valfx/unrouted :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (mt (procRusage)"
    "        ((err e) (println (str \"rusage err \" e)))"
    "        ((ok r) (println (str \"rusage \" (> r.selfMaxRssKb 0) \" \" (>= r.selfUserUs 0)))))"
    "      (mt (fdClose 987654)"
    "        ((ok u) (println \"closed\"))"
    "        ((err e) (println (str \"close err \" (> (stringLength e) 0)))))"
    "      (mt (procSpawnv (list \"/bin/sh\" \"-c\" \"exit 3\") (some \"/\") (none))"
    "        ((err e) (println (str \"spawn err \" e)))"
    "        ((ok p) (mt (procWaitPid p.pid false)"
    "                  ((err e) (println (str \"wait err \" e)))"
    "                  ((ok w) (println (str \"waited \" w \" \" (= w (some 3))))))))"
    "      (ok 0))") "\n") "\n")

fn parSource -> String
  (str (stringJoin (list
    "(module valfx/par :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str (parMap (fn [(x Int64)] -> Int64 (/ 10 (- x 2))) (list 1 2 3))))"
    "      (ok 0))") "\n") "\n")

fn ! unrouted path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgram m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! linkWith dir: String name: String code: String libs: String -> String
  (let [(exe (str dir "/" name))]
    (do
      (assert (ok? (fileWrite (str exe ".ll") code)) (str "fileWrite " exe ".ll"))
      (let [(linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " exe ".ll -x none " libs " -lm -o " exe)))]
        (do (assert (= linked.exitCode 0) (str name " links: " linked.stderr))
            exe))))

fn ! testUnrouted dir: String -> Bool
  (let [(src (str dir "/valfx/unrouted.asl"))
        (par (str dir "/valfx/par.asl"))]
    (do
      (assert (ok? (fileWrite src (unroutedSource))) (str "fileWrite " src))
      (assert (ok? (fileWrite par (parSource))) (str "fileWrite " par))
      (mt (unrouted src)
        ((err e) (assert false (str "valfx/unrouted links and emits unrouted: " e)))
        ((ok code)
          (do
            (assert (stringContains? code "call %Val @asl_rt_builtin_sys(") "valfx/unrouted: procRusage, fdClose, procSpawnv and procWaitPid go to libaslhost.a's sys table")
            (testParity "" (linkWith dir "valfx/unrouted" code (str (runtime) " " (hostLib))) src "" "rusage true true\nclose err true\nwaited (some 3) true\n"))))
      (mt (unrouted par)
        ((err e) (assert false (str "valfx/par links and emits unrouted: " e)))
        ((ok code)
          (do
            (assert (stringContains? code "call %Val @asl_rt_builtin_parallel(") "valfx/par: parMap goes to libaslhost.a's parallel.c")
            (testParity "" (linkWith dir "valfx/parUnrouted" code (str (runtime) " " (hostLib))) par "" "ERR_WORKER_TRAP: parMap element 1: ERR_DIV_ZERO: division by zero"))))
      (mt (compiled par)
        ((err e) (assert false (str "valfx/par links and emits routed: " e)))
        ((ok code)
          (do
            (refute (stringContains? code "@asl_rt_builtin_parallel(") "valfx/par routed: parMap runs as asl-target-llvm/parallel")
            (testParity "" (linkWith dir "valfx/parRouted" code (runtime)) par "" "ERR_WORKER_TRAP: parMap element 1: ERR_DIV_ZERO: division by zero"))))
      true))

fn floorLibSource -> String
  (str (stringJoin (list
    "(module valLib :x [makeAdder] :i [])"
    ""
    "fn add3 a: Int64 b: Int64 c: Int64 -> Int64"
    "  (+ a (+ b c))"
    ""
    "fn makeAdder -> T"
    "  (partial add3 1 2)") "\n") "\n")

fn floorMain -> String
  (str (stringJoin (list
    "#include <setjmp.h>"
    "#include <stdint.h>"
    "#include <stdio.h>"
    "typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; void *o; } u; } Val;"
    "void asl_rt_init(void);"
    "Val aslCall(Val fn, int argc, Val *args);"
    "void *aslHandlerSlot(void);"
    "char *aslErrorText(void);"
    "Val makeAdder(void);"
    "static jmp_buf jb;"
    "int main(void) {"
    "  asl_rt_init();"
    "  Val four = {2, 0, {.i = 4}};"
    "  Val sum = aslCall(makeAdder(), 1, &four);"
    "  printf(\"partial %lld\\n\", (long long)sum.u.i);"
    "  fflush(stdout);"
    "  *(void **)aslHandlerSlot() = jb;"
    "  if (setjmp(jb)) { printf(\"caught %s\\n\", aslErrorText()); return 0; }"
    "  Val five = {2, 0, {.i = 5}};"
    "  aslCall(five, 0, 0);"
    "  printf(\"returned\\n\");"
    "  return 1;"
    "}") "\n") "\n")

fn ! testFloorCalls dir: String -> Bool
  (let [(cSrc (str dir "/valFloorMain.c"))]
    (do
      (assert (ok? (fileWrite cSrc (floorMain))) "fileWrite valFloorMain.c")
      (assert (ok? (fileWrite (str dir "/valRuntime.ll") (ssa/cRuntimeModule))) "fileWrite valRuntime.ll, the C main's runtime definitions")
      (mt (low/lowerSource (floorLibSource))
        ((err ds) (assert false (str "valLib lowers: " (formatDiags ds))))
        ((ok m) (mt (ssa/emitLlvmModule m)
                  ((err ds) (assert false (str "valLib emits: " (formatDiags ds))))
                  ((ok code)
                    (let [(exe (linkWith dir "valLib" code (str dir "/valRuntime.ll -x c " cSrc " -x none " (runtime))))
                          (out (sh exe))]
                      (do
                        (assert (= out.exitCode 0) (str "valLib: exit 0 after the handler caught aslCall's failure, got " out.exitCode "; " out.stdout out.stderr))
                        (assert (= out.stdout "partial 7\ncaught ERR_TYPE: cannot call a Int\n") (str "valLib: the partial adds 1 2 4 and aslCall's failure reaches the handler; got " out.stdout out.stderr))
                        (assert (= out.stderr "") (str "valLib: nothing reported on stderr, got " out.stderr))
                        true))))))
      true))

fn ! testCorpus name: String -> Bool
  (let [(out (sh (str "env -u ASL_ROOT -u ASL_LAUNCHED " (host) " test asl/packages/asl-target-llvm/tests/" name ".asl")))
        (text (str out.stdout out.stderr))]
    (do
      (assert (= out.exitCode 0) (str name ": exit " out.exitCode "; " text))
      (assert (stringContains? text " passed)") (str name ": reports its passed count; " text))
      (refute (stringContains? text "FAIL") (str name ": no failure; " text))
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (assert (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n")) "fixture package config written")
      (assert (= (sh (str "mkdir -p " dir "/valfx")).exitCode 0) "fixture module directory made")
      (testArchive)
      (testFixture dir)
      (testUnrouted dir)
      (testFloorCalls dir)
      (testMany dir)
      (map (fn [(n String)] -> Bool (testCorpus n)) (list "nativeFormatTest" "nativeTrapTest" "nativeOpsTest" "nativeObjectTest"))
      (assert (= (sh (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
