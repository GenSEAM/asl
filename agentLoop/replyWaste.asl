(module asl/agentLoop/replyWaste
  :x [ReplyWaste replyWaste]
  :i [])

(schema ReplyWaste (:f prose Int64) (:f total Int64) (:f noStep Bool))

fn replyWaste reply: String -> ReplyWaste
  (let [(total (stringLength reply))]
    (match (firstFormIndex reply)
      ((some i) (ReplyWaste :prose i :total total :noStep false))
      ((none) (ReplyWaste :prose total :total total :noStep true))))

fn firstFormIndex s: String -> Option Int64
  (findForm s 0 (stringLength s))

fn findForm s: String i: Int64 n: Int64 -> Option Int64
  (if (>= i n)
    (none)
    (let [(c (stringSlice s i 1))]
      (match c
        ((some " ") (findForm s (+ i 1) n))
        ((some "\t") (findForm s (+ i 1) n))
        ((some "\n") (findForm s (+ i 1) n))
        ((some "\r") (findForm s (+ i 1) n))
        ((some "(") (if (isFormStart s i) (some i) (none)))
        (_ (none)))))

fn isFormStart s: String i: Int64 -> Bool
  (match (stringSlice s i 2)
    ((some "(:") true)
    (_ false))
