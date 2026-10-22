(module asl-target-llvm/tests/nativeOpsTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/lower :a low) (asl-ir/types :a irTy) (asl-target-llvm :a llvm) (asl-target-llvm/ssa :a ssa)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): testParity/testValues/testSsaBuiltins used asl-host as a live parity oracle for a hand-built native binary over opsFixture/opsValues/each ssaCase's fixture. Every fixture and every case string is fixed (idOf is the identity function; the fixtures never read argv beyond the case args), so the oracle is replaced by recordedCase/recordedSsa/recordedValuesHost literal tables, captured once from the leftover asl-host binary before HL-DELETE removed it, covering all of matrixCases ++ edgeCases (276 distinct case strings) plus the 11 ssaCases plus the opsValuesHost lambda fixture. The native side (lower/emit/link/exe) is unchanged")

(schema Recorded
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn fixtureLines -> (List String)
  (list "(module opsFixture :x [main] :i [])"
        ""
        "(schema P (:f x Int64) (:f y Int64))"
        ""
        "(schema Q (:f x Int64) (:f y Int64))"
        ""
        "(schema Outer (:f inner P) (:f items (List Int64)))"
        ""
        "(enum Shape (:c circle [(r Int64)] \"Circle\") (:c rect [(w Int64) (h Int64)] \"Rect\"))"
        ""
        "fn idOf x: T -> T"
        "  x"
        ""
        "fn nest n: Int64 acc: T -> T"
        "  (if (= n 0) acc (nest (- n 1) (idOf (list acc))))"
        ""
        "fn upTo n: Int64 last: Int64 acc: T -> T"
        "  (if (= n 0) acc (upTo (- n 1) last (idOf (cons n acc))))"
        ""
        "fn longList last: Int64 -> T"
        "  (upTo 99999 last (idOf (list last)))"
        ""
        "fn valueOf name: String -> T"
        "  (cond ((= name \"i7\") (idOf 7)) ((= name \"im7\") (idOf -7)) ((= name \"i1\") (idOf 1)) ((= name \"i2\") (idOf 2)) ((= name \"im2\") (idOf -2))"
        "        ((= name \"i3\") (idOf 3)) ((= name \"im3\") (idOf -3)) ((= name \"i0\") (idOf 0)) ((= name \"im1\") (idOf -1))"
        "        ((= name \"max\") (idOf 9223372036854775807)) ((= name \"min\") (idOf (- -9223372036854775807 1)))"
        "        ((= name \"f75\") (idOf 7.5)) ((= name \"fm2\") (idOf -2.0)) ((= name \"f2\") (idOf 2.0)) ((= name \"f0\") (idOf 0.0)) ((= name \"fm0\") (idOf -0.0))"
        "        ((= name \"f55\") (idOf 5.5)) ((= name \"fm55\") (idOf -5.5)) ((= name \"f4\") (idOf 4.0)) ((= name \"fm4\") (idOf -4.0))"
        "        ((= name \"nan\") (/ (idOf 0.0) (idOf 0.0))) ((= name \"inf\") (/ (idOf 1.0) (idOf 0.0)))"
        "        ((= name \"sa\") (idOf \"abc\")) ((= name \"sb\") (idOf \"abd\")) ((= name \"sc\") (idOf \"ab\")) ((= name \"se\") (idOf \"\"))"
        "        ((= name \"sn\") (idOf \"a\\x00c\")) ((= name \"so\") (idOf \"a\\x00b\"))"
        "        ((= name \"ka\") (idOf :alpha)) ((= name \"kb\") (idOf :beta)) ((= name \"kc\") (idOf :alpha))"
        "        ((= name \"l1\") (idOf (list 1 2))) ((= name \"l2\") (idOf (list 1 3))) ((= name \"l3\") (idOf (list 1 2 3))) ((= name \"le\") (idOf (list)))"
        "        ((= name \"lm\") (idOf (list 1 \"x\"))) ((= name \"ll\") (idOf (list (list 1) (list 2 3))))"
        "        ((= name \"r1\") (idOf (P :x 1 :y 2))) ((= name \"r2\") (idOf (P :x 1 :y 3))) ((= name \"rk\") (idOf (P :y 2 :x 1))) ((= name \"q1\") (idOf (Q :x 1 :y 2)))"
        "        ((= name \"o1\") (idOf (Outer :inner (P :x 1 :y 2) :items (list 1 2)))) ((= name \"o2\") (idOf (Outer :inner (P :x 1 :y 2) :items (list 1 2))))"
        "        ((= name \"o3\") (idOf (Outer :items (list 1 2) :inner (P :y 2 :x 1)))) ((= name \"o4\") (idOf (Outer :inner (P :x 1 :y 9) :items (list 1 2))))"
        "        ((= name \"o5\") (idOf (Outer :inner (P :x 1 :y 2) :items (list 1 2 3))))"
        "        ((= name \"c1\") (idOf (some 1))) ((= name \"c2\") (idOf (some 2))) ((= name \"cn\") (idOf none))"
        "        ((= name \"s1\") (idOf (circle 1))) ((= name \"s2\") (idOf (rect 1 2))) ((= name \"s3\") (idOf (rect 1 3)))"
        "        ((= name \"ba\") (idOf (stringToBytes \"ab\"))) ((= name \"bb\") (idOf (stringToBytes \"ac\"))) ((= name \"be\") (idOf (stringToBytes \"\")))"
        "        ((= name \"u\") (idOf ())) ((= name \"t\") (idOf true)) ((= name \"f\") (idOf false))"
        "        (else (idOf \"no such value\")))"
        ""
        "fn apply op: String a: T b: T -> T"
        "  (cond ((= op \"+\") (+ a b)) ((= op \"-\") (- a b)) ((= op \"*\") (* a b)) ((= op \"/\") (/ a b)) ((= op \"mod\") (mod a b))"
        "        ((= op \"<\") (< a b)) ((= op \"<=\") (<= a b)) ((= op \">\") (> a b)) ((= op \">=\") (>= a b)) ((= op \"=\") (= a b)) ((= op \"!=\") (!= a b))"
        "        ((= op \"neg\") (- a)) ((= op \"not\") (not a))"
        "        (else (idOf \"no such operator\")))"
        ""
        "fn special op: String c: T d: T -> T"
        "  (let [(f (fn [(x T)] -> T x)) (g (fn [(x T)] -> T x))]"
        "    (cond ((= op \"+4\") (+ c d c d)) ((= op \"*3\") (* c d c))"
        "          ((= op \"sameFn\") (= f f)) ((= op \"otherFn\") (= f g)) ((= op \"neFn\") (!= f g))"
        "          ((= op \"deep9999\") (= (nest 9999 (idOf 0)) (nest 9999 (idOf 0))))"
        "          ((= op \"deep10000\") (= (nest 10000 (idOf 0)) (nest 10000 (idOf 0))))"
        "          ((= op \"deepNe10000\") (!= (nest 10000 (idOf 0)) (nest 10000 (idOf 0))))"
        "          ((= op \"deep100000\") (= (nest 100000 (idOf 0)) (nest 100000 (idOf 0))))"
        "          ((= op \"deepDiffer\") (= (nest 9999 (idOf 0)) (nest 9999 (idOf 1))))"
        "          ((= op \"long\") (= (longList 0) (longList 0)))"
        "          ((= op \"longDiffer\") (= (longList 0) (longList 1)))"
        "          (else (idOf \"no such case\"))))"
        ""
        "fn ! main args: (List String) -> (Result Int64 String)"
        "  (let [(op (optionOr (listHead args) \"\"))"
        "        (a (valueOf (optionOr (listGet args 1) \"\")))"
        "        (b (valueOf (optionOr (listGet args 2) \"\")))]"
        "    (do (println (str (if (or (= op \"+4\") (or (= op \"*3\") (= (listLength args) 1))) (special op a b) (apply op a b))))"
        "        (ok 0)))")

fn fixtureSrc -> String
  (str (stringJoin (fixtureLines) "\n") "\n")

fn binaryOps -> (List String)
  (list "+" "-" "*" "/" "mod" "<" "<=" ">" ">=" "=" "!=")

fn opSymbols -> (List (Pair String String))
  (list (pair "+" "add") (pair "-" "sub") (pair "*" "mul") (pair "/" "div") (pair "mod" "mod")
        (pair "<" "lt") (pair "<=" "le") (pair ">" "gt") (pair ">=" "ge") (pair "=" "eq") (pair "!=" "ne") (pair "not" "not"))

fn deletedEntries -> (List String)
  (listAppend (map (fn [(p (Pair String String))] -> String (str "asl_rt_b_" (pairSecond p))) (opSymbols))
              (list "asl_rt_int" "asl_rt_float" "asl_rt_bool" "asl_rt_unit" "asl_rt_unbox_int" "asl_rt_unbox_float" "asl_rt_unbox_bool"))

fn pairKinds -> (List (Pair String String))
  (list (pair "i7" "im3") (pair "f75" "fm2") (pair "i7" "f2") (pair "f75" "i2") (pair "sa" "sb") (pair "l1" "l2") (pair "r1" "r2")
        (pair "c1" "c2") (pair "u" "u") (pair "t" "f") (pair "ka" "kb") (pair "ba" "be") (pair "sa" "i7"))

fn matrixCases -> (List String)
  (fold (fn [(acc (List String)) (op String)] -> (List String)
          (listAppend acc (map (fn [(p (Pair String String))] -> String (str op " " (pairFirst p) " " (pairSecond p))) (pairKinds))))
        (list) (binaryOps))

fn edgeCases -> (List String)
  (list "/ i7 i2" "/ im7 i2" "/ i7 im2" "/ im7 im2" "/ i7 im1" "/ min im1" "/ i0 i3" "/ i7 i0" "/ im7 i7" "/ max im1"
        "mod i7 i2" "mod im7 i2" "mod i7 im2" "mod im7 im2" "mod min im1" "mod i7 im1" "mod i7 i0" "mod i0 im3"
        "mod f55 f2" "mod fm55 f2" "mod f55 fm2" "mod fm4 f2" "mod f4 fm2" "mod f0 f2" "mod f75 f0" "mod nan f2" "mod f2 inf"
        "/ f75 f0" "/ fm2 f0" "/ f0 f0" "- inf inf" "* inf f0"
        "+ max i1" "+ min im1" "- min i1" "- max im1" "* max i2" "* min im1" "* max max" "+ max im1" "- min im1" "* min i1"
        "= nan nan" "!= nan nan" "= fm0 f0" "!= fm0 f0" "< fm0 f0" "<= fm0 f0" "< nan f0" ">= nan nan" "> inf max" "= inf inf" "< f0 nan"
        "< sc sa" "> sa sc" "<= se se" "< se sa" "= sa sa" "< sn so" "> sn so" "= sn so" "!= sa sc" ">= sb sa"
        "< ka kb" "> ka kb" "= ka kc" "!= ka kb" "<= kb ka" ">= ka kc"
        "= l1 l3" "= le le" "= l1 le" "= ll ll" "= l1 lm" "!= l1 l2" "= l3 l1" "< l1 l1"
        "= r1 rk" "= r1 q1" "= o1 o2" "= o1 o3" "= o1 o4" "= o1 o5" "!= r1 r2" "= r1 i7" "!= r1 rk" "<= r1 r1"
        "= c1 c1" "= c1 cn" "= cn cn" "= s1 s1" "= s1 s2" "= s2 s3" "= c1 s1" "!= c1 c2" "> c1 c1"
        "= ba ba" "= ba bb" "= be be" "= ba be" "!= ba bb"
        "= u u" "!= u u" "= t t" "!= t f" "= u t"
        "= i7 f2" "!= sa i7" "= l1 r1" "!= ka sa"
        "neg i7" "neg im7" "neg f75" "neg fm0" "neg f0" "neg nan" "neg min" "neg max" "neg sa" "neg u" "neg t"
        "not t" "not f" "not i1" "not u" "not sa"
        "+4 i1 i2" "+4 f75 f2" "+4 i1 sa" "+4 max i1" "*3 i2 i3" "*3 max i2" "*3 f2 fm2" "*3 i2 f2" "+4 sa sb"
        "sameFn" "otherFn" "neFn" "deep9999" "deep10000" "deepNe10000" "deep100000" "deepDiffer" "long" "longDiffer")

fn valuesTemplate -> (List String)
  (list "(module opsValues :x [main] :i [])"
        ""
        "fn idOf x: T -> T"
        "  x"
        ""
        "fn ! main -> (Result Int64 String)"
        "  (let [(a (idOf 7)) (b (idOf 3)) (x (idOf 2.5)) (y (idOf -0.5))]"
        "    (do (println (str (map (fn [(f T)] -> T (f a b)) (list {+} {-} {*} {/} {mod} {<} {<=} {>} {>=} {=} {!=}))))"
        "        (println (str (map (fn [(f T)] -> T (f x y)) (list {+} {-} {*} {/} {mod} {<} {<=} {>} {>=} {=} {!=}))))"
        "        (println (str (fold {+} 0 (list 1 2 3 4)) \" \" (fold {*} 1 (list 1 2 3 4)) \" \" (fold {-} 0.5 (list 1.5 2.5)) \" \" (map {not} (list true false))))"
        "        (ok 0)))")

fn lambdaFor op: String -> String
  (if (= op "not") "(fn [(p T)] -> T (not p))" (str "(fn [(p T) (q T)] -> T (" op " p q))"))

fn valuesSrc asValues: Bool -> String
  (str (fold (fn [(text String) (p (Pair String String))] -> String
               (stringReplace text (str "{" (pairFirst p) "}") (if asValues (pairFirst p) (lambdaFor (pairFirst p)))))
             (stringJoin (valuesTemplate) "\n") (opSymbols))
       "\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiled path: String -> (Result String String)
  (match (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (match (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (processRun (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (match (listHead known)
      ((some o) (some o))
      ((none) (if (= (processRun "command -v opt >/dev/null 2>&1").exitCode 0) (some "opt") (none)))))

fn ! testRuntimeDecls -> Bool
  (do
    (refute (listAny? (fn [(d String)] -> Bool (stringContains? d "@asl_rt_b_")) (llvm/runtimeDecls)) "runtimeDecls declares no asl_rt_b_ entry")
    (map (fn [(n String)] -> Bool
           (do (refute (listAny? (fn [(d String)] -> Bool (stringContains? d (str "@" n "("))) (llvm/runtimeDecls)) (str "runtimeDecls declares no " n))
               true))
         (deletedEntries))
    true)

fn ! testArchive -> Bool
  (let [(listed (processRun "nm -g asl/host/out/libaslrt.a"))]
    (do
      (assert (= listed.exitCode 0) (str "nm lists libaslrt.a: " listed.stderr))
      (assert (stringContains? listed.stdout "asl_rt_init\n") "nm output holds the entries libaslrt.a keeps")
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? listed.stdout (str "_" n "\n")) (str "libaslrt.a defines no " n))
                 true))
           (deletedEntries))
      true))

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): sourceDirs used to scan asl/host/src (the old C runtime, abi.c etc.) alongside this package for stale asl_rt_b_* names. HL-DELETE removed asl/host/src entirely (only build.sh, out/ and tests/ remain under asl/host/), so dirList on it fails with notFound; dropped, since the C runtime it scanned no longer exists anywhere and its replacement, asl-target-llvm/src/rtAbi.asl, is already covered by the first dir below (testStaleNames still asserts rtAbi.asl is among the scanned files)")
fn sourceDirs -> (List (Pair String (List String)))
  (list (pair "asl/packages/asl-target-llvm/src" (list ".asl"))
        (pair "asl/packages/asl-target-llvm/tests" (list ".asl")))

fn ! sourceFiles -> (List String)
  (fold (fn [(acc (List String)) (d (Pair String (List String)))] -> (List String)
          (match (dirList (pairFirst d))
            ((err e) (do (assert false (str "lists " (pairFirst d) ": " e)) acc))
            ((ok names) (listAppend acc (map (fn [(n String)] -> String (str (pairFirst d) "/" n))
                                             (filter (fn [(n String)] -> Bool (listAny? (fn [(s String)] -> Bool (stringEndsWith? n s)) (pairSecond d))) names))))))
        (list) (sourceDirs))

fn ! testStaleNames -> Bool
  (let [(files (sourceFiles))
        (names (listAppend (map (fn [(p (Pair String String))] -> String (str "asl_rt_b_" (pairSecond p))) (opSymbols)) (list (str "OPEN" "TRY("))))
        (stale (fold (fn [(acc (List String)) (f String)] -> (List String)
                       (match (fileReadString f)
                         ((err e) (do (assert false (str "reads " f ": " e)) acc))
                         ((ok text) (listAppend acc (map (fn [(n String)] -> String (str f ": " n))
                                                         (filter (fn [(n String)] -> Bool (stringContains? text n)) names))))))
                     (list) files))]
    (do
      (assert (> (listLength files) 60) (str "scans the package and the host runtime, got " (listLength files) " files"))
      (assert (listAny? (fn [(f String)] -> Bool (stringEndsWith? f "/rtAbi.asl")) files) "scans asl-target-llvm/src/rtAbi.asl, which replaced asl/host/src/abi.c")
      (assert (listEmpty? stale) (str "no source names an operator entry; stale: " (stringJoin stale "; ")))
      true))

fn ! testIr dir: String name: String code: String helpers: (List String) -> Bool
  (let [(ll (str dir "/" name ".ll"))]
    (do
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@" n "(")) (str name ": the IR neither declares nor calls " n))
                 true))
           (deletedEntries))
      (refute (stringContains? code "@asl_rt_b_") (str name ": the IR names no asl_rt_b_ entry"))
      (map (fn [(p (Pair String String))] -> Bool
             (do (refute (stringContains? code (str "(ptr @name." (ssa/llvmName (pairFirst p)) ", i64 ")) (str name ": no asl_rt_builtin call names " (pairFirst p)))
                 true))
           (opSymbols))
      (map (fn [(h String)] -> Bool
             (do (assert (stringContains? code (str " @opsrt." h "(%Val ")) (str name ": the IR calls @opsrt." h))
                 true))
           helpers)
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (match (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (processRun (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str name ": opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn ! nativeExe dir: String name: String -> String
  (let [(exe (str dir "/" name))
        (linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " exe ".ll -x none asl/host/out/libaslrt.a -lm -o " exe)))]
    (do (assert (= linked.exitCode 0) (str name " links against libaslrt.a: " linked.stderr))
        exe))

fn recordedCase args: String -> Recorded
  (cond
    ((= args "!= ba bb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= ba be") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= c1 c2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= f75 fm2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Float with Int (after 0 asserts)\n"))
    ((= args "!= fm0 f0") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "!= i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Int with Float (after 0 asserts)\n"))
    ((= args "!= i7 im3") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= ka kb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= ka sa") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Keyword with String (after 0 asserts)\n"))
    ((= args "!= l1 l2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= nan nan") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= r1 r2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= r1 rk") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "!= sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares String with Int (after 0 asserts)\n"))
    ((= args "!= sa sb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= sa sc") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= t f") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "!= u u") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "* ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "* c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "* f75 fm2") (Recorded :exitCode 0 :stdout "-15.0\n" :stderr ""))
    ((= args "* f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "* i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "* i7 im3") (Recorded :exitCode 0 :stdout "-21\n" :stderr ""))
    ((= args "* inf f0") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "* ka kb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Keyword and Keyword (after 0 asserts)\n"))
    ((= args "* l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "* max i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "* max max") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "* min i1") (Recorded :exitCode 0 :stdout "-9223372036854775808\n" :stderr ""))
    ((= args "* min im1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "* r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "* sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "* sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "* t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "* u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "*3 f2 fm2") (Recorded :exitCode 0 :stdout "-8.0\n" :stderr ""))
    ((= args "*3 i2 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: * expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "*3 i2 i3") (Recorded :exitCode 0 :stdout "12\n" :stderr ""))
    ((= args "*3 max i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int * leaves int64 (after 0 asserts)\n"))
    ((= args "+ ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "+ c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "+ f75 fm2") (Recorded :exitCode 0 :stdout "5.5\n" :stderr ""))
    ((= args "+ f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "+ i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "+ i7 im3") (Recorded :exitCode 0 :stdout "4\n" :stderr ""))
    ((= args "+ ka kb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Keyword and Keyword (after 0 asserts)\n"))
    ((= args "+ l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "+ max i1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "+ max im1") (Recorded :exitCode 0 :stdout "9223372036854775806\n" :stderr ""))
    ((= args "+ min im1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "+ r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "+ sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "+ sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "+ t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "+ u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "+4 f75 f2") (Recorded :exitCode 0 :stdout "19.0\n" :stderr ""))
    ((= args "+4 i1 i2") (Recorded :exitCode 0 :stdout "6\n" :stderr ""))
    ((= args "+4 i1 sa") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got Int and String (after 0 asserts)\n"))
    ((= args "+4 max i1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= args "+4 sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: + expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "- ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "- c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "- f75 fm2") (Recorded :exitCode 0 :stdout "9.5\n" :stderr ""))
    ((= args "- f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "- i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "- i7 im3") (Recorded :exitCode 0 :stdout "10\n" :stderr ""))
    ((= args "- inf inf") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "- ka kb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Keyword and Keyword (after 0 asserts)\n"))
    ((= args "- l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "- max im1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int - leaves int64 (after 0 asserts)\n"))
    ((= args "- min i1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int - leaves int64 (after 0 asserts)\n"))
    ((= args "- min im1") (Recorded :exitCode 0 :stdout "-9223372036854775807\n" :stderr ""))
    ((= args "- r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "- sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "- sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "- t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "- u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "/ ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "/ c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "/ f0 f0") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "/ f75 f0") (Recorded :exitCode 0 :stdout "inf\n" :stderr ""))
    ((= args "/ f75 fm2") (Recorded :exitCode 0 :stdout "-3.75\n" :stderr ""))
    ((= args "/ f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "/ fm2 f0") (Recorded :exitCode 0 :stdout "-inf\n" :stderr ""))
    ((= args "/ i0 i3") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "/ i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "/ i7 i0") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_DIV_ZERO: division by zero (after 0 asserts)\n"))
    ((= args "/ i7 i2") (Recorded :exitCode 0 :stdout "3\n" :stderr ""))
    ((= args "/ i7 im1") (Recorded :exitCode 0 :stdout "-7\n" :stderr ""))
    ((= args "/ i7 im2") (Recorded :exitCode 0 :stdout "-4\n" :stderr ""))
    ((= args "/ i7 im3") (Recorded :exitCode 0 :stdout "-3\n" :stderr ""))
    ((= args "/ im7 i2") (Recorded :exitCode 0 :stdout "-4\n" :stderr ""))
    ((= args "/ im7 i7") (Recorded :exitCode 0 :stdout "-1\n" :stderr ""))
    ((= args "/ im7 im2") (Recorded :exitCode 0 :stdout "3\n" :stderr ""))
    ((= args "/ ka kb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Keyword and Keyword (after 0 asserts)\n"))
    ((= args "/ l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "/ max im1") (Recorded :exitCode 0 :stdout "-9223372036854775807\n" :stderr ""))
    ((= args "/ min im1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int / leaves int64 (after 0 asserts)\n"))
    ((= args "/ r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "/ sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "/ sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "/ t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "/ u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: / expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "< ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "< c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "< f0 nan") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< f75 fm2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "< fm0 f0") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "< i7 im3") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< ka kb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "< l1 l1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "< l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "< nan f0") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "< sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "< sa sb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "< sc sa") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "< se sa") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "< sn so") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "< t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "< u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: < expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "<= ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "<= c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "<= f75 fm2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "<= f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "<= fm0 f0") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "<= i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "<= i7 im3") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "<= ka kb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "<= kb ka") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "<= l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "<= r1 r1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "<= r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "<= sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "<= sa sb") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "<= se se") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "<= t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "<= u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: <= expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "= ba ba") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= ba bb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= ba be") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= be be") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= c1 c1") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= c1 c2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= c1 cn") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= c1 s1") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= cn cn") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= f75 fm2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Float with Int (after 0 asserts)\n"))
    ((= args "= fm0 f0") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Int with Float (after 0 asserts)\n"))
    ((= args "= i7 im3") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= inf inf") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= ka kb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= ka kc") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= l1 l2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= l1 l3") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= l1 le") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= l1 lm") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Int with String (after 0 asserts)\n"))
    ((= args "= l1 r1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares List with Record (after 0 asserts)\n"))
    ((= args "= l3 l1") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= le le") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= ll ll") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= nan nan") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= o1 o2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= o1 o3") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= o1 o4") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= o1 o5") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= r1 i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Record with Int (after 0 asserts)\n"))
    ((= args "= r1 q1") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= r1 r2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= r1 rk") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= s1 s1") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= s1 s2") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= s2 s3") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares String with Int (after 0 asserts)\n"))
    ((= args "= sa sa") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= sa sb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= sn so") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= t f") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "= t t") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "= u t") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: = compares Unit with Bool (after 0 asserts)\n"))
    ((= args "= u u") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "> ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "> c1 c1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "> c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "> f75 fm2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "> f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "> i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "> i7 im3") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "> inf max") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "> ka kb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "> l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "> r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "> sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "> sa sb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "> sa sc") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "> sn so") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "> t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "> u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: > expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args ">= ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args ">= c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args ">= f75 fm2") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args ">= f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args ">= i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args ">= i7 im3") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args ">= ka kb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args ">= ka kc") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args ">= l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args ">= nan nan") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args ">= r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args ">= sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args ">= sa sb") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args ">= sb sa") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args ">= t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args ">= u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: >= expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "deep10000") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_DEPTH: = on values nested deeper than 10000 (after 0 asserts)\n"))
    ((= args "deep100000") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_DEPTH: = on values nested deeper than 10000 (after 0 asserts)\n"))
    ((= args "deep9999") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "deepDiffer") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "deepNe10000") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_DEPTH: = on values nested deeper than 10000 (after 0 asserts)\n"))
    ((= args "long") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "longDiffer") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "mod ba be") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Bytes and Bytes (after 0 asserts)\n"))
    ((= args "mod c1 c2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Variant and Variant (after 0 asserts)\n"))
    ((= args "mod f0 f2") (Recorded :exitCode 0 :stdout "0.0\n" :stderr ""))
    ((= args "mod f2 inf") (Recorded :exitCode 0 :stdout "2.0\n" :stderr ""))
    ((= args "mod f4 fm2") (Recorded :exitCode 0 :stdout "-0.0\n" :stderr ""))
    ((= args "mod f55 f2") (Recorded :exitCode 0 :stdout "1.5\n" :stderr ""))
    ((= args "mod f55 fm2") (Recorded :exitCode 0 :stdout "-0.5\n" :stderr ""))
    ((= args "mod f75 f0") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "mod f75 fm2") (Recorded :exitCode 0 :stdout "-0.5\n" :stderr ""))
    ((= args "mod f75 i2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Float and Int (after 0 asserts)\n"))
    ((= args "mod fm4 f2") (Recorded :exitCode 0 :stdout "0.0\n" :stderr ""))
    ((= args "mod fm55 f2") (Recorded :exitCode 0 :stdout "0.5\n" :stderr ""))
    ((= args "mod i0 im3") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "mod i7 f2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Int and Float (after 0 asserts)\n"))
    ((= args "mod i7 i0") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_DIV_ZERO: mod by zero (after 0 asserts)\n"))
    ((= args "mod i7 i2") (Recorded :exitCode 0 :stdout "1\n" :stderr ""))
    ((= args "mod i7 im1") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "mod i7 im2") (Recorded :exitCode 0 :stdout "-1\n" :stderr ""))
    ((= args "mod i7 im3") (Recorded :exitCode 0 :stdout "-2\n" :stderr ""))
    ((= args "mod im7 i2") (Recorded :exitCode 0 :stdout "1\n" :stderr ""))
    ((= args "mod im7 im2") (Recorded :exitCode 0 :stdout "-1\n" :stderr ""))
    ((= args "mod ka kb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Keyword and Keyword (after 0 asserts)\n"))
    ((= args "mod l1 l2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got List and List (after 0 asserts)\n"))
    ((= args "mod min im1") (Recorded :exitCode 0 :stdout "0\n" :stderr ""))
    ((= args "mod nan f2") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "mod r1 r2") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Record and Record (after 0 asserts)\n"))
    ((= args "mod sa i7") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got String and Int (after 0 asserts)\n"))
    ((= args "mod sa sb") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got String and String (after 0 asserts)\n"))
    ((= args "mod t f") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Bool and Bool (after 0 asserts)\n"))
    ((= args "mod u u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: mod expects two Int or two Float, got Unit and Unit (after 0 asserts)\n"))
    ((= args "neFn") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "neg f0") (Recorded :exitCode 0 :stdout "-0.0\n" :stderr ""))
    ((= args "neg f75") (Recorded :exitCode 0 :stdout "-7.5\n" :stderr ""))
    ((= args "neg fm0") (Recorded :exitCode 0 :stdout "0.0\n" :stderr ""))
    ((= args "neg i7") (Recorded :exitCode 0 :stdout "-7\n" :stderr ""))
    ((= args "neg im7") (Recorded :exitCode 0 :stdout "7\n" :stderr ""))
    ((= args "neg max") (Recorded :exitCode 0 :stdout "-9223372036854775807\n" :stderr ""))
    ((= args "neg min") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_INT_OVERFLOW: Int - leaves int64 (after 0 asserts)\n"))
    ((= args "neg nan") (Recorded :exitCode 0 :stdout "nan\n" :stderr ""))
    ((= args "neg sa") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects Int or Float, got String (after 0 asserts)\n"))
    ((= args "neg t") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects Int or Float, got Bool (after 0 asserts)\n"))
    ((= args "neg u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: - expects Int or Float, got Unit (after 0 asserts)\n"))
    ((= args "not f") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    ((= args "not i1") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: not expects Bool, got Int (after 0 asserts)\n"))
    ((= args "not sa") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: not expects Bool, got String (after 0 asserts)\n"))
    ((= args "not t") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "not u") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/fixture.asl: ERR_TYPE: not expects Bool, got Unit (after 0 asserts)\n"))
    ((= args "otherFn") (Recorded :exitCode 0 :stdout "false\n" :stderr ""))
    ((= args "sameFn") (Recorded :exitCode 0 :stdout "true\n" :stderr ""))
    (else (Recorded :exitCode -1 :stdout "" :stderr (str "no recorded case: " args))))

fn ! recordedSsa name: String -> Recorded
  (let [(home (str (optionOr (envGet "HOME") "/tmp") "/opsCapRecorded"))]
  (cond
    ((= name "nary") (Recorded :exitCode 0 :stdout "10\n" :stderr ""))
    ((= name "product") (Recorded :exitCode 0 :stdout "24\n" :stderr ""))
    ((= name "pair") (Recorded :exitCode 0 :stdout "1\n" :stderr ""))
    ((= name "negate") (Recorded :exitCode 0 :stdout "7\n" :stderr ""))
    ((= name "notFalse") (Recorded :exitCode 0 :stdout "1\n" :stderr ""))
    ((= name "less") (Recorded :exitCode 0 :stdout "2\n" :stderr ""))
    ((= name "equal") (Recorded :exitCode 0 :stdout "1\n" :stderr ""))
    ((= name "naryOverflow") (Recorded :exitCode 1 :stdout "" :stderr "FAIL asl/tmp/opsCap/naryOverflowHost.asl: ERR_INT_OVERFLOW: Int + leaves int64 (after 0 asserts)\n"))
    ((= name "subThree") (Recorded :exitCode 1 :stdout "" :stderr (str home "/asl/tmp/opsCap/subThreeHost.asl:7:21: ERR_ARITY - takes 2 operands, got 3\nFAIL asl/tmp/opsCap/subThreeHost.asl: 1 load error(s) (after 0 asserts)\n")))
    ((= name "lessOne") (Recorded :exitCode 1 :stdout "" :stderr (str home "/asl/tmp/opsCap/lessOneHost.asl:7:21: ERR_ARITY < takes 2 operands, got 1\nFAIL asl/tmp/opsCap/lessOneHost.asl: 1 load error(s) (after 0 asserts)\n")))
    ((= name "notTwo") (Recorded :exitCode 1 :stdout "" :stderr (str home "/asl/tmp/opsCap/notTwoHost.asl:7:21: ERR_ARITY not takes 1 operand\nFAIL asl/tmp/opsCap/notTwoHost.asl: 1 load error(s) (after 0 asserts)\n")))
    (else (Recorded :exitCode -1 :stdout "" :stderr (str "no recorded ssa case: " name)))))

fn recordedValuesHost -> Recorded
  (Recorded :exitCode 0 :stdout "(10 4 21 2 1 false false true true false true)\n(2.0 3.0 -1.25 -5.0 -0.0 false false true true false true)\n10 24 -3.5 (false true)\n" :stderr "")

fn ! testParity exe: String src: String args: String -> Bool
  (let [(quoted (stringJoin (map (fn [(a String)] -> String (str "'" a "'")) (stringSplit args " ")) " "))
        (native (processRun (str exe " " quoted)))
        (interp (recordedCase args))
        (line (stringReplace native.stderr "\n" ""))]
    (do
      (assert (= native.exitCode interp.exitCode) (str args ": native exit " native.exitCode " equals the recorded asl-host exit " interp.exitCode "; native stderr " native.stderr "; recorded stderr " interp.stderr))
      (assert (= native.stdout interp.stdout) (str args ": native prints " native.stdout " and the recorded asl-host run " interp.stdout))
      (refute (stringContains? interp.stdout "no such") (str args ": the fixture knows the case and its values, got " interp.stdout))
      (if (= interp.exitCode 0)
        (do (assert (> (stringLength interp.stdout) 1) (str args ": the recorded asl-host run prints a result"))
            (assert (= native.stderr "") (str args ": native stderr empty, got " native.stderr)))
        (do (assert (stringStartsWith? line "ERR_") (str args ": native stderr is one error line: " native.stderr))
            (assert (= native.stderr (str line "\n")) (str args ": native stderr is a single line: " native.stderr))
            (assert (stringContains? interp.stderr (str ": " line " (after")) (str args ": the recorded asl-host run reports " line "; it reported " interp.stderr))))
      true))

fn ! testValues dir: String -> Bool
  (let [(nativeSrc (str dir "/opsValues.asl"))
        (hostSrc (str dir "/opsValuesHost.asl"))]
    (do
      (assert (ok? (fileWrite nativeSrc (valuesSrc true))) (str "fileWrite " nativeSrc))
      (assert (ok? (fileWrite hostSrc (valuesSrc false))) (str "fileWrite " hostSrc))
      (match (compiled nativeSrc)
        ((err e) (do (assert false (str "opsValues links and emits: " e)) true))
        ((ok code)
          (do
            (testIr dir "opsValues" code (map (fn [(p (Pair String String))] -> String (pairSecond p)) (opSymbols)))
            (let [(exe (nativeExe dir "opsValues"))
                  (native (processRun exe))
                  (interp (recordedValuesHost))]
              (do
                (assert (= interp.exitCode 0) (str "opsValues: the recorded asl-host run of the lambda twin exits 0: " interp.stderr))
                (assert (= native.exitCode 0) (str "opsValues: native exit " native.exitCode "; stderr " native.stderr))
                (assert (> (stringLength interp.stdout) 40) (str "opsValues: the recorded asl-host run prints three lines, got " interp.stdout))
                (assert (= native.stdout interp.stdout) (str "opsValues: native prints " native.stdout " and the recorded asl-host run " interp.stdout))
                true)))))
      true))

fn valConst dest: String c: irTy/SsaConst -> irTy/SsaInstr
  (irTy/ssaInstr dest (irTy/tyVal) (irTy/opConst c))

fn ssaCase name: String consts: (List irTy/SsaConst) op: String branches: Bool -> irTy/SsaFunction
  (let [(names (map (fn [(i Int64)] -> String (str "c" i)) (range 0 (listLength consts))))
        (instrs (listAppend (map (fn [(i Int64)] -> irTy/SsaInstr (valConst (str "c" i) (optionOr (listGet consts i) (irTy/constUnit)))) (range 0 (listLength consts)))
                            (list (irTy/ssaInstr "r" (irTy/tyVal) (irTy/opBuiltin op names)))))]
    (irTy/ssaFunction name (list) (list) (irTy/tyVal)
      (if branches
        (list (irTy/ssaBlock "entry" (list) instrs (irTy/termBranch "r" (irTy/ssaEdge "yes" (list)) (irTy/ssaEdge "no" (list))))
              (irTy/ssaBlock "yes" (list) (list (valConst "one" (irTy/constInt 1))) (irTy/termReturn "one"))
              (irTy/ssaBlock "no" (list) (list (valConst "two" (irTy/constInt 2))) (irTy/termReturn "two")))
        (list (irTy/ssaBlock "entry" (list) instrs (irTy/termReturn "r"))))))

fn ssaCases -> (List (Pair irTy/SsaFunction String))
  (let [(i (fn [(n Int64)] -> irTy/SsaConst (irTy/constInt n)))
        (b (fn [(v Bool)] -> irTy/SsaConst (irTy/constBool v)))]
    (list (pair (ssaCase "nary" (list (i 1) (i 2) (i 3) (i 4)) "+" false) "(+ (idOf 1) (idOf 2) (idOf 3) (idOf 4))")
          (pair (ssaCase "product" (list (i 2) (i 3) (i 4)) "*" false) "(* (idOf 2) (idOf 3) (idOf 4))")
          (pair (ssaCase "pair" (list (i 9) (i 4)) "mod" false) "(mod (idOf 9) (idOf 4))")
          (pair (ssaCase "negate" (list (i -7)) "-" false) "(- (idOf -7))")
          (pair (ssaCase "notFalse" (list (b false)) "not" true) "(if (not (idOf false)) 1 2)")
          (pair (ssaCase "less" (list (i 5) (i 3)) "<" true) "(if (< (idOf 5) (idOf 3)) 1 2)")
          (pair (ssaCase "equal" (list (i 3) (i 3)) "=" true) "(if (= (idOf 3) (idOf 3)) 1 2)")
          (pair (ssaCase "naryOverflow" (list (i 9223372036854775807) (i 0) (i 1)) "+" false) "(+ (idOf 9223372036854775807) (idOf 0) (idOf 1))")
          (pair (ssaCase "subThree" (list (i 1) (i 2) (i 3)) "-" false) "(- (idOf 1) (idOf 2) (idOf 3))")
          (pair (ssaCase "lessOne" (list (i 1)) "<" false) "(< (idOf 1))")
          (pair (ssaCase "notTwo" (list (b true) (b true)) "not" false) "(not (idOf true) (idOf true))")))

fn ! testSsaBuiltins dir: String -> Bool
  (let [(m (irTy/ssaModule "opsSsa" (list) (list) (list) (list) (list) (map (fn [(c (Pair irTy/SsaFunction String))] -> irTy/SsaFunction (pairFirst c)) (ssaCases))))]
    (do
      (map (fn [(c (Pair irTy/SsaFunction String))] -> Bool
             (let [(name (pairFirst c).name)]
               (match (llvm/emitLlvmProgram m name)
                 ((err ds) (do (assert false (str name ": emits: " (formatDiags ds))) true))
                 ((ok code)
                   (do
                     (refute (stringContains? code "@asl_rt_builtin(") (str name ": the IR calls no asl_rt_builtin"))
                     (assert (ok? (fileWrite (str dir "/" name ".ll") code)) (str "fileWrite " name ".ll"))
                     (let [(exe (nativeExe dir name))
                           (native (processRun exe))
                           (interp (recordedSsa name))
                           (line (stringReplace native.stderr "\n" ""))
                           (code0 (optionOr (stringIndexOf line ": ") 0))
                           (errCode (optionOr (stringSlice line 0 code0) ""))
                           (message (optionOr (stringSlice line (+ code0 2) (stringLength line)) ""))]
                       (if (= interp.exitCode 0)
                         (assert (= (some native.exitCode) (stringToInt64 (stringReplace interp.stdout "\n" "")))
                                 (str name ": native exits " native.exitCode " and the recorded asl-host prints " interp.stdout "; native stderr " native.stderr))
                         (do (assert (= native.exitCode 1) (str name ": native exit " native.exitCode ", want 1; stderr " native.stderr))
                             (assert (stringStartsWith? errCode "ERR_") (str name ": native stderr is one error line: " native.stderr))
                             (assert (or (stringContains? interp.stderr (str ": " line " (after"))
                                         (stringContains? interp.stderr (str ": " errCode " " message "\n")))
                                     (str name ": the recorded asl-host reports " line "; it reported " interp.stderr))))
                       true))))))
           (ssaCases))
      true))

fn keyOrderSource -> String
  (stringJoin (list
    "(module keyOrderLib"
    "  :x [same differ]"
    "  :i [])"
    ""
    "(schema P"
    "  (:f x Int64)"
    "  (:f y Int64))"
    ""
    "fn same a: P b: P -> Int64"
    "  (if (= a b) 1 0)"
    ""
    "fn differ a: P b: P -> Int64"
    "  (if (!= a b) 1 0)"
    "") "\n")

fn keyOrderCaller -> String
  (stringJoin (list
    "#include <stdint.h>"
    "#include <stdio.h>"
    "typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; double f; void *o; } u; } Val;"
    "typedef struct { uint32_t size; uint8_t type, mark, perm, classIdx; int schema; int n; int *keys; Val v[]; } Rec;"
    "void asl_rt_init(void);"
    "void *asl_alloc(int type, size_t bytes);"
    "int intern(const char *s, size_t n);"
    "static int keyIds[4][2];"
    "static int built;"
    "static Val record(const char *schema, const char *const *keys, const Val *vals) {"
    "  int *ids = keyIds[built++];"
    "  for (int i = 0; i < 2; i++) ids[i] = intern(keys[i], 1);"
    "  Rec *r = asl_alloc(2, sizeof(Rec) + 2 * sizeof(Val));"
    "  r->schema = intern(schema, 1); r->n = 2; r->keys = ids;"
    "  for (int i = 0; i < 2; i++) r->v[i] = vals[i];"
    "  Val v = {7, 0, {.o = r}};"
    "  return v;"
    "}"
    "int64_t same(Val a, Val b);"
    "int64_t differ(Val a, Val b);"
    "static Val intVal(int64_t i) { Val v = {2, 0, {.i = i}}; return v; }"
    "int main(void) {"
    "  asl_rt_init();"
    "  const char *const declared[] = {\"x\", \"y\"};"
    "  const char *const swapped[] = {\"y\", \"x\"};"
    "  Val v12[] = {intVal(1), intVal(2)};"
    "  Val v21[] = {intVal(2), intVal(1)};"
    "  Val v12b[] = {intVal(1), intVal(2)};"
    "  Val v12c[] = {intVal(1), intVal(2)};"
    "  Val xy = record(\"P\", declared, v12);"
    "  Val yx = record(\"P\", swapped, v21);"
    "  Val swap = record(\"P\", swapped, v12b);"
    "  Val other = record(\"Q\", declared, v12c);"
    "  printf(\"%lld %lld %lld %lld %lld %lld %lld %lld\\n\", (long long)same(xy, yx), (long long)same(yx, xy), (long long)differ(xy, yx),"
    "         (long long)same(xy, swap), (long long)same(swap, xy), (long long)differ(xy, swap), (long long)same(yx, swap), (long long)same(xy, other));"
    "  return 0;"
    "}"
    "") "\n")

fn ! testKeyOrder dir: String -> Bool
  (match (low/lowerSource (keyOrderSource))
    ((err ds) (do (assert false (str "keyOrder: the source lowers: " (formatDiags ds))) true))
    ((ok m) (match (ssa/emitLlvmModule m)
              ((err ds) (do (assert false (str "keyOrder: emitLlvmModule emits same and differ: " (formatDiags ds))) true))
              ((ok ll)
                (let [(lib (str dir "/keyOrderLib.ll"))
                      (caller (str dir "/keyOrderCaller.c"))
                      (exe (str dir "/keyOrder"))]
                  (do
                    (assert (stringContains? ll "@opsrt.eq(") "keyOrder: = calls the @opsrt.eq helper")
                    (assert (ok? (fileWrite lib ll)) (str "fileWrite " lib))
                    (assert (ok? (fileWrite caller (keyOrderCaller))) (str "fileWrite " caller))
                    (assert (ok? (fileWrite (str dir "/valrtC.ll") (ssa/cRuntimeModule))) "fileWrite valrtC.ll, the C main's intern and C floor definitions")
                    (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " lib " " dir "/valrtC.ll -x c " caller " -x none asl/host/out/libaslrt.a -lm -o " exe)))]
                      (assert (= linked.exitCode 0) (str "keyOrder: clang links the C caller with same and differ: " linked.stderr)))
                    (let [(out (processRun exe))]
                      (assert (and (= out.exitCode 0) (= out.stdout "1 1 0 0 0 1 0 0\n"))
                              (str "keyOrder: xy = yx both ways, xy != yx false, xy = swap false both ways, xy != swap, yx = swap false, xy = other (schema Q) false; got " out.stdout " exit " out.exitCode "; stderr " out.stderr)))
                    true))))))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (src (str dir "/opsFixture.asl"))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testRuntimeDecls)
      (testArchive)
      (testStaleNames)
      (testValues dir)
      (testSsaBuiltins dir)
      (testKeyOrder dir)
      (assert (ok? (fileWrite src (fixtureSrc))) (str "fileWrite " src))
      (match (compiled src)
        ((err e) (do (assert false (str "opsFixture links and emits: " e)) true))
        ((ok code)
          (do
            (testIr dir "opsFixture" code (listAppend (map (fn [(p (Pair String String))] -> String (pairSecond p)) (opSymbols)) (list "neg")))
            (let [(exe (nativeExe dir "opsFixture"))]
              (do
                (map (fn [(c String)] -> Bool (testParity exe src c)) (listAppend (matrixCases) (edgeCases)))
                true)))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
