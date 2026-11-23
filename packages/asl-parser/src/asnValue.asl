(module asl-parser/asnValue
  :x [AsnValue asnParse asnGet asnText asnInt asnFloat asnItems]
  :i [(asl-parser/reader :a rd)])

(enum AsnValue
  (:c asnKey [(name String)] "Keyword atom such as :name, stored without the colon")
  (:c asnSym [(name String)] "Bare symbol atom")
  (:c asnStr [(text String)] "String literal with escapes decoded")
  (:c asnNum [(n Int64)] "Integer literal")
  (:c asnReal [(x Float64)] "Floating point literal")
  (:c asnList [(items (List AsnValue))] "Parenthesized or bracketed list"))

(schema AsnScan
  (:f stack (List (Pair String Int64)))
  (:f inStr Bool)
  (:f esc Bool)
  (:f idx Int64)
  (:f strStart Int64)
  (:f err (Option String)))

fn asnScanStep st: AsnScan c: String -> AsnScan
  (match st.err
    ((some _) st)
    ((none)
     (let [(i (+ st.idx 1))]
       (if st.inStr
         (if st.esc
           (with st :idx i :esc false)
           (if (= c "\\")
             (with st :idx i :esc true)
             (if (= c "\"")
               (with st :idx i :inStr false)
               (with st :idx i))))
         (cond
           ((= c "\"") (with st :idx i :inStr true :strStart i))
           ((or (= c "(") (= c "[")) (with st :idx i :stack (cons (pair c i) st.stack)))
           ((or (= c ")") (= c "]"))
            (match (listHead st.stack)
              ((some top)
               (if (= (pairFirst top) (if (= c ")") "(" "["))
                 (with st :idx i :stack (optionOr (listTail st.stack) (list)))
                 (with st :idx i :err (some (str "mismatched '" c "' at position " (stringFromInt64 i))))))
              ((none) (with st :idx i :err (some (str "unbalanced '" c "' at position " (stringFromInt64 i)))))))
           (else (with st :idx i)))))))

fn asnScanEnd st: AsnScan -> (Option String)
  (match st.err
    ((some e) (some e))
    ((none)
     (if st.inStr
       (some (str "unterminated string starting at position " (stringFromInt64 st.strStart)))
       (match (listHead st.stack)
         ((some top) (some (str "unclosed '" (pairFirst top) "' at position " (stringFromInt64 (pairSecond top)))))
         ((none) (none))))))

fn asnEscChar c: String -> String
  (cond
    ((= c "\\") "\\")
    ((= c "\"") "\"")
    (else c))

fn asnUnescStep st: (Pair (List String) Bool) c: String -> (Pair (List String) Bool)
  (if (pairSecond st)
    (pair (cons (asnEscChar c) (pairFirst st)) false)
    (if (= c "\\")
      (pair (pairFirst st) true)
      (pair (cons c (pairFirst st)) false)))

fn asnUnescape s: String -> String
  (stringJoin (listReverse (pairFirst (fold asnUnescStep (pair (list) false) (stringChars s)))) "")

fn asnAtom v: String -> AsnValue
  (if (stringStartsWith? v "\"")
    (asnStr (asnUnescape (optionOr (stringSlice v 1 (- (stringLength v) 1)) "")))
    (if (stringStartsWith? v ":")
      (asnKey (optionOr (stringSlice v 1 (stringLength v)) ""))
      (match (stringToInt64 v)
        ((some n) (asnNum n))
        ((none)
         (match (stringToFloat64 v)
           ((some x) (asnReal x))
           ((none) (asnSym v)))))))

fn asnFromSexpr s: rd/SExpr -> AsnValue
  (match s
    ((rd/sexprAtom v) (asnAtom v))
    ((rd/sexprList items) (asnList (map asnFromSexpr items)))
    ((rd/sexprVect items) (asnList (map asnFromSexpr items))))

fn asnParse text: String -> (Result (List AsnValue) String)
  (let [(st (fold asnScanStep (AsnScan :stack (list) :inStr false :esc false :idx 0 :strStart 0 :err (none)) (stringChars text)))]
    (match (asnScanEnd st)
      ((some e) (err e))
      ((none)
       (let [(sx (rd/parseSexpr (str "(" text ")")))]
         (ok (map asnFromSexpr (rd/sexprToList sx)))))))

fn asnKeyName key: String -> String
  (if (stringStartsWith? key ":")
    (optionOr (stringSlice key 1 (stringLength key)) "")
    key)

fn asnGetLoop items: (List AsnValue) k: String -> (Option AsnValue)
  (match (listHead items)
    ((none) (none))
    ((some h)
     (let [(rest (optionOr (listTail items) (list)))]
       (match h
         ((asnKey n) (if (= n k) (listHead rest) (asnGetLoop (optionOr (listTail rest) (list)) k)))
         (_ (asnGetLoop rest k))))))

fn asnGet row: AsnValue key: String -> (Option AsnValue)
  (match row
    ((asnList items) (asnGetLoop items (asnKeyName key)))
    (_ (none)))

fn asnText v: AsnValue -> (Option String)
  (match v ((asnStr t) (some t)) (_ (none)))

fn asnInt v: AsnValue -> (Option Int64)
  (match v ((asnNum n) (some n)) (_ (none)))

fn asnFloat v: AsnValue -> (Option Float64)
  (match v ((asnReal x) (some x)) (_ (none)))

fn asnItems v: AsnValue -> (List AsnValue)
  (match v ((asnList items) items) (_ (list)))
