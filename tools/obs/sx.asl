(module ws/asl/tools/obs/sx
  :x [Scan bodyFields scanRow listItems topFields head field fieldRaw unq quoteText intField maxScan]
  :i [])

; (:m :ref OBSCORPUS :do "reads the top-level fields of one single-line ASN row without a parser: strings, brackets and escapes are tracked per byte, so a key inside a quoted prompt or a nested form is never taken for a field; a row longer than maxScan bytes is cut there")
(schema Scan
  (:f depth Int64)
  (:f inStr Bool)
  (:f esc Bool)
  (:f tok Int64)
  (:f key String)
  (:f done Bool)
  (:f items Bool)
  (:f started Bool)
  (:f pairs (List (Pair String String))))

fn maxScan -> Int64
  24000

fn blank? b: Int64 -> Bool
  (or (= b 32) (or (= b 10) (or (= b 9) (= b 13))))

fn open? b: Int64 -> Bool
  (or (= b 40) (or (= b 91) (= b 123)))

fn close? b: Int64 -> Bool
  (or (= b 41) (or (= b 93) (= b 125)))

fn finish s: Scan text: String end: Int64 -> Scan
  (let [(t (optionOr (stringSlice text s.tok end) ""))]
    (if (not s.started)
      (with s :started true :tok -1 :pairs (cons (pair "_head" t) s.pairs))
    (if (stringEmpty? s.key)
      (if (stringStartsWith? t ":")
        (with (with s :key t) :tok -1)
        (if s.items (with (with s :pairs (cons (pair "_" t) s.pairs)) :tok -1) (with s :tok -1)))
      (with (with (with s :pairs (cons (pair s.key t) s.pairs)) :key "") :tok -1))))

fn step text: String bs: Bytes s: Scan i: Int64 -> Scan
  (let [(b (bytesGet bs i))]
    (cond
      (s.done s)
      (s.inStr
        (cond
          (s.esc (with s :esc false))
          ((= b 92) (with s :esc true))
          ((= b 34)
            (let [(s2 (with s :inStr false))]
              (if (= s.depth 1) (finish s2 text (+ i 1)) s2)))
          (else s)))
      ((= b 34)
        (if (and (= s.depth 1) (< s.tok 0))
          (with (with s :inStr true) :tok i)
          (with s :inStr true)))
      ((open? b)
        (if (and (= s.depth 1) (< s.tok 0))
          (with (with s :depth 2) :tok i)
          (with s :depth (+ s.depth 1))))
      ((close? b)
        (let [(d (- s.depth 1))]
          (cond
            ((= d 0)
              (with (if (>= s.tok 0) (finish s text i) s) :done true))
            ((= d 1) (finish (with s :depth 1) text (+ i 1)))
            (else (with s :depth d)))))
      ((blank? b)
        (if (and (= s.depth 1) (>= s.tok 0)) (finish s text i) s))
      (else
        (if (and (= s.depth 1) (< s.tok 0)) (with s :tok i) s))))

fn scanRow row: String items: Bool -> (List (Pair String String))
  (let [(text (if (> (stringLength row) (maxScan)) (optionOr (stringSlice row 0 (maxScan)) row) row))
        (bs (stringToBytes text))
        (n (bytesLength bs))
        (s0 (Scan :depth 0 :inStr false :esc false :tok -1 :key "" :done false :items items :started items :pairs (list)))
        (first (if (and (> n 0) (= (bytesGet bs 0) 40)) (with s0 :depth 1) s0))]
    (let [(end (fold (fn [(s Scan) (i Int64)] -> Scan (step text bs s i)) first (range 1 n)))]
      (listReverse end.pairs)))

fn head row: String -> String
  (let [(t (stringTrim row))]
    (if (stringStartsWith? t "(")
      (let [(rest (optionOr (stringSlice t 1 (min (stringLength t) 40)) ""))
            (cut (optionOr (stringIndexOf rest " ") (stringLength rest)))
            (cut2 (optionOr (stringIndexOf rest ")") (stringLength rest)))]
        (optionOr (stringSlice rest 0 (min cut cut2)) ""))
      ""))

fn fieldRaw fields: (List (Pair String String)) key: String -> (Option String)
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) key)) fields)
    ((some p) (some (pairSecond p)))
    ((none) none))

fn unq t: String -> String
  (if (and (stringStartsWith? t "\"") (stringEndsWith? t "\""))
    (stringReplace (stringReplace (stringReplace (stringReplace (optionOr (stringSlice t 1 (- (stringLength t) 1)) "") "\\n" "\n") "\\\"" "\"") "\\t" "\t") "\\\\" "\\")
    t)

fn field fields: (List (Pair String String)) key: String -> (Option String)
  (match (fieldRaw fields key)
    ((some t) (some (unq t)))
    ((none) none))

fn intField fields: (List (Pair String String)) key: String -> Int64
  (match (field fields key)
    ((some t) (optionOr (stringToInt64 t) 0))
    ((none) 0))

fn quoteText t: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace t "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn topFields row: String -> (List (Pair String String))
  (scanRow row false)

fn listItems raw: String -> (List String)
  (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) "_")) (scanRow raw true)))

; (:m :ref OBSCORPUS :do "a nested form that opens with a key, as (:input 1 :output 2), has no head atom; bodyFields reads such a form by giving it a dummy head")
fn bodyFields raw: String -> (List (Pair String String))
  (let [(t (stringTrim raw))]
    (topFields (if (stringStartsWith? t "(") (str "(:_ " (optionOr (stringSlice t 1 (stringLength t)) "")) t)))
