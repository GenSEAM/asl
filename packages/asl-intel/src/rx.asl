(module asl-intel/rx
  :x [Cls Rx Rex clsSet! clsNot! clsAny clsSpace! clsSetSpace!
      rxLit rxLitI rxOne rxRep rxSeq rxAlt rxOpt rxGroup rxBol rxBos rxEos rxWordB rxLook
      rexCompile! rexCompileLead! rexSearch rexFindAll rexCount rexGroup rexGroupSpan rexHas? preAny preLine preNewline preByte]
  :i [(asl-intel/text :a t)])

enum Cls
  (clsSetOf tbl: Bytes space: Bool)
  (clsNotOf tbl: Bytes)
  (clsAnyOf)

enum Rx
  (rxLit bs: Bytes)
  (rxLitI bs: Bytes)
  (rxOne c: Cls)
  (rxRep c: Cls lo: Int64 greedy: Bool)
  (rxSeq xs: (List Rx))
  (rxAlt xs: (List Rx))
  (rxOpt x: Rx)
  (rxGroup i: Int64 x: Rx)
  (rxBol)
  (rxBos)
  (rxEos)
  (rxWordB)
  (rxLook x: Rx)

(schema Rex
  (:f m (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))))
  (:f memos Int64)
  (:f groups Int64)
  (:f pre Int64)
  (:f preB Int64)
  (:f leads (List Bytes))
  (:f paren Bool)
  (:f leadFirst Bytes))

fn preAny -> Int64
  0

fn preNewline -> Int64
  1

fn preLine -> Int64
  2

fn preByte -> Int64
  3

fn tableMark! tbl: Bytes spec: Bytes k: Int64 i: Int64 -> Bytes
  (if (>= i k) tbl
    (let [(c (bytesGet spec i))]
      (if (and (< (+ i 2) k) (= (bytesGet spec (+ i 1)) 45))
        (do (markRange! tbl c (bytesGet spec (+ i 2))) (tableMark! tbl spec k (+ i 3)))
        (do (bytesSet tbl c 1) (tableMark! tbl spec k (+ i 1))))))

fn markRange! tbl: Bytes a: Int64 z: Int64 -> Unit
  (if (> a z) ()
    (do (bytesSet tbl a 1) (markRange! tbl (+ a 1) z)))

fn specTable! spec: String -> Bytes
  (let [(sb (stringToBytes spec))]
    (tableMark! (bytesAlloc 256) sb (bytesLength sb) 0))

fn clsSet! spec: String -> Cls
  (clsSetOf (specTable! spec) false)

fn clsSetSpace! spec: String -> Cls
  (clsSetOf (markWs! (specTable! spec)) true)

fn markWs! tbl: Bytes -> Bytes
  (do (markRange! tbl 9 13) (markRange! tbl 28 32) tbl)

fn clsNot! spec: String -> Cls
  (clsNotOf (specTable! spec))

fn clsAny -> Cls
  (clsAnyOf)

fn clsSpace! -> Cls
  (clsSetOf (markWs! (bytesAlloc 256)) true)

fn clsStep c: Cls b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) -1
    (let [(x (bytesGet b i))]
      (mt c
        ((clsSetOf tbl space)
          (if (< x 128)
            (if (= (bytesGet tbl x) 1) (+ i 1) -1)
            (if space (let [(k (t/spaceLen b n i))] (if (> k 0) (+ i k) -1)) -1)))
        ((clsNotOf tbl)
          (if (< x 128)
            (if (= (bytesGet tbl x) 1) -1 (+ i 1))
            (min n (+ i (t/utf8Len x)))))
        ((clsAnyOf) (min n (+ i (t/utf8Len x)))))))

fn capSet caps: (List Int64) k: Int64 v: Int64 -> (List Int64)
  (capSetLoop caps k v 0 (list))

fn capSetLoop caps: (List Int64) k: Int64 v: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (mt (listHead caps)
    ((none) (listReverse acc))
    ((some x) (capSetLoop (optionOr (listTail caps) (list)) k v (+ i 1) (cons (if (= i k) v x) acc))))

fn foldByte c: Int64 -> Int64
  (if (and (>= c 65) (<= c 90)) (+ c 32) c)

fn litAt? b: Bytes n: Int64 i: Int64 t: Bytes k: Int64 j: Int64 fold: Bool -> Bool
  (cond
    ((>= j k) true)
    ((>= (+ i j) n) false)
    ((if fold (!= (foldByte (bytesGet b (+ i j))) (foldByte (bytesGet t j))) (!= (bytesGet b (+ i j)) (bytesGet t j))) false)
    (else (litAt? b n i t k (+ j 1) fold)))

fn runEnd c: Cls b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (clsStep c b n i))]
    (if (< j 0) i (runEnd c b n j)))

fn prevStart b: Bytes e: Int64 -> Int64
  (if (< (bytesGet b (- e 1)) 128) (- e 1) (t/cpStartBefore b e))

fn memoIdx id: Int64 n: Int64 mb: Int64 e: Int64 -> Int64
  (+ (* id (rowLen n mb)) (+ 24 (- e mb)))

fn rowLen n: Int64 mb: Int64 -> Int64
  (+ 24 (* 8 (/ (+ (- n mb) 8) 8)))

fn triedLow id: Int64 n: Int64 mb: Int64 mo: Bytes -> Int64
  (- (mt (float64ToInt64 (bytesGetFloat64 mo (+ (/ (* id (rowLen n mb)) 8) 2))) ((some i) i) ((none) 0)) 1)

fn setTried! id: Int64 n: Int64 mb: Int64 mo: Bytes t: Int64 -> Unit
  (bytesSetFloat64 mo (+ (/ (* id (rowLen n mb)) 8) 2) (int64ToFloat64 (+ t 1)))

fn memoAlloc r: Rex n: Int64 mb: Int64 -> Bytes
  (bytesAlloc (* r.memos (rowLen n mb)))

fn runEndCached! id: Int64 c: Cls b: Bytes n: Int64 i: Int64 mo: Bytes mb: Int64 -> Int64
  (let [(slot (/ (* id (rowLen n mb)) 8))
        (s0 (- (mt (float64ToInt64 (bytesGetFloat64 mo slot)) ((some i) i) ((none) 0)) 1))
        (e0 (- (mt (float64ToInt64 (bytesGetFloat64 mo (+ slot 1))) ((some i) i) ((none) 0)) 1))]
    (if (and (>= e0 0) (and (>= i s0) (<= i e0))) e0
      (let [(e (runEnd c b n i))]
        (do (bytesSetFloat64 mo slot (int64ToFloat64 (+ i 1)))
            (bytesSetFloat64 mo (+ slot 1) (int64ToFloat64 (+ e 1)))
            (bytesSetFloat64 mo (+ slot 2) 0.0)
            e))))

fn memoRun! id: Int64 k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) b: Bytes n: Int64 e: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (let [(ix (memoIdx id n mb e))]
    (if (= (bytesGet mo ix) 1) (none)
      (mt (k b n e caps mo mb)
        ((some r) (some r))
        ((none) (do (bytesSet mo ix 1) (none))))))

fn greedyFrom! id: Int64 c: Cls k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) b: Bytes n: Int64 low: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (let [(e (runEndCached! id c b n low mo mb)) (t (triedLow id n mb mo))]
    (if (and (>= t 0) (<= t low)) (none)
      (mt (repBack! id k b n low (if (>= t 0) (prevStart b t) e) caps mo mb)
        ((some r) (some r))
        ((none) (do (setTried! id n mb mo low) (none))))))

fn repBack! id: Int64 k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) b: Bytes n: Int64 low: Int64 e: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (mt (memoRun! id k b n e caps mo mb)
    ((some r) (some r))
    ((none) (if (<= e low) (none) (repBack! id k b n low (prevStart b e) caps mo mb))))

fn lazyTry! id: Int64 c: Cls k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) b: Bytes n: Int64 i: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (mt (memoRun! id k b n i caps mo mb)
    ((some r) (some r))
    ((none)
      (let [(j (clsStep c b n i))]
        (if (< j 0) (none) (lazyTry! id c k b n j caps mo mb)))))

fn lazyToByte! id: Int64 k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) x: Int64 b: Bytes n: Int64 i: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (let [(j (byteFrom b n x i))]
    (if (< j 0) (none)
      (mt (memoRun! id k b n j caps mo mb)
        ((some r) (some r))
        ((none) (lazyToByte! id k x b n (+ j 1) caps mo mb)))))

fn byteFrom b: Bytes n: Int64 x: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet b i) x) i)
    (else (byteFrom b n x (+ i 1))))

fn firstByte x: Rx -> Int64
  (mt x
    ((rxLit bs) (if (> (bytesLength bs) 0) (bytesGet bs 0) -1))
    ((rxGroup g y) (firstByte y))
    ((rxLook y) (firstByte y))
    ((rxSeq xs) (mt (listHead xs) ((some y) (firstByte y)) ((none) -1)))
    (else -1))

fn altTable! xs: (List Rx) -> (Option Bytes)
  (fold (fn [(acc (Option Bytes)) (y Rx)] -> (Option Bytes)
          (mt acc
            ((none) (none))
            ((some tb)
              (mt y
                ((rxEos) (some tb))
                (else (let [(f (firstByte y))] (if (< f 0) (none) (do (bytesSet tb f 1) (some tb)))))))))
        (some (bytesAlloc 256)) xs)

fn stepN c: Cls b: Bytes n: Int64 i: Int64 lo: Int64 -> Int64
  (if (or (<= lo 0) (< i 0)) i
    (stepN c b n (clsStep c b n i) (- lo 1)))

fn altTry ms: (List (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64)))) b: Bytes n: Int64 i: Int64 caps: (List Int64) mo: Bytes mb: Int64 -> (Option (List Int64))
  (mt (listHead ms)
    ((none) (none))
    ((some m)
      (mt (m b n i caps mo mb)
        ((some r) (some r))
        ((none) (altTry (optionOr (listTail ms) (list)) b n i caps mo mb)))))

fn compileNode! x: Rx k: (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) kFirst: Int64 id: Int64 -> (Pair (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) Int64)
  (mt x
    ((rxLit bs)
      (let [(len (bytesLength bs))]
        (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                (if (litAt? b n i bs len 0 false) (k b n (+ i len) caps mo mb) (none)))
              id)))
    ((rxLitI bs)
      (let [(len (bytesLength bs))]
        (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                (if (litAt? b n i bs len 0 true) (k b n (+ i len) caps mo mb) (none)))
              id)))
    ((rxOne c)
      (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (let [(j (clsStep c b n i))] (if (< j 0) (none) (k b n j caps mo mb))))
            id))
    ((rxRep c lo greedy)
      (pair
        (if greedy
          (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
            (let [(low (stepN c b n i lo))]
              (if (< low 0) (none) (greedyFrom! id c k b n low caps mo mb))))
          (if (and (>= kFirst 0) (and (< kFirst 128) (anyCls? c)))
            (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (let [(s (stepN c b n i lo))]
                (if (< s 0) (none) (lazyToByte! id k kFirst b n s caps mo mb))))
            (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (let [(s (stepN c b n i lo))]
                (if (< s 0) (none) (lazyTry! id c k b n s caps mo mb))))))
        (+ id 1)))
    ((rxSeq xs)
      (let [(r (fold (fn [(acc (Pair (Pair (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) Int64) Int64)) (y Rx)] -> (Pair (Pair (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64))) Int64) Int64)
                       (let [(c (compileNode! y (pairFirst (pairFirst acc)) (pairSecond (pairFirst acc)) (pairSecond acc)))]
                         (pair (pair (pairFirst c) (firstByte y)) (pairSecond c))))
                     (pair (pair k kFirst) id) (listReverse xs)))]
        (pair (pairFirst (pairFirst r)) (pairSecond r))))
    ((rxAlt xs)
      (let [(r (fold (fn [(acc (Pair (List (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64)))) Int64)) (y Rx)] -> (Pair (List (Fn Bytes Int64 Int64 (List Int64) Bytes Int64 (Option (List Int64)))) Int64)
                       (let [(c (compileNode! y k kFirst (pairSecond acc)))]
                         (pair (cons (pairFirst c) (pairFirst acc)) (pairSecond c))))
                     (pair (list) id) xs))
            (ms (listReverse (pairFirst r)))
            (tbl (altTable! xs))]
        (pair (if (some? tbl)
                (let [(tb (optionOr tbl (bytesAlloc 256)))]
                  (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                    (if (and (< i n) (= (bytesGet tb (bytesGet b i)) 0)) (none) (altTry ms b n i caps mo mb))))
                (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                  (altTry ms b n i caps mo mb)))
              (pairSecond r))))
    ((rxOpt y)
      (let [(c (compileNode! y k kFirst id)) (m (pairFirst c))]
        (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                (mt (m b n i caps mo mb)
                  ((some r) (some r))
                  ((none) (k b n i caps mo mb))))
              (pairSecond c))))
    ((rxGroup g y)
      (let [(c (compileNode! y (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                                 (k b n i (capSet caps (+ (* 2 g) 1) i) mo mb))
                            kFirst id))
            (inner (pairFirst c))]
        (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                (inner b n i (capSet caps (* 2 g) i) mo mb))
              (pairSecond c))))
    ((rxBol)
      (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (if (or (= i 0) (= (bytesGet b (- i 1)) 10)) (k b n i caps mo mb) (none)))
            id))
    ((rxBos)
      (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (if (= i 0) (k b n i caps mo mb) (none)))
            id))
    ((rxEos)
      (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (if (= i n) (k b n i caps mo mb) (none)))
            id))
    ((rxWordB)
      (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
              (if (!= (t/wordBefore? b n i) (t/wordAt? b n i)) (k b n i caps mo mb) (none)))
            id))
    ((rxLook y)
      (let [(c (compileNode! y (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64)) (some caps)) -1 id))
            (inner (pairFirst c))]
        (pair (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64))
                (if (some? (inner b n i caps mo mb)) (k b n i caps mo mb) (none)))
              (pairSecond c)))))

fn rexCompile! x: Rx groups: Int64 pre: Int64 preB: Int64 -> Rex
  (rexCompileLead! x groups pre preB (list) false)

fn rexCompileLead! x: Rx groups: Int64 pre: Int64 preB: Int64 leads: (List String) paren: Bool -> Rex
  (let [(c (compileNode! x (fn [(b Bytes) (n Int64) (i Int64) (caps (List Int64)) (mo Bytes) (mb Int64)] -> (Option (List Int64)) (some (capSet caps 1 i))) -1 0))]
    (Rex :m (pairFirst c) :memos (pairSecond c)
         :groups groups :pre pre :preB preB :leads (map stringToBytes leads) :paren paren :leadFirst (firstTable! leads)))

fn firstTable! leads: (List String) -> Bytes
  (fold (fn [(tbl Bytes) (w String)] -> Bytes
          (let [(wb (stringToBytes w))] (if (> (bytesLength wb) 0) (do (bytesSet tbl (bytesGet wb 0) 1) tbl) tbl)))
        (bytesAlloc 256) leads)

fn anyCls? c: Cls -> Bool
  (mt c ((clsAnyOf) true) (else false))

fn skipWs b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) i
    (let [(c (bytesGet b i))]
      (cond
        ((or (= c 32) (= c 10)) (skipWs b n (+ i 1)))
        ((and (< c 128) (not (isSpaceByte c))) i)
        (else (let [(k (t/spaceLen b n i))] (if (> k 0) (skipWs b n (+ i k)) i))))))

fn isSpaceByte c: Int64 -> Bool
  (t/isSpaceByte c)

fn leadOk? r: Rex b: Bytes n: Int64 i: Int64 -> Bool
  (if (listEmpty? r.leads) true
    (let [(j0 (skipWs b n i))]
      (if (>= j0 n) false
        (let [(c0 (bytesGet b j0))]
          (if (and (= (bytesGet r.leadFirst c0) 0) (not (and r.paren (= c0 40)))) false
            (let [(j (if (and r.paren (= c0 40)) (skipWs b n (+ j0 1)) j0))]
              (listAny? (fn [(w Bytes)] -> Bool (litAt? b n j w (bytesLength w) 0 false)) r.leads)))))))

fn emptyCaps k: Int64 acc: (List Int64) -> (List Int64)
  (if (<= k 0) acc (emptyCaps (- k 1) (cons -1 acc)))

fn preStart r: Rex b: Bytes n: Int64 i: Int64 -> Int64
  (let [(p r.pre)]
    (cond
      ((> i n) -1)
      ((= p 0) i)
      ((= p 1) (if (= i 0) 0 (byteFrom b n 10 i)))
      ((= p 2) (cond ((= i 0) 0) ((= (bytesGet b (- i 1)) 10) i) (else (byteFrom b n 10 i))))
      (else (byteFrom b n r.preB i))))

fn nextStart r: Rex b: Bytes n: Int64 i: Int64 -> Int64
  (let [(s (preStart r b n i))]
    (cond
      ((< s 0) -1)
      ((leadOk? r b n s) s)
      (else (nextStart r b n (+ s 1)))))

fn rexSearch r: Rex b: Bytes n: Int64 i: Int64 -> (Option (List Int64))
  (searchFrom r b n i (memoAlloc r n i) i)

fn searchFrom r: Rex b: Bytes n: Int64 i: Int64 mo: Bytes mb: Int64 -> (Option (List Int64))
  (let [(s (nextStart r b n i))]
    (if (< s 0) (none)
      (let [(caps (capSet (emptyCaps (* 2 (+ r.groups 1)) (list)) 0 s))]
        (mt (r.m b n s caps mo mb)
          ((some c) (some c))
          ((none) (searchFrom r b n (+ s 1) mo mb))))))

fn rexFindAll r: Rex b: Bytes n: Int64 -> (List (List Int64))
  (listReverse (findLoop r b n 0 (memoAlloc r n 0) (list)))

fn findLoop r: Rex b: Bytes n: Int64 i: Int64 mo: Bytes acc: (List (List Int64)) -> (List (List Int64))
  (if (> i n) acc
    (mt (searchFrom r b n i mo 0)
      ((none) acc)
      ((some c)
        (let [(s (optionOr (listGet c 0) 0)) (e (optionOr (listGet c 1) 0))]
          (findLoop r b n (if (= e s) (+ e 1) e) mo (cons c acc))))))

fn rexCount r: Rex b: Bytes n: Int64 -> Int64
  (countLoop r b n 0 (memoAlloc r n 0) 0)

fn countLoop r: Rex b: Bytes n: Int64 i: Int64 mo: Bytes acc: Int64 -> Int64
  (if (> i n) acc
    (mt (searchFrom r b n i mo 0)
      ((none) acc)
      ((some c)
        (let [(s (optionOr (listGet c 0) 0)) (e (optionOr (listGet c 1) 0))]
          (countLoop r b n (if (= e s) (+ e 1) e) mo (+ acc 1))))))

fn rexHas? r: Rex b: Bytes n: Int64 -> Bool
  (some? (rexSearch r b n 0))

fn rexGroupSpan caps: (List Int64) g: Int64 -> (Option (Pair Int64 Int64))
  (let [(s (optionOr (listGet caps (* 2 g)) -1)) (e (optionOr (listGet caps (+ (* 2 g) 1)) -1))]
    (if (or (< s 0) (< e 0)) (none) (some (pair s e))))

fn rexGroup s: String caps: (List Int64) g: Int64 -> (Option String)
  (mt (rexGroupSpan caps g)
    ((none) (none))
    ((some p) (some (t/sliceStr s (pairFirst p) (pairSecond p)))))
