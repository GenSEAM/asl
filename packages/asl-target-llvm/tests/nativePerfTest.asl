(module asl-target-llvm/tests/nativePerfTest
  :x [runTests]
  :i [(tools/nativeTest :a nt)])

fn probe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/trapProbe.asl"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! nativeRun cache: String env: String path: String args: String -> ProcessOutput
  (sh (str "ASL_NATIVE_TEST_CACHE='" cache "' " env " nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " path " " args " </dev/null"))

fn ! hostRun path: String args: String -> ProcessOutput
  (sh (str "nice -n 15 asl/host/out/asl-host run " path " " args " </dev/null"))

fn errorTail text: String -> String
  (mt (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) (stringLines text)))
    ((none) "")
    ((some line) (mt (stringIndexOf line "ERR_")
                   ((some i) (stringReplace (optionOr (stringSlice line i (stringLength line)) line) " (after 0 asserts)" ""))
                   ((none) line))))

fn ! sameOutcome what: String native: ProcessOutput host: ProcessOutput -> Bool
  (do
    (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str what ": native run does not fall back: " native.stderr))
    (assert (= (= native.exitCode 0) (= host.exitCode 0)) (str what ": native exit " native.exitCode " agrees with asl-host exit " host.exitCode))
    (assert (= native.stdout host.stdout) (str what ": native stdout " native.stdout " equals asl-host stdout " host.stdout))
    (assert (= (errorTail native.stderr) (errorTail (str host.stdout "\n" host.stderr))) (str what ": native error '" (errorTail native.stderr) "' equals asl-host's '" (errorTail host.stderr) "'"))
    true)

fn trapCases -> (List (Pair String String))
  (list (pair "add 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "sub -9223372036854775808 1" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "mul 4611686018427387904 2" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "div 7 0" "ERR_DIV_ZERO: division by zero")
        (pair "mod 7 0" "ERR_DIV_ZERO: mod by zero")
        (pair "div -9223372036854775808 -1" "ERR_INT_OVERFLOW: Int / leaves int64")
        (pair "divConst -9223372036854775808" "ERR_INT_OVERFLOW: Int / leaves int64")
        (pair "neg -9223372036854775808" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "countUp 9223372036854775806 -1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "modMul 3037000500 3037000501 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "modConstMul 3037000500 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "modConstMul -1 3037000500" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "index 5 5" "ERR_RANGE: i64ArrayGet index 5 outside length 5")
        (pair "index 5 -1" "ERR_RANGE: i64ArrayGet index -1 outside length 5")
        (pair "modConst -9" "")
        (pair "scaled 0 1000" "")
        (pair "modMul 3037000500 1000 3037000500" "")
        (pair "modConstMul 3037000499 3037000500" "")
        (pair "countUp 9223372036854775800 9223372036854775807" "")
        (pair "index 5 4" "")
        (pair "fields 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "fields 40 2" "")
        (pair "fields -3 5" "")
        (pair "mapOrder 5 3" "")
        (pair "mapOrder 0 3" "")
        (pair "filterOrder 7 2" "")
        (pair "filterOrder 0 2" "")
        (pair "mapTrap 9223372036854775807 1" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "filterNonBool 1 1" "ERR_TYPE: condition must be Bool, got Int")
        (pair "mod -7 3" "")
        (pair "mod 7 -3" "")
        (pair "mod -7 -3" "")
        (pair "mod -6 3" "")
        (pair "mod -9223372036854775808 -1" "")
        (pair "div -7 2" "")
        (pair "div 7 -2" "")
        (pair "div -7 -2" "")
        (pair "div -8 2" "")
        (pair "listOps 3" "")
        (pair "listOps 0" "")
        (pair "listOpsVal 5" "ERR_TYPE: listHead expects List, got Int")
        (pair "bytesGet 4 3" "")
        (pair "bytesGet 4 4" "ERR_RANGE: bytesGet: slot 4 outside 4 bytes")
        (pair "bytesGet 4 -1" "ERR_RANGE: bytesGet: slot -1 outside 4 bytes")
        (pair "bytesLength 0" "")
        (pair "bytesLength 9" "")
        (pair "stringLength -9223372036854775808" "")
        (pair "stringLengthVal 7" "ERR_TYPE: stringLength expects String, got Int"))

fn ! testTraps cache: String -> Bool
  (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
          (let [(args (pairFirst c))
                (native (nativeRun cache "" (probe) args))
                (host (hostRun (probe) args))]
            (do (sameOutcome (str "trapProbe " args) native host)
                (assert (= (errorTail native.stderr) (pairSecond c)) (str "trapProbe " args ": native error is '" (pairSecond c) "', got '" (errorTail native.stderr) "'"))
                (and acc true))))
        true (trapCases))

fn ! testGcStress cache: String -> Bool
  (let [(fp (nt/fingerprint))]
    (fold (fn [(acc Bool) (name String)] -> Bool
            (let [(path (str "bench/native/" name ".asl"))
                  (built (nt/prepareRunIn cache path fp))
                  (host (hostRun path "1500"))]
              (mt built.binary
                ((none) (do (assert false (str name ": native build falls back: " built.reason)) false))
                ((some bin)
                 (let [(native (sh (str "ASL_GC_STRESS=1 ASL_GC_VERIFY=1 ASL_PRELUDE=asl/host/out/prelude.asl nice -n 15 " bin " 1500 </dev/null")))]
                   (do (sameOutcome (str name " under ASL_GC_STRESS=1 ASL_GC_VERIFY=1") native host)
                       (assert (= native.exitCode 0) (str name ": stressed native run exits 0: " native.stderr))
                       (and acc true)))))))
          true (list "list" "record" "map" "str")))

fn ! testTypedFields cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/typed' ASL_NATIVE_KEEP_LL=1 nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run bench/native/record.asl 1000 </dev/null")))
        (step (sh (str "cat $(find '" cache "/typed' -name '*.ll') | awk '/^define .*record[$]2Estep[(]/,/^}/'")))]
    (do (assert (= native.exitCode 0) (str "record bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "820 41") "record bench at 1000 prints 820 41")
        (assert (stringContains? step.stdout "define tailcc %Val @bench$2Fnative$2Frecord$2Estep(") "the kept IR holds record.step")
        (assert (not (stringContains? step.stdout "@opsrt.add(")) "record.step adds its Int64 fields raw, with no @opsrt.add call")
        (assert (stringContains? step.stdout "@llvm.sadd.with.overflow.i64") "the raw add of the fields keeps its overflow check")
        true))

fn ! testListBuilders cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/builders' ASL_NATIVE_KEEP_LL=1 nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run bench/native/list.asl 1000 </dev/null")))
        (lls (str "$(find '" cache "/builders' -name '*.ll')"))
        (mapBody (sh (str "cat " lls " | awk '/^define .*@prelude[$]2Emap[(]/,/^}/'")).stdout)
        (filterBody (sh (str "cat " lls " | awk '/^define .*@prelude[$]2Efilter[(]/,/^}/'")).stdout)]
    (do (assert (= native.exitCode 0) (str "list bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "751500") "list bench at 1000 prints 751500")
        (assert (stringContains? mapBody "call ptr @gcAsl.allocFastCons(i32 1, i64 40)") "prelude.map allocates its cells in the loop through the ALLOC-INLINE cons fast path")
        (assert (stringContains? filterBody "call ptr @gcAsl.allocFastCons(i32 1, i64 40)") "prelude.filter allocates its cells in the loop through the ALLOC-INLINE cons fast path")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2EpreludeMapOnto")) "prelude.map does not build a reversed copy")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2EpreludeFilterOnto")) "prelude.filter does not build a reversed copy")
        (assert (not (stringContains? (str mapBody filterBody) "@prelude$2ElistReverse")) "neither reverses its result")
        true))

fn ! testFloorFix cache: String -> Bool
  (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/floor' ASL_NATIVE_KEEP_LL=1 nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run bench/native/loop.asl 1000 </dev/null")))
        (go (sh (str "cat $(find '" cache "/floor' -name '*.ll') | awk '/^define .*loop[$]2Ego[(]/,/^}/'")).stdout)]
    (do (assert (= native.exitCode 0) (str "loop bench runs natively: " native.stderr))
        (assert (= (stringTrim native.stdout) "691508967") "loop bench at 1000 prints 691508967")
        (assert (stringContains? go "call i64 @mathrt.floorModFix(") "loop.go fixes a negative remainder in the cold helper")
        (assert (stringContains? go "@llvm.expect.i1(") "the fix-up branch is marked unlikely")
        (assert (not (stringContains? go ".p.shifted")) "no inline shifted-remainder select remains in loop.go")
        true))

fn bitProbe -> String
  "asl/packages/asl-target-llvm/tests/fixtures/nativePerf/bitProbe.asl"

fn bitCases -> (List (Pair String String))
  (list
        (pair "and -1 9223372036854775807" "9223372036854775807 9223372036854775807")
        (pair "and -9223372036854775808 -1" "-9223372036854775808 -9223372036854775808")
        (pair "and -6 3" "2 2")
        (pair "or -9223372036854775808 9223372036854775807" "-1 -1")
        (pair "or -8 5" "-3 -3")
        (pair "xor -1 9223372036854775807" "-9223372036854775808 -9223372036854775808")
        (pair "xor -6 3" "-7 -7")
        (pair "xor -9223372036854775808 -9223372036854775808" "0 0")
        (pair "not 9223372036854775807" "-9223372036854775808 -9223372036854775808")
        (pair "not -9223372036854775808" "9223372036854775807 9223372036854775807")
        (pair "not 0" "-1 -1")
        (pair "not -6" "5 5")
        (pair "shl 1 63" "-9223372036854775808 -9223372036854775808")
        (pair "shl 1 64" "1 1")
        (pair "shl 3 -1" "-9223372036854775808 -9223372036854775808")
        (pair "shl 9223372036854775807 1" "-2 -2")
        (pair "shl -5 2" "-20 -20")
        (pair "shr -9223372036854775808 63" "-1 -1")
        (pair "shr -16 2" "-4 -4")
        (pair "shr 9223372036854775807 64" "9223372036854775807 9223372036854775807")
        (pair "shr -1 -1" "-1 -1")
        (pair "shr 5 -63" "2 2")
        (pair "shr -9223372036854775808 0" "-9223372036854775808 -9223372036854775808"))

fn ! testBits cache: String -> Bool
  (let [(results (map (fn [(c (Pair String String))] -> Bool
                        (let [(native (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' ASL_NATIVE_KEEP_LL=1 nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " (bitProbe) " " (pairFirst c) " </dev/null")))]
                          (do (assert (not (stringContains? native.stderr "NATIVE-FALLBACK")) (str "bitProbe " (pairFirst c) ": native run does not fall back: " native.stderr))
                              (assert (= native.exitCode 0) (str "bitProbe " (pairFirst c) " exits 0: " native.stderr))
                              (assert (= (stringTrim native.stdout) (pairSecond c)) (str "bitProbe " (pairFirst c) " prints '" (pairSecond c) "', got '" (stringTrim native.stdout) "'"))
                              true)))
                      (bitCases)))
        (andText (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " (bitProbe) " andText 3 </dev/null")))
        (notText (sh (str "ASL_NATIVE_TEST_CACHE='" cache "/bits' nice -n 15 asl/host/out/asl-host run tools/nativeTest.asl run " (bitProbe) " notText </dev/null")))
        (rawOp (sh (str "cat $(find '" cache "/bits' -name '*.ll') | awk '/^define .*bitProbe[$]2ErawOp[(]/,/^}/'")).stdout)]
    (do (assert (= (listLength results) (listLength (bitCases))) "every bitProbe case ran")
        (assert (!= andText.exitCode 0) "& over a String Val fails")
        (assert (= (errorTail andText.stderr) "ERR_TYPE: & expects Int, got String") (str "& over a String Val fails with want()'s text, got '" (errorTail andText.stderr) "'"))
        (assert (!= notText.exitCode 0) "~ over a String Val fails")
        (assert (= (errorTail notText.stderr) "ERR_TYPE: ~ expects Int, got String") (str "~ over a String Val fails with want()'s text, got '" (errorTail notText.stderr) "'"))
        (assert (stringContains? rawOp "define tailcc i64 @asl$2Dtarget$2Dllvm$2Ftests$2Ffixtures$2FnativePerf$2FbitProbe$2ErawOp(") "the kept IR holds bitProbe.rawOp with a raw i64 signature")
        (assert (stringContains? rawOp " = and i64 %a, %b") "& over raw operands is one and")
        (assert (stringContains? rawOp " = or i64 %a, %b") "| over raw operands is one or")
        (assert (stringContains? rawOp " = xor i64 %a, %b") "^ over raw operands is one xor")
        (assert (stringContains? rawOp " = shl i64 %a, ") "<< over raw operands is one shl behind the count mask")
        (assert (stringContains? rawOp " = ashr i64 %a, ") ">> over raw operands is one ashr behind the count mask")
        (assert (not (stringContains? rawOp "@mathrt.")) "rawOp calls no @mathrt helper")
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (cache (stringTrim made.stdout))]
    (do
      (assert (= made.exitCode 0) "temporary native cache created")
      (testTraps cache)
      (testGcStress cache)
      (testTypedFields cache)
      (testListBuilders cache)
      (testFloorFix cache)
      (testBits cache)
      (assert (= (sh (str "rm -rf '" cache "'")).exitCode 0) "temporary native cache removed")
      true))
