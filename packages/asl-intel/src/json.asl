(module asl-intel/json
  :x [Json jNull jBool jInt jFloat jStr jArr jObj jStrs dumps jsonString]
  :i [(asl-intel/text :a t)])

enum Json
  (jNull)
  (jBool v: Bool)
  (jInt v: Int64)
  (jFloat v: Float)
  (jStr v: String)
  (jArr xs: (List Json))
  (jObj kvs: (List (Pair String Json)))

fn jStrs xs: (List String) -> Json
  (jArr (map (fn [(x String)] -> Json (jStr x)) xs))

fn hex4 v: Int64 -> String
  (let [(d "0123456789abcdef")]
    (str (t/sliceStr d (mod (/ v 4096) 16) (+ (mod (/ v 4096) 16) 1))
         (t/sliceStr d (mod (/ v 256) 16) (+ (mod (/ v 256) 16) 1))
         (t/sliceStr d (mod (/ v 16) 16) (+ (mod (/ v 16) 16) 1))
         (t/sliceStr d (mod v 16) (+ (mod v 16) 1))))

fn escCp cp: Int64 -> String
  (cond
    ((= cp 34) "\\\"")
    ((= cp 92) "\\\\")
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((= cp 9) "\\t")
    ((= cp 8) "\\b")
    ((= cp 12) "\\f")
    ((and (>= cp 32) (<= cp 126)) "")
    ((> cp 65535)
      (let [(v (- cp 65536))]
        (str "\\u" (hex4 (+ 55296 (/ v 1024))) "\\u" (hex4 (+ 56320 (mod v 1024))))))
    (else (str "\\u" (hex4 cp))))

fn jsonString s: String -> String
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (str "\"" (escLoop s b n 0 0 (list)) "\""))

fn escLoop s: String b: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> String
  (if (>= i n)
    (t/concatAll (listReverse (cons (t/sliceStr s start n) acc)))
    (let [(k (t/utf8Len (bytesGet b i))) (e (escCp (t/cpAt b n i)))]
      (if (stringEmpty? e)
        (escLoop s b n (+ i k) start acc)
        (escLoop s b n (+ i k) (+ i k) (cons e (cons (t/sliceStr s start i) acc))))))

fn emit v: Json level: Int64 acc: (List String) -> (List String)
  (mt v
    ((jNull) (cons "null" acc))
    ((jBool x) (cons (if x "true" "false") acc))
    ((jInt x) (cons (t/intStr x) acc))
    ((jFloat x) (cons (t/floatStr x) acc))
    ((jStr x) (cons (jsonString x) acc))
    ((jArr xs)
      (if (listEmpty? xs) (cons "[]" acc)
        (let [(inner (stringRepeat "  " (+ level 1)))
              (body (fold (fn [(a (List String)) (p (Pair Int64 Json))] -> (List String)
                            (emit (pairSecond p) (+ level 1) (cons inner (if (= (pairFirst p) 0) a (cons ",\n" a)))))
                          (cons "[\n" acc) (enumerate xs)))]
          (cons "]" (cons (stringRepeat "  " level) (cons "\n" body))))))
    ((jObj kvs)
      (if (listEmpty? kvs) (cons "{}" acc)
        (let [(inner (stringRepeat "  " (+ level 1)))
              (body (fold (fn [(a (List String)) (p (Pair Int64 (Pair String Json)))] -> (List String)
                            (let [(kv (pairSecond p))]
                              (emit (pairSecond kv) (+ level 1)
                                (cons ": " (cons (jsonString (pairFirst kv)) (cons inner (if (= (pairFirst p) 0) a (cons ",\n" a))))))))
                          (cons "{\n" acc) (enumerate kvs)))]
          (cons "}" (cons (stringRepeat "  " level) (cons "\n" body)))))))

fn dumps v: Json -> String
  (t/concatAll (listReverse (emit v 0 (list))))
