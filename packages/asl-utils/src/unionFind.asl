(module asl-utils/unionFind
  :x [Dsu empty add find union connected componentCount]
  :i [])

(schema Dsu
  (:f parent (Map Int64 Int64))
  (:f rank (Map Int64 Int64))
  (:f count Int64))

fn empty -> Dsu
  (Dsu :parent (mapEmpty) :rank (mapEmpty) :count 0)

fn add d: Dsu n: Int64 -> Dsu
  (match (mapGet d.parent n)
    ((some _) d)
    ((none)
      (with d
        :parent (mapSet d.parent n n)
        :rank (mapSet d.rank n 0)
        :count (+ d.count 1))))

fn find d: Dsu n: Int64 -> (Pair Dsu Int64)
  (let [(p (mapGetOr d.parent n n))]
    (if (= p n)
      (pair d n)
      (let [(gp (mapGetOr d.parent p p))]
        (if (= gp p)
          (pair d p)
          (find (with d :parent (mapSet d.parent n gp)) gp)))))

fn union d0: Dsu a: Int64 b: Int64 -> Dsu
  (let [(d (add (add d0 a) b))
        (ra (find d a))
        (rb (find (pairFirst ra) b))
        (x (pairSecond ra))
        (y (pairSecond rb))
        (d1 (pairFirst rb))]
    (if (= x y)
      d1
      (let [(rx (mapGetOr d1.rank x 0))
            (ry (mapGetOr d1.rank y 0))]
        (if (< rx ry)
          (Dsu :parent (mapSet d1.parent x y) :rank d1.rank :count (- d1.count 1))
          (if (< ry rx)
            (Dsu :parent (mapSet d1.parent y x) :rank d1.rank :count (- d1.count 1))
            (Dsu :parent (mapSet d1.parent y x) :rank (mapSet d1.rank x (+ rx 1)) :count (- d1.count 1)))))))

fn connected d: Dsu a: Int64 b: Int64 -> Bool
  (match (mapGet d.parent a)
    ((none) false)
    ((some _)
      (match (mapGet d.parent b)
        ((none) false)
        ((some _)
          (let [(ra (find d a))
                (rb (find (pairFirst ra) b))]
            (= (pairSecond ra) (pairSecond rb)))))))

fn componentCount d: Dsu -> Int64
  d.count
