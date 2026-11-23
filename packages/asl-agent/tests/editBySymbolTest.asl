(module aslAgent/tests/editBySymbolTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/aslOps :a o)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)])

; (:m :ref EDIT-BY-SYMBOL :do "gates of replaceDef, the whole-file line guard and the edit :near receipt: the replaceDef stub run answers the outline and accepts only the exact write form the span swap should produce, so a wrong span turns the receipt red")
fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn nearFirst rec: (List (Pair String ex/Val)) -> Int64
  (match (ex/recGet rec "near")
    ((some v) (match v ((ex/vPair a _) a) (_ -1)))
    ((none) -1))

fn nearLast rec: (List (Pair String ex/Val)) -> Int64
  (match (ex/recGet rec "near")
    ((some v) (match v ((ex/vPair _ b) b) (_ -1)))
    ((none) -1))

fn stepOp opName: String kvs: (List (Pair String c/KvVal)) -> (List (Pair String c/KvVal))
  (listAppend (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr opName))) kvs)

fn defText i: Int64 -> String
  (str "fn f" (stringFromInt64 i) " -> Int64\n  (+ " (stringFromInt64 i) " 1)\n\n")

fn fileText n: Int64 -> String
  (stringJoin (map defText (range 0 n)) "")

fn readHit -> String
  "(:read :file \"defs.txt\" :symbol \"f50\" :kind \"fn\" :language \"asl\" :start 151 :end 152 :content \"x\")"

fn readMiss n: Int64 -> String
  (str "(:read :status :rejected :error ERR_SYMBOL_NOT_FOUND :file \"defs.txt\" :symbol \"nope\" :language \"asl\" :outline ("
    (stringJoin (map (fn [i] (str "\"f" (stringFromInt64 i) " " (stringFromInt64 (+ (* i 3) 1)) "-" (stringFromInt64 (+ (* i 3) 2)) "\"")) (range 0 n)) " ") "))")

fn numbered n: Int64 -> String
  (stringJoin (map (fn [i] (str "line " (stringFromInt64 i))) (range 0 n)) "\n")

fn freshRoot -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        root (str base "/editBySymbolTest-" (stringFromInt64 (nowNs)))]
    (if (ok? (dirCreate root)) root root))

fn runTests -> Bool
  (let [root (freshRoot)
        defs (fileText 100)
        wrote (ok? (fileWrite (str root "/defs.txt") defs))
        long (ok? (fileWrite (str root "/long.txt") (numbered 100)))
        edge (ok? (fileWrite (str root "/edge.txt") (str (numbered 80) "\n")))
        env (ex/makeExecEnv root root "auto" (list "**") false "HEAD" (list)
              (list (pair "read" "local") (pair "write" "local") (pair "edit" "local") (pair "replaceDef" "local"))
              "" (list) 20000 60 (none) "editBySymbolTest" (none))
        idf (fn [] "id1")
        snap (fn [s] false)
        onKeep (fn [a b n] true)
        body "fn f50 -> Int64\n  (+ 50 1000)\n"
        want (str (fileText 50) body "\n" (stringJoin (map defText (range 51 100)) ""))
        wantForm (str "(:txn :owns (\"**\") (:write :file \"defs.txt\" :content \"" (c/escapeAsn want) "\"))")
        run (fn [f d]
              (cond
                ((and (stringStartsWith? f "(:read") (stringContains? f ":symbol \"f50\"")) (t/aslRun 0 (readHit) ""))
                ((stringStartsWith? f "(:read") (t/aslRun 0 (readMiss 100) ""))
                ((= f wantForm) (t/aslRun 0 "(:txn :ok)" ""))
                ((stringContains? f ":old") (t/aslRun 1 "(:txn :error \"ERR_NO_MATCH\")" ""))
                (else (t/aslRun 9 "unexpected form" f))))
        runWrite (fn [f d] (t/aslRun 0 "" ""))
        rd (ex/execOp! (stepOp "replaceDef" (list (pair "file" (c/kvStr "defs.txt")) (pair "symbol" (c/kvStr "f50")) (pair "content" (c/kvStr body)))) env (r/newProcs) idf snap onKeep run).rec
        rdMissing (ex/execOp! (stepOp "replaceDef" (list (pair "file" (c/kvStr "defs.txt")) (pair "symbol" (c/kvStr "nope")) (pair "content" (c/kvStr body)))) env (r/newProcs) idf snap onKeep run).rec
        wholeLong (ex/execOp! (stepOp "write" (list (pair "file" (c/kvStr "long.txt")) (pair "content" (c/kvStr "x")))) env (r/newProcs) idf snap onKeep runWrite).rec
        wholeEdge (ex/execOp! (stepOp "write" (list (pair "file" (c/kvStr "edge.txt")) (pair "content" (c/kvStr "x")))) env (r/newProcs) idf snap onKeep runWrite).rec
        noMatch (ex/execOp! (stepOp "edit" (list (pair "file" (c/kvStr "long.txt")) (pair "old" (c/kvStr "line 50x")) (pair "new" (c/kvStr "y")))) env (r/newProcs) idf snap onKeep run).rec
        shown (ex/formatOpReceipt noMatch 20000)]
    (do
      (assert (and wrote (and long edge)) "fixtures are written")
      (assert (= (listLength (stringSplit defs "\n")) 301) "the replaceDef fixture has 300 lines")
      (assert (= (o/spliceDef defs 151 152 body) (some want)) "spliceDef swaps exactly lines 151-152 and keeps all other bytes (expected text built independently)")
      (assert (stringStartsWith? want (c/sliceOf defs 0 (stringLength (str (fileText 50))))) "spliceDef keeps every byte before the span")
      (assert (stringEndsWith? want (c/sliceOf defs (stringLength (str (fileText 51))) (stringLength defs))) "spliceDef keeps every byte after the span")
      (assert (= (strField rd "status") "ok") (str "replaceDef lands the one-definition change: the write form equals the expected whole text, got " (strField rd "status") " " (strField rd "stdout") " " (strField rd "message")))
      (assert (= (strField rd "op") "replaceDef") "the receipt names replaceDef")
      (assert (= (strField rdMissing "error") "ERR_NO_SYMBOL") (str "an unknown symbol is refused with the outline names, got " (strField rdMissing "error")))
      (assert (and (stringContains? (strField rdMissing "message") "nearest of 100") (not (stringContains? (strField rdMissing "message") "f99"))) (str "the refusal names a bounded list, not all 100 definitions, got " (strField rdMissing "message")))
      (assert (= (strField wholeLong "error") "ERR_WRITE_WHOLE_FILE") (str "a whole write of an existing 100-line file is refused, got " (strField wholeLong "status") " " (strField wholeLong "error")))
      (assert (and (stringContains? (strField wholeLong "message") ":why") (and (stringContains? (strField wholeLong "message") ":fix") (stringContains? (strField wholeLong "message") "replaceDef"))) "the refusal is an ASN form with :why and :fix naming replaceDef")
      (assert (stringContains? (strField wholeLong "hint") "replaceDef") "the hint shows the replaceDef step")
      (assert (= (strField wholeEdge "status") "ok") (str "a whole write of an existing 80-line file still passes, got " (strField wholeEdge "error")))
      (assert (= (strField noMatch "status") "rejected") "an edit of absent text is rejected")
      (assert (and (<= (nearFirst noMatch) 51) (>= (nearLast noMatch) 51)) (str "the receipt carries :near lines around the nearest match, got " (stringFromInt64 (nearFirst noMatch)) "-" (stringFromInt64 (nearLast noMatch))))
      (assert (stringContains? shown " :near (") "the formatted receipt prints :near")
      (assert (ok? (pathRemove root)) "the temp dir is removed")
      true))
