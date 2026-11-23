(module asl-utils/textDiff :x [Hunk textDiff applyDiff renderUnified] :i [])

(schema Hunk (:f op String) (:f text String) (:f srcLine Int64) (:f tgtLine Int64))

fn atLine xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn atNum xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn atRow tbl: (List (List Int64)) i: Int64 -> (List Int64)
  (optionOr (listGet tbl i) (list))

fn buildRow a: (List String) b: (List String) prev: (List Int64) i: Int64 j: Int64 m: Int64 left: Int64 -> (List Int64)
  (if (> j m)
    (list)
    (let [(v (if (or (= i 0) (= j 0))
               0
               (if (= (atLine a (- i 1)) (atLine b (- j 1)))
                 (+ 1 (atNum prev (- j 1)))
                 (max (atNum prev j) left))))]
      (cons v (buildRow a b prev i (+ j 1) m v))))

fn buildRows a: (List String) b: (List String) i: Int64 n: Int64 m: Int64 prev: (List Int64) -> (List (List Int64))
  (if (> i n)
    (list)
    (let [(row (buildRow a b prev i 0 m 0))]
      (cons row (buildRows a b (+ i 1) n m row))))

fn lcsTable a: (List String) b: (List String) -> (List (List Int64))
  (let [(n (listLength a))
        (m (listLength b))]
    (buildRows a b 0 n m (list)))

fn walk tbl: (List (List Int64)) a: (List String) b: (List String) i: Int64 j: Int64 -> (List Hunk)
  (if (= i 0)
    (if (= j 0)
      (list)
      (cons (Hunk :op "add" :text (atLine b (- j 1)) :srcLine 1 :tgtLine j)
            (walk tbl a b 0 (- j 1))))
    (if (= j 0)
      (cons (Hunk :op "del" :text (atLine a (- i 1)) :srcLine i :tgtLine 1)
            (walk tbl a b (- i 1) 0))
      (if (= (atLine a (- i 1)) (atLine b (- j 1)))
        (cons (Hunk :op "keep" :text (atLine a (- i 1)) :srcLine i :tgtLine j)
              (walk tbl a b (- i 1) (- j 1)))
        (if (>= (atNum (atRow tbl (- i 1)) j) (atNum (atRow tbl i) (- j 1)))
          (cons (Hunk :op "del" :text (atLine a (- i 1)) :srcLine i :tgtLine (+ j 1))
                (walk tbl a b (- i 1) j))
          (cons (Hunk :op "add" :text (atLine b (- j 1)) :srcLine (+ i 1) :tgtLine j)
                (walk tbl a b i (- j 1)))))))

fn textDiff a: (List String) b: (List String) -> (List Hunk)
  (listReverse (walk (lcsTable a b) a b (listLength a) (listLength b)))

fn applyDiff hunks: (List Hunk) -> String
  (fold (fn [(acc String) (h Hunk)] -> String
          (if (= h.op "del") acc (str acc h.text "\n")))
        "" hunks)

fn renderUnified srcName: String tgtName: String src: (List String) tgt: (List String) -> String
  (let [(hunks (textDiff src tgt))
        (srcCount (fold (fn [(acc Int64) (h Hunk)] -> Int64 (if (= h.op "add") acc (+ acc 1))) 0 hunks))
        (tgtCount (fold (fn [(acc Int64) (h Hunk)] -> Int64 (if (= h.op "del") acc (+ acc 1))) 0 hunks))
        (srcStart (match (listHead (filter (fn [(h Hunk)] -> Bool (not (= h.op "add"))) hunks))
                    ((some h) h.srcLine)
                    ((none) 0)))
        (tgtStart (match (listHead (filter (fn [(h Hunk)] -> Bool (not (= h.op "del"))) hunks))
                    ((some h) h.tgtLine)
                    ((none) 0)))
        (body (fold (fn [(acc String) (h Hunk)] -> String
                      (str acc (if (= h.op "keep") " " (if (= h.op "add") "+" "-")) h.text "\n"))
                    "" hunks))]
    (str "--- a/" srcName "\n" "+++ b/" tgtName "\n"
         "@@ -" (str srcStart) "," (str srcCount) " +" (str tgtStart) "," (str tgtCount) " @@\n"
         body))
