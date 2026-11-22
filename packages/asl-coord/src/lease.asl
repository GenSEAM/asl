(module asl-coord/lease
  :x [Lease q leaseContent parseLease parseOwns quotedField atomField]
  :i [])

; (:m :ref VS-COORD :do "a lease is the value of one claims row; at is epoch ms of the last heartbeat and ttl is seconds, so a lease is expired when now > at + ttl*1000 by the caller-supplied now")
(schema Lease (:f unit String) (:f owns (List String)) (:f branch String) (:f worktree String)
  (:f agent String) (:f host String) (:f pid Int64) (:f at Int64) (:f ttl Int64))

fn q s: String -> String
  (let [(a (stringReplace s "\\" "\\\\"))
        (b (stringReplace a "\"" "\\\""))]
    (str "\"" (stringReplace b "\n" "\\n") "\""))


fn skipSpaces text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (isSpaceChar (charAt text i)))
    (skipSpaces text (+ i 1))
    i)

fn charAt text: String i: Int64 -> String
  (optionOr (stringSlice text i (+ i 1)) "")

fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn quoteTail text: String i: Int64 -> (Pair String Int64)
  (let [(n (stringLength text))]
    (if (>= i n)
      (pair "" n)
      (let [(c (charAt text i))]
        (cond
          ((= c "\\")
            (if (>= (+ i 1) n) (pair "" n)
              (let [(next (charAt text (+ i 1)))
                    (value (cond ((= next "n") "\n") ((= next "r") "\r") ((= next "t") "\t") (else next)))
                    (tail (quoteTail text (+ i 2)))]
                (pair (str value (pairFirst tail)) (pairSecond tail)))))
          ((= c "\"") (pair "" (+ i 1)))
          (else (let [(tail (quoteTail text (+ i 1)))]
                  (pair (str c (pairFirst tail)) (pairSecond tail))))))))

fn fieldStart text: String key: String -> Int64
  (let [(found (stringIndexOf text (str ":" key)))]
    (match found ((some i) (skipSpaces text (+ i (stringLength key) 1))) ((none) (stringLength text))))

fn quotedField text: String key: String -> String
  (let [(i (fieldStart text key))]
    (if (and (< i (stringLength text)) (= (charAt text i) "\""))
      (pairFirst (quoteTail text (+ i 1)))
      ""))

fn atomEnd text: String i: Int64 -> Int64
  (if (or (>= i (stringLength text)) (isSpaceChar (charAt text i)) (= (charAt text i) ")"))
    i
    (atomEnd text (+ i 1)))

fn atomField text: String key: String -> String
  (let [(i (fieldStart text key))
        (start (if (and (< i (stringLength text)) (= (charAt text i) "\"")) (pairSecond (quoteTail text (+ i 1))) i))
        (end (atomEnd text start))]
    (optionOr (stringSlice text start end) ""))

fn quotedItems text: String i: Int64 acc: (List String) -> (List String)
  (let [(j (skipSpaces text i))]
    (cond
      ((>= j (stringLength text)) (listReverse acc))
      ((= (charAt text j) ")") (listReverse acc))
      ((= (charAt text j) "\"")
        (let [(item (quoteTail text (+ j 1)))]
          (quotedItems text (pairSecond item) (cons (pairFirst item) acc))))
      (else (quotedItems text (+ j 1) acc))))

fn parseOwns raw: String -> (List String)
  (let [(i (fieldStart raw "owns"))]
    (cond
      ((and (< i (stringLength raw)) (= (charAt raw i) "(")) (quotedItems raw (+ i 1) (list)))
      ((stringStartsWith? raw "(") (quotedItems raw 1 (list)))
      (else (list))))

fn parseNumber text: String key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (atomField text key)) fallback)

fn leaseContent lease: Lease -> String
  (str "(:lease :unit " (q lease.unit)
       " :owns (" (stringJoin (map q lease.owns) " ") ")"
       " :branch " (q lease.branch) " :worktree " (q lease.worktree)
       " :agent " (q lease.agent) " :host " (q lease.host)
       " :pid " (stringFromInt64 lease.pid) " :at " (stringFromInt64 lease.at)
       " :ttl " (stringFromInt64 lease.ttl) ")\n")

fn parseLease raw: String -> Lease
  (Lease :unit (quotedField raw "unit") :owns (parseOwns raw)
         :branch (quotedField raw "branch") :worktree (quotedField raw "worktree")
         :agent (quotedField raw "agent") :host (quotedField raw "host")
         :pid (parseNumber raw "pid" 0) :at (parseNumber raw "at" 0) :ttl (parseNumber raw "ttl" 7200))

