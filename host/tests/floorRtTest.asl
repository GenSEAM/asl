(module asl/host/tests/floorRtTest
  :x [runTests]
  :i [])

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

fn errorLine out: ProcessOutput -> String
  (let [(text (str out.stdout out.stderr))
        (at (optionOr (stringIndexOf text "ERR_") (stringLength text)))
        (tail (optionOr (stringSlice text at (stringLength text)) ""))
        (lineEnd (optionOr (stringIndexOf tail "\n") (stringLength tail)))
        (line (optionOr (stringSlice tail 0 lineEnd) tail))]
    (optionOr (stringSlice line 0 (optionOr (stringIndexOf line " (after ") (stringLength line))) line))

fn ! write! work: String name: String count: String -> String
  (let [(src (str work "/" name ".asl"))]
    (do (assert (ok? (fileWrite src (source count))) (str name ": source written"))
        src))

fn ! testFits work: String -> Bool
  (let [(src (write! work "floorFits" "1000"))
        (native (sh (str (cap) "bin/asl run " src)))]
    (do (assert (= native.exitCode 0) (str "floorFits: native fits the cap; " native.stderr))
        (assert (= native.stdout "1000\n") (str "floorFits: native output; got " native.stdout))
        true))

fn ! testExhausts work: String -> Bool
  (let [(src (write! work "floorOom" "1000000"))
        (native (sh (str (cap) "bin/asl run " src)))
        (want (errorLine native))]
    (do (assert (= native.exitCode 1) (str "floorOom: native run exit " (stringFromInt64 native.exitCode) ", want 1; " native.stdout native.stderr))
        (assert (stringStartsWith? want "ERR_OOM: ") (str "floorOom: native reports ERR_OOM; got " want))
        (assert (= native.stderr (str want "\n")) (str "floorOom: native's whole stderr is the error line " want "; got " native.stderr))
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
        (assert (= listed.exitCode 0) (str member ": nm -u exit " (stringFromInt64 listed.exitCode) "; " listed.stderr))
        (assert (listContains? names needs) (str member ": nm -u lists " needs "; got " (stringJoin names " ")))
        (assert (= (filter (fn [(name String)] -> Bool (listContains? names name)) (valueErrorNames)) (list))
          (str member ": no undefined reference to value.c's old error machinery " (stringJoin (valueErrorNames) " ") "; got " (stringJoin names " ")))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/floorRtTest/" (stringFromInt64 (procSelf))))
        (fresh (sh (str "rm -rf " work)))
        (made (dirCreate work))]
    (do (assert (ok? made) "the work dir was created")
        (testFloorObject work "gcAsl.o" "mmap")
        (testFloorObject work "rtFloor.o" "write")
        (testFits work)
        (testExhausts work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
