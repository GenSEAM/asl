(module asl-target-llvm/tests/fixtures/recordUnbox/par
  :x [main]
  :i [])

(schema Pt
  (:f x Int64)
  (:f label String)
  (:f w Float64)
  (:f on Bool))

fn bump p: Pt -> Pt
  (Pt :x (+ p.x 1) :label (str p.label "+") :w (* p.w 2.0) :on (not p.on))

fn px p: Pt -> Int64
  (if p.on (* p.x 10) p.x)

fn ! main args: (List String) -> (Result Unit String)
  (let [(pts (map (fn [(i Int64)] -> Pt (Pt :x i :label (str "p" i) :w (int64ToFloat64 i) :on (= (mod i 2) 0))) (list 1 2 3 4)))
        (back (parMap bump pts 2))]
    (do (println (str "par " (stringJoin (map (fn [(p Pt)] -> String (str p)) back) " ")))
        (println (str "fields " (fold (fn [(a Int64) (p Pt)] -> Int64 (+ a p.x)) 0 back) " " (fold (fn [(a Float64) (p Pt)] -> Float64 (+ a p.w)) 0.0 back) " " (listLength (filter (fn [(p Pt)] -> Bool p.on) back))))
        (println (str "typed " (stringJoin (map (fn [(p Pt)] -> String (str (px p))) back) ",")))
        (println (str "eq " (= back (map bump pts))))
        (ok ())))
