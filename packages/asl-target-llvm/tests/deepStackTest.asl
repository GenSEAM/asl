(module asl-target-llvm/tests/deepStackTest
  :x [runTests]
  :i [])

fn depth -> Int64
  400000

fn opens n: Int64 -> String
  (stringRepeat "(" n)

fn closes n: Int64 -> String
  (stringRepeat ")" n)

fn group bs: Bytes n: Int64 p: Int64 -> Int64
  (if (and (< p n) (= (bytesGet bs p) 40))
    (let [(q (group bs n (+ p 1)))]
      (if (and (>= q 0) (and (< q n) (= (bytesGet bs q) 41))) (+ q 1) -1))
    p)

fn keep k: Int64 -> Int64
  (if (= k 0)
    0
    (let [(mine (stringRepeat "x" (+ 200 (mod k 7))))
          (spent (stringLength (stringRepeat "y" (+ 40 (mod k 5)))))
          (below (keep (- k 1)))]
      (+ below (+ (stringLength mine) spent))))

fn kept k: Int64 -> Int64
  (if (= k 0) 0 (+ (+ (+ 200 (mod k 7)) (+ 40 (mod k 5))) (kept (- k 1))))

fn ! runTests -> Bool
  (let [(text (str (opens (depth)) (closes (depth))))
        (bs (stringToBytes text))
        (n (bytesLength bs))
        (end (group bs n 0))
        (total (keep (depth)))]
    (do
      (assert (= n (* 2 (depth))) "the probe text holds every bracket")
      (assert (= end n) (str "a 400000-deep group parses to the end: " end))
      (assert (= total (kept (depth))) (str "strings held only by deep frames survive collections: " total))
      true))
