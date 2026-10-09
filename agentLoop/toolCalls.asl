(module asl/agentLoop/toolCalls
  :x [untagToolCalls]
  :i [(asl/agentLoop/core :a c) (asl/agentLoop/context :a cx)])

enum Evt
  (evt end: Int64 open: Bool)
fn at s: String i: Int64 t: String -> Bool
  (and (<= (+ i (stringLength t)) (stringLength s)) (= (c/sliceOf s i (+ i (stringLength t))) t))
fn scan s: String n: Int64 i: Int64 q: Bool e: Bool a: (List Evt) -> (List Evt)
  (if (>= i n) (listReverse a) (let [c0 (c/ch s i)]
    (cond (q (cond (e (scan s n (+ i 1) true false a))
      ((= c0 "\\") (scan s n (+ i 1) true true a))
      ((= c0 "\"") (scan s n (+ i 1) false false a))
      (else (scan s n (+ i 1) true false a))))
      ((= c0 "\"") (scan s n (+ i 1) true false a))
      ((at s i "<tool_call>") (scan s n (+ i 11) false false (cons (evt (+ i 11) true) a)))
      ((at s i "</tool_call>") (scan s n (+ i 12) false false (cons (evt (+ i 12) false) a)))
      ((at s i "]]>") (scan s n (+ i 3) false false (cons (evt (+ i 3) false) a)))
      (else (scan s n (+ i 1) false false a)))))
fn hasOpen es: (List Evt) -> Bool
  (if (listEmpty? es) false (mt (c/firstOf es) ((evt end open) (or open (hasOpen (c/restOf es))))))
fn depth s: String n: Int64 i: Int64 d: Int64 q: Bool e: Bool -> Int64
  (if (>= i n) d (let [c0 (c/ch s i)]
    (cond (q (cond (e (depth s n (+ i 1) d true false))
      ((= c0 "\\") (depth s n (+ i 1) d true true))
      ((= c0 "\"") (depth s n (+ i 1) d false false))
      (else (depth s n (+ i 1) d true false))))
      ((= c0 "\"") (depth s n (+ i 1) d true false))
      ((= c0 "(") (depth s n (+ i 1) (+ d 1) false false))
      ((= c0 ")") (depth s n (+ i 1) (- d 1) false false))
      (else (depth s n (+ i 1) d false false)))))
fn digitsOnly s: String i: Int64 -> Bool
  (if (>= i (stringLength s)) true (and (c/isDigit (c/ch s i)) (digitsOnly s (+ i 1))))
fn integerText s: String -> Bool
  (cond ((stringEmpty? s) false)
    ((= (c/ch s 0) "-") (and (> (stringLength s) 1) (digitsOnly s 1)))
    (else (digitsOnly s 0)))
fn pyGapEnd b: String n: Int64 i: Int64 -> Int64
  (let [tail (c/sliceOf b i n) trimmed (cx/pyStrip tail)]
    (+ i (- (stringLength tail) (stringLength trimmed))))
fn keyClose b: String n: Int64 from: Int64 -> (Option (Pair Int64 Int64))
  (mt (stringIndexOf (c/sliceOf b from n) "</arg_key>")
    ((none) (none))
    ((some rel)
      (let [ke (+ from rel) ws (pyGapEnd b n (+ ke 10))]
        (if (at b ws "<arg_value>") (some (pair ke ws)) (keyClose b n (+ ke 10))))))
fn argFields b: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (mt (stringIndexOf (c/sliceOf b i n) "<arg_key>")
    ((none) (listReverse acc))
    ((some rel)
      (let [ks (+ i rel 9)]
        (mt (keyClose b n ks) ((none) (listReverse acc)) ((some kw)
          (let [ke (pairFirst kw) vs (+ (pairSecond kw) 11) vr (stringIndexOf (c/sliceOf b vs n) "</arg_value>")]
            (mt vr ((none) (listReverse acc)) ((some endrel)
              (let [ve (+ vs endrel) key (cx/pyStrip (c/sliceOf b ks ke))
                    v (c/sliceOf b vs ve) bare (cx/pyStrip v)
                    field (if (integerText bare) (str ":" key " " bare)
                      (str ":" key " \"" (c/escapeAsn v) "\""))]
                (argFields b n (+ ve 12) (cons field acc)))))))))))
fn rewrite raw: String -> String
  (let [b (cx/pyStrip raw) n (stringLength b) a (stringIndexOf b "<arg_key>")]
    (cond ((= n 0) "")
      ((and (some? a) (not (listEmpty? (argFields b n (optionOr a 0) (list))))) (mt a ((some p)
        (let [name (cx/pyStrip (c/sliceOf b 0 p)) fields (argFields b n p (list))]
          (if (stringEmpty? name) "" (str "(:step :op \"" (c/escapeAsn name) "\" " (stringJoin fields " ") ")"))))
        ((none) b)))
      (else (let [f (if (stringStartsWith? b "(") b (if (stringStartsWith? b "step") (str "(:" b) (str "(" b)))
        d (depth f (stringLength f) 0 0 false false)]
        (cond ((> d 0) (str f (stringRepeat ")" d)))
          ((< d 0) (let [z (stringRepeat ")" (- 0 d))]
            (if (stringEndsWith? f z) (c/sliceOf f 0 (+ (stringLength f) d)) f)))
          (else f))))))
fn wrap raw: String -> String
  (let [r (rewrite raw)] (if (stringEmpty? r) "" (str "\n" r "\n")))
fn run s: String es: (List Evt) cur: Int64 active: Int64 out: (List String) count: Int64 -> (Pair String Int64)
  (if (listEmpty? es)
    (let [tail (if (>= active 0) (wrap (c/sliceOf s active (stringLength s))) (c/sliceOf s cur (stringLength s)))
      xs (if (stringEmpty? tail) out (cons tail out))
      n (if (and (>= active 0) (not (stringEmpty? tail))) 1 0)]
      (pair (stringJoin (listReverse xs) "") (+ count n)))
    (mt (c/firstOf es) ((evt end open)
      (if open
        (if (>= active 0) (let [r (wrap (c/sliceOf s active (- end 11))) xs (if (stringEmpty? r) out (cons r out))]
          (run s (c/restOf es) end end xs (+ count (if (stringEmpty? r) 0 1))))
          (let [p (c/sliceOf s cur (- end 11))]
            (run s (c/restOf es) end end (if (stringEmpty? p) out (cons p out)) count)))
        (if (>= active 0) (let [r (wrap (c/sliceOf s active (- end (if (at s (- end 3) "]]>") 3 12))))
            xs (if (stringEmpty? r) out (cons r out))]
          (run s (c/restOf es) end -1 xs (+ count (if (stringEmpty? r) 0 1))))
          (run s (c/restOf es) cur -1 out count))))))
fn untagToolCalls input: String -> (Pair String Int64)
  (let [s (if (stringEmpty? input) "" input) es (scan s (stringLength s) 0 false false (list))]
    (if (hasOpen es) (run s es 0 -1 (list) 0) (pair s 0)))
