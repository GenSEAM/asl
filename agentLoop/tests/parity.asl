(module asl/agentLoop/tests/parity
  :x [argStr argInt argBool argNil? argItems argField argStrs argInts argOptStr argOptInt argAt
      sStr sInt sBool sNil sList sDict sOpt sOptInt sStrs sPair canon replay!]
  :i [(asl/agentLoop/plan :a p) (asl/agentLoop/core :a c)])

fn atomOf n: p/SexpNode -> String
  (mt n ((p/sexpAtom a) a) ((p/sexpStr _) "") ((p/sexpList _) ""))

fn listOf n: p/SexpNode -> (List p/SexpNode)
  (mt n ((p/sexpList xs) xs) ((p/sexpAtom _) (list)) ((p/sexpStr _) (list)))

fn headOf n: p/SexpNode -> String
  (let [xs (listOf n)]
    (if (listEmpty? xs) "" (atomOf (c/firstOf xs))))

fn argAt args: (List p/SexpNode) i: Int64 -> p/SexpNode
  (mt (listGet args i) ((some v) v) (none (p/sexpAtom "nil")))

fn argStr n: p/SexpNode -> String
  (mt n
    ((p/sexpStr s) s)
    ((p/sexpAtom a) (if (= a "nil") "" a))
    ((p/sexpList xs)
      (cond
        ((= (headOf n) "rep") (stringRepeat (argStr (argAt xs 1)) (argInt (argAt xs 2))))
        ((= (headOf n) "seq") (c/joinAll (map (fn [i] (str (argStr (argAt xs 1)) (stringFromInt64 i) "\n")) (range (argInt (argAt xs 2)) (argInt (argAt xs 3))))))
        ((= (headOf n) "cat") (c/joinAll (map argStr (c/restOf xs))))
        (else ""))))

fn argInt n: p/SexpNode -> Int64
  (optionOr (stringToInt64 (atomOf n)) 0)

fn argBool n: p/SexpNode -> Bool
  (= (atomOf n) "true")

fn argNil? n: p/SexpNode -> Bool
  (= (atomOf n) "nil")

fn argItems n: p/SexpNode -> (List p/SexpNode)
  (let [xs (listOf n)]
    (if (listEmpty? xs) (list) (c/restOf xs)))

fn argStrs n: p/SexpNode -> (List String)
  (map argStr (argItems n))

fn argInts n: p/SexpNode -> (List Int64)
  (map argInt (argItems n))

fn argOptStr n: p/SexpNode -> (Option String)
  (if (argNil? n) none (some (argStr n)))

fn argOptInt n: p/SexpNode -> (Option Int64)
  (if (argNil? n) none (some (argInt n)))

fn fieldIn xs: (List p/SexpNode) key: String -> (Option p/SexpNode)
  (if (listEmpty? xs)
    none
    (let [pr (listOf (c/firstOf xs))]
      (if (and (= (listLength pr) 2) (= (argStr (c/firstOf pr)) key))
        (some (argAt pr 1))
        (fieldIn (c/restOf xs) key))))

fn argField n: p/SexpNode key: String -> (Option p/SexpNode)
  (fieldIn (argItems n) key)

fn sStr s: String -> String
  (if (> (stringLength s) 4096)
    (str "(h " (stringFromInt64 (stringLength s)) " \"" (bytesSha256 (stringToBytes s)) "\")")
    (c/serString s))

fn sInt i: Int64 -> String
  (stringFromInt64 i)

fn sBool b: Bool -> String
  (if b "true" "false")

fn sNil -> String
  "nil"

fn sList xs: (List String) -> String
  (str "(l" (c/joinAll (map (fn [x] (str " " x)) xs)) ")")

fn sStrs xs: (List String) -> String
  (sList (map sStr xs))

fn sPair a: String b: String -> String
  (sList (list a b))

fn sOpt o: (Option String) -> String
  (mt o ((some s) (sStr s)) (none "nil"))

fn sOptInt o: (Option Int64) -> String
  (mt o ((some i) (sInt i)) (none "nil"))

fn sDict kv: (List (Pair String String)) -> String
  (str "(d" (c/joinAll (map (fn [pr] (str " (" (c/serString (pairFirst pr)) " " (pairSecond pr) ")")) (listSortBy pairFirst kv))) ")")

fn canon n: p/SexpNode -> String
  (mt n
    ((p/sexpAtom a) a)
    ((p/sexpStr s) (c/serString s))
    ((p/sexpList xs) (str "(" (c/joinSep (map canon xs) " ") ")")))

fn kvField xs: (List p/SexpNode) key: String -> p/SexpNode
  (cond
    ((listEmpty? xs) (p/sexpAtom "nil"))
    ((listEmpty? (c/restOf xs)) (p/sexpAtom "nil"))
    ((= (atomOf (c/firstOf xs)) key) (c/firstOf (c/restOf xs)))
    (else (kvField (c/restOf xs) key)))

fn cut s: String -> String
  (if (> (stringLength s) 300) (str (c/sliceOf s 0 300) "...") s)

fn ! checkLine line: String dispatch: (fn [String (List p/SexpNode)] -> String) -> Bool
  (mt (p/planTree line)
    ((err e) (do (assert (= e "") (str "fixture line parses: " (cut line))) false))
    ((ok nodes)
      (let [xs (listOf (c/firstOf nodes))
            cid (argStr (kvField xs ":id"))
            fname (argStr (kvField xs ":fn"))
            want (canon (kvField xs ":out"))
            got (dispatch fname (argItems (kvField xs ":args")))]
        (do (assert (= got want) (str cid " (" fname "): got " (cut got) " want " (cut want))) (= got want)))))

fn ! replay! path: String fns: (List String) dispatch: (fn [String (List p/SexpNode)] -> String) -> Int64
  (let [content (resultOr (fileReadString path) "")
        lines (stringLines content)
        header (filter (fn [l] (stringStartsWith? l "(:fixture ")) lines)
        cases (filter (fn [l] (stringStartsWith? l "(:case ")) lines)
        declared (mt (p/planTree (if (listEmpty? header) "()" (c/firstOf header)))
                   ((ok ns) (argInt (kvField (listOf (c/firstOf ns)) ":cases")))
                   ((err _) -1))
        present (fn [f] (listAny? (fn [l] (stringContains? l (str ":fn \"" f "\" "))) cases))]
    (do
      (assert (> (listLength cases) 0) (str path " holds cases"))
      (assert (= (listLength cases) declared) (str path " case count equals its header"))
      (fold (fn [acc f] (do (assert (present f) (str "fixture covers " f)) acc)) 0 fns)
      (fold (fn [acc line] (if (checkLine line dispatch) (+ acc 1) acc)) 0 cases)))
