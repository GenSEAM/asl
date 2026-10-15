(module asl-html/markdown
  :x [inline blocks]
  :i [(asl-html/html :a h)])

fn cut s: String from: Int64 to: Int64 -> String
  (optionOr (stringSlice s from to) "")

fn rest s: String from: Int64 -> String
  (cut s from (stringLength s))

fn earliest s: String marks: (List String) -> (Option (Pair Int64 String))
  (fold (fn [(best (Option (Pair Int64 String))) (mark String)] -> (Option (Pair Int64 String))
          (mt (stringIndexOf s mark)
            ((none) best)
            ((some at) (mt best ((none) (some (pair at mark))) ((some b) (if (< at (pairFirst b)) (some (pair at mark)) best))))))
        (none) marks)

fn closeAfter s: String start: Int64 mark: String -> (Option Int64)
  (optionMap (fn [(i Int64)] -> Int64 (+ i start)) (stringIndexOf (rest s start) mark))

fn span s: String at: Int64 mark: String -> (Option (Pair h/Node Int64))
  (cond
    ((= mark "`") (optionMap (fn [(e Int64)] -> (Pair h/Node Int64) (pair (h/code [] [(h/text (cut s (+ at 1) e))]) (+ e 1))) (closeAfter s (+ at 1) "`")))
    ((= mark "*") (optionMap (fn [(e Int64)] -> (Pair h/Node Int64) (pair (h/em [] (inline (cut s (+ at 1) e))) (+ e 1))) (closeAfter s (+ at 1) "*")))
    ((= mark "**") (optionMap (fn [(e Int64)] -> (Pair h/Node Int64) (pair (h/strong [] (inline (cut s (+ at 2) e))) (+ e 2))) (closeAfter s (+ at 2) "**")))
    (else
      (mt (closeAfter s at "](")
        ((none) (none))
        ((some mid) (optionMap (fn [(e Int64)] -> (Pair h/Node Int64) (pair (h/a [(h/href (cut s (+ mid 2) e))] (inline (cut s (+ at 1) mid))) (+ e 1))) (closeAfter s (+ mid 2) ")"))))))

fn inline s: String -> (List h/Node)
  (mt (earliest s ["`" "**" "[" "*"])
    ((none) (if (stringEmpty? s) [] [(h/text s)]))
    ((some found)
      (let [(at (pairFirst found)) (mark (pairSecond found)) (before (cut s 0 at))
            (lead (if (stringEmpty? before) [] [(h/text before)]))]
        (mt (span s at mark)
          ((some done) (listAppend lead (cons (pairFirst done) (inline (rest s (pairSecond done))))))
          ((none) (listAppend lead (cons (h/text mark) (inline (rest s (+ at (stringLength mark)))))))))))

fn listItem? line: String -> Bool
  (or (stringStartsWith? line "- ") (stringStartsWith? line "* "))

fn digitsThenDot? line: String -> Bool
  (mt (stringIndexOf line ". ")
    ((none) false)
    ((some at) (and (> at 0) (and (< at 4) (some? (stringToInt64 (cut line 0 at)))))))

fn special? line: String -> Bool
  (or (stringStartsWith? line "#") (or (stringStartsWith? line "```") (or (stringStartsWith? line "|") (or (listItem? line) (or (digitsThenDot? line) (or (stringStartsWith? line ">") (= line "---")))))))

fn takeWhile lines: (List String) keep: (fn [String] -> Bool) acc: (List String) -> (Pair (List String) (List String))
  (mt (listHead lines)
    ((none) (pair (listReverse acc) []))
    ((some line) (if (keep line) (takeWhile (listDrop lines 1) keep (cons line acc)) (pair (listReverse acc) lines))))

fn afterMarker line: String -> String
  (mt (stringIndexOf line " ") ((some at) (stringTrim (rest line (+ at 1)))) ((none) line))

fn cells line: String -> (List String)
  (let [(trimmed (stringTrim line))
        (inner (cut trimmed 1 (- (stringLength trimmed) (if (stringEndsWith? trimmed "|") 1 0))))]
    (map stringTrim (stringSplit inner "|")))

fn tableNode rows: (List String) -> h/Node
  (let [(headRow (cells (optionOr (listHead rows) "")))
        (bodyRows (filter (fn [(r String)] -> Bool (not (stringContains? r "---"))) (listDrop rows 1)))]
    (h/div [(h/cls "tablewrap")]
      [(h/table []
        [(h/thead [] [(h/tr [] (map (fn [(c String)] -> h/Node (h/th [] (inline c))) headRow))])
         (h/tbody [] (map (fn [(r String)] -> h/Node (h/tr [] (map (fn [(c String)] -> h/Node (h/td [] (inline c))) (cells r)))) bodyRows))])]))

fn headingNode line: String -> h/Node
  (cond
    ((stringStartsWith? line "#### ") (h/h4 [] (inline (afterMarker line))))
    ((stringStartsWith? line "### ") (h/h3 [] (inline (afterMarker line))))
    (else (h/h2 [] (inline (afterMarker line)))))

fn fence lines: (List String) -> (Pair h/Node (List String))
  (let [(open (optionOr (listHead lines) "```"))
        (lang (stringTrim (rest open 3)))
        (split (takeWhile (listDrop lines 1) (fn [(l String)] -> Bool (not (stringStartsWith? l "```"))) []))]
    (pair (h/pre (if (stringEmpty? lang) [] [(h/attr "data-lang" lang)]) [(h/code [] [(h/text (stringJoin (pairFirst split) "\n"))])])
          (listDrop (pairSecond split) 1)))

fn blocks lines: (List String) -> (List h/Node)
  (mt (listHead lines)
    ((none) [])
    ((some line)
      (cond
        ((stringEmpty? (stringTrim line)) (blocks (listDrop lines 1)))
        ((stringStartsWith? line "```") (let [(f (fence lines))] (cons (pairFirst f) (blocks (pairSecond f)))))
        ((stringStartsWith? line "# ") (blocks (listDrop lines 1)))
        ((stringStartsWith? line "#") (cons (headingNode line) (blocks (listDrop lines 1))))
        ((= line "---") (cons (h/hr []) (blocks (listDrop lines 1))))
        ((stringStartsWith? line "|")
          (let [(t (takeWhile lines (fn [(l String)] -> Bool (stringStartsWith? l "|")) []))] (cons (tableNode (pairFirst t)) (blocks (pairSecond t)))))
        ((listItem? line)
          (let [(t (takeWhile lines listItem? []))] (cons (h/ul [] (map (fn [(l String)] -> h/Node (h/li [] (inline (afterMarker l)))) (pairFirst t))) (blocks (pairSecond t)))))
        ((digitsThenDot? line)
          (let [(t (takeWhile lines digitsThenDot? []))] (cons (h/ol [] (map (fn [(l String)] -> h/Node (h/li [] (inline (afterMarker l)))) (pairFirst t))) (blocks (pairSecond t)))))
        ((stringStartsWith? line ">")
          (let [(t (takeWhile lines (fn [(l String)] -> Bool (stringStartsWith? l ">")) []))]
            (cons (h/blockquote [] [(h/p [] (inline (stringJoin (map (fn [(l String)] -> String (stringTrim (rest l 1))) (pairFirst t)) " ")))]) (blocks (pairSecond t)))))
        (else
          (let [(t (takeWhile lines (fn [(l String)] -> Bool (and (not (stringEmpty? (stringTrim l))) (not (special? l)))) []))]
            (cons (h/p [] (inline (stringJoin (map stringTrim (pairFirst t)) " "))) (blocks (pairSecond t))))))))
