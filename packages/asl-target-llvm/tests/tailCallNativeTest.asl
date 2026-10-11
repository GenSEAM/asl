(module asl-target-llvm/tests/tailCallNativeTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (tools/nativeTest :a nt)])

fn probe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/tailCall/tailProbe.asl"

fn steps -> String
  "10000000"

fn ! smallStack bin: String mode: String n: String -> ProcessOutput
  (processRun (str "ulimit -s 1024; '" bin "' " mode " " n " </dev/null"))

fn ! expectMode bin: String mode: String want: String -> Bool
  (let [(out (smallStack bin mode (steps)))]
    (do
      (assert (= out.exitCode 0) (str mode ": " (steps) " tail steps exit 0 on a 1 MiB stack, got " out.exitCode " " out.stderr))
      (assert (= (stringTrim out.stdout) want) (str mode ": prints " want ", got " out.stdout))
      true))

fn ! testNativeRuns -> Bool
  (let [(built (nt/prepareRun (probe) (nt/fingerprint)))]
    (do
      (assert (some? built.binary) (str "tailProbe builds natively: " built.reason))
      (mt built.binary
        ((none) false)
        ((some bin)
          (let [(arity (smallStack bin "arity" "3"))]
            (do
              (expectMode bin "self" "10000000")
              (expectMode bin "mutual" "even")
              (expectMode bin "arms" "50000000")
              (expectMode bin "closure" "3")
              (expectMode bin "value" "3")
              (expectMode bin "cross" "3")
              (assert (!= arity.exitCode 0) "a wrong-arity closure call in tail position still fails")
              (assert (stringContains? arity.stderr "ERR_ARITY: viaValue expects 2 argument(s), got 1") (str "wrong-arity tail closure call keeps objrt.call's error, got " arity.stderr))
              true))))))

fn closureSource -> String
  (stringJoin (list "(module closval :x [main viaClosure viaValue countBox])"
                    "fn viaClosure n: Int64 acc: String -> String"
                    "  (if (= n 0) acc (let [(h (fn [(m Int64)] -> String (viaClosure m acc)))] (h (- n 1))))"
                    "fn viaValue n: Int64 acc: String -> String"
                    "  (if (= n 0) acc (let [(g viaValue)] (g (- n 1) acc)))"
                    "fn countBox n: Int64 -> Int64"
                    "  (if (= n 0) 0 (let [(g countBox)] (g (- n 1))))"
                    "fn main -> Int64 (if (and (= (viaClosure 10000000 \"x\") \"x\") (= (viaValue 10000000 \"y\") \"y\")) (+ 3 (countBox 3)) 1)")
              "\n")

fn functionIr ir: String name: String -> String
  (sliceFrom ir (str "@" name "("))

fn definitionIr ir: String name: String -> String
  (sliceFrom ir (str "define internal tailcc %Val @" name "("))

fn sliceFrom ir: String anchor: String -> String
  (let [(at (optionOr (stringIndexOf ir anchor) (stringLength ir)))
        (tail (optionOr (stringSlice ir at (stringLength ir)) ""))
        (end (optionOr (stringIndexOf tail "\ndefine") (stringLength tail)))]
    (optionOr (stringSlice tail 0 end) tail))

fn ! testClosureIrO0 -> Bool
  (let [(emitted (llvm/emitLlvmSource (closureSource) "main"))]
    (do
      (assert (ok? emitted) (str "closure tail source lowers: " emitted))
      (mt emitted
        ((err _) false)
        ((ok ir)
          (let [(made (processRun "mktemp -d"))
                (work (stringTrim made.stdout))
                (ll (str work "/closval.ll"))
                (exe (str work "/closval"))
                (written (fileWrite ll ir))
                (cc (processRun (str "/usr/bin/clang -Wno-override-module -O0 -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))
                (run (processRun (str "ulimit -s 1024; '" exe "' </dev/null")))
                (removed (processRun (str "rm -rf '" work "'")))]
            (do
              (assert (stringContains? (functionIr ir "viaClosure") "musttail call tailcc %Val @tailrt.closure(") "closure call in tail position is musttail through tailrt.closure")
              (assert (stringContains? (functionIr ir "viaValue") "musttail call tailcc %Val @tailrt.closure(") "function-value call in tail position is musttail through tailrt.closure")
              (assert (stringContains? (definitionIr ir "viaClosure$40lambda0.tailCode") "musttail call tailcc %Val @viaClosure$40lambda0(") "tailCode trampoline enters the lambda with musttail")
              (assert (stringContains? (definitionIr ir "tailrt.closure") "musttail call tailcc %Val %tail(") "tailrt.closure enters the proto's tailcc slot with musttail")
              (assert (stringContains? (definitionIr ir "tailrt.closure") "call %Val @objrt.call(") "tailrt.closure falls back to objrt.call")
              (assert (stringContains? ir "ptr @viaClosure$40lambda0.code, ptr @viaClosure$40lambda0.tailCode }") "proto carries the tailCode slot after the native entry")
              (assert (not (stringContains? (functionIr ir "countBox") "musttail")) "an Int64 result unboxed from a closure call is not a tail call")
              (assert (= made.exitCode 0) "scratch directory created")
              (assert (= written (ok ())) "closure IR written")
              (assert (= cc.exitCode 0) (str "clang -O0 accepts the musttail closure IR: " cc.stderr))
              (assert (= run.exitCode 3) (str "1e7 closure and function-value tail steps at -O0 on a 1 MiB stack exit 3, got " run.exitCode " " run.stderr))
              (assert (= removed.exitCode 0) "scratch directory removed")
              true))))))

fn externFixture -> ty/SsaModule
  (ty/ssaModule "externTail" (list) (list) (list)
    (list (ty/ssaExternTyped "peer.hop" (list (ty/tyI64)) (ty/tyVal)))
    (list)
    (list
      (ty/ssaFunction "spin" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyVal)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "r" (ty/tyVal) (ty/opCall "peer.hop" (list "n"))))
          (ty/termReturn "r"))))
      (ty/ssaFunction "spinUsed" (list) (list (ty/ssaParam "n" (ty/tyI64))) (ty/tyVal)
        (list (ty/ssaBlock "entry" (list)
          (list (ty/ssaInstr "r" (ty/tyVal) (ty/opCall "peer.hop" (list "n")))
                (ty/ssaInstr "s" (ty/tyVal) (ty/opCall "peer.hop" (list "n"))))
          (ty/termReturn "r"))))))

fn testExternIr -> Bool
  (let [(emitted (llvm/emitLlvmModule (externFixture)))]
    (do
      (assert (ok? emitted) (str "extern fixture emits: " emitted))
      (mt emitted
        ((err _) false)
        ((ok ir)
          (do
            (assert (stringContains? (functionIr ir "spin") "musttail call tailcc %Val @peer") "a tail call to a typed cross-module function is musttail")
            (assert (not (stringContains? (functionIr ir "spinUsed") "musttail")) "a cross-module call whose result is not returned is not musttail")
            true)))))

fn ! runTests -> Bool
  (do
    (assert (testExternIr) "extern tail IR")
    (assert (testClosureIrO0) "closure tail IR at -O0")
    (assert (testNativeRuns) "native tail runs")
    true)
