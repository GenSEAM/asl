(module asl-syntax/tests/asl/asnTest
  :x [runTests]
  :i [(asl-syntax/asl/asn :a asn)
      (asl-transpile/asn :a at)])

fn testStringJoin -> Bool
  (do
    (assert (= (stringJoin (list) ",") "") "stringJoin empty list")
    (assert (= (stringJoin (list "only") ",") "only") "stringJoin singleton adds no separator")
    (assert (= (stringJoin (list "a" "b") ",") "a,b") "stringJoin two items inserts separator")
    (assert (= (stringJoin (list "a" "b" "c") ",") "a,b,c") "stringJoin odd item count inserts separators")
    (assert (= (stringJoin (list "a" "b" "c" "d") ",") "a,b,c,d") "stringJoin even item count inserts separators")
    (assert (= (stringJoin (list "a" "b" "c" "d" "e") ",") "a,b,c,d,e") "stringJoin preserves five-item ordering")
    (assert (= (stringJoin (list "a" "b" "c" "d" "e" "f") " :: ") "a :: b :: c :: d :: e :: f") "stringJoin preserves multi-character separators")
    true)

fn testBasicScalars -> Bool
  (let [(rInt (asn/asnRead "42"))
        (rNegInt (asn/asnRead "-10"))
        (rFloat (asn/asnRead "3.14"))
        (rStr (asn/asnRead "\"hello world\""))
        (rBoolT (asn/asnRead "true"))
        (rBoolF (asn/asnRead "false"))
        (rNil (asn/asnRead "_"))
        (rUnit (asn/asnRead "()"))
        (rKw (asn/asnRead ":fooBar"))]
    (assert (ok? rInt) "asnRead parses int")
    (assert (ok? rNegInt) "asnRead parses negative int")
    (assert (ok? rFloat) "asnRead parses float")
    (assert (ok? rStr) "asnRead parses string")
    (assert (ok? rBoolT) "asnRead parses true")
    (assert (ok? rBoolF) "asnRead parses false")
    (assert (ok? rNil) "asnRead parses nil")
    (assert (ok? rUnit) "asnRead parses unit")
    (assert (ok? rKw) "asnRead parses keyword")
    (assert (= (asn/asnWrite (resultOr rInt (asn/asnNil))) "42") "int renders back")
    (assert (= (asn/asnWrite (resultOr rNegInt (asn/asnNil))) "-10") "negative int renders back")
    (assert (= (asn/asnWrite (resultOr rFloat (asn/asnNil))) "3.14") "float renders back")
    (assert (= (asn/asnWrite (resultOr rStr (asn/asnNil))) "\"hello world\"") "str renders back")
    (assert (= (asn/asnWrite (resultOr rBoolT (asn/asnNil))) "true") "true renders back")
    (assert (= (asn/asnWrite (resultOr rBoolF (asn/asnNil))) "false") "false renders back")
    (assert (= (asn/asnWrite (resultOr rNil (asn/asnNil))) "_") "nil renders back")
    (assert (= (asn/asnWrite (resultOr rUnit (asn/asnNil))) "()") "unit renders back")
    (assert (= (asn/asnWrite (resultOr rKw (asn/asnNil))) ":fooBar") "kw renders back")
    true)

fn testCompoundValues -> Bool
  (let [(rVecEmpty (asn/asnRead "[]"))
        (rVec (asn/asnRead "[1 2 3]"))
        (rVecNested (asn/asnRead "[[:a] [true false]]"))
        (rRec (asn/asnRead "(:a 1 :b \"two\")"))
        (rRecNested (asn/asnRead "(:outer (:inner :val))"))
        (rMapEmpty (asn/asnRead "{}"))
        (rMap (asn/asnRead "{:a 1 :b 2}"))
        (rMapPairs (asn/asnRead "{(1 \"one\") (2 \"two\")}"))
        (rMapSingleRec (asn/asnRead "{(:k 99)}"))
        (rCtor (asn/asnRead "(Person :name \"Alice\" :age 30)"))
        (rRows (asn/asnRead "(Point [1 2] [3 4])"))
        (rCase (asn/asnRead "(some 42)"))
        (rTable (asn/asnRead "([:name :age] [[\"Alice\" 30] [\"Bob\" 25]])"))
        (rPair (asn/asnRead "{(\"key\" 100)}"))]
    (assert (ok? rVecEmpty) "vec empty ok")
    (assert (= (asn/asnWrite (resultOr rVecEmpty (asn/asnNil))) "[]") "vec empty render")
    (assert (ok? rVec) "vec ok")
    (assert (= (asn/asnWrite (resultOr rVec (asn/asnNil))) "[1 2 3]") "vec render")
    (assert (ok? rVecNested) "nested vec ok")
    (assert (= (asn/asnWrite (resultOr rVecNested (asn/asnNil))) "[[:a] [true false]]") "nested vec render")
    (assert (ok? rRec) "rec ok")
    (assert (= (asn/asnWrite (resultOr rRec (asn/asnNil))) "(:a 1 :b \"two\")") "rec render")
    (assert (ok? rRecNested) "nested rec ok")
    (assert (= (asn/asnWrite (resultOr rRecNested (asn/asnNil))) "(:outer (:inner :val))") "nested rec render")
    (assert (ok? rMapEmpty) "map empty ok")
    (assert (= (asn/asnWrite (resultOr rMapEmpty (asn/asnNil))) "{}") "map empty render")
    (assert (ok? rMap) "map ok")
    (assert (= (asn/asnWrite (resultOr rMap (asn/asnNil))) "{:a 1 :b 2}") "map render")
    (assert (ok? rMapPairs) "map pairs ok")
    (assert (= (asn/asnWrite (resultOr rMapPairs (asn/asnNil))) "{(1 \"one\") (2 \"two\")}") "map pairs render")
    (assert (ok? rMapSingleRec) "map single rec ok")
    (assert (= (asn/asnWrite (resultOr rMapSingleRec (asn/asnNil))) "{(:k 99)}") "map single rec render")
    (assert (ok? rCtor) "ctor ok")
    (assert (= (asn/asnWrite (resultOr rCtor (asn/asnNil))) "(Person :name \"Alice\" :age 30)") "ctor render")
    (assert (ok? rRows) "rows ok")
    (assert (= (asn/asnWrite (resultOr rRows (asn/asnNil))) "(Point [1 2] [3 4])") "rows render")
    (assert (ok? rCase) "case ok")
    (assert (= (asn/asnWrite (resultOr rCase (asn/asnNil))) "(some 42)") "case render")
    (assert (ok? rTable) "table ok")
    (assert (= (asn/asnWrite (resultOr rTable (asn/asnNil))) "([:name :age] [[\"Alice\" 30] [\"Bob\" 25]])") "table render")
    (assert (ok? rPair) "pair ok")
    (assert (= (asn/asnWrite (resultOr rPair (asn/asnNil))) "{(\"key\" 100)}") "pair render")
    true)

fn testAtAsnReadComments -> Bool
  (let [(r (at/asnRead "; leading comment\n42 ; trailing comment\n"))]
    (do
      (assert (ok? r) "at/asnRead ignores comments through newline")
      (assert (= (at/asnWrite (resultOr r (at/asnNil))) "42") "at/asnRead resumes after comment newline")
      true))

fn ! runTests -> Bool
  (and (testAtAsnReadComments)
  (and (testStringJoin)
  (and (testBasicScalars)
  (and (testCompoundValues)
  (and (testInvalidAsnRejected)
       (testDirectStepParsing))))))

fn testInvalidAsnRejected -> Bool
  (let [(rEmpty (asn/asnRead ""))
        (rBareSym (asn/asnRead "foo"))
        (rBarePair (asn/asnRead "(\"key\" 100)"))
        (rUnclosed (asn/asnRead "(:a 1"))
        (rStrayClose (asn/asnRead ")"))
        (rStrayBracket (asn/asnRead "]"))
        (rOddRec (asn/asnRead "(:a 1 :b)"))
        (rSpaceUnit (asn/asnRead "( )"))
        (rFloatMapKey (asn/asnRead "{(1.5 \"val\")}"))
        (rUntermStr (asn/asnRead "\"unterminated"))
        (rMulti (asn/asnRead "(:a 1) (:b 2)"))
        (rMapPair3Str (asn/asnRead "{(\"k\" 1 2)}"))
        (rMapPair1Str (asn/asnRead "{(\"k\")}"))
        (rMapPair3Int (asn/asnRead "{(1 2 3)}"))
        (rMapPair1Int (asn/asnRead "{(1)}"))
        (rMapPair3Bool (asn/asnRead "{(true 1 2)}"))
        (rMapPair1Bool (asn/asnRead "{(true)}"))]
    (assert (err? rEmpty) "empty input rejected")
    (assert (err? rBareSym) "bare symbol rejected")
    (assert (err? rBarePair) "bare pair rejected")
    (assert (err? rUnclosed) "unclosed paren rejected")
    (assert (err? rStrayClose) "stray close paren rejected")
    (assert (err? rStrayBracket) "stray bracket rejected")
    (assert (err? rOddRec) "odd record rejected")
    (assert (err? rSpaceUnit) "space unit rejected")
    (assert (err? rFloatMapKey) "float map key rejected")
    (assert (err? rUntermStr) "unterminated string rejected")
    (assert (err? (asn/asnRead (str "\"" "\\" "q" "\""))) "unknown string escape rejected during asnRead")
    (assert (err? (asn/asnRead (str "\"" "\\" "x4" "\""))) "short hex string escape rejected during asnRead")
    (assert (err? rMulti) "multiple top-level forms rejected")
    (assert (err? rMapPair3Str) "3-item string pair in map rejected")
    (assert (err? rMapPair1Str) "1-item string pair in map rejected")
    (assert (err? rMapPair3Int) "3-item int pair in map rejected")
    (assert (err? rMapPair1Int) "1-item int pair in map rejected")
    (assert (err? rMapPair3Bool) "3-item bool pair in map rejected")
    (assert (err? rMapPair1Bool) "1-item bool pair in map rejected")
    true)

fn kw step: asn/AsnStep key: String -> String
  (optionOr (mapGet step.kwargs key) "<absent>")

fn stepOk text: String -> asn/AsnStep
  (let [(r (asn/parseStep text))]
    (do (assert (ok? r) (str "parseStep accepts " text))
        (resultOr r (asn/AsnStep :op "" :kwargs (mapEmpty) :args (list)))))

fn testDirectStepParsing -> Bool
  (let [(s1 (stepOk "(:read :file \"scripts/agentLoop/loop.py\" :start 21 :end 40)"))
        (s2 (stepOk ":ping"))
        (s3 (stepOk "(:batch :seq true (:ping))"))
        (s4 (stepOk "(:read :x (:a \"b)\" :c 1) :file \"f\" :depth :deep extra)"))
        (s5 (stepOk "(:case :src edge :form \"(:read :file \\\"scripts/agentLoop/loop.py\\\" :symbol \\\"parse_step\\\")\" :expect fallback)"))]
    (assert (= s1.op "read") "s1 op read")
    (assert (= (kw s1 "file") "scripts/agentLoop/loop.py") "s1 file")
    (assert (= (kw s1 "start") "21") "s1 start")
    (assert (= (kw s1 "end") "40") "s1 end")
    (assert (listEmpty? s1.args) "s1 args empty")
    (assert (= s2.op "ping") "s2 op ping")
    (assert (= s3.op "batch") "s3 op batch")
    (assert (= (kw s3 "seq") "true") "s3 seq true")
    (assert (= (optionOr (listHead s3.args) "") "(:ping)") "s3 arg ping")
    (assert (= s4.op "read") "s4 op read")
    (assert (= (kw s4 "x") "(:a \"b)\" :c 1)") "s4 x keeps nested paren")
    (assert (= (kw s4 "file") "f") "s4 file")
    (assert (= (kw s4 "depth") "true") "s4 depth flag")
    (assert (= (kw s4 "deep") "extra") "s4 deep value")
    (assert (= s5.op "case") "s5 op case")
    (assert (= (kw s5 "src") "edge") "s5 src")
    (assert (= (kw s5 "form") "(:read :file \"scripts/agentLoop/loop.py\" :symbol \"parse_step\")") "s5 form")
    (assert (= (kw s5 "expect") "fallback") "s5 expect")
    true)

fn findField fs: (List asn/AsnField) key: String -> asn/AsnValue
  (mt (listHead (filter (fn [(f asn/AsnField)] -> Bool (= f.key key)) fs))
    ((some f) f.val)
    ((none) (asn/asnNil)))

fn checkKwEntry kw: (Map String String) item: asn/AsnValue okSoFar: Bool -> Bool
  (and okSoFar
       (mt item
         ((asn/asnRec fs)
          (let [(k (optionOr (asn/asnStringValue (findField fs ":localKey")) ""))
                (expV (optionOr (asn/asnStringValue (findField fs ":localVal")) ""))
                (actV (optionOr (mapGet kw k) ""))]
            (= actV expV)))
         (_ false)))

fn checkArgsEqual gotArgs: (List String) expArgs: (List asn/AsnValue) -> Bool
  (if (!= (listLength gotArgs) (listLength expArgs))
    false
    (listEmpty? (filter (fn [(i Int64)] -> Bool
                          (!= (optionOr (listGet gotArgs i) "")
                              (optionOr (asn/asnStringValue (optionOr (listGet expArgs i) (asn/asnNil))) "")))
                        (range 0 (listLength gotArgs)))))

fn checkOneStepCase! acc: Int64 rec: asn/AsnValue -> Int64
  (mt rec
    ((asn/asnRec fs)
     (let [(formOpt (asn/asnStringValue (findField fs ":form")))
           (opOpt (asn/asnStringValue (findField fs ":op")))
           (kwVal (findField fs ":kw"))
           (argsVal (findField fs ":args"))]
       (mt formOpt
         ((some form)
          (let [(stepRes (asn/parseStep form))
                (step (resultOr stepRes (asn/AsnStep :op "<parseStep error>" :kwargs (mapEmpty) :args (list))))
                (expectedOp (optionOr opOpt ""))
                (kwItems (asn/vecItems kwVal))
                (expArgs (asn/vecItems argsVal))
                (opMatches (= step.op expectedOp))
                (kwSizeMatches (= (mapSize step.kwargs) (listLength kwItems)))
                (kwValsMatch (fold (fn [(okB Bool) (p asn/AsnValue)] -> Bool (checkKwEntry step.kwargs p okB)) true kwItems))
                (argsMatch (checkArgsEqual step.args expArgs))]
            (if (and opMatches (and kwSizeMatches (and kwValsMatch argsMatch)))
              acc
              (do
                (println (str "Step mismatch for: " form "\n  got op: " step.op " exp op: " expectedOp (mt stepRes ((err e) (str " error: " e)) ((ok _) ""))))
                (+ acc 1)))))
         ((none) (+ acc 1)))))
    (_ (+ acc 1)))

fn crFormText -> String
  "(:echo :message \"a\\rb\")"

fn crForm? rec: asn/AsnValue -> Bool
  (mt rec
    ((asn/asnRec fs) (= (asn/asnStringValue (findField fs ":form")) (some (crFormText))))
    (_ false))

fn recField rec: asn/AsnValue key: String -> (Option String)
  (mt rec
    ((asn/asnRec fs)
     (mt (listHead (asn/vecItems (findField fs key)))
       ((some kv) (mt kv ((asn/asnRec kfs) (asn/asnStringValue (findField kfs ":localVal"))) (_ (none))))
       ((none) (none))))
    (_ (none)))
