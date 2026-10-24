(module asl-target-llvm/tests/fixtures/recordUnbox/mixed
  :x [main]
  :i [])

(schema Mix
  (:f id Int64)
  (:f name String)
  (:f ratio Float64)
  (:f tags (List String))
  (:f ok Bool))

(schema Fl
  (:f x Float64)
  (:f y Float64)
  (:f b Bool))

fn make i: Int64 -> Mix
  (Mix :id i :name (str "m" i) :ratio (/ (int64ToFloat64 i) 4.0) :tags (list "t" (str i)) :ok (= (mod i 2) 0))

fn permuted i: Int64 -> Mix
  (Mix :ok (> i 1) :tags (list) :ratio 2.5 :name "p" :id (* i 7))

fn relay v: V -> W
  v

fn wrong -> W
  "not an int"

fn idOf r: V -> W
  r.id

fn line m: Mix -> String
  (str m.id "|" m.name "|" m.ratio "|" (stringJoin m.tags ",") "|" m.ok)

fn score m: Mix -> Float64
  (if m.ok (+ m.ratio 1.0) m.ratio)

fn nameOf m: Mix -> String
  m.name

fn tagsOf m: Mix -> (List String)
  m.tags

fn ! main args: (List String) -> (Result Unit String)
  (let [(ms (map make (list 1 2 3 4 5)))
        (p (permuted 3))
        (q (make 3))
        (up (with q :id 42))
        (upName (with q :name "renamed" :ok false))
        (dyn (Mix :id (relay 11) :name "dyn" :ratio 1.5 :tags (list) :ok true))
        (fb (Mix :id (wrong) :name "fb" :ratio 0.5 :tags (list "x") :ok false))
        (nan (Fl :x (/ 0.0 0.0) :y -0.0 :b true))
        (zero (Fl :x 1.0 :y 0.0 :b true))
        (negz (Fl :x 1.0 :y -0.0 :b true))]
    (do (println (str "ids " (fold (fn [(a Int64) (m Mix)] -> Int64 (+ a m.id)) 0 ms)))
        (println (str "ratios " (fold (fn [(a Float64) (m Mix)] -> Float64 (+ a m.ratio)) 0.0 ms)))
        (println (str "oks " (listLength (filter (fn [(m Mix)] -> Bool m.ok) ms))))
        (println (stringJoin (map line ms) " "))
        (println (str "record " q))
        (println (str "permuted " p " " (line p)))
        (println (str "with " (line up) " " (line upName) " " up))
        (println (str "dyn " (line dyn) " " dyn))
        (println (str "fallback " fb " " (idOf fb) " " fb.name " " fb.ratio " " fb.ok))
        (println (str "fallback typed " (score fb) " " (score q) " " (nameOf fb) " " (stringJoin (tagsOf fb) ",")))
        (println (str "generic " (idOf q) " " (idOf p)))
        (println (str "eq " (= q (make 3)) " " (= q p) " " (= p (Mix :id 21 :name "p" :ratio 2.5 :tags (list) :ok true)) " " (= dyn (Mix :ok true :tags (list) :ratio 1.5 :name "dyn" :id 11))))
        (println (str "floats " nan " " nan.x " " nan.y " " nan.b " " (= zero negz) " " (= nan nan) " " zero.y " " negz.y))
        (ok ())))
