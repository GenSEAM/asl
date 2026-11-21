(module asl-checker/layout
  :x [FieldSpec Layout layoutOf]
  :i [(asl-checker/numKinds :a nk)])

; (:m :ref LL-LAYOUT-VIEW :do "pure struct layout: packed and C modes over FieldSpec rows, natural alignment from numKinds intKindWidth plus F64, an :align override of the struct alignment, and ERR_LAYOUT_FIELD for an unknown kind or a count below 1")

(schema FieldSpec (:f name String) (:f kind String) (:f count Int64))

(schema Layout (:f sizeOf Int64) (:f offsetOf (List Int64)))

fn kindSize kind: String -> Int64
  (let [(w (nk/intKindWidth kind))]
    (cond ((= kind "F64") 8) ((= w 8) 1) ((= w 16) 2) ((= w 32) 4) ((= w 64) 8) (else 0)))

fn fieldSize f: FieldSpec -> Int64
  (* (kindSize f.kind) f.count)

fn badField? f: FieldSpec -> Bool
  (or (< f.count 1) (<= (kindSize f.kind) 0))

fn alignUp n: Int64 a: Int64 -> Int64
  (if (or (<= a 1) (= (mod n a) 0)) n (+ n (- a (mod n a))))

fn place mode: String fields: (List FieldSpec) off: Int64 maxA: Int64 acc: (List Int64) -> (Pair (List Int64) (Pair Int64 Int64))
  (match (listHead fields)
    ((none) (pair (listReverse acc) (pair off maxA)))
    ((some f)
      (let [(a (if (= mode "c") (kindSize f.kind) 1))
            (o (alignUp off a))]
        (place mode (optionOr (listTail fields) (list)) (+ o (fieldSize f)) (max maxA a) (cons o acc)))))

fn layoutOf mode: String fields: (List FieldSpec) align: (Option Int64) -> (Result Layout String)
  (if (listAny? badField? fields)
    (err "ERR_LAYOUT_FIELD")
    (let [(r (place mode fields 0 1 (list)))
          (offs (pairFirst r))
          (off (pairFirst (pairSecond r)))
          (maxA (pairSecond (pairSecond r)))
          (sa (optionOr align maxA))]
      (ok (Layout :sizeOf (alignUp off sa) :offsetOf offs))))
