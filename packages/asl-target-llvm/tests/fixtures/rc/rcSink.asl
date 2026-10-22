(module rcSink
  :x [main]
  :i [])

enum Dict (dleaf) (dnode left: Dict key: Int64 name: String right: Dict)

fn insert t: Dict k: Int64 s: String -> Dict
  (match t
    ((dleaf) (dnode (dleaf) k s (dleaf)))
    ((dnode l v n r) (cond ((< k v) (dnode (insert l k s) v n r))
                           ((> k v) (dnode l v n (insert r k s)))
                           (else (dnode l v s r)))))

fn lookup t: Dict k: Int64 -> (Option String)
  (match t
    ((dleaf) none)
    ((dnode l v n r) (cond ((= k v) (some n)) ((< k v) (lookup l k)) (else (lookup r k)))))

fn build i: Int64 n: Int64 t: Dict -> Dict
  (if (>= i n) t (build (+ i 1) n (insert t (mod (* i 7919) 1009) (str "n" i))))

fn hits t: Dict i: Int64 acc: Int64 -> Int64
  (if (= i 0) acc (hits t (- i 1) (match (lookup t i) ((some s) (+ acc (stringLength s))) ((none) acc))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(t (build 0 600 (dleaf)))]
    (do (println (str (hits t 1009 0)))
        (ok 0)))
