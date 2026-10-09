(module asl-target-llvm/tests/musttailClangTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm :a llvm)])

fn routeTail name: String builtin: String arity: Int64 -> ty/SsaFunction
  (let [(args (if (= arity 2) (list "arg" "arg") (list "arg" "arg" "arg")))]
    (ty/ssaFunction name (list) (list (ty/ssaParam "arg" (ty/tyVal))) (ty/tyVal)
      (list (ty/ssaBlock "entry" (list)
        (list (ty/ssaInstr "result" (ty/tyVal) (ty/opBuiltin builtin args)))
        (ty/termReturn "result")))))

fn fixture -> ty/SsaModule
  (ty/ssaModule "musttailFixture" (list "/tmp") (list) (list) (list) (list)
    (list
      (routeTail "readRange" "fileReadRange" 3)
      (routeTail "readAt" "fileReadAt" 2)
      (ty/ssaFunction "fib" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "fib" (list "n"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "loopHelper" (list) (list (ty/ssaParam "a" (ty/tyI64)) (ty/ssaParam "b" (ty/tyI64))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "loopHelper" (list "a" "b"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "intTarget" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "intTarget" (list "n"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "boolCaller" (list) (list (ty/ssaParam "flag" (ty/tyI1))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "zero" (ty/tyI64) (ty/opConst (ty/constInt 0)))
                (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "intTarget" (list "zero"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "captureTarget" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "captureTarget" (list "n"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "captureCaller" (list (ty/ssaParam "captured" (ty/tyI1))) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "next" (ty/tyI64) (ty/opCall "captureTarget" (list "n"))))
          (ty/termReturn "next"))))
      (ty/ssaFunction "main" (list) (list) (ty/tyI64)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "path" (ty/tyVal) (ty/opConst (ty/constStr 0)))
                (ty/ssaInstr "read.range" (ty/tyVal) (ty/opCall "readRange" (list "path")))
                (ty/ssaInstr "read.at" (ty/tyVal) (ty/opCall "readAt" (list "path")))
                (ty/ssaInstr "zero" (ty/tyI64) (ty/opConst (ty/constInt 0))))
          (ty/termReturn "zero"))))))

fn functionIr ir: String name: String -> String
  (let [(at (optionOr (stringIndexOf ir (str "@" name "(")) (stringLength ir)))
        (tail (optionOr (stringSlice ir at (stringLength ir)) ""))
        (end (optionOr (stringIndexOf tail "\ndefine") (stringLength tail)))]
    (optionOr (stringSlice tail 0 end) tail))

fn darwinHost? os: String -> Bool
  (= os "Darwin")

fn returnAbiMismatchUsesOrdinaryCall? -> Bool
  (let [(target (ty/ssaFunction "returnTarget" (list) (list) (ty/tyI1) (list)))
        (mod (ssa/ModEnv :name "returnAbiFixture"
              :functions (ssa/nameIndexSet (ssa/nameIndexEmpty) "returnTarget" target)
              :externs (ssa/nameIndexEmpty) :types (ssa/nameIndexEmpty) :strings (ssa/nameIndexEmpty) :records (ssa/nameIndexEmpty)))
        (env (ssa/FnEnv :mod mod :defs (ssa/nameIndexEmpty) :blocks (ssa/nameIndexEmpty) :order (list)
              :retTy (ty/tyI64) :name "returnCaller" :fused (ssa/nameIndexEmpty)
              :records (ssa/nameIndexEmpty) :wants (ssa/nameIndexEmpty) :preds (ssa/nameIndexEmpty) :size 0))
        (block (ty/ssaBlock "entry" (list)
                 (list (ty/ssaInstr "result" (ty/tyI1) (ty/opCall "returnTarget" (list))))
                 (ty/termReturn "result")))]
    (not (ssa/tailCall? env block)))

fn ! runDarwinTests -> Bool
  (let [(emitted (mt (libc/libcFacts "darwin-arm64")
                  ((none) (err (list)))
                  ((some facts) (llvm/emitLlvmProgramFor facts (fixture) "main"))))]
    (do
      (assert (ok? emitted) (str "fixture emits LLVM: " emitted))
      (mt emitted
        ((err _) false)
        ((ok ir)
          (let [(workOut (processRun "mktemp -d"))
                (work (stringTrim workOut.stdout))
                (ll (str work "/musttail.ll"))
                (exe0 (str work "/musttail-o0"))
                (exe2 (str work "/musttail-o2"))
                (written (fileWrite ll ir))
                (cc0 (processRun (str "/usr/bin/clang -Wno-override-module -O0 -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe0)))
                (cc2 (processRun (str "/usr/bin/clang -Wno-override-module -O2 -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe2)))
                (run0 (processRun exe0))
                (run2 (processRun exe2))
                (removed (processRun (str "rm -rf " work)))]
            (do
              (assert (stringContains? ir "musttail call tailcc i64 @fib") "compatible self-recursive fib retains musttail")
              (assert (stringContains? ir "musttail call tailcc i64 @loopHelper") "compatible multi-parameter loop helper retains musttail")
              (assert (returnAbiMismatchUsesOrdinaryCall?) "different return ABI does not qualify for musttail")
              (assert (and (stringContains? (functionIr ir "readRange") "fileReadRange")
                           (not (stringContains? (functionIr ir "readRange") "musttail"))) "sysRoute fileReadRange wrapper call is not marked musttail")
              (assert (and (stringContains? (functionIr ir "readAt") "fileReadAt")
                           (not (stringContains? (functionIr ir "readAt") "musttail"))) "sysRoute fileReadAt wrapper call is not marked musttail")
              (assert (= workOut.exitCode 0) "scratch directory created")
              (assert (= written (ok ())) "fixture IR written")
              (assert (= cc0.exitCode 0) (str "Apple clang -O0 accepts fixture: " cc0.stderr))
              (assert (= cc2.exitCode 0) (str "Apple clang -O2 accepts fixture: " cc2.stderr))
              (assert (stringContains? ir "define tailcc i64 @boolCaller(i1 %flag)") "mismatched fixture caller has one i1 parameter")
              (assert (stringContains? (functionIr ir "boolCaller") "musttail call tailcc i64 @intTarget") "different-signature tailcc call retains musttail")
              (assert (stringContains? ir "define tailcc i64 @captureCaller(i1 %captured, i64 %n)") "captured caller has its capture in the emitted tailcc signature")
              (assert (stringContains? (functionIr ir "captureCaller") "musttail call tailcc i64 @captureTarget") "tailcc call with captures retains musttail across signatures")
              (assert (= run0.exitCode 0) "Apple clang -O0 fixture runs")
              (assert (= run2.exitCode 0) "Apple clang -O2 fixture runs")
              (assert (= removed.exitCode 0) "scratch directory removed")
              true))))))

fn ! runTests -> Bool
  (let [(os (stringTrim (processRun "uname -s").stdout))]
    (do
      (assert (not (stringEmpty? os)) "uname reports the host operating system")
      (if (darwinHost? os)
        (runDarwinTests)
        true)))
