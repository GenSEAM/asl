(module asl-target-llvm/tests/nativeFormatTest
  :x [runTests]
  :i [])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn runtimeLib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (src (str work "/format.asl"))
        (ll (str work "/format.ll"))
        (nativePath (str work "/format"))]
    (do
      (assert (= made.exitCode 0) "nativeFormat: makes work directory")
      (assert (ok? (fileWrite src
        (stringJoin (list
          "(module formatGate"
          "  :x [main]"
          "  :i [])"
          ""
          "(schema Point (:f x Int64) (:f y String))"
          "(enum Shape (:c circle [(radius Int64)] \"Circle\") (:c square [(side Int64)] \"Square\"))"
          "(enum Tagged (:c labelled [(text String)] \"Labelled\"))"
          ""
          "fn stringifyInteger n: Int64 -> String"
          "  (str n)"
          ""
          "fn ! floatCorpusStep state: Int64 count: Int64 bytes: Bytes -> Bool"
          "  (if (= count 100000) true"
          "    (let [(s1 (mod (+ (* state 1103515245) 12345) 2147483647))"
          "          (s2 (mod (+ (* s1 1103515245) 12345) 2147483647))"
          "          (s3 (mod (+ (* s2 1103515245) 12345) 2147483647))"
          "          (s4 (mod (+ (* s3 1103515245) 12345) 2147483647))"
          "          (s5 (mod (+ (* s4 1103515245) 12345) 2147483647))"
          "          (s6 (mod (+ (* s5 1103515245) 12345) 2147483647))"
          "          (s7 (mod (+ (* s6 1103515245) 12345) 2147483647))"
          "          (s8 (mod (+ (* s7 1103515245) 12345) 2147483647))]"
          "      (do (bytesSet bytes 0 (mod s1 256)) (bytesSet bytes 1 (mod s2 256))"
          "          (bytesSet bytes 2 (mod s3 256)) (bytesSet bytes 3 (mod s4 256))"
          "          (bytesSet bytes 4 (mod s5 256)) (bytesSet bytes 5 (mod s6 256))"
          "          (bytesSet bytes 6 (mod s7 256)) (bytesSet bytes 7 (mod s8 112))"
          "          (let [(value (bytesGetFloat64 bytes 0))"
          "                (text (stringFromFloat64 value))"
          "                (parsedResult (stringToFloat64 text))"
          "                (parsed (optionOr parsedResult 0.0))]"
          "            (do (println text)"
          "                (if (and (some? parsedResult) (= value parsed)) (floatCorpusStep s8 (+ count 1) bytes) false))))))"
          ""
          "fn ! writeText s: String -> Unit"
          "  (print s)"
          ""
          "fn ! main -> (Result Int64 String)"
          "  (let [(stringify stringifyInteger) (show writeText) (corpusBytes (bytesAlloc 8))"
          "        (point (Point :x 8 :y \"value\"))]"
          "    (do"
          "      (assert (floatCorpusStep 17 0 corpusBytes) \"100000 seeded Float64 bit patterns round-trip\")"
          "      (print \"out-a\")"
          "      (eprintln \"err-a\")"
          "      (print \"out-b\")"
          "      (eprintln \"err-b\")"
          "      (print (str () true false [1 2 3] -9223372036854775808 9223372036854775807 0.1 1e16 1e15 1e-5 1e-4 5e-324 2.2250738585072014e-308 1.7976931348623157e308 -0.0 (optionOr (stringToFloat64 \"nan\") 0.0) (optionOr (stringToFloat64 \"inf\") 0.0) (optionOr (stringToFloat64 \"-inf\") 0.0) 123456789012345680.0 \"UTF-8:λ\" \"quote:\\\" slash:\\\\\\\\ newline:\\n tab:\\t control:\\x01\" point (circle 3) (stringToBytes \"bytes\") (f64ArrayGenerate 2 (fn [(i Int64)] -> Float64 (int64ToFloat64 i))) (i64ArrayGenerate 2 (fn [(i Int64)] -> Int64 i)) (i8ArrayGenerate 2 (fn [(i Int64)] -> Int64 i)) stringify))"
          "      (println (stringFromFloat64 0.1))"
          "      (println (str (list \"q\\\"\" \"b\\\\\" \"n\\n\" \"t\\t\" \"c\\x01\") (Point :x 1 :y \"r\\\"\\\\\\n\\t\") (labelled \"l\\\"\\\\\\n\\t\")))"
          "      (println (str (stringToFloat64 \"1e400\") (stringToFloat64 \" 1\") (stringToFloat64 \"1 \") (stringToFloat64 \"0x10\") (stringToFloat64 \"nan\") (stringToFloat64 \"-inf\") (stringToFloat64 \"1e\") (stringToFloat64 \"\")))"
          (str "      (println (str (stringToFloat64 \"" (decimalZeros 511) "\") (stringToFloat64 \"" (decimalZeros 512) "\")))")
          "      (eprintln \"stderr\")"
          "      (show (stringify 17))"
          "      (ok 0)))") "\n")))
        "nativeFormat: writes source")
      (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))]
        (do
          (assert (= built.exitCode 0) (str "nativeFormat: asl1 emits IR; stderr " built.stderr))
          (let [(ir (mt (fileReadString ll) ((ok t) t) ((err _) "")))]
            (do
              (refute (stringContains? ir "@asl_rt_b_stringFromFloat64") "nativeFormat: IR has no float formatter wrapper")
              (refute (stringContains? ir "@asl_rt_b_stringToFloat64") "nativeFormat: IR has no float parser wrapper")
              (refute (or (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.str")
                          (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.print")
                          (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.println")
                          (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.eprintln")
                          (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.stringFromFloat64")
                          (stringContains? ir "call %Val @asl_rt_builtin(ptr @name.stringToFloat64"))
                      "nativeFormat: formatting builtins avoid generic dispatch")
              (assert (stringContains? (formatFloatLoop ir) "call double @strtod") "nativeFormat: IR has the float formatter retry loop")
              (refute (stringContains? (formatFloatLoop ir) "alloca") "nativeFormat: float formatter retry loop allocates no stack slot")))))
      (let [(linked (sh (str (clang) " -x ir " ll " -x none " (runtimeLib) " -lm -o " nativePath)))
            (hosted (sh (str (host) " run " src)))]
        (do
          (assert (= linked.exitCode 0) (str "nativeFormat: clang links generated formatter IR; stderr " linked.stderr))
          (let [(native (sh nativePath))]
            (do
              (assert (= native.exitCode hosted.exitCode) (str "nativeFormat: exit equals asl-host; native " native.exitCode " host " hosted.exitCode))
              (assert (= native.stdout hosted.stdout) (str "nativeFormat: stdout equals asl-host; got " native.stdout " host " hosted.stdout))
              (assert (= native.stderr hosted.stderr) (str "nativeFormat: stderr equals asl-host; got " native.stderr " host " hosted.stderr))
              (assert (and (stringContains? hosted.stdout "(\"q\\\"\" \"b\\\\\" \"n\\n\" \"t\\t\" \"c")
                           (stringContains? hosted.stdout "{:x 1 :y \"r\\\"\\\\\\n\\t\"}(labelled \"l\\\"\\\\\\n\\t\")"))
                      "nativeFormat: strings nested in a list, record and variant print escaped"))))
      (testDepth work)
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "nativeFormat: removes work directory")
      true)))

fn decimalZeros length: Int64 -> String
  (str "0." (zeroDigits (- length 2) ""))

fn zeroDigits count: Int64 acc: String -> String
  (if (<= count 0) acc (zeroDigits (- count 1) (str acc "0")))

fn formatFloatLoop ir: String -> String
  (let [(body (mt (stringIndexOf ir "define internal %Val @asl_rt_format_float(")
                ((some at) (optionOr (stringSlice ir at (stringLength ir)) ""))
                (_ "")))]
    (mt (stringIndexOf body "\ntry:")
      ((some start) (mt (stringIndexOf body "\ndone:")
                      ((some stop) (optionOr (stringSlice body start stop) ""))
                      (_ "")))
      (_ "")))

fn ! testDepth work: String -> Bool
  (let [(src (str work "/deep.asl"))
        (ll (str work "/deep.ll"))
        (nativePath (str work "/deep"))]
    (do
      (assert (ok? (fileWrite src (stringJoin (list
          "(module deepGate"
          "  :x [main]"
          "  :i [])"
          ""
          "(enum Nest (:c leaf [] \"Leaf\") (:c node [(inner Nest)] \"Node\"))"
          ""
          "fn build n: Int64 acc: Nest -> Nest"
          "  (if (= n 0) acc (build (- n 1) (node acc)))"
          ""
          "fn ! main -> (Result Int64 String)"
          "  (do"
          "    (println (str (stringLength (str (build 10000 (leaf))))))"
          "    (println (str (build 10001 (leaf))))"
          "    (ok 0))") "\n")))
        "nativeDepth: writes source")
      (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))
            (linked (sh (str (clang) " -x ir " ll " -x none " (runtimeLib) " -lm -o " nativePath)))
            (hosted (sh (str (host) " run " src)))
            (native (sh nativePath))
            (message "ERR_DEPTH: printing a value nested deeper than 10000")]
        (do
          (assert (and (= built.exitCode 0) (= linked.exitCode 0)) (str "nativeDepth: builds and links; stderr " built.stderr linked.stderr))
          (assert (= hosted.stdout "70006\n") (str "nativeDepth: asl-host formats the 10000-deep value; got " hosted.stdout))
          (assert (= native.stdout hosted.stdout) (str "nativeDepth: stdout equals asl-host; got " native.stdout))
          (assert (and (= hosted.exitCode 1) (= native.exitCode 1)) (str "nativeDepth: both exit 1; native " native.exitCode " host " hosted.exitCode))
          (assert (and (stringContains? hosted.stderr message) (stringContains? native.stderr message))
                  (str "nativeDepth: both report ERR_DEPTH; native " native.stderr " host " hosted.stderr)))
      true)))
