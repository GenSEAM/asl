(module regionInfer
  :x [main]
  :i [])

schema Rec
  a: Int64
  b: Int64

schema Holder
  items: (List Rec)
  n: Int64

fn build i: Int64 n: Int64 acc: (List Rec) -> (List Rec)
  (if (= i n) acc (build (+ i 1) n (cons (Rec :a i :b (* i 3)) acc)))

fn sumB xs: (List Rec) acc: Int64 -> Int64
  (if (listEmpty? xs)
    acc
    (sumB (optionOr (listTail xs) (list)) (+ acc (match (listHead xs) ((some r) r.b) ((none) 0)))))

; (:m :ref SOAREGION :do "regioned: the built list is read only by a fold whose Int64 result is unboxed")
fn regionSum n: Int64 -> Int64
  (let [(xs (build 0 n (list)))
        (s (fold (fn [(a Int64) (r Rec)] -> Int64 (+ a r.b)) 0 xs))]
    s)

; (:m :ref SOAREGION :do "regioned: the consumer returns a raw Int64")
fn regionRaw n: Int64 -> Int64
  (sumB (build 0 n (list)) 0)

fn rounds i: Int64 k: Int64 acc: Int64 -> Int64
  (if (= i k) acc (rounds (+ i 1) k (+ acc (regionSum (+ 100 i)))))

; (:m :ref SOAREGION :do "kept, return: the list leaves the function")
fn keepReturn n: Int64 -> (List Rec)
  (let [(xs (build 0 n (list)))
        (s (sumB xs 0))]
    (if (> s 0) xs (list)))

fn wrap xs: (List Rec) -> Holder
  (Holder :items xs :n (sumB xs 0))

; (:m :ref SOAREGION :do "kept, store to an outer value: the list is stored in a record that is the consumer's result")
fn keepStore n: Int64 -> Int64
  (let [(h (wrap (build 0 n (list))))]
    (+ h.n (listLength h.items)))

fn sumVia xs: (List Rec) -> Int64
  (let [(k (fn [(a Int64)] -> Int64 (+ a (sumB xs 0))))]
    (+ (sumB xs 0) (listLength (list k))))

; (:m :ref SOAREGION :do "kept, closure capture: the consumer captures the list in a closure")
fn keepClosure n: Int64 -> Int64
  (sumVia (build 0 n (list)))

fn ! sumLog xs: (List Rec) -> Int64
  (do (println "log") (sumB xs 0))

; (:m :ref SOAREGION :do "kept, unknown call: the consumer calls a builtin with an effect")
fn ! keepUnknown n: Int64 -> Int64
  (sumLog (build 0 n (list)))

; (:m :ref SOAREGION :do "kept, outer heap value: the producer conses onto a list from outside")
fn keepOuter n: Int64 base: (List Rec) -> Int64
  (sumB (build 0 n base) 0)

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (base (build 0 3 (list)))]
    (do (println (str (regionSum n) " " (regionRaw n) " " (rounds 0 50 0)))
        (println (str (listLength (keepReturn n)) " " (keepStore n) " " (keepClosure n) " " (keepUnknown n) " " (keepOuter n base) " " (listLength base)))
        (ok ())))
