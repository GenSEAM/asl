(module asl/host/tests/floorRtTest
  :x [runTests]
  :i [])

fn host -> String
  "asl/host/out/asl-host"

fn runtime -> String
  "asl/host/out/libaslrt.a"

fn cap -> String
  "ASL_GC_MAX_MIB=8 "

fn source count: String -> String
  (stringJoin (list
    "(module floorOom"
    "  :x [main]"
    "  :i [])"
    ""
    "fn grow acc: (List Int64) i: Int64 -> (List Int64)"
    "  (if (= i 0) acc (grow (cons i acc) (- i 1)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    (str "  (do (println (stringFromInt64 (listLength (grow (list) " count "))))")
    "      (ok 0))"
    "")
    "\n")

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn hostErrorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn ! build work: String name: String count: String -> String
  (let [(src (str work "/" name ".asl"))
        (ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite src (source count))) (str name ": source written"))
        (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))
              (linked (sh (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none " (runtime) " -lm -o " work "/" name)))]
          (do (assert (= built.exitCode 0) (str name ": asl1 builds it; " built.stderr))
              (assert (= linked.exitCode 0) (str name ": links against libaslrt.a; " linked.stderr))
              src))))

fn ! testFits work: String -> Bool
  (let [(src (build work "floorFits" "1000"))
        (native (sh (str (cap) work "/floorFits")))
        (interp (sh (str (cap) (host) " run " src)))]
    (do (assert (= interp.exitCode 0) (str "floorFits: asl-host run fits the cap; " interp.stdout interp.stderr))
        (assert (= native.exitCode 0) (str "floorFits: native fits the cap; " native.stderr))
        (assert (= native.stdout "1000\n") (str "floorFits: native output; got " native.stdout))
        (assert (= native.stdout interp.stdout) (str "floorFits: native output equals asl-host run; host " interp.stdout))
        true))

fn ! testExhausts work: String -> Bool
  (let [(src (build work "floorOom" "1000000"))
        (native (sh (str (cap) work "/floorOom")))
        (interp (sh (str (cap) (host) " run " src)))
        (want (hostErrorLine interp))]
    (do (assert (= interp.exitCode 1) (str "floorOom: asl-host run exit " interp.exitCode ", want 1; " interp.stdout interp.stderr))
        (assert (stringStartsWith? want "ERR_OOM: ") (str "floorOom: asl-host reports ERR_OOM; got " want))
        (assert (= native.exitCode interp.exitCode) (str "floorOom: native exit " native.exitCode " equals asl-host run exit " interp.exitCode))
        (assert (= native.stderr (str want "\n")) (str "floorOom: native stderr is asl-host's error line " want "; got " native.stderr))
        (assert (= native.stdout "") (str "floorOom: native prints nothing before the error; got " native.stdout))
        true))

fn undefinedNames text: String -> (List String)
  (map (fn [(line String)] -> String
         (let [(name (stringTrim line))]
           (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
    (filter (fn [(line String)] -> Bool (not (stringEmpty? (stringTrim line)))) (stringLines text)))

fn valueErrorNames -> (List String)
  (list "aslError" "aslErrorRethrow" "aslErrorHandlerGet" "aslErrorHandlerSet" "aslErrorMsg")

fn ! testFloorObject work: String member: String needs: String -> Bool
  (let [(obj (str work "/" member))
        (extracted (sh (str "ar p " (runtime) " " member " > " obj)))
        (listed (sh (str "nm -u " obj)))
        (names (undefinedNames listed.stdout))]
    (do (assert (= extracted.exitCode 0) (str member ": extracted from libaslrt.a; " extracted.stderr))
        (assert (= listed.exitCode 0) (str member ": nm -u exit " listed.exitCode "; " listed.stderr))
        (assert (listContains? names needs) (str member ": nm -u lists " needs "; got " (stringJoin names " ")))
        (assert (= (filter (fn [(name String)] -> Bool (listContains? names name)) (valueErrorNames)) (list))
          (str member ": no undefined reference to value.c's error machinery " (stringJoin (valueErrorNames) " ") "; got " (stringJoin names " ")))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testFloorObject work "gcAsl.o" "mmap")
        (testFloorObject work "strFloor.o" "asl_alloc")
        (testFits work)
        (testExhausts work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
