(module asl-text/wrap
  :x [wordWrap wrapIndent]
  :i [])

fn cpLen s: String -> Int64
  (listLength (stringChars s))

fn cpSlice s: String a: Int64 b: Int64 -> String
  (stringJoin (optionOr (listSlice (stringChars s) a b) (list)) "")

fn splitLong w: String width: Int64 -> (List String)
  (let [(n (cpLen w))]
    (if (<= n width) (list w)
      (cons (cpSlice w 0 width) (splitLong (cpSlice w width n) width))))

fn wordsOf line: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit line " "))

fn flushCur cur: String acc: (List String) -> (List String)
  (if (stringEmpty? cur) acc (cons cur acc))

fn wrapWords words: (List String) width: Int64 cur: String acc: (List String) -> (List String)
  (match (listHead words)
    ((none) (listReverse (flushCur cur acc)))
    ((some w) (stepWord w (optionOr (listTail words) (list)) width cur acc)))

fn stepWord w: String rest: (List String) width: Int64 cur: String acc: (List String) -> (List String)
  (if (> (cpLen w) width)
    (longWord w rest width cur acc)
    (shortWord w rest width cur acc))

fn shortWord w: String rest: (List String) width: Int64 cur: String acc: (List String) -> (List String)
  (cond
    ((stringEmpty? cur) (wrapWords rest width w acc))
    ((<= (+ (cpLen cur) 1 (cpLen w)) width) (wrapWords rest width (str cur " " w) acc))
    (else (wrapWords rest width w (cons cur acc))))

fn longWord w: String rest: (List String) width: Int64 cur: String acc: (List String) -> (List String)
  (let [(chunks (splitLong w width))
        (lastChunk (optionOr (listLast chunks) ""))
        (full (optionOr (listSlice chunks 0 (- (listLength chunks) 1)) (list)))]
    (wrapWords rest width lastChunk (listAppend (listReverse full) (flushCur cur acc))))

; (:m :do "a line with no words stays one blank line so hard breaks survive")
fn wrapLine line: String width: Int64 -> (List String)
  (let [(ws (wordsOf line))]
    (if (listEmpty? ws) (list "")
      (wrapWords ws width "" (list))))

fn wordWrap s: String width: Int64 -> (List String)
  (if (< width 1) (list s)
    (listFlatMap (fn [(l String)] -> (List String) (wrapLine l width)) (stringSplit s "\n")))

fn wrapIndent s: String width: Int64 prefix: String -> (List String)
  (map (fn [(l String)] -> String (str prefix l)) (wordWrap s width))
