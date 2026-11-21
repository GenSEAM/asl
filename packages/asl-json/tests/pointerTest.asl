(module asl-json/tests/pointerTest
  :x [runTests]
  :i [(asl-json/json :a j)
      (asl-json/pointer :a p)])

fn getEmit doc: j/Json ptr: String -> String
  (match (p/jsonPointerGet doc ptr)
    ((some v) (j/jsonEmit v))
    ((none) "NONE"))

fn setEmit doc: j/Json ptr: String x: j/Json -> String
  (match (p/jsonPointerSet doc ptr x)
    ((ok v) (j/jsonEmit v))
    ((err e) (str "ERR:" e)))

fn setThenGet doc: j/Json ptr: String x: j/Json back: String -> String
  (match (p/jsonPointerSet doc ptr x)
    ((ok v) (getEmit v back))
    ((err e) (str "ERR:" e)))

fn sampleDoc -> j/Json
  (optionOr
    (match (j/jsonParse "{\n \"foo\": [\"bar\", \"baz\"],\n \"\": 0,\n \"a/b\": 1,\n \"c%d\": 2,\n \"e^f\": 3,\n \"g|h\": 4,\n \"i\\\\j\": 5,\n \"k\\\"l\": 6,\n \" \": 7,\n \"m~n\": 8\n}")
      ((ok v) (some v))
      ((err _) none))
    (j/jnull))

fn wholeDocEmit -> String
  "{\"foo\":[\"bar\",\"baz\"],\"\":0,\"a/b\":1,\"c%d\":2,\"e^f\":3,\"g|h\":4,\"i\\\\j\":5,\"k\\\"l\":6,\" \":7,\"m~n\":8}"

fn runTests -> Bool
  (do
    (let [(doc (sampleDoc))]
      (assert (= (j/jsonEmit doc) (wholeDocEmit)) "doc round trips through emit")
      (assert (= (getEmit doc "") (wholeDocEmit)) "get empty pointer returns whole doc")
      (assert (= (getEmit doc "/foo") "[\"bar\",\"baz\"]") "get /foo")
      (assert (= (getEmit doc "/foo/0") "\"bar\"") "get /foo/0")
      (assert (= (getEmit doc "/") "0") "get / (empty key)")
      (assert (= (getEmit doc "/a~1b") "1") "get /a~1b")
      (assert (= (getEmit doc "/c%d") "2") "get /c%d")
      (assert (= (getEmit doc "/e^f") "3") "get /e^f")
      (assert (= (getEmit doc "/g|h") "4") "get /g|h")
      (assert (= (getEmit doc "/i\\j") "5") "get /i\\j")
      (assert (= (getEmit doc "/k\"l") "6") "get /k\"l")
      (assert (= (getEmit doc "/ ") "7") "get space key")
      (assert (= (getEmit doc "/m~0n") "8") "get /m~0n")
      (assert (= (getEmit doc "/foo/2") "NONE") "get array index out of range")
      (assert (= (getEmit doc "/foo/-") "NONE") "get '-' is none")
      (assert (= (getEmit doc "/foo/00") "NONE") "get leading zero index")
      (assert (= (getEmit doc "/foo/01") "NONE") "get leading zero index 01")
      (assert (= (getEmit doc "foo") "NONE") "get missing leading slash")
      (assert (= (getEmit doc "/a~b") "NONE") "get invalid ~ escape")
      (assert (= (setThenGet doc "/foo/0" (j/jstr "qux") "/foo/0") "\"qux\"") "set array element")
      (assert (= (setThenGet doc "/foo/0" (j/jstr "qux") "/foo") "[\"qux\",\"baz\"]") "set array element keeps sibling")
      (assert (= (setThenGet doc "/a~1b" (j/jint 9) "/a~1b") "9") "set escaped key")
      (assert (= (setThenGet doc "/new" (j/jint 42) "/new") "42") "set adds new object key")
      (assert (= (setThenGet doc "/" (j/jint 10) "/") "10") "set empty key")
      (assert (= (setThenGet doc "/m~0n" (j/jint 88) "/m~0n") "88") "set ~0 key")
      (assert (= (setThenGet doc "" (j/jint 7) "") "7") "set whole doc")
      (assert (= (setThenGet doc "/foo/1" (j/jstr "qux") "") "{\"foo\":[\"bar\",\"qux\"],\"\":0,\"a/b\":1,\"c%d\":2,\"e^f\":3,\"g|h\":4,\"i\\\\j\":5,\"k\\\"l\":6,\" \":7,\"m~n\":8}") "set preserves rest of doc")
      (assert (stringContains? (setEmit doc "/foo/5" (j/jint 1)) "ERR") "set out-of-range index errors")
      (assert (stringContains? (setEmit doc "/foo/00" (j/jint 1)) "ERR") "set leading-zero index errors")
      (assert (stringContains? (setEmit doc "/foo/-" (j/jint 1)) "ERR") "set '-' errors")
      (assert (stringContains? (setEmit doc "/missing/deep" (j/jint 1)) "ERR") "set through missing key errors")
      (assert (stringContains? (setEmit (j/jint 1) "/a" (j/jint 2)) "ERR") "set into scalar errors")
      true))
