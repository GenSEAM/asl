(module asl-json/pointer
  :x [jsonPointerGet jsonPointerSet]
  :i [(asl-json/json :a j)])

fn sliceSeg s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn splitPointer pointer: String -> (Option (List String))
  (let [(bs (stringToBytes pointer))
        (len (bytesLength bs))]
    (if (= len 0)
      (some (list))
      (if (= (bytesGet bs 0) 47)
        (splitFrom pointer bs len 1 1 (list))
        none)))

fn splitFrom pointer: String bs: Bytes len: Int64 pos: Int64 segStart: Int64 acc: (List String) -> (Option (List String))
  (if (>= pos len)
    (some (listReverse (cons (sliceSeg pointer segStart pos) acc)))
    (if (= (bytesGet bs pos) 47)
      (splitFrom pointer bs len (+ pos 1) (+ pos 1) (cons (sliceSeg pointer segStart pos) acc))
      (splitFrom pointer bs len (+ pos 1) segStart acc)))

fn unescapeFrom t: String bs: Bytes len: Int64 pos: Int64 pieces: (List String) -> (Option String)
  (if (>= pos len)
    (some (stringJoin (listReverse pieces) ""))
    (let [(b (bytesGet bs pos))]
      (if (not (= b 126))
        (unescapeFrom t bs len (+ pos 1) (cons (sliceSeg t pos (+ pos 1)) pieces))
        (if (>= (+ pos 1) len)
          none
          (let [(nxt (bytesGet bs (+ pos 1)))]
            (cond
              ((= nxt 49) (unescapeFrom t bs len (+ pos 2) (cons "/" pieces)))
              ((= nxt 48) (unescapeFrom t bs len (+ pos 2) (cons "~" pieces)))
              (else none)))))))

fn unescapeToken t: String -> (Option String)
  (let [(bs (stringToBytes t))
        (len (bytesLength bs))]
    (unescapeFrom t bs len 0 (list)))

fn unescapeAll toks: (List String) -> (Option (List String))
  (if (listEmpty? toks)
    (some (list))
    (match (unescapeToken (preludeHead toks))
      ((none) none)
      ((some u)
       (match (unescapeAll (preludeTail toks))
         ((none) none)
         ((some rest) (some (cons u rest)))))))

fn allDigits bs: Bytes len: Int64 pos: Int64 -> Bool
  (if (>= pos len)
    true
    (let [(b (bytesGet bs pos))]
      (if (and (>= b 48) (<= b 57))
        (allDigits bs len (+ pos 1))
        false)))

fn arrayIndex tok: String -> (Option Int64)
  (let [(bs (stringToBytes tok))
        (len (bytesLength bs))]
    (if (= len 0)
      none
      (if (and (> len 1) (= (bytesGet bs 0) 48))
        none
        (if (and (<= len 18) (allDigits bs len 0))
          (stringToInt64 tok)
          none))))

fn getAt v: j/Json toks: (List String) -> (Option j/Json)
  (if (listEmpty? toks)
    (some v)
    (let [(tok (preludeHead toks))
          (rest (preludeTail toks))]
      (match v
        ((j/jobj _)
         (match (j/jsonGet v tok)
           ((none) none)
           ((some child) (getAt child rest))))
        ((j/jarr xs)
         (match (arrayIndex tok)
           ((none) none)
           ((some i)
            (match (listGet xs i)
              ((none) none)
              ((some child) (getAt child rest))))))
        (_ none))))

fn jsonPointerGet v: j/Json pointer: String -> (Option j/Json)
  (match (splitPointer pointer)
    ((none) none)
    ((some raw)
     (match (unescapeAll raw)
       ((none) none)
       ((some toks) (getAt v toks)))))

fn replaceKey kvs: (List (Pair String j/Json)) key: String nv: j/Json -> (List (Pair String j/Json))
  (if (listEmpty? kvs)
    kvs
    (let [(p (preludeHead kvs))]
      (if (= (pairFirst p) key)
        (cons (pair key nv) (preludeTail kvs))
        (cons p (replaceKey (preludeTail kvs) key nv)))))

fn appendPair kvs: (List (Pair String j/Json)) p: (Pair String j/Json) -> (List (Pair String j/Json))
  (if (listEmpty? kvs)
    (list p)
    (cons (preludeHead kvs) (appendPair (preludeTail kvs) p)))

fn replaceIndex xs: (List j/Json) i: Int64 nv: j/Json -> (List j/Json)
  (if (= i 0)
    (cons nv (preludeTail xs))
    (cons (preludeHead xs) (replaceIndex (preludeTail xs) (- i 1) nv)))

fn setAt v: j/Json toks: (List String) x: j/Json -> (Result j/Json String)
  (if (listEmpty? toks)
    (ok x)
    (let [(tok (preludeHead toks))
          (rest (preludeTail toks))]
      (match v
        ((j/jobj kvs)
         (match (j/jsonGet v tok)
           ((some old)
            (match (setAt old rest x)
              ((ok nv) (ok (j/jobj (replaceKey kvs tok nv))))
              ((err e) (err e))))
           ((none)
            (if (listEmpty? rest)
              (ok (j/jobj (appendPair kvs (pair tok x))))
              (err (str "key not found: " tok))))))
        ((j/jarr xs)
         (match (arrayIndex tok)
           ((none) (err (str "bad array index: " tok)))
           ((some i)
            (match (listGet xs i)
              ((none) (err "array index out of range"))
              ((some old)
               (match (setAt old rest x)
                 ((ok nv) (ok (j/jarr (replaceIndex xs i nv))))
                 ((err e) (err e))))))))
        (_ (err "cannot traverse into scalar")))))

fn jsonPointerSet v: j/Json pointer: String x: j/Json -> (Result j/Json String)
  (if (= pointer "")
    (ok x)
    (match (splitPointer pointer)
      ((none) (err "pointer must begin with '/'"))
      ((some raw)
       (match (unescapeAll raw)
         ((none) (err "invalid ~ escape in pointer"))
         ((some toks) (setAt v toks x))))))
