(module asl-target-llvm/tests/nativeObjectTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-ir/lower :a low) (asl-target-llvm :a llvm) (asl-target-llvm/ssa :a ssa)])

fn host -> String
  "asl/host/out/asl-host"

fn clangIr -> String
  "/usr/bin/clang -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

fn deletedEntries -> (List String)
  (list "asl_rt_construct" "asl_rt_record" "asl_rt_field" "asl_rt_variant_field" "asl_rt_make_closure" "asl_rt_closure_capture"
        "asl_rt_call_closure" "asl_rt_str" "asl_rt_keyword" "asl_rt_symbol" "asl_rt_tag")

fn numbered prefix: String n: Int64 -> (List String)
  (map (fn [(i Int64)] -> String (str prefix i)) (range 0 n))

fn nestedSum names: (List String) -> String
  (mt (listTail names)
    ((some rest) (if (listEmpty? rest)
                   (optionOr (listHead names) "0")
                   (str "(+ " (optionOr (listHead names) "0") " " (nestedSum rest) ")")))
    ((none) "0"))

fn ones n: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " ")

fn capSource n: Int64 -> String
  (if (= n 0)
    "fn cap0 -> T\n  (idOf (fn [(x Int64)] -> Int64 (+ x 1)))\n"
    (str "fn cap" n " -> T\n  (let [" (stringJoin (map (fn [(i Int64)] -> String (str "(v" i " (idOf " (+ i 1) "))")) (range 0 n)) " ")
         "]\n    (idOf (fn [(x Int64)] -> Int64 (+ x " (nestedSum (numbered "v" n)) "))))\n"))

fn wideSource n: Int64 -> String
  (str "fn wide" n " -> T\n  (idOf (fn [" (stringJoin (map (fn [(p String)] -> String (str "(" p " T)")) (numbered "a" n)) " ") "] -> T a" (- n 1) "))\n")

fn manyVariants -> String
  (stringJoin (map (fn [(k Int64)] -> String
                     (str "(:c a" k " [" (stringJoin (map (fn [(x String)] -> String (str "(" x " Int64)")) (numbered "x" k)) " ") "] \"" k " fields\")"))
                   (range 0 9))
              " ")

fn manySumArms -> String
  (stringJoin (map (fn [(k Int64)] -> String
                     (if (= k 0) "((a0) 0)" (str "((a" k " " (stringJoin (numbered "x" k) " ") ") " (nestedSum (numbered "x" k)) ")")))
                   (range 0 9))
              " ")

fn manyOfArms -> String
  (stringJoin (map (fn [(k Int64)] -> String
                     (if (= k 0) "((= n 0) a0)" (str "((= n " k ") (a" k " " (stringJoin (map (fn [(i Int64)] -> String (str (* (+ i 1) 3))) (range 0 k)) " ") "))")))
                   (range 0 8))
              " ")

fn wideRecord -> String
  (str "(Wide " (stringJoin (map (fn [(i Int64)] -> String (str ":f" i " " (* i 3))) (range 0 40)) " ") ")")

fn callCases -> (List (Pair String String))
  (listAppend
    (fold (fn [(acc (List (Pair String String))) (n Int64)] -> (List (Pair String String))
            (listAppend acc (list (pair (str "cap" n) (str "((cap" n ") 5)"))
                                  (pair (str "cap" n "Many") (str "((cap" n ") 5 6)"))
                                  (pair (str "cap" n "Few") (str "((cap" n "))")))))
          (list) (list 0 1 7 256))
    (list (pair "wide256" (str "((wide256) " (ones 256) ")"))
          (pair "wide256Many" (str "((wide256) " (ones 257) ")"))
          (pair "wide257" (str "((wide257) " (ones 257) ")"))
          (pair "wide257Few" (str "((wide257) " (ones 256) ")"))
          (pair "partial" "((idOf (partial add3 (idOf 1) 2)) 3)")
          (pair "partialMany" "((idOf (partial add3 (idOf 1) 2)) 3 4)")
          (pair "named" "((idOf add3) 1 2 3)")
          (pair "namedFew" "((idOf add3) 1)")
          (pair "notFn" "((idOf 5) 1)")))

fn appSource -> String
  (str (stringJoin (list
    "(module objfx/app :x [main] :i [(objfx/other :a o)])"
    ""
    "(schema One (:f a Int64))"
    ""
    (str "(schema Wide " (stringJoin (map (fn [(f String)] -> String (str "(:f " f " Int64)")) (numbered "f" 40)) " ") ")")
    ""
    (str "(enum Many " (manyVariants) ")")
    ""
    "(enum Wider (:c box [(w Int64) (h Int64)] \"Two-field box\"))"
    ""
    "fn idOf x: T -> T"
    "  x"
    ""
    "fn add3 a: Int64 b: Int64 c: Int64 -> Int64"
    "  (+ a (+ b c))"
    ""
    "fn area b: Wider -> Int64"
    "  (mt b ((box w h) (* w h)))"
    ""
    "fn manyOf n: Int64 -> Many"
    (str "  (cond " (manyOfArms) " (else (a8 1 2 3 4 5 6 7 8)))")
    ""
    "fn manySum m: Many -> Int64"
    (str "  (mt m " (manySumArms) ")")
    ""
    "fn spin n: Int64 acc: Int64 -> Int64"
    "  (if (= n 0) acc (spin (- n 1) (+ acc (stringLength (idOf \"constant text\")))))"
    ""
    (capSource 0) (capSource 1) (capSource 7) (capSource 256)
    (wideSource 256) (wideSource 257)
    "fn run op: String n: Int64 -> T"
    "  (cond ((= op \"rec1\") (let [(r (idOf (One :a (idOf 5))))] (idOf (str r.a \" \" r))))"
    (str "        ((= op \"rec40\") (let [(w (idOf " (wideRecord) "))] (idOf (str w.f0 \" \" w.f20 \" \" w.f39 \" \" w))))")
    "        ((= op \"missing\") (idOf (idOf (One :a 5)).zz))"
    (str "        ((= op \"missing40\") (idOf (idOf " (wideRecord) ").f40))")
    "        ((= op \"notRec\") (idOf (idOf 5).a))"
    "        ((= op \"many\") (let [(m (idOf (manyOf n)))] (idOf (str (manySum m) \" \" m))))"
    "        ((= op \"wrongVariant\") (idOf (area (o/idAny (o/thinBox)))))"
    "        ((= op \"kw\") (idOf (str (= :alpha (o/otherKw)) \" \" (o/sameKw :alpha) \" \" (o/otherKw) \" \" (= :beta (o/otherKw)) \" \" (o/sameKw (idOf :beta)))))"
    "        ((= op \"loop\") (idOf (spin n 0)))"
    "        ((= op \"strings\") (idOf (str \"hello\" \" \" (idOf \"hello\") (stringLength \"hello\"))))"
    (stringJoin (map (fn [(c (Pair String String))] -> String (str "        ((= op \"" (pairFirst c) "\") (idOf " (pairSecond c) "))")) (callCases)) "\n")
    "        (else (idOf \"no such case\")))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(op (optionOr (listHead args) \"\"))"
    "        (n (optionOr (stringToInt64 (optionOr (listGet args 1) \"0\")) 0))]"
    "    (do (println (str (run op n)))"
    "        (ok 0)))") "\n") "\n")

fn otherSource -> String
  (str (stringJoin (list
    "(module objfx/other :x [Thin thinBox otherKw sameKw idAny] :i [])"
    ""
    "(enum Thin (:c box [(w Int64)] \"One-field box, named as objfx/app's two-field box\"))"
    ""
    "fn thinBox -> Thin"
    "  (box 7)"
    ""
    "fn otherKw -> T"
    "  :alpha"
    ""
    "fn sameKw k: T -> Bool"
    "  (= k :alpha)"
    ""
    "fn idAny x: T -> T"
    "  x") "\n") "\n")

fn parityCases -> (List String)
  (listAppend (list "rec1" "rec40" "missing" "missing40" "notRec"
                    "many 0" "many 1" "many 2" "many 3" "many 4" "many 5" "many 6" "many 7" "many 8"
                    "wrongVariant" "kw" "loop 10" "loop 1000000" "strings")
              (map (fn [(c (Pair String String))] -> String (pairFirst c)) (callCases)))

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
           (do (refute (listAny? (fn [(d String)] -> Bool (stringContains? d (str "@" n "("))) (llvm/runtimeDecls)) (str "runtimeDecls declares no " n))
               true))
         (deletedEntries))
    (refute (listAny? (fn [(d String)] -> Bool (stringContains? d "@aslCall(")) (llvm/runtimeDecls)) "runtimeDecls declares no aslCall: a program's IR defines it (NX4)")
    true)

fn ! testArchive -> Bool
  (let [(listed (processRun "nm -g asl/host/out/libaslrt.a"))
        (defines (fn [(n String)] -> Bool
                   (listAny? (fn [(k String)] -> Bool (or (stringContains? listed.stdout (str " " k " _" n "\n")) (stringContains? listed.stdout (str " " k " " n "\n"))))
                             (list "T" "W"))))]
    (do
      (assert (= listed.exitCode 0) (str "nm lists libaslrt.a: " listed.stderr))
      (assert (defines "asl_rt_init") "nm output holds the entries libaslrt.a keeps")
      (refute (defines "aslCall") "libaslrt.a defines no aslCall")
      (map (fn [(n String)] -> Bool
             (do (refute (defines n) (str "libaslrt.a defines no " n))
                 true))
           (deletedEntries))
      true))

fn ! verified dir: String name: String code: String -> Bool
  (let [(ll (str dir "/" name ".ll"))]
    (do
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@" n "(")) (str name ": the IR neither declares nor calls " n))
                 true))
           (deletedEntries))
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (mt (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (processRun (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str name ": opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn ! nativeExe dir: String name: String extra: String -> String
  (let [(exe (str dir "/" name))
        (linked (processRun (str (clangIr) exe ".ll" extra (lib) exe)))]
    (do (assert (= linked.exitCode 0) (str name " links against libaslrt.a: " linked.stderr))
        exe))

fn hostErrorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn ! testParity exe: String src: String args: String -> Bool
  (let [(native (processRun (str exe " " args)))
        (interp (processRun (str (host) " run " src " " args)))]
    (do
      (assert (= native.exitCode interp.exitCode) (str args ": native exit " native.exitCode " equals asl-host run exit " interp.exitCode "; native stderr " native.stderr "; asl-host stderr " interp.stderr))
      (assert (= native.stdout interp.stdout) (str args ": native prints " native.stdout " and asl-host run " interp.stdout))
      (refute (stringContains? interp.stdout "no such case") (str args ": the fixture knows the case"))
      (if (= interp.exitCode 0)
        (do (assert (> (stringLength interp.stdout) 1) (str args ": asl-host run prints a result"))
            (assert (= native.stderr "") (str args ": native stderr empty, got " native.stderr)))
        (do (assert (stringStartsWith? (hostErrorLine interp) "ERR_") (str args ": asl-host run fails with an error line: " interp.stderr))
            (assert (= native.stderr (str (hostErrorLine interp) "\n")) (str args ": native stderr is asl-host's error line " (hostErrorLine interp) "; got " native.stderr))))
      true))

fn objectsAllocated text: String -> (Option Int64)
  (let [(mark ":objectsAllocated ")]
    (mt (stringIndexOf text mark)
      ((none) (none))
      ((some at) (let [(tail (optionOr (stringSlice text (+ at (stringLength mark)) (stringLength text)) ""))]
                   (stringToInt64 (optionOr (stringSlice tail 0 (optionOr (stringIndexOf tail " ") (stringLength tail))) ""))))))

fn ! testConstantLoop exe: String -> Bool
  (let [(few (processRun (str "ASL_GC_STATS=1 " exe " loop 10")))
        (many (processRun (str "ASL_GC_STATS=1 " exe " loop 1000000")))
        (fewCount (objectsAllocated few.stderr))
        (manyCount (objectsAllocated many.stderr))]
    (do
      (assert (and (= few.exitCode 0) (= few.stdout "130\n")) (str "loop 10: prints 130, got " few.stdout few.stderr))
      (assert (and (= many.exitCode 0) (= many.stdout "13000000\n")) (str "loop 1000000: prints 13000000, got " many.stdout many.stderr))
      (assert (some? fewCount) (str "loop 10: ASL_GC_STATS=1 reports objectsAllocated: " few.stderr))
      (assert (some? manyCount) (str "loop 1000000: ASL_GC_STATS=1 reports objectsAllocated: " many.stderr))
      (assert (< (- (optionOr manyCount 1000000) (optionOr fewCount 0)) 100)
              (str "1,000,000 iterations allocate fewer than 100 objects more than 10 do (the longer argument and result text only), not one per iteration: " (optionOr manyCount -1) " against " (optionOr fewCount -1)))
      true))

fn ! testFixture dir: String -> Bool
  (let [(src (str dir "/objfx/app.asl"))]
    (do
      (assert (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n")) "fixture package config written")
      (assert (= (processRun (str "mkdir -p " dir "/objfx")).exitCode 0) "fixture module directory made")
      (assert (ok? (fileWrite src (appSource))) (str "fileWrite " src))
      (assert (ok? (fileWrite (str dir "/objfx/other.asl") (otherSource))) "fileWrite objfx/other.asl")
      (mt (compiled src)
        ((err e) (assert false (str "objfx/app links and emits: " e)))
        ((ok code)
          (do
            (verified dir "objfx/app" code)
            (map (fn [(h String)] -> Bool
                   (do (assert (stringContains? code (str " @objrt." h "(")) (str "objfx/app: the IR calls @objrt." h))
                       true))
                 (list "field" "call" "str" "nameId" "patternArity"))
            (let [(exe (nativeExe dir "objfx/app" ""))]
              (do
                (map (fn [(c String)] -> Bool (testParity exe src c)) (parityCases))
                (testConstantLoop exe))))))
      true))

fn cap300Source -> String
  (str "(module cap300 :x [main] :i [])\n\nfn idOf x: T -> T\n  x\n\n"
       (capSource 300)
       "\nfn ! main args: (List String) -> (Result Int64 String)\n"
       "  (let [(op (optionOr (listHead args) \"\"))]\n"
       "    (do (println (str (cond ((= op \"many\") ((cap300) 5 6)) ((= op \"few\") ((cap300))) (else ((cap300) 5)))))\n"
       "        (ok 0)))\n")

fn ! testCapture300 dir: String -> Bool
  (let [(src (str dir "/cap300.asl"))]
    (do
      (assert (ok? (fileWrite src (cap300Source))) "fileWrite cap300.asl")
      (assert (stringContains? (processRun (str (host) " run " src)).stderr "ERR_LIMIT: more than 256 captured variables") "cap300: asl-host refuses more than 256 captures at load")
      (mt (compiled src)
        ((err e) (assert false (str "cap300 links and emits: " e)))
        ((ok code)
          (do
            (verified dir "cap300" code)
            (let [(exe (nativeExe dir "cap300" ""))
                  (right (processRun exe))
                  (many (processRun (str exe " many")))
                  (few (processRun (str exe " few")))]
              (do
                (assert (and (= right.exitCode 0) (= right.stdout "45155\n")) (str "cap300: 5 plus 1..300 is 45155, got " right.stdout right.stderr))
                (assert (and (= many.exitCode 1) (= many.stderr "ERR_ARITY: lambda expects 1 argument(s), got 2\n")) (str "cap300 many: " many.stderr))
                (assert (and (= few.exitCode 1) (= few.stderr "ERR_ARITY: lambda expects 1 argument(s), got 0\n")) (str "cap300 few: " few.stderr)))))))
      true))

fn libSource -> String
  (str (stringJoin (list
    "(module objLib :x [readA readB readZ] :i [])"
    ""
    "fn readA r: T -> T"
    "  r.a"
    ""
    "fn readB r: T -> T"
    "  r.b"
    ""
    "fn readZ r: T -> T"
    "  r.z") "\n") "\n")

fn libTwinSource -> String
  (str (stringJoin (list
    "(module objLibHost :x [main] :i [])"
    ""
    "(schema R (:f a Int64) (:f b Int64))"
    ""
    "fn idOf x: T -> T"
    "  x"
    ""
    "fn ! main -> (Result Int64 String)"
    "  (let [(r (idOf (R :b 2 :a 1)))]"
    "    (do (println (str \"a=\" r.a \" b=\" r.b))"
    "        (println (str r.z))"
    "        (ok 0)))") "\n") "\n")

fn cFixture -> String
  (str (stringJoin (list
    "#include <stdint.h>"
    "#include <stdio.h>"
    "typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; void *o; } u; } Val;"
    "typedef struct { uint32_t size; uint8_t type, mark, perm, classIdx; int schema; int n; int *keys; Val v[]; } Rec;"
    "void asl_rt_init(void);"
    "void *asl_alloc(int type, size_t bytes);"
    "int intern(const char *s, size_t n);"
    "Val readA(Val r);"
    "Val readB(Val r);"
    "Val readZ(Val r);"
    "static int ids[2];"
    "int main(void) {"
    "  asl_rt_init();"
    "  ids[0] = intern(\"b\", 1); ids[1] = intern(\"a\", 1);"
    "  Rec *r = asl_alloc(2, sizeof(Rec) + 2 * sizeof(Val));"
    "  r->schema = intern(\"R\", 1); r->n = 2; r->keys = ids;"
    "  r->v[0] = (Val){2, 0, {.i = 2}}; r->v[1] = (Val){2, 0, {.i = 1}};"
    "  Val v = {7, 0, {.o = r}};"
    "  Val a = readA(v), b = readB(v);"
    "  printf(\"a=%lld b=%lld\\n\", (long long)a.u.i, (long long)b.u.i);"
    "  fflush(stdout);"
    "  readZ(v);"
    "  return 0;"
    "}") "\n") "\n")

fn ! testCRecord dir: String -> Bool
  (let [(twin (str dir "/objLibHost.asl"))
        (cSrc (str dir "/objLibMain.c"))]
    (do
      (assert (ok? (fileWrite twin (libTwinSource))) "fileWrite objLibHost.asl")
      (assert (ok? (fileWrite cSrc (cFixture))) "fileWrite objLibMain.c")
      (assert (ok? (fileWrite (str dir "/valrtC.ll") (ssa/cRuntimeModule))) "fileWrite valrtC.ll, the C main's intern and C floor definitions")
      (mt (low/lowerSource (libSource))
        ((err ds) (assert false (str "objLib lowers: " (formatDiags ds))))
        ((ok m) (mt (ssa/emitLlvmModule m)
                  ((err ds) (assert false (str "objLib emits: " (formatDiags ds))))
                  ((ok code)
                    (do
                      (verified dir "objLib" code)
                      (assert (stringContains? code " @objrt.field(") "objLib: the field reads call @objrt.field")
                      (let [(exe (nativeExe dir "objLib" (str " " dir "/valrtC.ll -x c " cSrc)))
                            (native (processRun exe))
                            (interp (processRun (str (host) " run " twin)))]
                        (do
                          (assert (= native.stdout "a=1 b=2\n") (str "objLib: the C-built record reads a=1 b=2, got " native.stdout native.stderr))
                          (assert (= native.stdout interp.stdout) (str "objLib: native stdout equals asl-host run's " interp.stdout))
                          (assert (= native.exitCode 1) (str "objLib: readZ fails, exit " native.exitCode))
                          (assert (= (hostErrorLine interp) "ERR_FIELD: record has no field z") (str "objLib: asl-host run fails on z: " interp.stderr))
                          (assert (= native.stderr (str (hostErrorLine interp) "\n")) (str "objLib: native stderr is asl-host's error line; got " native.stderr))
                          true)))))))
      true))

fn ! testSymbol dir: String -> Bool
  (let [(m (irTy/ssaModule "objSym" (list) (list) (list) (list) (list)
             (list (irTy/ssaFunction "sym" (list) (list) (irTy/tyVal)
                     (list (irTy/ssaBlock "entry" (list) (list (irTy/ssaInstr "s" (irTy/tyVal) (irTy/opConst (irTy/constSymbol "foo")))) (irTy/termReturn "s")))))))]
    (mt (llvm/emitLlvmProgram m "sym")
      ((err ds) (assert false (str "objSym emits: " (formatDiags ds))))
      ((ok code)
        (do
          (verified dir "objSym" code)
          (assert (stringContains? code " @objrt.symbol(") "objSym: the constant calls @objrt.symbol")
          (let [(out (processRun (nativeExe dir "objSym" "")))]
            (do (assert (= out.exitCode 1) (str "objSym: exit 1, got " out.exitCode))
                (assert (= out.stderr "ERR_UNSUPPORTED: symbol foo: the host value model has no symbol type\n") (str "objSym: stderr " out.stderr))
                true))))))

fn emptyRecordCase name: String last: (List irTy/SsaInstr) result: String -> irTy/SsaFunction
  (irTy/ssaFunction name (list) (list) (irTy/tyVal)
    (list (irTy/ssaBlock "entry" (list)
            (listAppend (list (irTy/ssaInstr "r" (irTy/tyVal) (irTy/opRecord "Empty" (list) (list)))
                              (irTy/ssaInstr "s" (irTy/tyVal) (irTy/opRecord "Empty" (list) (list)))
                              (irTy/ssaInstr "q" (irTy/tyVal) (irTy/opCall "idOf" (list "r"))))
                        last)
            (irTy/termReturn result))))

fn ! testEmptyRecord dir: String -> Bool
  (let [(idFn (irTy/ssaFunction "idOf" (list) (list (irTy/ssaParam "x" (irTy/tyVal))) (irTy/tyVal) (list (irTy/ssaBlock "entry" (list) (list) (irTy/termReturn "x")))))
        (eqFn (emptyRecordCase "emptyEq" (list (irTy/ssaInstr "e" (irTy/tyI1) (irTy/opEntry "=" (list "q" "s")))
                                               (irTy/ssaInstr "eb" (irTy/tyVal) (irTy/opBox "e"))
                                               (irTy/ssaInstr "one" (irTy/tyVal) (irTy/opConst (irTy/constInt 1)))
                                               (irTy/ssaInstr "two" (irTy/tyVal) (irTy/opConst (irTy/constInt 2)))
                                               (irTy/ssaInstr "pick" (irTy/tyVal) (irTy/opCall "pick" (list "eb" "one" "two"))))
                                 "pick"))
        (pickFn (irTy/ssaFunction "pick" (list) (list (irTy/ssaParam "c" (irTy/tyVal)) (irTy/ssaParam "y" (irTy/tyVal)) (irTy/ssaParam "n" (irTy/tyVal))) (irTy/tyVal)
                  (list (irTy/ssaBlock "entry" (list) (list) (irTy/termBranch "c" (irTy/ssaEdge "yes" (list)) (irTy/ssaEdge "no" (list))))
                        (irTy/ssaBlock "yes" (list) (list) (irTy/termReturn "y"))
                        (irTy/ssaBlock "no" (list) (list) (irTy/termReturn "n")))))
        (fieldFn (emptyRecordCase "emptyField" (list (irTy/ssaInstr "f" (irTy/tyVal) (irTy/opField "q" "zz"))) "f"))
        (m (irTy/ssaModule "objEmpty" (list) (list) (list (irTy/SsaRecordDecl :name "Empty" :fields (list))) (list) (list) (list idFn pickFn eqFn fieldFn)))
        (twin (str dir "/objEmptyHost.asl"))]
    (do
      (assert (ok? (fileWrite twin (str "(module objEmptyHost :x [main] :i [])\n\n(schema Empty)\n\nfn idOf x: T -> T\n  x\n\n"
                                        "fn ! main args: (List String) -> (Result Int64 String)\n"
                                        "  (do (println (str (if (= (idOf (Empty)) (Empty)) 1 2)))\n      (println (str (idOf (Empty)).zz))\n      (ok 0))\n")))
              "fileWrite objEmptyHost.asl")
      (let [(interp (processRun (str (host) " run " twin)))]
        (do
          (assert (= interp.stdout "1\n") (str "objEmptyHost: asl-host prints 1, got " interp.stdout interp.stderr))
          (map (fn [(entry String)] -> Bool
                 (mt (llvm/emitLlvmProgram m entry)
                   ((err ds) (do (assert false (str entry " emits: " (formatDiags ds))) true))
                   ((ok code)
                     (do
                       (verified dir entry code)
                       (let [(out (processRun (nativeExe dir entry "")))]
                         (if (= entry "emptyEq")
                           (assert (= out.exitCode 1) (str "emptyEq: equal empty records exit 1 as asl-host prints 1; exit " out.exitCode " stderr " out.stderr))
                           (do (assert (= out.exitCode 1) (str "emptyField: exit 1, got " out.exitCode))
                               (assert (= out.stderr (str (hostErrorLine interp) "\n")) (str "emptyField: native stderr is asl-host's " (hostErrorLine interp) "; got " out.stderr)))))
                       true))))
               (list "emptyEq" "emptyField"))
          true))))

fn suiteSource -> String
  (str (stringJoin (list
    "(module objSuite :x [checks] :i [])"
    ""
    "fn idOf x: T -> T"
    "  x"
    ""
    "fn ! checks n: T -> T"
    "  (do (assert (= (idOf n) n) \"n is itself\")"
    "      (assert (> (idOf n) 0) \"n is positive\")"
    "      (refute (= (idOf n) 0) \"n is not zero\")"
    "      (- n 7))") "\n") "\n")

fn ! testReport dir: String -> Bool
  (mt (low/lowerSource (suiteSource))
    ((err ds) (assert false (str "objSuite lowers: " (formatDiags ds))))
    ((ok suite)
      (mt (ssa/emitLlvmModule suite)
        ((err ds) (assert false (str "objSuite emits: " (formatDiags ds))))
        ((ok suiteCode)
          (let [(entry (irTy/ssaModule "objEntry" (list) (list) (list) (list (irTy/ssaExtern "checks" 1)) (list)
                         (list (irTy/ssaFunction "start" (list) (list) (irTy/tyVal)
                                 (list (irTy/ssaBlock "entry" (list)
                                         (list (irTy/ssaInstr "seven" (irTy/tyVal) (irTy/opConst (irTy/constInt 7)))
                                               (irTy/ssaInstr "r" (irTy/tyVal) (irTy/opCall "checks" (list "seven"))))
                                         (irTy/termReturn "r")))))))]
            (mt (llvm/emitLlvmProgram entry "start")
              ((err ds) (assert false (str "objEntry emits: " (formatDiags ds))))
              ((ok entryCode)
                (do
                  (verified dir "objSuite" suiteCode)
                  (verified dir "objEntry" entryCode)
                  (refute (stringContains? entryCode "@rterr.assert(") "objEntry: the entry module holds no assert")
                  (let [(exe (str dir "/objReport"))
                        (linked (processRun (str (clangIr) dir "/objEntry.ll " dir "/objSuite.ll" (lib) exe)))
                        (reported (processRun (str "ASL_ASSERT_REPORT=1 " exe)))
                        (quiet (processRun exe))]
                    (do
                      (assert (= linked.exitCode 0) (str "objReport: the two modules link: " linked.stderr))
                      (assert (= reported.exitCode 0) (str "objReport: exit 0, got " reported.exitCode "; stderr " reported.stderr))
                      (assert (= reported.stderr "2 assertion(s) executed, 1 refutation(s) executed\n") (str "objReport: ASL_ASSERT_REPORT=1 reports the suite's counts; stderr " reported.stderr))
                      (assert (and (= quiet.exitCode 0) (= quiet.stderr "")) (str "objReport: no report without ASL_ASSERT_REPORT; stderr " quiet.stderr))
                      true))))))))))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testRuntimeDecls)
      (testArchive)
      (testFixture dir)
      (testCapture300 dir)
      (testEmptyRecord dir)
      (testCRecord dir)
      (testSymbol dir)
      (testReport dir)
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
