(module prelude
  :x []
  :i [])

enum Pair
  (pair first: A second: B)

enum IoError
  (notFound)
  (permissionDenied)
  (alreadyExists)
  (invalidPath)
  (interrupted)
  (other)

enum PreludeMap
  (preludeMapOf size: Int64 root: (PreludeTree K V))

enum PreludeTree
  (preludeLeaf)
  (preludeNode key: K value: V rank: Int64 left: (PreludeTree K V) right: (PreludeTree K V))

fn preludeTrap message: String -> T
  (mt message)

fn preludeIsFloat x: N -> Bool
  (let [s (str x)]
    (or (stringContains? s ".") (or (stringContains? s "e") (stringContains? s "n"))))

fn preludeHead xs: (List T) -> T
  (mt (listHead xs) ((some x) x))

fn preludeTail xs: (List T) -> (List T)
  (mt (listTail xs) ((some t) t))

fn preludeSlice s: String i: Int64 j: Int64 -> String
  (mt (stringSlice s i j) ((some t) t))

fn preludeLess a: T b: T -> Bool
  (cond
    ((!= a a) false)
    ((!= b b) true)
    (else (< a b)))

fn checkedDiv a: N b: N -> (Option N)
  (if (preludeIsFloat b)
    (if (= b 0.0) none (some (/ a b)))
    (cond
      ((= b 0) none)
      ((and (= b -1) (= a -9223372036854775808)) none)
      (else (some (/ a b)))))

fn checkedMod a: N b: N -> (Option N)
  (if (preludeIsFloat b)
    (if (= b 0.0) none (some (mod a b)))
    (if (= b 0) none (some (mod a b))))

fn floatNan -> Float64
  (/ 0.0 0.0)

fn floatInf -> Float64
  (/ 1.0 0.0)

fn floatNegInf -> Float64
  (/ -1.0 0.0)

fn int32ToInt64 x: Int32 -> Int64
  (+ x 0)

fn int64ToInt32 x: Int64 -> (Option Int32)
  (if (and (>= x -2147483648) (<= x 2147483647)) (some x) none)

fn some? o: (Option T) -> Bool
  (mt o ((some _) true) (none false))

fn none? o: (Option T) -> Bool
  (mt o ((some _) false) (none true))

fn ok? r: (Result T E) -> Bool
  (mt r ((ok _) true) ((err _) false))

fn err? r: (Result T E) -> Bool
  (mt r ((ok _) false) ((err _) true))

fn optionOr o: (Option T) fallback: T -> T
  (mt o ((some x) x) (none fallback))

fn optionMap f: (fn [A] -> B) o: (Option A) -> (Option B)
  (mt o ((some x) (some (f x))) (none none))

fn resultMapErr f: (fn [E] -> F) r: (Result T E) -> (Result T F)
  (mt r ((ok x) (ok x)) ((err e) (err (f e))))

fn resultOr r: (Result T E) fallback: T -> T
  (mt r ((ok x) x) ((err _) fallback))

fn resultMap r: (Result A E) f: (fn [A] -> B) -> (Result B E)
  (mt r ((ok x) (ok (f x))) ((err e) (err e)))

fn optionToResult o: (Option T) e: E -> (Result T E)
  (mt o ((some x) (ok x)) (none (err e)))

fn resultToOption r: (Result T E) -> (Option T)
  (mt r ((ok x) (some x)) ((err _) none))

fn preludeLengthFrom xs: (List T) n: Int64 -> Int64
  (mt (listTail xs) ((some t) (preludeLengthFrom t (+ n 1))) (none n))

fn listLength xs: (List T) -> Int64
  (preludeLengthFrom xs 0)

fn preludeReverseOnto xs: (List T) acc: (List T) -> (List T)
  (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) (preludeReverseOnto t (cons x acc))))) (none acc))

fn listReverse xs: (List T) -> (List T)
  (preludeReverseOnto xs (list))

fn preludeRangeDown lo: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (if (< i lo) acc (preludeRangeDown lo (- i 1) (cons i acc)))

fn range lo: Int64 hi: Int64 -> (List Int64)
  (preludeRangeDown lo (- hi 1) (list))

fn preludeMapOnto f: (fn [A] -> B) xs: (List A) acc: (List B) -> (List B)
  (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) (preludeMapOnto f t (cons (f x) acc))))) (none (listReverse acc)))

fn map f: (fn [A] -> B) xs: (List A) -> (List B)
  (preludeMapOnto f xs (list))

fn preludeFilterOnto f: (fn [T] -> Bool) xs: (List T) acc: (List T) -> (List T)
  (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) (preludeFilterOnto f t (if (f x) (cons x acc) acc))))) (none (listReverse acc)))

fn filter f: (fn [T] -> Bool) xs: (List T) -> (List T)
  (preludeFilterOnto f xs (list))

fn fold f: (fn [B A] -> B) init: B xs: (List A) -> B
  (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) (fold f (f init x) t)))) (none init))

fn preludeRevOnto xs: (List T) acc: (List T) -> (List T)
  (preludeReverseOnto xs acc)

fn preludeAppendSpan -> Int64
  2048

fn preludeDropSpan xs: (List T) n: Int64 -> (List T)
  (if (= n 0) xs
    (mt (listTail xs) ((some t) (preludeDropSpan t (- n 1))) (none xs)))

fn preludeChunkStarts xs: (List T) acc: (List (List T)) -> (List (List T))
  (if (listEmpty? xs) acc
    (preludeChunkStarts (preludeDropSpan xs (preludeAppendSpan)) (cons xs acc)))

fn preludeAppendBounded xs: (List T) n: Int64 rest: (List T) -> (List T)
  (if (= n 0) rest
    (mt (listHead xs)
      ((some x) (cons x (preludeAppendBounded (preludeTail xs) (- n 1) rest)))
      (none rest)))

fn preludeAppendChunks chunks: (List (List T)) rest: (List T) -> (List T)
  (mt (listHead chunks)
    ((some c) (preludeAppendChunks (preludeTail chunks) (preludeAppendBounded c (preludeAppendSpan) rest)))
    (none rest))

fn listAppend a: (List T) b: (List T) -> (List T)
  (preludeAppendChunks (preludeChunkStarts a (list)) b)

fn preludeGetLoop xs: (List T) i: Int64 -> (Option T)
  (cond
    ((listEmpty? xs) none)
    ((= i 0) (some (preludeHead xs)))
    (else (preludeGetLoop (preludeTail xs) (- i 1))))

fn listGet xs: (List T) i: Int64 -> (Option T)
  (if (< i 0) none (preludeGetLoop xs i))

fn preludeDrop xs: (List T) n: Int64 -> (List T)
  (if (= n 0) xs (preludeDrop (preludeTail xs) (- n 1)))

fn preludeTake xs: (List T) n: Int64 acc: (List T) -> (List T)
  (if (= n 0) (listReverse acc) (preludeTake (preludeTail xs) (- n 1) (cons (preludeHead xs) acc)))

fn listSlice xs: (List T) s: Int64 e: Int64 -> (Option (List T))
  (if (or (< s 0) (or (< e s) (> e (listLength xs))))
    none
    (some (preludeTake (preludeDrop xs s) (- e s) (list))))

fn preludeIndexLoop xs: (List T) x: T i: Int64 -> (Option Int64)
  (cond
    ((listEmpty? xs) none)
    ((= (preludeHead xs) x) (some i))
    (else (preludeIndexLoop (preludeTail xs) x (+ i 1))))

fn listIndexOf xs: (List T) x: T -> (Option Int64)
  (preludeIndexLoop xs x 0)

fn listContains? xs: (List T) x: T -> Bool
  (some? (preludeIndexLoop xs x 0))

fn preludeZip a: (List A) b: (List B) acc: (List (Pair A B)) -> (List (Pair A B))
  (if (or (listEmpty? a) (listEmpty? b))
    (listReverse acc)
    (preludeZip (preludeTail a) (preludeTail b) (cons (pair (preludeHead a) (preludeHead b)) acc)))

fn zip a: (List A) b: (List B) -> (List (Pair A B))
  (preludeZip a b (list))

fn listSum xs: (List N) -> N
  (if (listEmpty? xs) 0 (fold (fn [acc x] (+ acc x)) (preludeHead xs) (preludeTail xs)))

fn listMin xs: (List T) -> (Option T)
  (if (listEmpty? xs) none
    (some (fold (fn [m x] (if (preludeLess x m) x m)) (preludeHead xs) (preludeTail xs))))

fn listMax xs: (List T) -> (Option T)
  (if (listEmpty? xs) none
    (some (fold (fn [m x] (if (preludeLess m x) x m)) (preludeHead xs) (preludeTail xs))))

fn preludeMerge less: (fn [T T] -> Bool) a: (List T) b: (List T) acc: (List T) -> (List T)
  (cond
    ((listEmpty? a) (preludeRevOnto acc b))
    ((listEmpty? b) (preludeRevOnto acc a))
    ((less (preludeHead b) (preludeHead a)) (preludeMerge less a (preludeTail b) (cons (preludeHead b) acc)))
    (else (preludeMerge less (preludeTail a) b (cons (preludeHead a) acc))))

fn preludeSort less: (fn [T T] -> Bool) xs: (List T) n: Int64 -> (List T)
  (if (< n 2) xs
    (let [h (/ n 2)]
      (preludeMerge less
        (preludeSort less (preludeTake xs h (list)) h)
        (preludeSort less (preludeDrop xs h) (- n h))
        (list))))

fn listSort xs: (List T) -> (List T)
  (preludeSort preludeLess xs (listLength xs))

fn listSortBy f: (fn [T] -> K) xs: (List T) -> (List T)
  (map (fn [p] (mt p ((pair _ x) x)))
    (preludeSort (fn [p q] (mt p ((pair a _) (mt q ((pair b _) (preludeLess a b))))))
      (map (fn [x] (pair (f x) x)) xs)
      (listLength xs)))

fn stringEmpty? s: String -> Bool
  (= (stringLength s) 0)

fn stringEndsWith? s: String suffix: String -> Bool
  (let [n (stringLength s) k (stringLength suffix)]
    (if (> k n) false (= (preludeSlice s (- n k) n) suffix)))

fn preludeBytesEq sb: Bytes tb: Bytes i: Int64 j: Int64 k: Int64 -> Bool
  (if (= j k) true
    (if (= (bytesGet sb (+ i j)) (bytesGet tb j)) (preludeBytesEq sb tb i (+ j 1) k) false))

fn preludeFindBytes sb: Bytes tb: Bytes i: Int64 last: Int64 k: Int64 -> (Option Int64)
  (cond
    ((> i last) none)
    ((preludeBytesEq sb tb i 0 k) (some i))
    (else (preludeFindBytes sb tb (+ i 1) last k)))

fn preludeFind s: String t: String i: Int64 last: Int64 -> (Option Int64)
  (preludeFindBytes (stringToBytes s) (stringToBytes t) i last (stringLength t))

fn stringIndexOf s: String t: String -> (Option Int64)
  (preludeFind s t 0 (- (stringLength s) (stringLength t)))

fn preludeSplitBytes s: String sb: Bytes sepb: Bytes k: Int64 start: Int64 i: Int64 acc: (List String) -> (List String)
  (let [n (bytesLength sb)]
    (cond
      ((> (+ i k) n) (listReverse (cons (preludeSlice s start n) acc)))
      ((preludeBytesEq sb sepb i 0 k) (preludeSplitBytes s sb sepb k (+ i k) (+ i k) (cons (preludeSlice s start i) acc)))
      (else (preludeSplitBytes s sb sepb k start (+ i 1) acc))))

fn preludeSplit s: String sep: String start: Int64 i: Int64 acc: (List String) -> (List String)
  (preludeSplitBytes s (stringToBytes s) (stringToBytes sep) (stringLength sep) start i acc)

fn stringSplit s: String sep: String -> (List String)
  (if (= (stringLength sep) 0)
    (preludeTrap "stringSplit: empty separator")
    (preludeSplit s sep 0 0 (list)))

fn preludeJoinShort xs: (List String) sep: String -> String
  (fold (fn [(acc String) (x String)] -> String (stringConcat (stringConcat acc sep) x)) (preludeHead xs) (preludeTail xs))

fn preludeJoinRun xs: (List String) sep: String acc: (List String) -> (List String)
  (mt (listHead xs)
    (none acc)
    ((some x0)
      (let [r1 (preludeTail xs)]
      (mt (listHead r1)
        (none (cons (preludeJoinShort xs sep) acc))
        ((some x1)
          (let [r2 (preludeTail r1)]
          (mt (listHead r2)
            (none (cons (preludeJoinShort xs sep) acc))
            ((some x2)
              (let [r3 (preludeTail r2)]
              (mt (listHead r3)
                (none (cons (preludeJoinShort xs sep) acc))
                ((some x3)
                  (let [r4 (preludeTail r3)]
                  (mt (listHead r4)
                    (none (cons (preludeJoinShort xs sep) acc))
                    ((some x4)
                      (let [r5 (preludeTail r4)]
                      (mt (listHead r5)
                        (none (cons (preludeJoinShort xs sep) acc))
                        ((some x5)
                          (let [r6 (preludeTail r5)]
                          (mt (listHead r6)
                            (none (cons (preludeJoinShort xs sep) acc))
                            ((some x6)
                              (let [r7 (preludeTail r6)]
                              (mt (listHead r7)
                                (none (cons (preludeJoinShort xs sep) acc))
                                ((some x7)
                                  (let [r8 (preludeTail r7)]
                                  (mt (listHead r8)
                                    (none (cons (preludeJoinShort xs sep) acc))
                                    ((some x8)
                                      (let [r9 (preludeTail r8)]
                                      (mt (listHead r9)
                                        (none (cons (preludeJoinShort xs sep) acc))
                                        ((some x9)
                                          (let [r10 (preludeTail r9)]
                                          (mt (listHead r10)
                                            (none (cons (preludeJoinShort xs sep) acc))
                                            ((some x10)
                                              (let [r11 (preludeTail r10)]
                                              (mt (listHead r11)
                                                (none (cons (preludeJoinShort xs sep) acc))
                                                ((some x11)
                                                  (let [r12 (preludeTail r11)]
                                                  (mt (listHead r12)
                                                    (none (cons (preludeJoinShort xs sep) acc))
                                                    ((some x12)
                                                      (let [r13 (preludeTail r12)]
                                                      (mt (listHead r13)
                                                        (none (cons (preludeJoinShort xs sep) acc))
                                                        ((some x13)
                                                          (let [r14 (preludeTail r13)]
                                                          (mt (listHead r14)
                                                            (none (cons (preludeJoinShort xs sep) acc))
                                                            ((some x14)
                                                              (let [r15 (preludeTail r14)]
                                                              (mt (listHead r15)
                                                                (none (cons (preludeJoinShort xs sep) acc))
                                                                ((some x15)
                                                                  (preludeJoinRun (preludeTail r15) sep
                                                                    (cons (stringConcat (stringConcat (stringConcat (stringConcat (stringConcat x0 sep) (stringConcat x1 sep)) (stringConcat (stringConcat x2 sep) (stringConcat x3 sep))) (stringConcat (stringConcat (stringConcat x4 sep) (stringConcat x5 sep)) (stringConcat (stringConcat x6 sep) (stringConcat x7 sep)))) (stringConcat (stringConcat (stringConcat (stringConcat x8 sep) (stringConcat x9 sep)) (stringConcat (stringConcat x10 sep) (stringConcat x11 sep))) (stringConcat (stringConcat (stringConcat x12 sep) (stringConcat x13 sep)) (stringConcat (stringConcat x14 sep) x15)))) acc)))))))))))))))))))))))))))))))))))))))))))))))))

fn preludeJoinAll xs: (List String) sep: String -> String
  (mt (listHead xs)
    (none "")
    ((some a) (if (listEmpty? (preludeTail xs)) a (preludeJoinAll (listReverse (preludeJoinRun xs sep (list))) sep))))

fn stringJoin xs: (List String) sep: String -> String
  (preludeJoinAll xs sep)

fn stringReplace s: String old: String new: String -> String
  (if (= (stringLength old) 0)
    (preludeTrap "stringReplace: empty search string")
    (stringJoin (preludeSplit s old 0 0 (list)) new))

fn preludeIsSpace c: String -> Bool
  (stringContains? " \t\n\r" c)

fn preludeTrimStart s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (preludeIsSpace (preludeSlice s i (+ i 1)))) (preludeTrimStart s (+ i 1)) i)

fn preludeTrimEnd s: String j: Int64 lo: Int64 -> Int64
  (if (and (> j lo) (preludeIsSpace (preludeSlice s (- j 1) j))) (preludeTrimEnd s (- j 1) lo) j)

fn stringTrim s: String -> String
  (let [i (preludeTrimStart s 0)]
    (preludeSlice s i (preludeTrimEnd s (stringLength s) i)))

fn preludeIsContinuation b: String -> Bool
  (and (>= b (preludeSlice "À" 1 2)) (<= b (preludeSlice "¿" 1 2)))

fn preludeCharEnd s: String j: Int64 -> Int64
  (if (and (< j (stringLength s)) (preludeIsContinuation (preludeSlice s j (+ j 1)))) (preludeCharEnd s (+ j 1)) j)

fn preludeChars s: String i: Int64 acc: (List String) -> (List String)
  (if (>= i (stringLength s)) (listReverse acc)
    (let [j (preludeCharEnd s (+ i 1))]
      (preludeChars s j (cons (preludeSlice s i j) acc))))

fn stringChars s: String -> (List String)
  (preludeChars s 0 (list))

fn stringReverse s: String -> String
  (stringJoin (listReverse (stringChars s)) "")

fn preludeMapCaseChar c: String from: String to: String -> String
  (mt (stringIndexOf from c) ((some i) (preludeSlice to i (+ i 1))) (none c))

fn preludeMapCase s: String from: String to: String -> String
  (stringJoin (map (fn [(c String)] -> String (preludeMapCaseChar c from to)) (stringChars s)) "")

fn stringUpper s: String -> String
  (preludeMapCase s "abcdefghijklmnopqrstuvwxyz" "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

fn stringLower s: String -> String
  (preludeMapCase s "ABCDEFGHIJKLMNOPQRSTUVWXYZ" "abcdefghijklmnopqrstuvwxyz")

fn preludeDigits s: String i: Int64 acc: Int64 -> (Option Int64)
  (if (>= i (stringLength s)) (some acc)
    (mt (stringIndexOf "0123456789" (preludeSlice s i (+ i 1)))
      ((some d)
        (if (or (< acc -922337203685477580) (and (= acc -922337203685477580) (> d 8)))
          none
          (preludeDigits s (+ i 1) (- (* acc 10) d))))
      (none none)))

fn stringToInt64 s: String -> (Option Int64)
  (let [n (stringLength s)
        sign (if (> n 0) (preludeSlice s 0 1) "")
        start (if (or (= sign "-") (= sign "+")) 1 0)]
    (if (>= start n) none
      (mt (preludeDigits s start 0)
        ((some v)
          (cond
            ((= sign "-") (some v))
            ((= v -9223372036854775808) none)
            (else (some (- v)))))
        (none none))))

fn preludeRankPow5 t: Int64 -> Int64
  (let [t2 (mod (* t t) 2147483647)
        t4 (mod (* t2 t2) 2147483647)]
    (mod (* t4 t) 2147483647))

fn preludeRankLane h: Int64 m: Int64 c: Int64 x: Int64 -> Int64
  (preludeRankPow5 (mod (+ (* h m) (+ x c)) 2147483647))

fn preludeRankNegZero bs: Bytes j: Int64 n: Int64 -> Bool
  (if (> (+ j 3) n) false
    (and (= (bytesGet bs j) 48)
      (and (= (bytesGet bs (+ j 1)) 46)
        (and (= (bytesGet bs (+ j 2)) 48)
          (or (= (+ j 3) n)
            (let [d (bytesGet bs (+ j 3))] (or (< d 48) (> d 57))))))))

fn preludeRankStep bs: Bytes i: Int64 n: Int64 q: Int64 a: Int64 b: Int64 -> Int64
  (if (>= i n) (+ (* a 2147483648) b)
    (let [x (bytesGet bs i)]
      (if (and (= q 0) (and (= x 45) (preludeRankNegZero bs (+ i 1) n)))
        (preludeRankStep bs (+ i 1) n q a b)
        (preludeRankStep bs (+ i 1) n
          (cond ((= q 2) 1) ((= q 1) (cond ((= x 92) 2) ((= x 34) 0) (else 1))) ((= x 34) 1) (else 0))
          (preludeRankLane a 48271 12345 x)
          (preludeRankLane b 69621 40503 x)))))

fn preludeRank k: K -> Int64
  (let [bs (stringToBytes (str (list k)))]
    (preludeRankStep bs 0 (bytesLength bs) 0 1013904223 1103515245))

fn preludeAbove r1: Int64 k1: K r2: Int64 k2: K -> Bool
  (or (> r1 r2) (and (= r1 r2) (< k1 k2)))

fn preludeTreeInsert t: (PreludeTree K V) k: K v: V -> (PreludeTree K V)
  (mt t
    ((preludeLeaf) (preludeNode k v (preludeRank k) t t))
    ((preludeNode nk nv r l g)
      (if (< k nk)
        (let [l2 (preludeTreeInsert l k v)]
          (mt l2
            ((preludeLeaf) (preludeNode nk nv r l2 g))
            ((preludeNode ck cv cr cl cg)
              (if (preludeAbove cr ck r nk)
                (preludeNode ck cv cr cl (preludeNode nk nv r cg g))
                (preludeNode nk nv r l2 g)))))
        (let [g2 (preludeTreeInsert g k v)]
          (mt g2
            ((preludeLeaf) (preludeNode nk nv r l g2))
            ((preludeNode ck cv cr cl cg)
              (if (preludeAbove cr ck r nk)
                (preludeNode ck cv cr (preludeNode nk nv r l cl) cg)
                (preludeNode nk nv r l g2))))))))

fn preludeTreeReplace t: (PreludeTree K V) k: K v: V -> (PreludeTree K V)
  (mt t
    ((preludeLeaf) t)
    ((preludeNode nk nv r l g)
      (cond
        ((= k nk) (preludeNode k v r l g))
        ((< k nk) (preludeNode nk nv r (preludeTreeReplace l k v) g))
        (else (preludeNode nk nv r l (preludeTreeReplace g k v))))))

fn preludeTreeGet t: (PreludeTree K V) k: K -> (Option V)
  (mt t
    ((preludeLeaf) none)
    ((preludeNode nk nv _ l g)
      (cond
        ((= k nk) (some nv))
        ((< k nk) (preludeTreeGet l k))
        (else (preludeTreeGet g k)))))

fn preludeTreeMerge a: (PreludeTree K V) b: (PreludeTree K V) -> (PreludeTree K V)
  (mt a
    ((preludeLeaf) b)
    ((preludeNode ak av ar al ag)
      (mt b
        ((preludeLeaf) a)
        ((preludeNode bk bv br bl bg)
          (if (preludeAbove ar ak br bk)
            (preludeNode ak av ar al (preludeTreeMerge ag b))
            (preludeNode bk bv br (preludeTreeMerge a bl) bg))))))

fn preludeTreeRemove t: (PreludeTree K V) k: K -> (PreludeTree K V)
  (mt t
    ((preludeLeaf) t)
    ((preludeNode nk nv r l g)
      (cond
        ((= k nk) (preludeTreeMerge l g))
        ((< k nk) (preludeNode nk nv r (preludeTreeRemove l k) g))
        (else (preludeNode nk nv r l (preludeTreeRemove g k))))))

fn preludeTreePairs t: (PreludeTree K V) acc: (List (Pair K V)) -> (List (Pair K V))
  (mt t
    ((preludeLeaf) acc)
    ((preludeNode k v _ l g) (preludeTreePairs l (cons (pair k v) (preludeTreePairs g acc)))))

fn preludeTreeKeys t: (PreludeTree K V) acc: (List K) -> (List K)
  (mt t
    ((preludeLeaf) acc)
    ((preludeNode k _ _ l g) (preludeTreeKeys l (cons k (preludeTreeKeys g acc)))))

fn preludeTreeValues t: (PreludeTree K V) acc: (List V) -> (List V)
  (mt t
    ((preludeLeaf) acc)
    ((preludeNode _ v _ l g) (preludeTreeValues l (cons v (preludeTreeValues g acc)))))

fn preludeTree m: (Map K V) -> (PreludeTree K V)
  (mt m ((preludeMapOf _ t) t))

fn mapEmpty -> (Map K V)
  (preludeMapOf 0 (preludeLeaf))

fn mapGet m: (Map K V) k: K -> (Option V)
  (preludeTreeGet (preludeTree m) k)

fn mapHas? m: (Map K V) k: K -> Bool
  (some? (mapGet m k))

fn mapSize m: (Map K V) -> Int64
  (mt m ((preludeMapOf n _) n))

fn mapSet m: (Map K V) k: K v: V -> (Map K V)
  (mt m
    ((preludeMapOf n t)
      (if (mapHas? m k)
        (preludeMapOf n (preludeTreeReplace t k v))
        (preludeMapOf (+ n 1) (preludeTreeInsert t k v)))))

fn mapRemove m: (Map K V) k: K -> (Map K V)
  (mt m
    ((preludeMapOf n t)
      (if (mapHas? m k) (preludeMapOf (- n 1) (preludeTreeRemove t k)) m)))

fn mapKeys m: (Map K V) -> (List K)
  (preludeTreeKeys (preludeTree m) (list))

fn mapValues m: (Map K V) -> (List V)
  (preludeTreeValues (preludeTree m) (list))

fn mapPairs m: (Map K V) -> (List (Pair K V))
  (preludeTreePairs (preludeTree m) (list))

fn mapFromPairs ps: (List (Pair K V)) -> (Map K V)
  (fold (fn [m p] (mt p ((pair k v) (mapSet m k v)))) (mapEmpty) ps)

fn preludeIoError message: String -> IoError
  (cond
    ((stringStartsWith? message "notFound:") (notFound))
    ((stringStartsWith? message "permissionDenied:") (permissionDenied))
    ((stringStartsWith? message "alreadyExists:") (alreadyExists))
    ((stringStartsWith? message "invalidPath:") (invalidPath))
    ((stringStartsWith? message "interrupted:") (interrupted))
    (else (other)))

fn ! fileRead path: String -> (Result String IoError)
  (mt (fileReadString path) ((ok s) (ok s)) ((err m) (err (preludeIoError m))))

fn ! pathCanonicalize path: String -> (Result String IoError)
  (mt (realPath path) ((ok s) (ok s)) ((err m) (err (preludeIoError m))))

fn isNan? x: Float64 -> Bool
  (!= x x)

fn isFinite? x: Float64 -> Bool
  (and (= x x) (and (!= x (floatInf)) (!= x (floatNegInf))))

fn pairFirst p: (Pair A B) -> A
  (mt p ((pair a _) a))

fn pairSecond p: (Pair A B) -> B
  (mt p ((pair _ b) b))

fn listAll? pred: (fn [T] -> Bool) xs: (List T) -> Bool
  (mt (listTail xs)
    ((some t) (if (not (pred (preludeHead xs))) false (listAll? pred t)))
    ((none) true))

fn listTake xs: (List T) n: Int64 -> (List T)
  (if (<= n 0) (list)
    (mt (listTail xs)
      ((some t) (cons (preludeHead xs) (listTake t (- n 1))))
      ((none) (list))))

fn listDrop xs: (List T) n: Int64 -> (List T)
  (if (<= n 0) xs
    (mt (listTail xs)
      ((some t) (listDrop t (- n 1)))
      ((none) (list))))

fn listAny? pred: (fn [T] -> Bool) xs: (List T) -> Bool
  (mt (listTail xs)
    ((some t) (if (pred (preludeHead xs)) true (listAny? pred t)))
    ((none) false))

fn preludeStringRepeatBuild chunk: String count: Int64 acc: String -> String
  (if (<= count 0) acc
    (let [(nextAcc (if (= (mod count 2) 1) (stringConcat acc chunk) acc))
          (nextCount (optionOr (checkedDiv count 2) 0))]
      (if (<= nextCount 0) nextAcc
        (preludeStringRepeatBuild (stringConcat chunk chunk) nextCount nextAcc))))

fn stringRepeat s: String count: Int64 -> String
  (preludeStringRepeatBuild s count "")

fn ! fileExists? path: String -> Bool
  (ok? (fileStat path))

fn ! fileSize path: String -> (Result Int64 String)
  (mt (fileStat path)
    ((ok st) (ok st.size))
    ((err m) (err m)))

fn preludeUtf8Tail bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (preludeUtf8Tail bs (+ i 1) n (+ (* acc 64) (- (bytesGet bs i) 128))))

fn charCode c: String -> Int64
  (let [bs (stringToBytes c)
        b0 (if (> (bytesLength bs) 0) (bytesGet bs 0) (preludeTrap "charCode: empty string"))]
    (cond
      ((< b0 128) b0)
      ((< b0 192) (preludeTrap "charCode: not UTF-8"))
      ((< b0 224) (preludeUtf8Tail bs 1 2 (- b0 192)))
      ((< b0 240) (preludeUtf8Tail bs 1 3 (- b0 224)))
      (else (preludeUtf8Tail bs 1 4 (- b0 240)))))

fn preludeLow x: Int64 -> Int64
  (if (< x 0) (+ (+ x 9223372036854775807) 1) x)

fn preludeJoin sign: Bool low: Int64 -> Int64
  (if sign (- (- low 9223372036854775807) 1) low)

fn preludeAndBits a: Int64 b: Int64 -> Int64
  (if (and (= a 0) (= b 0)) 0
    (+ (* (preludeAndBits (/ a 2) (/ b 2)) 2) (* (mod a 2) (mod b 2))))

fn preludeOrBits a: Int64 b: Int64 -> Int64
  (if (and (= a 0) (= b 0)) 0
    (+ (* (preludeOrBits (/ a 2) (/ b 2)) 2) (max (mod a 2) (mod b 2))))

fn preludeXorBits a: Int64 b: Int64 -> Int64
  (if (and (= a 0) (= b 0)) 0
    (+ (* (preludeXorBits (/ a 2) (/ b 2)) 2) (mod (+ (mod a 2) (mod b 2)) 2)))

fn & a: Int64 b: Int64 -> Int64
  (preludeJoin (and (< a 0) (< b 0)) (preludeAndBits (preludeLow a) (preludeLow b)))

fn | a: Int64 b: Int64 -> Int64
  (preludeJoin (or (< a 0) (< b 0)) (preludeOrBits (preludeLow a) (preludeLow b)))

fn ^ a: Int64 b: Int64 -> Int64
  (preludeJoin (!= (< a 0) (< b 0)) (preludeXorBits (preludeLow a) (preludeLow b)))

fn ~ a: Int64 -> Int64
  (- -1 a)

fn preludePop x: Int64 -> Int64
  (if (= x 0) 0 (+ (mod x 2) (preludePop (/ x 2))))

fn popcount64 x: Int64 -> Int64
  (+ (if (< x 0) 1 0) (preludePop (preludeLow x)))

fn preludeB64Char i: Int64 -> String
  (preludeSlice "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" i (+ i 1))

fn preludeB64Enc b: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n) (stringJoin (listReverse acc) "")
    (let [k (min 3 (- n i))
          v (+ (* (bytesGet b i) 65536) (+ (* (if (> k 1) (bytesGet b (+ i 1)) 0) 256) (if (> k 2) (bytesGet b (+ i 2)) 0)))
          quad (str (preludeB64Char (/ v 262144)) (preludeB64Char (mod (/ v 4096) 64))
                    (if (> k 1) (preludeB64Char (mod (/ v 64) 64)) "=") (if (> k 2) (preludeB64Char (mod v 64)) "="))]
      (preludeB64Enc b (+ i 3) n (cons quad acc))))

fn bytesToBase64 b: Bytes -> String
  (preludeB64Enc b 0 (bytesLength b) (list))

fn preludeB64At s: String i: Int64 padFrom: Int64 -> (Option Int64)
  (mt (stringIndexOf "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" (preludeSlice s i (+ i 1)))
    ((some v) (some v))
    (none (if (>= i padFrom) (some 0) none)))

fn ! preludeB64Dec s: String out: Bytes g: Int64 groups: Int64 padFrom: Int64 -> (Result Bytes String)
  (if (>= g groups) (ok out)
    (let [i (* g 4) o (* g 3) n (bytesLength out)
          v0 (preludeB64At s i (stringLength s)) v1 (preludeB64At s (+ i 1) (stringLength s))
          v2 (preludeB64At s (+ i 2) padFrom) v3 (preludeB64At s (+ i 3) padFrom)]
      (if (or (none? v0) (or (none? v1) (or (none? v2) (none? v3))))
        (err (str "bytesFromBase64: invalid character in group at " i))
        (let [a (optionOr v0 0) b (optionOr v1 0) c (optionOr v2 0) d (optionOr v3 0)]
          (do
            (bytesSet out o (+ (* a 4) (/ b 16)))
            (if (< (+ o 1) n) (bytesSet out (+ o 1) (+ (* (mod b 16) 16) (/ c 4))) (+ 0 0))
            (if (< (+ o 2) n) (bytesSet out (+ o 2) (+ (* (mod c 4) 64) d)) (+ 0 0))
            (preludeB64Dec s out (+ g 1) groups padFrom))))))

fn ! bytesFromBase64 s: String -> (Result Bytes String)
  (let [n (stringLength s)
        pad (cond ((stringEndsWith? s "==") 2) ((stringEndsWith? s "=") 1) (else 0))]
    (if (!= (mod n 4) 0)
      (err (str "bytesFromBase64: length " n " is not a multiple of 4"))
      (preludeB64Dec s (bytesAlloc (- (* (/ n 4) 3) pad)) 0 (/ n 4) (- n pad))))

fn preludeFnvMul h: Int64 -> Int64
  (let [u (preludeLow h)
        lo (mod u 4294967296)
        hi (+ (/ u 4294967296) (if (< h 0) 2147483648 0))
        a (* lo 435)
        mid (mod (+ (+ (* hi 435) (* lo 256)) (/ a 4294967296)) 4294967296)
        top (if (< mid 2147483648) mid (- mid 4294967296))]
    (+ (* top 4294967296) (mod a 4294967296)))

fn preludeFnvStep bs: Bytes i: Int64 n: Int64 h: Int64 -> Int64
  (if (>= i n) h
    (let [low (mod (preludeLow h) 256)]
      (preludeFnvStep bs (+ i 1) n (preludeFnvMul (+ (- h low) (^ low (bytesGet bs i)))))))

fn fnv1a64 s: String -> Int64
  (let [bs (stringToBytes s)]
    (preludeFnvStep bs 0 (bytesLength bs) -3750763034362895579))

fn stringLines s: String -> (List String)
  (stringSplit s "\n")

fn listLast xs: (List T) -> (Option T)
  (let [n (listLength xs)]
    (if (<= n 0) none
      (listGet xs (- n 1))))

fn stringCountChar s: String ch: String -> Int64
  (listLength (filter (fn [c] (= c ch)) (stringChars s)))

fn enumerate xs: (List T) -> (List (Pair Int64 T))
  (zip (range 0 (listLength xs)) xs)

fn zstdAslCorrupt message: String -> (Result Bytes String)
  (err (str "ERR_ZSTD_CORRUPT: " message))

fn zstdAslUnsupported message: String -> (Result Bytes String)
  (err (str "ERR_ZSTD_UNSUPPORTED: " message))

fn zstdAslByte bs: Bytes i: Int64 -> Int64
  (bytesGet bs i)

fn zstdAslU32 bs: Bytes i: Int64 -> Int64
  (+ (zstdAslByte bs i)
    (+ (* (zstdAslByte bs (+ i 1)) 256)
      (+ (* (zstdAslByte bs (+ i 2)) 65536)
        (* (zstdAslByte bs (+ i 3)) 16777216))))

fn zstdAslUInt bs: Bytes at: Int64 n: Int64 factor: Int64 acc: Int64 -> Int64
  (if (= n 0) acc
    (zstdAslUInt bs (+ at 1) (- n 1) (* factor 256)
      (+ acc (* (zstdAslByte bs at) factor))))

fn zstdAslDictZero bs: Bytes at: Int64 n: Int64 -> Bool
  (if (= n 0) true
    (and (= (zstdAslByte bs at) 0)
      (zstdAslDictZero bs (+ at 1) (- n 1))))

fn zstdAslPow2 n: Int64 -> Int64
  (if (= n 0) 1 (* 2 (zstdAslPow2 (- n 1))))

fn zstdAslExtraFrame bs: Bytes at: Int64 len: Int64 -> Bool
  (and (>= (- len at) 4)
    (let [magic (zstdAslU32 bs at)]
      (or (= magic 4247762216) (= (& magic 4294967280) 407710288))))

fn ! zstdAslSetRaw src: Bytes si: Int64 dst: Bytes di: Int64 n: Int64 -> Bool
  (if (>= n 0)
    (if (= n 0) true
      (do
        (bytesSet dst di (zstdAslByte src si))
        (zstdAslSetRaw src (+ si 1) dst (+ di 1) (- n 1))))
    false)

fn ! zstdAslSetRle dst: Bytes di: Int64 byte: Int64 n: Int64 -> Bool
  (if (>= n 0)
    (if (= n 0) true
      (do
        (bytesSet dst di byte)
        (zstdAslSetRle dst (+ di 1) byte (- n 1))))
    false)

fn ! zstdAslLiteralBlock src: Bytes start: Int64 end: Int64 out: Bytes outAt: Int64 baseOut: Int64 window: Int64 hufState: Bytes seqState: Bytes reps: Bytes countOnly: Bool -> (Result (Pair Int64 Int64) String)
  (if (>= start end) (err "ERR_ZSTD_CORRUPT: literals header truncated")
    (let [head (zstdAslByte src start)
          typ (mod head 4)
          sizeFlag (mod (/ head 4) 4)
          headerSize (if (or (= sizeFlag 0) (= sizeFlag 2)) 1 (if (= sizeFlag 1) 2 3))]
      (if (> (+ start headerSize) end) (err "ERR_ZSTD_CORRUPT: literals header truncated")
        (let [regenerated
                (if (= headerSize 1) (/ head 8)
                  (if (= headerSize 2)
                    (+ (/ head 16) (* (zstdAslByte src (+ start 1)) 16))
                    (+ (/ head 16) (+ (* (zstdAslByte src (+ start 1)) 16)
                      (* (zstdAslByte src (+ start 2)) 4096)))))
              dataAt (+ start headerSize)
              stored (if (= typ 0) regenerated 1)
              seqAt (+ dataAt stored)]
          (cond
            ((> typ 1)
              (let [lit (bytesAlloc 131072)]
                (mt (zstdAslHufLiterals src start end lit 0 head sizeFlag hufState)
                  ((err message) (err message))
                  ((ok step)
                    (mt step
                      ((pair seqAt litCount)
                        (zstdAslSequences src seqAt end lit litCount out outAt baseOut window seqState reps countOnly)))))))
            ((> regenerated 131072) (err "ERR_ZSTD_CORRUPT: literals larger than a block"))
            ((> seqAt end) (if (= typ 0) (err "ERR_ZSTD_CORRUPT: raw literals truncated") (err "ERR_ZSTD_CORRUPT: RLE literals truncated")))
            ((>= seqAt end) (err "ERR_ZSTD_CORRUPT: sequences header truncated"))
            ((> (+ outAt regenerated) (bytesLength out)) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB"))
            (else
              (let [lit (bytesAlloc 131072)]
                (do
                  (if (= typ 0) (zstdAslSetRaw src dataAt lit 0 regenerated)
                    (zstdAslSetRle lit 0 (zstdAslByte src dataAt) regenerated))
                  (zstdAslSequences src seqAt end lit regenerated out outAt baseOut window seqState reps countOnly)))))))))

fn ! zstdAslHufLiterals src: Bytes start: Int64 end: Int64 out: Bytes outAt: Int64 head: Int64 sizeFlag: Int64 hufState: Bytes -> (Result (Pair Int64 Int64) String)
  (let [type (mod head 4)
        hdr (if (< sizeFlag 2) 3 (if (= sizeFlag 2) 4 5))
        width (if (< sizeFlag 2) 10 (if (= sizeFlag 2) 14 18))]
    (if (> (+ start hdr) end) (err "ERR_ZSTD_CORRUPT: literals header truncated")
      (let [value (zstdAslUInt src start hdr 1 0)
            regenerated (mod (/ value 16) (zstdAslPow2 width))
            compressed (mod (/ value (zstdAslPow2 (+ width 4))) (zstdAslPow2 width))
            dataAt (+ start hdr)]
        (cond
          ((> regenerated 131072) (err "ERR_ZSTD_CORRUPT: literals larger than a block"))
          ((> (+ dataAt compressed) end) (err "ERR_ZSTD_CORRUPT: compressed literals truncated"))
          ((> (+ outAt regenerated) (bytesLength out)) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB"))
          ((= type 3)
            (mt (zstdAslHufCached hufState src dataAt compressed out outAt regenerated sizeFlag)
              ((err message) (err message))
              ((ok _) (ok (pair (+ dataAt compressed) regenerated)))))
          (else
            (mt (zstdAslHufRead src dataAt compressed)
              ((err message) (err message))
              ((ok treeState)
                (mt treeState
                  ((pair tableAndLog treeBytes)
                    (mt tableAndLog
                      ((pair table log)
                        (let [streamAt (+ dataAt treeBytes) streamLen (- compressed treeBytes)
                              tableSize (bytesLength table)]
                          (if (> treeBytes compressed) (err "ERR_ZSTD_CORRUPT: Huffman tree description truncated")
                            (do
                              (zstdAslSetRaw table 0 hufState 2 tableSize)
                              (bytesSet hufState 0 1)
                              (bytesSet hufState 1 log)
                              (mt (zstdAslHufCached hufState src streamAt streamLen out outAt regenerated sizeFlag)
                                ((err message) (err message))
                                ((ok _) (ok (pair (+ dataAt compressed) regenerated))))))))))))))))))

fn ! zstdAslHufCached hufState: Bytes src: Bytes at: Int64 len: Int64 out: Bytes outAt: Int64 regenerated: Int64 sizeFlag: Int64 -> (Result Int64 String)
  (if (= (bytesGet hufState 0) 0) (err "ERR_ZSTD_CORRUPT: treeless literals without a previous Huffman table")
    (let [log (bytesGet hufState 1) streams (if (>= sizeFlag 1) 4 1) each (/ (+ regenerated 3) 4)]
      (if (= streams 1)
        (zstdAslHufOne hufState 2 log src at len out outAt regenerated)
        (zstdAslHufFour hufState 2 log src at len out outAt regenerated each))))

fn ! zstdAslHufOne table: Bytes tableAt: Int64 log: Int64 src: Bytes at: Int64 len: Int64 out: Bytes outAt: Int64 regenerated: Int64 -> (Result Int64 String)
  (mt (zstdAslBackwardInit src at len)
    ((err message) (err message))
    ((ok pos) (zstdAslHufStream table tableAt log src at pos out outAt regenerated 0)))

fn ! zstdAslHufFour table: Bytes tableAt: Int64 log: Int64 src: Bytes at: Int64 len: Int64 out: Bytes outAt: Int64 regenerated: Int64 each: Int64 -> (Result Int64 String)
  (if (< len 6) (err "ERR_ZSTD_CORRUPT: Huffman jump table truncated")
    (let [s1 (+ (bytesGet src at) (* (bytesGet src (+ at 1)) 256))
          s2 (+ (bytesGet src (+ at 2)) (* (bytesGet src (+ at 3)) 256))
          s3 (+ (bytesGet src (+ at 4)) (* (bytesGet src (+ at 5)) 256))
          base (+ at 6) s4 (- len (+ 6 (+ s1 (+ s2 s3)) ))]
      (cond
        ((> (+ 6 (+ s1 (+ s2 s3))) len) (err "ERR_ZSTD_CORRUPT: Huffman jump table beyond the literals"))
        ((> (* each 3) regenerated) (err "ERR_ZSTD_CORRUPT: literals too short for four streams"))
        (else
          (mt (zstdAslHufOne table tableAt log src base s1 out outAt each)
            ((err message) (err message))
            ((ok _)
              (mt (zstdAslHufOne table tableAt log src (+ base s1) s2 out (+ outAt each) each)
                ((err message) (err message))
                ((ok _)
                  (mt (zstdAslHufOne table tableAt log src (+ base (+ s1 s2)) s3 out (+ outAt (* each 2)) each)
                    ((err message) (err message))
                    ((ok _)
                      (zstdAslHufOne table tableAt log src (+ base (+ s1 (+ s2 s3))) s4 out (+ outAt (* each 3)) (- regenerated (* each 3)))))))))))))

fn ! zstdAslCountBlocks src: Bytes len: Int64 at: Int64 window: Int64 total: Int64 hufState: Bytes seqState: Bytes reps: Bytes -> (Result (Pair Int64 Int64) String)
  (if (> (+ at 3) len) (err "ERR_ZSTD_CORRUPT: block header truncated")
    (let [bh (+ (zstdAslByte src at)
              (+ (* (zstdAslByte src (+ at 1)) 256)
                (* (zstdAslByte src (+ at 2)) 65536)))
          last (= (mod bh 2) 1)
          typ (mod (/ bh 2) 4)
          size (/ bh 8)
          dataAt (+ at 3)
          blockMax (min window 131072)]
      (cond
        ((> size blockMax) (err "ERR_ZSTD_CORRUPT: block larger than the block maximum"))
        ((= typ 3) (err "ERR_ZSTD_CORRUPT: reserved block type"))
        ((= typ 0)
          (if (> (+ dataAt size) len) (err "ERR_ZSTD_CORRUPT: block truncated")
            (zstdAslCountBlockDone src len last (+ dataAt size) window total size hufState seqState reps)))
        ((= typ 1)
          (if (>= dataAt len) (err "ERR_ZSTD_CORRUPT: RLE block truncated")
            (zstdAslCountBlockDone src len last (+ dataAt 1) window total size hufState seqState reps)))
        (else
          (if (> (+ dataAt size) len) (err "ERR_ZSTD_CORRUPT: block truncated")
            (mt (zstdAslLiteralBlock src dataAt (+ dataAt size) (bytesAlloc 131072) 0 total window hufState seqState reps true)
              ((err e) (err e))
              ((ok step)
                (mt step
                  ((pair nextAt produced)
                    (zstdAslCountBlockDone src len last nextAt window total produced hufState seqState reps))))))))))

fn ! zstdAslCountBlockDone src: Bytes len: Int64 last: Bool nextAt: Int64 window: Int64 total: Int64 produced: Int64 hufState: Bytes seqState: Bytes reps: Bytes -> (Result (Pair Int64 Int64) String)
  (if (> (+ total produced) 1073741824) (err "ERR_ZSTD_CORRUPT: content size above 1 GiB")
    (if last (ok (pair nextAt (+ total produced)))
      (zstdAslCountBlocks src len nextAt window (+ total produced) hufState seqState reps)))

fn ! zstdAslBlocks src: Bytes len: Int64 at: Int64 out: Bytes outAt: Int64 window: Int64 hufState: Bytes seqState: Bytes reps: Bytes -> (Result Int64 String)
  (if (> (+ at 3) len) (err "ERR_ZSTD_CORRUPT: block header truncated")
    (let [bh (+ (zstdAslByte src at)
              (+ (* (zstdAslByte src (+ at 1)) 256)
                (* (zstdAslByte src (+ at 2)) 65536)))
          last (= (mod bh 2) 1)
          typ (mod (/ bh 2) 4)
          size (/ bh 8)
          blockMax (min window 131072)
          dataAt (+ at 3)
          outLen (bytesLength out)]
      (cond
        ((> size blockMax) (err "ERR_ZSTD_CORRUPT: block larger than the block maximum"))
        ((= typ 3) (err "ERR_ZSTD_CORRUPT: reserved block type"))
        ((= typ 2)
          (if (> (+ dataAt size) len) (err "ERR_ZSTD_CORRUPT: block truncated")
            (mt (zstdAslLiteralBlock src dataAt (+ dataAt size) out outAt outAt window hufState seqState reps false)
              ((err e) (err e))
              ((ok step)
                (mt step
                  ((pair endAt produced)
                    (if last
                    (if (= (+ outAt produced) outLen) (ok endAt)
                        (err "ERR_ZSTD_CORRUPT: decoded size differs from the frame content size"))
                      (zstdAslBlocks src len endAt out (+ outAt produced) window hufState seqState reps))))))))
        ((= typ 0)
          (if (> (+ dataAt size) len) (err "ERR_ZSTD_CORRUPT: block truncated")
            (if (> (+ outAt size) outLen) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB")
              (do
                (zstdAslSetRaw src dataAt out outAt size)
                (if last
                  (if (= (+ outAt size) outLen) (ok (+ dataAt size))
                    (err "ERR_ZSTD_CORRUPT: decoded size differs from the frame content size"))
                  (zstdAslBlocks src len (+ dataAt size) out (+ outAt size) window hufState seqState reps))))))
        (else
          (if (>= dataAt len) (err "ERR_ZSTD_CORRUPT: RLE block truncated")
            (if (> (+ outAt size) outLen) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB")
              (do
                (zstdAslSetRle out outAt (zstdAslByte src dataAt) size)
                (if last
                  (if (= (+ outAt size) outLen) (ok (+ dataAt 1))
                    (err "ERR_ZSTD_CORRUPT: decoded size differs from the frame content size"))
                  (zstdAslBlocks src len (+ dataAt 1) out (+ outAt size) window hufState seqState reps)))))))))

fn ! zstdAslFrame src: Bytes -> (Result Bytes String)
  (let [len (bytesLength src)]
    (if (< len 4) (zstdAslCorrupt "shorter than a frame magic")
      (let [magic (zstdAslU32 src 0)]
        (cond
          ((= (& magic 4294967280) 407710288) (zstdAslUnsupported "skippable frame"))
          ((!= magic 4247762216) (zstdAslCorrupt "bad frame magic"))
          ((< len 5) (zstdAslCorrupt "frame header truncated"))
          (else
            (let [fhd (zstdAslByte src 4)
                  fcsFlag (/ fhd 64)
                  single (= (mod (/ fhd 32) 2) 1)
                  checksum (= (mod (/ fhd 4) 2) 1)
                  dictFlag (mod fhd 4)
                  descriptorAt (if single 5 6)
                  windowDescriptor (if (or single (< len 6)) 0 (zstdAslByte src 5))
                  windowLog (+ 10 (/ windowDescriptor 8))
                  windowBase (zstdAslPow2 windowLog)
                  window (if single 0 (+ windowBase (* (/ windowBase 8) (mod windowDescriptor 8))))
                  dictSize (cond ((= dictFlag 0) 0) ((= dictFlag 1) 1) ((= dictFlag 2) 2) (else 4))
                  fcsSize (cond ((= fcsFlag 0) (if single 1 0)) ((= fcsFlag 1) 2) ((= fcsFlag 2) 4) (else 8))
                  fcsAt (+ descriptorAt dictSize)
                  fcsRaw (if (> (+ fcsAt fcsSize) len) 0
                           (zstdAslUInt src fcsAt (if (= fcsSize 8) 4 fcsSize) 1 0))
                  fcs (if (= fcsSize 2) (+ fcsRaw 256) fcsRaw)]
              (cond
                ((!= (mod (/ fhd 8) 2) 0) (zstdAslCorrupt "reserved frame header bit set"))
                ((and (not single) (< len 6)) (zstdAslCorrupt "window descriptor truncated"))
                ((and (not single) (> windowLog 27)) (zstdAslCorrupt "window larger than 128 MiB"))
                ((> (+ 5 (if single 0 1) dictSize) len) (zstdAslCorrupt "dictionary id truncated"))
                ((and (> dictSize 0) (not (zstdAslDictZero src descriptorAt dictSize))) (zstdAslUnsupported "frame needs a dictionary"))
                ((> (+ fcsAt fcsSize) len) (zstdAslCorrupt "frame content size truncated"))
                ((and (= fcsSize 8) (not (and (= (zstdAslByte src (+ fcsAt 4)) 0)
                  (and (= (zstdAslByte src (+ fcsAt 5)) 0)
                    (and (= (zstdAslByte src (+ fcsAt 6)) 0) (= (zstdAslByte src (+ fcsAt 7)) 0))))))
                  (zstdAslCorrupt "content size above 1 GiB"))
                ((> fcs 1073741824) (zstdAslCorrupt "content size above 1 GiB"))
                (else
                  (let [blockAt (+ fcsAt fcsSize)
                        blockWindow (if single fcs window)
                        countHufState (bytesAlloc 4100)
                        decodeHufState (bytesAlloc 4100)
                        countSeqState (bytesAlloc 5200)
                        decodeSeqState (bytesAlloc 5200)
                        countReps (bytesAlloc 12)
                        decodeReps (bytesAlloc 12)]
                    (do
                    (zstdAslRepSet countReps 0 1) (zstdAslRepSet countReps 1 4) (zstdAslRepSet countReps 2 8)
                    (zstdAslRepSet decodeReps 0 1) (zstdAslRepSet decodeReps 1 4) (zstdAslRepSet decodeReps 2 8)
                    (mt (zstdAslCountBlocks src len blockAt blockWindow 0 countHufState countSeqState countReps)
                      ((err message) (err message))
                      ((ok countPair)
                        (mt countPair
                          ((pair endAt actualSize)
                            (if (and (> fcsSize 0) (> actualSize fcs))
                              (zstdAslCorrupt "output exceeds the frame content size or 1 GiB")
                              (if (and (> fcsSize 0) (!= actualSize fcs))
                                (zstdAslCorrupt "decoded size differs from the frame content size")
                                (let [out (bytesAlloc actualSize)]
                                  (mt (zstdAslBlocks src len blockAt out 0 blockWindow decodeHufState decodeSeqState decodeReps)
                                    ((err message) (err message))
                                    ((ok writtenEnd)
                                      (if (!= endAt writtenEnd)
                                        (zstdAslCorrupt "decoder block passes disagree")
                                        (zstdAslFinishFrame src len endAt checksum out)))))))))))))))))))))

fn zstdAslUnsignedHigh x: Int64 -> Int64
  (+ (/ (preludeLow x) 4294967296) (if (< x 0) 2147483648 0))

fn zstdAslPack64 high: Int64 low: Int64 -> Int64
  (let [signedHigh (if (>= high 2147483648) (- high 4294967296) high)]
    (+ (* signedHigh 4294967296) low))

fn zstdAslAdd64 a: Int64 b: Int64 -> Int64
  (let [alo (mod (preludeLow a) 4294967296) blo (mod (preludeLow b) 4294967296)
        ahi (zstdAslUnsignedHigh a) bhi (zstdAslUnsignedHigh b)
        lowSum (+ alo blo) low (mod lowSum 4294967296)
        high (mod (+ (+ ahi bhi) (/ lowSum 4294967296)) 4294967296)]
    (zstdAslPack64 high low))

fn zstdAslMul64 a: Int64 b: Int64 -> Int64
  (let [alo (preludeLow a) blo (preludeLow b)
        ahi (zstdAslUnsignedHigh a) bhi (zstdAslUnsignedHigh b)
        a0 (mod alo 65536) a1 (mod (/ alo 65536) 65536)
        a2 (mod ahi 65536) a3 (/ ahi 65536)
        b0 (mod blo 65536) b1 (mod (/ blo 65536) 65536)
        b2 (mod bhi 65536) b3 (/ bhi 65536)
        t0 (* a0 b0) d0 (mod t0 65536) c0 (/ t0 65536)
        t1 (+ (+ (* a1 b0) (* a0 b1)) c0) d1 (mod t1 65536) c1 (/ t1 65536)
        t2 (+ (+ (+ (* a2 b0) (* a1 b1)) (* a0 b2)) c1) d2 (mod t2 65536) c2 (/ t2 65536)
        t3 (+ (+ (+ (+ (* a3 b0) (* a2 b1)) (* a1 b2)) (* a0 b3)) c2)
        low (+ d0 (* d1 65536)) high (+ (mod t2 65536) (* (mod t3 65536) 65536))]
    (zstdAslPack64 high low))

fn zstdAslPow64 n: Int64 -> Int64
  (if (= n 63) -9223372036854775808 (zstdAslPow2 n))

fn zstdAslShiftRight64 x: Int64 n: Int64 -> Int64
  (let [low (mod (preludeLow x) 4294967296) high (zstdAslUnsignedHigh x)]
    (if (= n 0) x
      (if (< n 32)
        (zstdAslPack64 (/ high (zstdAslPow2 n))
          (+ (/ low (zstdAslPow2 n)) (* (mod high (zstdAslPow2 n)) (zstdAslPow2 (- 32 n)))))
        (zstdAslPack64 0 (/ high (zstdAslPow2 (- n 32)))))))

fn zstdAslRotateLeft64 x: Int64 n: Int64 -> Int64
  (zstdAslAdd64 (zstdAslMul64 x (zstdAslPow64 n)) (zstdAslShiftRight64 x (- 64 n)))

fn zstdAslRead64 src: Bytes at: Int64 count: Int64 i: Int64 value: Int64 -> Int64
  (if (>= i count) value
    (zstdAslRead64 src at count (+ i 1)
      (zstdAslAdd64 value (zstdAslMul64 (bytesGet src (+ at i)) (zstdAslPow64 (* i 8))))))

fn zstdAslXxhRound acc: Int64 input: Int64 -> Int64
  (zstdAslMul64 (zstdAslRotateLeft64 (zstdAslAdd64 acc (zstdAslMul64 input -4417276706812531889)) 31) -7046029288634856825)

fn zstdAslXxhMerge acc: Int64 value: Int64 -> Int64
  (zstdAslAdd64 (zstdAslMul64 (^ acc (zstdAslXxhRound 0 value)) -7046029288634856825) -8796714831421723037)

fn zstdAslXxhStripe src: Bytes at: Int64 end: Int64 v1: Int64 v2: Int64 v3: Int64 v4: Int64 -> (Pair Int64 (Pair Int64 (Pair Int64 (Pair Int64 Int64))))
  (if (> (+ at 32) end) (pair at (pair v1 (pair v2 (pair v3 v4))))
    (let [a (zstdAslXxhRound v1 (zstdAslRead64 src at 8 0 0))
          b (zstdAslXxhRound v2 (zstdAslRead64 src (+ at 8) 8 0 0))
          c (zstdAslXxhRound v3 (zstdAslRead64 src (+ at 16) 8 0 0))
          d (zstdAslXxhRound v4 (zstdAslRead64 src (+ at 24) 8 0 0))]
      (zstdAslXxhStripe src (+ at 32) end a b c d)))

fn zstdAslXxhHash src: Bytes -> Int64
  (let [n (bytesLength src)
        initial (if (>= n 32)
          (mt (zstdAslXxhStripe src 0 n 6983438078262162902 -4417276706812531889 0 7046029288634856825)
            ((pair at rest1)
              (mt rest1
                ((pair v1 rest2)
                  (mt rest2
                    ((pair v2 rest3)
                      (mt rest3
                        ((pair v3 v4)
                          (let [combined (zstdAslAdd64 (zstdAslAdd64 (zstdAslRotateLeft64 v1 1) (zstdAslRotateLeft64 v2 7)) (zstdAslAdd64 (zstdAslRotateLeft64 v3 12) (zstdAslRotateLeft64 v4 18)))]
                            (pair at (zstdAslXxhMerge (zstdAslXxhMerge (zstdAslXxhMerge (zstdAslXxhMerge combined v1) v2) v3) v4)))))))))))
          (pair 0 2870177450012600261))]
    (mt initial
      ((pair at base)
        (let [h (zstdAslAdd64 base n)]
          (zstdAslXxhTail src at n h)))))

fn zstdAslXxhTail src: Bytes at: Int64 end: Int64 hash: Int64 -> Int64
  (if (> (+ at 8) end)
    (if (> (+ at 4) end)
      (if (>= at end)
        (zstdAslXxhAvalanche hash)
        (zstdAslXxhTailByte src at end hash))
      (zstdAslXxhTailByte src at end hash))
    (let [input (zstdAslRead64 src at 8 0 0)
          next (zstdAslAdd64 (zstdAslMul64 (zstdAslRotateLeft64 (^ hash (zstdAslXxhRound 0 input)) 27) -7046029288634856825) -8796714831421723037)]
      (zstdAslXxhTail src (+ at 8) end next)))

fn zstdAslXxhTailByte src: Bytes at: Int64 end: Int64 hash: Int64 -> Int64
  (if (> (+ at 4) end)
    (if (>= at end) (zstdAslXxhAvalanche hash)
      (let [next (zstdAslMul64 (zstdAslRotateLeft64 (^ hash (zstdAslMul64 (bytesGet src at) 2870177450012600261)) 11) -7046029288634856825)]
        (zstdAslXxhTailByte src (+ at 1) end next)))
      (let [word (+ (bytesGet src at) (+ (* (bytesGet src (+ at 1)) 256) (+ (* (bytesGet src (+ at 2)) 65536) (* (bytesGet src (+ at 3)) 16777216))))
          next (zstdAslAdd64 (zstdAslMul64 (zstdAslRotateLeft64 (^ hash (zstdAslMul64 word -7046029288634856825)) 23) -4417276706812531889) 1609587929392839161)]
      (zstdAslXxhTailByte src (+ at 4) end next)))

fn zstdAslXxhAvalanche hash: Int64 -> Int64
  (let [a (^ hash (zstdAslShiftRight64 hash 33))
        b (^ (zstdAslMul64 a -4417276706812531889) (zstdAslShiftRight64 (zstdAslMul64 a -4417276706812531889) 29))
        c (zstdAslMul64 b 1609587929392839161)]
    (^ c (zstdAslShiftRight64 c 32)))

fn ! zstdAslFinishFrame src: Bytes len: Int64 endAt: Int64 checksum: Bool out: Bytes -> (Result Bytes String)
  (if (and checksum (< (- len endAt) 4)) (err "ERR_ZSTD_CORRUPT: content checksum truncated")
    (let [afterAt (if checksum (+ endAt 4) endAt)
          mismatch (if checksum
            (let [hash (zstdAslXxhHash out)
                  hashLow (mod (if (< hash 0) (preludeLow hash) hash) 4294967296)]
              (!= (zstdAslU32 src endAt) hashLow))
            false)]
      (if mismatch
        (err "ERR_ZSTD_CORRUPT: content checksum mismatch")
        (if (!= afterAt len)
          (if (zstdAslExtraFrame src afterAt len)
            (err "ERR_ZSTD_UNSUPPORTED: more than one frame")
            (err "ERR_ZSTD_CORRUPT: trailing bytes after the frame"))
          (ok out)))))

fn zstdAslHighBit n: Int64 -> Int64
  (if (<= n 0) -1 (+ 1 (zstdAslHighBit (/ n 2))))

fn ! zstdAslForwardBitsLoop src: Bytes at: Int64 bit: Int64 need: Int64 i: Int64 value: Int64 -> (Result (Pair Int64 Int64) String)
  (if (>= i need) (ok (pair value (+ bit need)))
    (let [pos (+ bit i) index (+ at (/ pos 8))]
      (if (>= index (bytesLength src)) (err "ERR_ZSTD_CORRUPT: table description truncated")
        (let [byte (bytesGet src index) bitValue (mod (/ byte (zstdAslPow2 (mod pos 8))) 2)]
          (zstdAslForwardBitsLoop src at bit need (+ i 1) (+ value (* bitValue (zstdAslPow2 i))))))))

fn ! zstdAslForwardBits src: Bytes at: Int64 bit: Int64 need: Int64 -> (Result (Pair Int64 Int64) String)
  (if (or (< need 0) (> need 31)) (err "ERR_ZSTD_CORRUPT: invalid table bit count")
    (zstdAslForwardBitsLoop src at bit need 0 0))

fn zstdAslNormCode norms: Bytes sym: Int64 -> Int64
  (+ (bytesGet norms (* sym 2)) (* (bytesGet norms (+ (* sym 2) 1)) 256))

fn ! zstdAslNormSet norms: Bytes sym: Int64 code: Int64 -> Bool
  (do
    (bytesSet norms (* sym 2) (mod code 256))
    (bytesSet norms (+ (* sym 2) 1) (/ code 256))
    true)

fn ! zstdAslNormInit norms: Bytes sym: Int64 -> Bool
  (if (>= (* sym 2) (bytesLength norms)) true
    (do (zstdAslNormSet norms sym 1) (zstdAslNormInit norms (+ sym 1))))

fn ! zstdAslFseCounts src: Bytes at: Int64 bit: Int64 maxSym: Int64 remaining: Int64 threshold: Int64 nb: Int64 sym: Int64 norms: Bytes -> (Result (Pair Int64 Int64) String)
  (if (<= remaining 1) (if (= remaining 1) (ok (pair bit sym)) (err "ERR_ZSTD_CORRUPT: FSE probabilities do not sum to the table size"))
    (if (> sym maxSym) (err "ERR_ZSTD_CORRUPT: FSE table has too many symbols")
      (let [maximum (- (- (* 2 threshold) 1) remaining)]
        (mt (zstdAslForwardBits src at bit (- nb 1))
          ((err message) (err message))
          ((ok lowState)
            (mt lowState
              ((pair low afterLow)
                (if (< low maximum)
                  (zstdAslFseCountFinish src at afterLow maxSym remaining threshold nb sym norms low)
                  (mt (zstdAslForwardBits src at afterLow 1)
                    ((err message) (err message))
                    ((ok highState)
                      (mt highState
                        ((pair high afterHigh)
                          (let [combined (+ low (* high (zstdAslPow2 (- nb 1))))
                                raw (if (>= combined threshold) (- combined maximum) combined)]
                            (zstdAslFseCountFinish src at afterHigh maxSym remaining threshold nb sym norms raw))))))))))))))

fn ! zstdAslFseZeroRun src: Bytes at: Int64 bit: Int64 maxSym: Int64 sym: Int64 norms: Bytes -> (Result (Pair Int64 Int64) String)
  (mt (zstdAslForwardBits src at bit 2)
    ((err message) (err message))
    ((ok state)
      (mt state
        ((pair rep nextBit)
          (if (> (+ sym rep) (+ maxSym 1)) (err "ERR_ZSTD_CORRUPT: FSE zero run past the alphabet")
            (do
              (zstdAslNormZeroRun norms sym rep)
              (if (= rep 3)
                (mt (zstdAslFseZeroRun src at nextBit maxSym (+ sym rep) norms)
                  ((err message) (err message))
                  ((ok nextState) (ok (pair (pairFirst nextState) (pairSecond nextState)))))
                (ok (pair (+ sym rep) nextBit)))))))))

fn zstdAslFseAdjust remaining: Int64 threshold: Int64 nb: Int64 -> (Pair Int64 Int64)
  (if (and (< remaining threshold) (> nb 1))
    (zstdAslFseAdjust remaining (/ threshold 2) (- nb 1))
    (pair threshold nb))

fn ! zstdAslFseCountFinish src: Bytes at: Int64 bit: Int64 maxSym: Int64 remaining: Int64 threshold: Int64 nb: Int64 sym: Int64 norms: Bytes raw: Int64 -> (Result (Pair Int64 Int64) String)
  (let [count (- raw 1) magnitude (if (< count 0) (- count) count)]
    (if (> magnitude remaining) (err "ERR_ZSTD_CORRUPT: FSE probabilities do not sum to the table size")
      (do
        (zstdAslNormSet norms sym (+ count 1))
        (mt (if (= count 0) (zstdAslFseZeroRun src at bit maxSym (+ sym 1) norms) (ok (pair (+ sym 1) bit)))
          ((err message) (err message))
          ((ok runState)
            (let [nextSym (pairFirst runState) nextBit (pairSecond runState) nextRemaining (- remaining magnitude)
                  adjusted (zstdAslFseAdjust nextRemaining threshold nb)]
              (zstdAslFseCounts src at nextBit maxSym nextRemaining (pairFirst adjusted) (pairSecond adjusted) nextSym norms)))))))

fn ! zstdAslNormZeroRun norms: Bytes sym: Int64 count: Int64 -> Bool
  (if (<= count 0) true
    (do (zstdAslNormSet norms sym 1) (zstdAslNormZeroRun norms (+ sym 1) (- count 1))))

fn ! zstdAslFseInit syms: Bytes next: Bytes norms: Bytes sym: Int64 size: Int64 high: Int64 -> Int64
  (if (>= (* sym 2) (bytesLength norms)) high
    (let [code (zstdAslNormCode norms sym) count (- code 1)]
      (if (= count -1)
        (do (zstdAslHufSet16 next sym 1) (bytesSet syms high sym)
            (zstdAslFseInit syms next norms (+ sym 1) size (- high 1)))
        (do (zstdAslHufSet16 next sym (max 0 count))
            (zstdAslFseInit syms next norms (+ sym 1) size high)))))

fn ! zstdAslFseSpread syms: Bytes norms: Bytes next: Bytes size: Int64 high: Int64 sym: Int64 pos: Int64 -> Int64
  (if (>= (* sym 2) (bytesLength norms)) pos
    (let [count (- (zstdAslNormCode norms sym) 1)]
      (if (<= count 0)
        (zstdAslFseSpread syms norms next size high (+ sym 1) pos)
        (zstdAslFseSpreadOne syms norms next size high sym count 0 pos))))

fn ! zstdAslFseSpreadOne syms: Bytes norms: Bytes next: Bytes size: Int64 high: Int64 sym: Int64 count: Int64 done: Int64 pos: Int64 -> Int64
  (if (>= done count) (zstdAslFseSpread syms norms next size high (+ sym 1) pos)
    (do
      (bytesSet syms pos sym)
      (let [step (+ (+ (/ size 2) (/ size 8)) 3)
            nextPos (mod (+ pos step) size)]
        (zstdAslFseSpreadSkip syms norms next size high sym count (+ done 1) nextPos))))

fn ! zstdAslFseSpreadSkip syms: Bytes norms: Bytes next: Bytes size: Int64 high: Int64 sym: Int64 count: Int64 done: Int64 pos: Int64 -> Int64
  (if (> pos high)
    (zstdAslFseSpreadSkip syms norms next size high sym count done (mod (+ pos (+ (+ (/ size 2) (/ size 8)) 3)) size))
    (zstdAslFseSpreadOne syms norms next size high sym count done pos))

fn ! zstdAslFseBuildCell table: Bytes syms: Bytes next: Bytes size: Int64 log: Int64 idx: Int64 -> Bool
  (if (>= idx size) true
    (let [sym (bytesGet syms idx) x (zstdAslHufGet16 next sym) nb (- log (zstdAslHighBit x))
          base (mod (- (* x (zstdAslPow2 nb)) size) 65536)]
      (do
        (bytesSet table (* idx 4) sym)
        (bytesSet table (+ (* idx 4) 1) nb)
        (bytesSet table (+ (* idx 4) 2) (mod base 256))
        (bytesSet table (+ (* idx 4) 3) (/ base 256))
        (zstdAslHufSet16 next sym (+ x 1))
        (zstdAslFseBuildCell table syms next size log (+ idx 1)))))

fn ! zstdAslFseRead src: Bytes at: Int64 len: Int64 maxSym: Int64 maxLog: Int64 -> (Result (Pair (Pair Bytes Int64) Int64) String)
  (mt (zstdAslForwardBits src at 0 4)
    ((err message) (err message))
    ((ok logState)
      (mt logState
        ((pair logCode afterLog)
          (let [log (+ 5 logCode) size (zstdAslPow2 (+ 5 logCode))]
            (cond
              ((> log maxLog) (err "ERR_ZSTD_CORRUPT: FSE accuracy log too large"))
              ((> (+ at len) (bytesLength src)) (err "ERR_ZSTD_CORRUPT: table description truncated"))
              (else
                (let [norms (bytesAlloc (* (+ maxSym 1) 2))]
                  (do
                    (zstdAslNormInit norms 0)
                    (mt (zstdAslFseCounts src at afterLog maxSym (+ size 1) size (+ log 1) 0 norms)
                      ((err message) (err message))
                      ((ok countState)
                        (let [bitsUsed (pairFirst countState) symbols (pairSecond countState)
                              next (bytesAlloc (* (+ maxSym 1) 2))
                              syms (bytesAlloc size)
                              table (bytesAlloc (* size 4))
                              high (zstdAslFseInit syms next norms 0 size (- size 1))
                              spreadEnd (zstdAslFseSpread syms norms next size high 0 0)]
                          (if (> bitsUsed (* len 8)) (err "ERR_ZSTD_CORRUPT: table description truncated")
                            (if (!= spreadEnd 0) (err "ERR_ZSTD_CORRUPT: FSE table spread does not close")
                            (if (zstdAslFseBuildCell table syms next size log 0)
                              (ok (pair (pair table log) (/ (+ bitsUsed 7) 8)))
                              (err "ERR_ZSTD_CORRUPT: FSE table build failed"))))))))))))))))

fn zstdAslRepeatInt value: Int64 count: Int64 -> (List Int64)
  (if (<= count 0) (list) (cons value (zstdAslRepeatInt value (- count 1))))

fn zstdAslDefaultNorms kind: Int64 -> (List Int64)
  (if (= kind 0)
    (list 4 3 2 2 2 2 2 2 2 2 2 2 2 1 1 1 2 2 2 2 2 2 2 2 2 3 2 1 1 1 1 1 -1 -1 -1 -1)
    (if (= kind 1)
      (list 1 1 1 1 1 1 2 2 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 -1 -1 -1 -1 -1)
      (listAppend (list 1 4 3 2 2 2 2 2 2)
        (listAppend (zstdAslRepeatInt 1 37) (zstdAslRepeatInt -1 7)))))

fn ! zstdAslFillFseNorms values: (List Int64) norms: Bytes i: Int64 -> Bool
  (if (>= (* i 2) (bytesLength norms)) true
    (do
      (zstdAslNormSet norms i (+ (optionOr (listGet values i) 0) 1))
      (zstdAslFillFseNorms values norms (+ i 1))))

fn ! zstdAslFseBuildNorms norms: Bytes symbolCount: Int64 log: Int64 -> (Result (Pair Bytes Int64) String)
  (let [size (zstdAslPow2 log) next (bytesAlloc (* symbolCount 2)) syms (bytesAlloc size) table (bytesAlloc (* size 4))
        high (zstdAslFseInit syms next norms 0 size (- size 1))
        spreadEnd (zstdAslFseSpread syms norms next size high 0 0)]
    (if (!= spreadEnd 0) (err "ERR_ZSTD_CORRUPT: FSE table spread does not close")
      (if (zstdAslFseBuildCell table syms next size log 0)
        (ok (pair table log))
        (err "ERR_ZSTD_CORRUPT: FSE table build failed"))))

fn ! zstdAslSeqTable mode: Int64 src: Bytes at: Int64 len: Int64 defaults: (List Int64) defaultLog: Int64 maxSym: Int64 maxLog: Int64 previous: Bytes previousLog: Int64 previousValid: Bool -> (Result (Pair (Pair Bytes Int64) Int64) String)
  (cond
    ((= mode 0)
      (let [norms (bytesAlloc (* (listLength defaults) 2))]
        (do
          (zstdAslFillFseNorms defaults norms 0)
          (mt (zstdAslFseBuildNorms norms (listLength defaults) defaultLog)
            ((err message) (err message))
            ((ok tableAndLog) (ok (pair tableAndLog 0)))))))
    ((= mode 1)
      (if (>= at len) (err "ERR_ZSTD_CORRUPT: RLE sequence table truncated")
        (let [sym (bytesGet src at) table (bytesAlloc 4)]
          (if (> sym maxSym) (err "ERR_ZSTD_CORRUPT: RLE symbol out of range")
            (do
              (bytesSet table 0 sym)
              (bytesSet table 1 0)
              (bytesSet table 2 0)
              (bytesSet table 3 0)
              (ok (pair (pair table 0) 1)))))))
    ((= mode 2) (zstdAslFseRead src at (- len at) maxSym maxLog))
    (else
      (if previousValid (ok (pair (pair previous previousLog) 0))
        (err "ERR_ZSTD_CORRUPT: repeat sequence table without a previous table"))))

fn ! zstdAslSeqStateCopy src: Bytes srcAt: Int64 dst: Bytes dstAt: Int64 n: Int64 -> Bool
  (if (<= n 0) true
    (do
      (bytesSet dst dstAt (bytesGet src srcAt))
      (zstdAslSeqStateCopy src (+ srcAt 1) dst (+ dstAt 1) (- n 1))))

fn ! zstdAslSeqLoad state: Bytes slot: Int64 offset: Int64 -> (Option (Pair Bytes Int64))
  (if (= (bytesGet state slot) 0) none
    (let [log (bytesGet state (+ slot 3)) size (zstdAslPow2 (bytesGet state (+ slot 3)))
          table (bytesAlloc (* size 4))]
      (do
        (zstdAslSeqStateCopy state offset table 0 (* size 4))
        (some (pair table log)))))

fn ! zstdAslSeqSave state: Bytes slot: Int64 offset: Int64 table: Bytes log: Int64 -> Bool
  (do
    (bytesSet state slot 1)
    (bytesSet state (+ slot 3) log)
    (zstdAslSeqStateCopy table 0 state offset (bytesLength table)))

fn ! zstdAslRepGet reps: Bytes index: Int64 -> Int64
  (zstdAslUInt reps (* index 4) 4 1 0)

fn ! zstdAslRepSet reps: Bytes index: Int64 value: Int64 -> Bool
  (do
    (bytesSet reps (* index 4) (mod value 256))
    (bytesSet reps (+ (* index 4) 1) (mod (/ value 256) 256))
    (bytesSet reps (+ (* index 4) 2) (mod (/ value 65536) 256))
    (bytesSet reps (+ (* index 4) 3) (mod (/ value 16777216) 256))
    true)

fn ! zstdAslSequenceCopy src: Bytes srcAt: Int64 dst: Bytes dstAt: Int64 n: Int64 -> Bool
  (if (<= n 0) true
    (do
      (bytesSet dst dstAt (bytesGet src srcAt))
      (zstdAslSequenceCopy src (+ srcAt 1) dst (+ dstAt 1) (- n 1))))

fn ! zstdAslSequenceMatch out: Bytes outAt: Int64 off: Int64 n: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (do
      (bytesSet out (+ outAt i) (bytesGet out (+ (- outAt off) i)))
      (zstdAslSequenceMatch out outAt off n (+ i 1))))

fn zstdAslLlBase code: Int64 -> Int64
  (optionOr (listGet (list 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 20 22 24 28 32 40 48 64 128 256 512 1024 2048 4096 8192 16384 32768 65536) code) 0)

fn zstdAslLlBits code: Int64 -> Int64
  (optionOr (listGet (list 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 2 2 3 3 4 6 7 8 9 10 11 12 13 14 15 16) code) 0)

fn zstdAslMlBase code: Int64 -> Int64
  (optionOr (listGet (list 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 37 39 41 43 47 51 59 67 83 99 131 259 515 1027 2051 4099 8195 16387 32771 65539) code) 0)

fn zstdAslMlBits code: Int64 -> Int64
  (optionOr (listGet (list 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 2 2 3 3 4 4 5 7 8 9 10 11 12 13 14 15 16) code) 0)

fn ! zstdAslSequenceRun src: Bytes bitsAt: Int64 bitsLen: Int64 pos: Int64 left: Int64
  llTable: Bytes llLog: Int64 ofTable: Bytes ofLog: Int64 mlTable: Bytes mlLog: Int64
  llState: Int64 ofState: Int64 mlState: Int64 lit: Bytes litCount: Int64 litPos: Int64
  out: Bytes outAt: Int64 baseOut: Int64 produced: Int64 window: Int64 reps: Bytes countOnly: Bool -> (Result Int64 String)
  (if (= left 0)
    (if (!= pos 0) (err "ERR_ZSTD_CORRUPT: sequence bitstream not fully consumed")
      (if (> litPos litCount) (err "ERR_ZSTD_CORRUPT: sequence uses more literals than decoded")
        (let [remaining (- litCount litPos) dest (+ outAt produced)]
          (if (> (+ (+ baseOut produced) remaining) 1073741824)
            (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB")
            (do
              (if countOnly true (zstdAslSequenceCopy lit litPos out dest remaining))
              (ok (+ produced remaining)))))))
    (let [lc (* llState 4) oc (* ofState 4) mc (* mlState 4)
          lcode (bytesGet llTable lc) obits (bytesGet ofTable (+ oc 1))
          mcode (bytesGet mlTable mc) lbits (zstdAslLlBits lcode)
          mbits (zstdAslMlBits mcode)
          ofCode (+ (bytesGet ofTable oc) 0)
          lbase (zstdAslLlBase lcode)
          mbase (zstdAslMlBase mcode)]
      (cond
        ((or (> ofCode 31) (> mcode 52) (> lcode 35)) (err "ERR_ZSTD_CORRUPT: sequence code out of range"))
        (else
          (mt (zstdAslBackwardRead src bitsAt pos ofCode)
            ((err message) (err message))
            ((ok ofBitsState)
              (mt ofBitsState
                ((pair ofExtra pos1)
                  (mt (zstdAslBackwardRead src bitsAt pos1 mbits)
                    ((err message) (err message))
                    ((ok mlBitsState)
                      (mt mlBitsState
                        ((pair mlExtra pos2)
                          (mt (zstdAslBackwardRead src bitsAt pos2 lbits)
                            ((err message) (err message))
                            ((ok llBitsState)
                              (mt llBitsState
                                ((pair llExtra pos3)
                                  (let [ll (+ lbase llExtra) ml (+ mbase mlExtra)
                                        ofv (+ (zstdAslPow2 ofCode) ofExtra)
                                        old0 (zstdAslRepGet reps 0) old1 (zstdAslRepGet reps 1) old2 (zstdAslRepGet reps 2)
                                        idx (+ (- ofv 1) (if (= ll 0) 1 0))
                                        off (if (> ofv 3) (- ofv 3)
                                          (if (= idx 0) old0 (if (= idx 3) (- old0 1) (if (= idx 1) old1 old2))))
                                        new0 off
                                        new1 (if (and (<= ofv 3) (= idx 0)) old1 old0)
                                        new2 (if (> ofv 3) old1 (if (> idx 1) old1 old2))]
                                    (cond
                                      ((< pos3 0) (err "ERR_ZSTD_CORRUPT: sequence bitstream overrun"))
                                      ((> (+ litPos ll) litCount) (err "ERR_ZSTD_CORRUPT: sequence uses more literals than decoded"))
                                      ((> (+ (+ baseOut produced) (+ ll ml)) 1073741824) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB"))
                                      ((and (not countOnly) (> (+ outAt produced (+ ll ml)) (bytesLength out))) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB"))
                                      ((or (= off 0) (> off (+ baseOut produced ll)) (> off window)) (err "ERR_ZSTD_CORRUPT: match offset beyond the window"))
                                      (else
                                        (do
                                          (if countOnly true (zstdAslSequenceCopy lit litPos out (+ outAt produced) ll))
                                          (zstdAslRepSet reps 0 new0) (zstdAslRepSet reps 1 new1) (zstdAslRepSet reps 2 new2)
                                          (zstdAslSequenceAdvance src bitsAt bitsLen pos3 left
                                            llTable llLog ofTable ofLog mlTable mlLog llState ofState mlState
                                            lit litCount litPos out outAt baseOut produced window reps countOnly ll ml off)))))))))))))))))))))

fn ! zstdAslSequenceAdvance src: Bytes bitsAt: Int64 bitsLen: Int64 pos3: Int64 left: Int64
  llTable: Bytes llLog: Int64 ofTable: Bytes ofLog: Int64 mlTable: Bytes mlLog: Int64
  llState: Int64 ofState: Int64 mlState: Int64
  lit: Bytes litCount: Int64 litPos: Int64 out: Bytes outAt: Int64 baseOut: Int64 produced: Int64 window: Int64 reps: Bytes countOnly: Bool
  ll: Int64 ml: Int64 off: Int64 -> (Result Int64 String)
  (if (and (> left 1) (>= pos3 0))
    (mt (zstdAslFseDecodeStep llTable src bitsAt pos3 llState)
      ((err message) (err message))
      ((ok llStep)
        (mt (zstdAslFseDecodeStep mlTable src bitsAt (pairSecond llStep) mlState)
          ((err message) (err message))
          ((ok mlStep)
            (mt (zstdAslFseDecodeStep ofTable src bitsAt (pairSecond mlStep) ofState)
              ((err message) (err message))
              ((ok ofStep)
                (do
                  (if countOnly true (zstdAslSequenceMatch out (+ outAt produced ll) off ml 0))
                  (zstdAslSequenceRun src bitsAt bitsLen (pairSecond ofStep) (- left 1)
                    llTable llLog ofTable ofLog mlTable mlLog
                    (pairSecond (pairFirst llStep)) (pairSecond (pairFirst ofStep)) (pairSecond (pairFirst mlStep))
                    lit litCount (+ litPos ll) out outAt baseOut (+ produced ll ml) window reps countOnly))))))))
    (do
      (if countOnly true (zstdAslSequenceMatch out (+ outAt produced ll) off ml 0))
      (if (and (= left 1) (= pos3 0))
        (zstdAslSequenceRun src bitsAt bitsLen pos3 0 llTable llLog ofTable ofLog mlTable mlLog llState ofState mlState lit litCount (+ litPos ll) out outAt baseOut (+ produced ll ml) window reps countOnly)
        (err "ERR_ZSTD_CORRUPT: sequence bitstream not fully consumed"))))

fn ! zstdAslSequences src: Bytes start: Int64 end: Int64 lit: Bytes litCount: Int64 out: Bytes outAt: Int64 baseOut: Int64 window: Int64 state: Bytes reps: Bytes countOnly: Bool -> (Result (Pair Int64 Int64) String)
  (if (>= start end) (err "ERR_ZSTD_CORRUPT: sequences header truncated")
    (let [first (zstdAslByte src start)
          headLen (if (< first 128) 1 (if (< first 255) 2 3))]
      (if (> (+ start headLen) end) (err "ERR_ZSTD_CORRUPT: sequences header truncated")
        (let [nseq (if (< first 128) first
                    (if (< first 255) (+ (* (- first 128) 256) (zstdAslByte src (+ start 1)))
                      (+ 32512 (zstdAslByte src (+ start 1)) (* (zstdAslByte src (+ start 2)) 256))))
              afterHead (+ start headLen)]
          (if (= nseq 0)
            (if (!= afterHead end) (err "ERR_ZSTD_CORRUPT: bytes after an empty sequences section")
              (if (> (+ baseOut litCount) 1073741824) (err "ERR_ZSTD_CORRUPT: output exceeds the frame content size or 1 GiB")
                (do (if countOnly true (zstdAslSequenceCopy lit 0 out outAt litCount)) (ok (pair end litCount)))))
            (if (>= afterHead end) (err "ERR_ZSTD_CORRUPT: sequences modes truncated")
              (let [modes (zstdAslByte src afterHead)
                    llMode (/ modes 64) ofMode (mod (/ modes 16) 4) mlMode (mod (/ modes 4) 4)
                    tablesAt (+ afterHead 1)]
                (if (!= (mod modes 4) 0) (err "ERR_ZSTD_CORRUPT: reserved sequence mode bits set")
                  (mt (zstdAslSeqLoad state 0 16)
                    ((some old) (zstdAslSequencesTables src start end tablesAt nseq lit litCount out outAt baseOut window state reps llMode ofMode mlMode (some old) countOnly))
                    ((none) (zstdAslSequencesTables src start end tablesAt nseq lit litCount out outAt baseOut window state reps llMode ofMode mlMode none countOnly)))))))))))

fn ! zstdAslSequencesTables src: Bytes seqStart: Int64 end: Int64 at: Int64 nseq: Int64 lit: Bytes litCount: Int64 out: Bytes outAt: Int64 baseOut: Int64 window: Int64 state: Bytes reps: Bytes llMode: Int64 ofMode: Int64 mlMode: Int64 oldLl: (Option (Pair Bytes Int64)) countOnly: Bool -> (Result (Pair Int64 Int64) String)
  (let [llPrev (optionOr oldLl (pair (bytesAlloc 4) 0))
        ofPrevOpt (zstdAslSeqLoad state 1 2064)
        mlPrevOpt (zstdAslSeqLoad state 2 3088)
        ofPrev (optionOr ofPrevOpt (pair (bytesAlloc 4) 0))
        mlPrev (optionOr mlPrevOpt (pair (bytesAlloc 4) 0))]
    (mt (zstdAslSeqTable llMode src at end (zstdAslDefaultNorms 0) 6 35 9 (pairFirst llPrev) (pairSecond llPrev) (some? oldLl))
      ((err message) (err message))
      ((ok llState)
        (let [llPair (pairFirst llState) afterLl (+ at (pairSecond llState))]
          (mt (zstdAslSeqTable ofMode src afterLl end (zstdAslDefaultNorms 1) 5 31 8 (pairFirst ofPrev) (pairSecond ofPrev) (some? ofPrevOpt))
            ((err message) (err message))
            ((ok ofState)
              (let [ofPair (pairFirst ofState) afterOf (+ afterLl (pairSecond ofState))]
                (mt (zstdAslSeqTable mlMode src afterOf end (zstdAslDefaultNorms 2) 6 52 9 (pairFirst mlPrev) (pairSecond mlPrev) (some? mlPrevOpt))
                  ((err message) (err message))
                  ((ok mlState)
              (let [mlPair (pairFirst mlState) bitAt (+ afterOf (pairSecond mlState))
                          llTable (pairFirst llPair) llLog (pairSecond llPair)
                          ofTable (pairFirst ofPair) ofLog (pairSecond ofPair)
                          mlTable (pairFirst mlPair) mlLog (pairSecond mlPair)]
                      (cond
                        ((>= bitAt end) (err "ERR_ZSTD_CORRUPT: sequence bitstream missing"))
                        ((not (zstdAslSeqSave state 0 16 llTable llLog)) (err "ERR_ZSTD_CORRUPT: FSE table build failed"))
                        ((not (zstdAslSeqSave state 1 2064 ofTable ofLog)) (err "ERR_ZSTD_CORRUPT: FSE table build failed"))
                        ((not (zstdAslSeqSave state 2 3088 mlTable mlLog)) (err "ERR_ZSTD_CORRUPT: FSE table build failed"))
                        (else
                          (mt (zstdAslBackwardInit src bitAt (- end bitAt))
                            ((err message) (err message))
                            ((ok pos)
                              (mt (zstdAslBackwardRead src bitAt pos llLog)
                                ((err message) (err message))
                                ((ok llInit)
                                  (mt (zstdAslBackwardRead src bitAt (pairSecond llInit) ofLog)
                                    ((err message) (err message))
                                    ((ok ofInit)
                                      (mt (zstdAslBackwardRead src bitAt (pairSecond ofInit) mlLog)
                                        ((err message) (err message))
                                        ((ok mlInit)
                                          (mt (zstdAslSequenceRun src bitAt (- end bitAt) (pairSecond mlInit) nseq
                                            llTable llLog ofTable ofLog mlTable mlLog
                                            (pairFirst llInit) (pairFirst ofInit) (pairFirst mlInit)
                                            lit litCount 0 out outAt baseOut 0 window reps countOnly)
                                            ((err message) (err message))
                                            ((ok produced) (ok (pair end produced))))))))))))))))))))))))

fn ! zstdAslFseDecodeStep table: Bytes src: Bytes at: Int64 pos: Int64 state: Int64 -> (Result (Pair (Pair Int64 Int64) Int64) String)
  (if (or (< state 0) (>= (* state 4) (bytesLength table)))
    (err "ERR_ZSTD_CORRUPT: FSE state outside its table")
    (let [cell (* state 4) sym (bytesGet table cell) nb (bytesGet table (+ cell 1))
          base (+ (bytesGet table (+ cell 2)) (* (bytesGet table (+ cell 3)) 256))]
      (mt (zstdAslBackwardRead src at pos nb)
        ((err message) (err message))
        ((ok bitsState)
          (mt bitsState
            ((pair bits nextPos)
              (let [nextState (+ base bits)]
                (if (or (< nextState 0) (>= nextState (/ (bytesLength table) 4)))
                  (err "ERR_ZSTD_CORRUPT: FSE state outside its table")
                  (ok (pair (pair sym nextState) nextPos))))))))))

fn ! zstdAslFseWeightLoop table: Bytes src: Bytes at: Int64 pos: Int64 state1: Int64 state2: Int64 weights: Bytes count: Int64 -> (Result (Pair Bytes Int64) String)
  (if (>= count 255) (err "ERR_ZSTD_CORRUPT: too many Huffman weights")
    (mt (zstdAslFseDecodeStep table src at pos state1)
      ((err message) (err message))
      ((ok state1Step)
        (mt state1Step
          ((pair decoded nextPos)
            (mt decoded
              ((pair weight nextState1)
                (do
                  (bytesSet weights count weight)
                  (if (< nextPos 0)
                    (if (>= (+ count 1) 255) (err "ERR_ZSTD_CORRUPT: too many Huffman weights")
                      (do (bytesSet weights (+ count 1) (bytesGet table (* state2 4)))
                          (ok (pair weights (+ count 2)))))
                    (if (>= (+ count 1) 255) (err "ERR_ZSTD_CORRUPT: too many Huffman weights")
                      (mt (zstdAslFseDecodeStep table src at nextPos state2)
                        ((err message) (err message))
                        ((ok state2Step)
                          (mt state2Step
                            ((pair decoded2 nextPos2)
                              (mt decoded2
                                ((pair weight2 nextState2)
                                  (do
                                    (bytesSet weights (+ count 1) weight2)
                                    (if (< nextPos2 0)
                                      (if (>= (+ count 2) 255) (err "ERR_ZSTD_CORRUPT: too many Huffman weights")
                                        (do (bytesSet weights (+ count 2) (bytesGet table (* nextState1 4)))
                                            (ok (pair weights (+ count 3)))))
                      (zstdAslFseWeightLoop table src at nextPos2 nextState1 nextState2 weights (+ count 2))))))))))))))))))))

fn ! zstdAslHufFseWeights src: Bytes at: Int64 len: Int64 -> (Result (Pair Bytes Int64) String)
  (if (= len 0) (err "ERR_ZSTD_CORRUPT: Huffman weight stream empty")
    (let [size len]
        (mt (zstdAslFseRead src at size 255 6)
          ((err message) (err message))
          ((ok fseState)
            (mt fseState
              ((pair tableAndLog descBytes)
                (mt tableAndLog
                  ((pair table log)
                    (if (>= descBytes size) (err "ERR_ZSTD_CORRUPT: Huffman weight stream empty")
                      (let [streamAt (+ at descBytes) streamLen (- size descBytes)
                            weights (bytesAlloc 255)]
                        (mt (zstdAslBackwardInit src streamAt streamLen)
                          ((err message) (err message))
                          ((ok initialPos)
                            (mt (zstdAslBackwardRead src streamAt initialPos log)
                              ((err message) (err message))
                              ((ok firstState)
                                (mt firstState
                                  ((pair s1 pos1)
                                    (mt (zstdAslBackwardRead src streamAt pos1 log)
                                      ((err message) (err message))
                                      ((ok secondState)
                                        (mt secondState
                                          ((pair s2 pos2)
                                            (if (< pos2 0) (err "ERR_ZSTD_CORRUPT: Huffman weight stream too short")
                                              (zstdAslFseWeightLoop table src streamAt pos2 s1 s2 weights 0))))))))))))))))))))))

fn ! zstdAslHufRead src: Bytes at: Int64 len: Int64 -> (Result (Pair (Pair Bytes Int64) Int64) String)
  (if (= len 0) (err "ERR_ZSTD_CORRUPT: Huffman tree description truncated")
    (let [head (bytesGet src at)]
      (if (>= head 128)
        (let [count (- head 127) used (+ 1 (/ (+ count 1) 2))]
          (if (> used len) (err "ERR_ZSTD_CORRUPT: Huffman direct weights truncated")
            (let [weights (bytesAlloc count)]
              (do
                (zstdAslHufDirectWeights src (+ at 1) count weights 0)
                (mt (zstdAslHufBuild weights count)
                  ((err message) (err message))
                  ((ok tableAndLog) (ok (pair tableAndLog used))))))))
        (let [used (+ 1 head)]
          (if (or (= head 0) (> used len)) (err "ERR_ZSTD_CORRUPT: Huffman FSE weights truncated")
            (mt (zstdAslHufFseWeights src (+ at 1) head)
              ((err message) (err message))
              ((ok weightsState)
                (mt weightsState
                  ((pair weights count)
                    (mt (zstdAslHufBuild weights count)
                      ((err message) (err message))
                      ((ok tableAndLog) (ok (pair tableAndLog used)))))))))))))

fn ! zstdAslHufDirectWeights src: Bytes at: Int64 count: Int64 weights: Bytes i: Int64 -> Bool
  (if (>= i count) true
    (let [packed (bytesGet src (+ at (/ i 2)))
          weight (if (= (mod i 2) 0) (/ packed 16) (mod packed 16))]
      (do
        (bytesSet weights i weight)
        (zstdAslHufDirectWeights src at count weights (+ i 1)))))

fn ! zstdAslHufStream table: Bytes tableAt: Int64 log: Int64 src: Bytes at: Int64 pos: Int64 dst: Bytes outAt: Int64 count: Int64 i: Int64 -> (Result Int64 String)
  (if (>= i count)
    (if (= pos 0) (ok pos) (err "ERR_ZSTD_CORRUPT: Huffman stream not fully consumed"))
    (let [index (zstdAslBackwardPeek src at pos log) cell (+ tableAt (* index 2))]
      (if (>= (+ cell 1) (bytesLength table)) (err "ERR_ZSTD_CORRUPT: Huffman stream overrun")
        (let [sym (bytesGet table cell) bits (bytesGet table (+ cell 1)) nextPos (- pos bits)]
          (if (< nextPos 0) (err "ERR_ZSTD_CORRUPT: Huffman stream overrun")
            (do
              (bytesSet dst (+ outAt i) sym)
              (zstdAslHufStream table tableAt log src at nextPos dst outAt count (+ i 1))))))))

fn zstdAslBackwardBit src: Bytes byteAt: Int64 position: Int64 -> Int64
  (if (< position 0) 0
    (mod (/ (bytesGet src (+ byteAt (/ position 8))) (zstdAslPow2 (mod position 8))) 2))

fn zstdAslBackwardPeekLoop src: Bytes byteAt: Int64 low: Int64 bit: Int64 count: Int64 value: Int64 -> Int64
  (if (>= bit count) value
    (zstdAslBackwardPeekLoop src byteAt low (+ bit 1) count
      (+ value (* (zstdAslBackwardBit src byteAt (+ low bit)) (zstdAslPow2 bit)))))

fn zstdAslBackwardPeek src: Bytes byteAt: Int64 position: Int64 count: Int64 -> Int64
  (if (<= count 0) 0
    (zstdAslBackwardPeekLoop src byteAt (- position count) 0 count 0))

fn ! zstdAslBackwardInit src: Bytes at: Int64 len: Int64 -> (Result Int64 String)
  (cond
    ((<= len 0) (err "ERR_ZSTD_CORRUPT: bitstream without an end marker"))
    ((= (bytesGet src (+ at (- len 1))) 0) (err "ERR_ZSTD_CORRUPT: bitstream without an end marker"))
    (else (ok (+ (* len 8) (+ -8 (zstdAslHighBit (bytesGet src (+ at (- len 1)))))))))

fn ! zstdAslBackwardRead src: Bytes at: Int64 pos: Int64 n: Int64 -> (Result (Pair Int64 Int64) String)
  (if (or (< n 0) (> n 31)) (err "ERR_ZSTD_CORRUPT: invalid backward bit count")
    (ok (pair (zstdAslBackwardPeek src at pos n) (- pos n))))

fn zstdAslPowerOfTwo? n: Int64 -> Bool
  (if (<= n 0) false
    (if (= n 1) true
      (and (= (mod n 2) 0) (zstdAslPowerOfTwo? (/ n 2)))))

fn ! zstdAslHufCheckWeights weights: Bytes i: Int64 count: Int64 sum: Int64 -> (Result Int64 String)
  (if (>= i count) (ok sum)
    (let [weight (bytesGet weights i)]
      (if (> weight 11) (err "ERR_ZSTD_CORRUPT: Huffman weight above 11")
        (zstdAslHufCheckWeights weights (+ i 1) count
          (if (= weight 0) sum (+ sum (zstdAslPow2 (- weight 1))))))))

fn zstdAslHufGet16 values: Bytes index: Int64 -> Int64
  (+ (bytesGet values (* index 2)) (* (bytesGet values (+ (* index 2) 1)) 256))

fn ! zstdAslHufSet16 values: Bytes index: Int64 value: Int64 -> Bool
  (do
    (bytesSet values (* index 2) (mod value 256))
    (bytesSet values (+ (* index 2) 1) (/ value 256))
    true)

fn ! zstdAslHufCountWeights weights: Bytes count: Int64 counts: Bytes i: Int64 -> Bool
  (if (>= i count) true
    (do
      (if (> (bytesGet weights i) 0)
        (zstdAslHufSet16 counts (bytesGet weights i) (+ (zstdAslHufGet16 counts (bytesGet weights i)) 1))
        true)
      (zstdAslHufCountWeights weights count counts (+ i 1))))

fn ! zstdAslHufStarts counts: Bytes starts: Bytes weight: Int64 maxBits: Int64 next: Int64 -> Int64
  (if (> weight maxBits) next
    (do
      (zstdAslHufSet16 starts weight next)
      (zstdAslHufStarts counts starts (+ weight 1) maxBits
        (+ next (* (zstdAslHufGet16 counts weight) (zstdAslPow2 (- weight 1)))))))

fn ! zstdAslHufFill table: Bytes starts: Bytes maxBits: Int64 weight: Int64 symbol: Int64 count: Int64 index: Int64 -> Bool
  (if (>= index count)
    (do
      (zstdAslHufSet16 starts weight (+ (zstdAslHufGet16 starts weight) count))
      true)
    (let [slot (+ (zstdAslHufGet16 starts weight) index)
          tableBits (+ (- maxBits weight) 1)]
      (do
        (bytesSet table (* slot 2) symbol)
        (bytesSet table (+ (* slot 2) 1) tableBits)
        (zstdAslHufFill table starts maxBits weight symbol count (+ index 1)))))

fn ! zstdAslHufSpread table: Bytes starts: Bytes weights: Bytes count: Int64 maxBits: Int64 symbol: Int64 -> Bool
  (if (>= symbol count) true
    (let [weight (bytesGet weights symbol)]
      (if (= weight 0) (zstdAslHufSpread table starts weights count maxBits (+ symbol 1))
        (let [copies (zstdAslPow2 (- weight 1))]
          (do
            (zstdAslHufFill table starts maxBits weight symbol copies 0)
            (zstdAslHufSpread table starts weights count maxBits (+ symbol 1)))))))

fn ! zstdAslHufBuild weights: Bytes count: Int64 -> (Result (Pair Bytes Int64) String)
  (mt (zstdAslHufCheckWeights weights 0 count 0)
    ((err message) (err message))
    ((ok sum)
      (if (= sum 0) (err "ERR_ZSTD_CORRUPT: Huffman weights all zero")
        (let [maxBits (+ (zstdAslHighBit sum) 1)
              rest (- (zstdAslPow2 maxBits) sum)]
          (if (or (> maxBits 11) (not (zstdAslPowerOfTwo? rest)))
            (err "ERR_ZSTD_CORRUPT: Huffman weights do not complete a tree")
            (let [allWeights (bytesAlloc (+ count 1)) counts (bytesAlloc 26) starts (bytesAlloc 26)
                  table (bytesAlloc (* (zstdAslPow2 maxBits) 2))]
              (do
                (zstdAslSetRaw weights 0 allWeights 0 count)
                (bytesSet allWeights count (+ (zstdAslHighBit rest) 1))
                (if (zstdAslHufCountWeights allWeights (+ count 1) counts 0)
                  (let [lastIndex (zstdAslHufStarts counts starts 1 maxBits 0)]
                    (if (and (= lastIndex (zstdAslPow2 maxBits))
                          (zstdAslHufSpread table starts allWeights (+ count 1) maxBits 0))
                      (ok (pair table maxBits))
                      (err "ERR_ZSTD_CORRUPT: Huffman weights do not complete a tree")))
                  (err "ERR_ZSTD_CORRUPT: Huffman table build failed")))))))))

fn ! zstdAslDecompress src: Bytes -> (Result Bytes String)
  (zstdAslFrame src)
