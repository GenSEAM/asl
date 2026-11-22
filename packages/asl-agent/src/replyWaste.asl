(module asl-agent/replyWaste
  :x [ReplyWaste replyWaste]
  :i [])

(schema ReplyWaste
  (:f prose Int64)
  (:f total Int64)
  (:f noStep Bool))

fn replyWaste reply: String -> ReplyWaste
  (let [(total (stringLength reply))
        (start (firstFormStart reply 0 total))]
    (match start
      ((some i)
        (let [(prose (if (blankPrefix? reply 0 i) 0 i))
              (stepped (anyStepForm? reply i total))]
          (ReplyWaste :prose prose :total total :noStep (not stepped))))
      ((none)
        (ReplyWaste :prose total :total total :noStep true))))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn skipString s: String i: Int64 n: Int64 -> Int64
  (skipStringBody s (+ i 1) n)

fn skipStringBody s: String i: Int64 n: Int64 -> Int64
  (if (>= i n)
    n
    (let [(c (charAt s i))]
      (if (= c "\\")
        (skipStringBody s (+ i 2) n)
        (if (= c "\"")
          (+ i 1)
          (skipStringBody s (+ i 1) n)))))

fn firstFormStart s: String i: Int64 n: Int64 -> (Option Int64)
  (if (>= i n)
    (none)
    (if (= (charAt s i) "\"")
      (firstFormStart s (skipString s i n) n)
      (if (and (= (charAt s i) "(") (= (charAt s (+ i 1)) ":"))
        (some i)
        (firstFormStart s (+ i 1) n))))

fn blankPrefix? s: String i: Int64 j: Int64 -> Bool
  (if (>= i j)
    true
    (and (isSpaceChar (charAt s i)) (blankPrefix? s (+ i 1) j)))

fn anyStepForm? s: String i: Int64 n: Int64 -> Bool
  (if (>= i n)
    false
    (if (= (charAt s i) "\"")
      (anyStepForm? s (skipString s i n) n)
      (if (and (= (charAt s i) "(") (= (charAt s (+ i 1)) ":"))
        (let [(head (formHead s (+ i 2) n))
              (end (formEnd s i n))]
          (if (stepHead? head)
            true
            (if (>= end n) false (anyStepForm? s end n))))
        (anyStepForm? s (+ i 1) n))))

fn formHead s: String i: Int64 n: Int64 -> String
  (if (>= i n)
    ""
    (let [(c (charAt s i))]
      (if (or (isSpaceChar c) (or (= c "(") (= c ")")))
        ""
        (stringConcat c (formHead s (+ i 1) n)))))

fn stepHead? h: String -> Bool
  (or (= h "step") (or (= h "write") (or (= h "edit") (or (= h "done") (= h "gate")))))

fn formEnd s: String i: Int64 n: Int64 -> Int64
  (scanForm s i n 0 false)

fn scanForm s: String i: Int64 n: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= i n)
    n
    (let [(c (charAt s i))]
      (if inStr
        (if (= c "\\")
          (scanForm s (+ i 2) n depth true)
          (if (= c "\"")
            (scanForm s (+ i 1) n depth false)
            (scanForm s (+ i 1) n depth true)))
        (if (= c "\"")
          (scanForm s (+ i 1) n depth true)
          (if (= c "(")
            (scanForm s (+ i 1) n (+ depth 1) false)
            (if (= c ")")
              (if (<= depth 1)
                (+ i 1)
                (scanForm s (+ i 1) n (- depth 1) false))
              (scanForm s (+ i 1) n depth false)))))))
