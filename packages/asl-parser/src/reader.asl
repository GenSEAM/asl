(module asl-parser/reader :x [SExpr makeAtom makeList makeVect isAtom? isList? isVect? isHeadMatch? sexprHead sexprToList renderCompound renderSexpr renderPrefix parseSexpr])

(enum SExpr (:c sexprAtom [(val String)] "Terminal atom token (symbol, literal or keyword)") (:c sexprList [(items (List SExpr))] "Parenthesized list '( ... )'") (:c sexprVect [(items (List SExpr))] "Bracketed vector '[ ... ]'"))

fn makeAtom v: String -> SExpr
  (sexprAtom v)

fn makeList items: (List SExpr) -> SExpr
  (sexprList items)

fn makeVect items: (List SExpr) -> SExpr
  (sexprVect items)

fn isAtom? s: SExpr -> Bool
  (mt s ((sexprAtom _) true) ((sexprList _) false) ((sexprVect _) false))

fn isList? s: SExpr -> Bool
  (mt s ((sexprAtom _) false) ((sexprList _) true) ((sexprVect _) false))

fn isVect? s: SExpr -> Bool
  (mt s ((sexprAtom _) false) ((sexprList _) false) ((sexprVect _) true))

fn sexprHead s: SExpr -> String
  (mt s ((sexprAtom v) v) ((sexprList items) (mt (listHead items) ((some h) (mt h ((sexprAtom hv) hv) ((sexprList _) "") ((sexprVect _) ""))) ((none) ""))) ((sexprVect _) ""))

fn isHeadMatch? s: SExpr expected: String -> Bool
  (= (sexprHead s) expected)

fn sexprToList s: SExpr -> (List SExpr)
  (mt s ((sexprVect items) items) ((sexprList items) items) ((sexprAtom _) (list)))

(enum RItem (:c rText [(t String)] "Literal output text, already final") (:c rExpr [(e SExpr)] "An SExpr still to be expanded"))

(schema RState (:f work (List RItem)) (:f out (List String)) (:f sugar Bool))

fn rTail items: (List RItem) -> (List RItem)
  (optionOr (listTail items) (list))

fn rSeparatedLoop items: (List SExpr) acc: (List RItem) -> (List RItem)
  (if (listEmpty? items)
    (listReverse acc)
    (let [(hd (optionOr (listHead items) (sexprAtom "")))
          (tl (optionOr (listTail items) (list)))]
      (rSeparatedLoop tl (cons (rExpr hd) (cons (rText " ") acc)))))

fn rSeparated items: (List SExpr) -> (List RItem)
  (if (listEmpty? items)
    (list)
    (let [(h (optionOr (listHead items) (sexprAtom "")))
          (rest (optionOr (listTail items) (list)))]
      (rSeparatedLoop rest (list (rExpr h)))))

fn rExpand open: String items: (List SExpr) close: String -> (List RItem)
  (cons (rText open) (listAppend (rSeparated items) (list (rText close))))

fn rFieldName head: SExpr -> String
  (mt head ((sexprAtom v) (if (and (stringStartsWith? v ".-") (> (stringLength v) 2)) (optionOr (stringSlice v 2 (stringLength v)) "") "")) (_ ""))

fn rNameAtom? v: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" (optionOr (stringSlice v 0 1) "-"))

fn rFieldOperand e: SExpr field: String -> (List RItem)
  (mt e
    ((sexprAtom v) (if (rNameAtom? v) (list (rExpr e) (rText (str "." field))) (list (rText "(do ") (rExpr e) (rText (str ")." field)))))
    ((sexprList _) (list (rExpr e) (rText (str "." field))))
    ((sexprVect _) (list (rText "(do ") (rExpr e) (rText (str ")." field)))))

fn rList items: (List SExpr) -> (List RItem)
  (let [(field (rFieldName (optionOr (listHead items) (sexprAtom ""))))
        (args (optionOr (listTail items) (list)))]
    (if (and (not (stringEmpty? field)) (= (listLength args) 1))
      (rFieldOperand (optionOr (listHead args) (sexprAtom "")) field)
      (rExpand "(" items ")")))

fn rTick st: RState tick: Int64 -> RState
  (mt (listHead st.work) ((some it) (let [(rest (rTail st.work))] (mt it ((rText t) (with st :work rest :out (cons t st.out))) ((rExpr e) (mt e ((sexprAtom v) (with st :work rest :out (cons v st.out))) ((sexprList items) (with st :work (listAppend (if st.sugar (rList items) (rExpand "(" items ")")) rest))) ((sexprVect items) (with st :work (listAppend (rExpand "[" items "]") rest)))))))) ((none) st))

fn rRunSteps st: RState stepsLeft: Int64 -> RState
  (if (<= stepsLeft 0)
    st
    (mt (listHead st.work)
      ((none) st)
      ((some _) (rRunSteps (rTick st 0) (- stepsLeft 1)))))

fn rRun st: RState budget: Int64 -> RState
  (let [(next (rRunSteps st budget))] (if (listEmpty? next.work) next (rRun next (* budget 2))))

fn rRender items: (List RItem) sugar: Bool -> String
  (stringJoin (listReverse (rRun (RState :work items :out (list) :sugar sugar) 64).out) "")

fn renderCompound isParen: Bool items: (List SExpr) -> String
  (rRender (rExpand (if isParen "(" "[") items (if isParen ")" "]")) true)

fn renderSexpr s: SExpr -> String
  (rRender (list (rExpr s)) true)

fn renderPrefix s: SExpr -> String
  (rRender (list (rExpr s)) false)

(schema TokState (:f toks (List String)) (:f cur String) (:f inStr Bool) (:f esc Bool))

fn flushTok toks: (List String) cur: String -> (List String)
  (if (stringEmpty? cur) toks (cons cur toks))

fn tokenizeStep st: TokState c: String -> TokState
  (if st.inStr
    (if st.esc
      (with st :cur (str st.cur c) :inStr true :esc false)
      (if (= c "\\")
        (with st :cur (str st.cur c) :inStr true :esc true)
        (if (= c "\"")
          (TokState :toks (flushTok st.toks (str st.cur c)) :cur "" :inStr false :esc false)
          (with st :cur (str st.cur c) :inStr true :esc false))))
    (cond
      ((= c "\"") (TokState :toks (flushTok st.toks st.cur) :cur "\"" :inStr true :esc false))
      ((or (= c "(") (or (= c ")") (or (= c "[") (= c "]"))))
       (TokState :toks (cons c (flushTok st.toks st.cur)) :cur "" :inStr false :esc false))
      ((or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))
       (TokState :toks (flushTok st.toks st.cur) :cur "" :inStr false :esc false))
      (else (with st :cur (str st.cur c) :inStr false :esc false))))

fn tokenize s: String -> (List String)
  (let [(st (fold tokenizeStep (TokState :toks (list) :cur "" :inStr false :esc false) (stringChars s)))]
    (listReverse (flushTok st.toks st.cur)))

fn parseItem toks: (List String) -> (Pair SExpr (List String))
  (mt (listHead toks)
    ((none) (pair (sexprAtom "") (list)))
    ((some h)
     (let [(rest (optionOr (listTail toks) (list)))]
       (cond
         ((= h "(") (let [(res (parseItems rest ")" (list)))] (pair (sexprList (pairFirst res)) (pairSecond res))))
         ((= h "[") (let [(res (parseItems rest "]" (list)))] (pair (sexprVect (pairFirst res)) (pairSecond res))))
         (else (pair (sexprAtom h) rest))))))

fn parseItems toks: (List String) closeTok: String acc: (List SExpr) -> (Pair (List SExpr) (List String))
  (mt (listHead toks)
    ((none) (pair (listReverse acc) (list)))
    ((some h)
     (if (= h closeTok)
       (pair (listReverse acc) (optionOr (listTail toks) (list)))
       (let [(itemRes (parseItem toks))] (parseItems (pairSecond itemRes) closeTok (cons (pairFirst itemRes) acc))))))

fn parseSexpr s: String -> SExpr
  (pairFirst (parseItem (tokenize s)))
