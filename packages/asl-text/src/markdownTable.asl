(module asl-text/markdownTable :x [renderTable parseTable parseAligns] :i [])

fn colWidth rows: (List (List String)) i: Int64 -> Int64
  (fold (fn [(acc Int64) (row (List String))] -> Int64
          (max acc (stringLength (optionOr (listGet row i) ""))))
        0
        rows)

fn padLeft s: String n: Int64 -> String
  (if (<= n 0) s (str (stringRepeat " " n) s))

fn padRight s: String n: Int64 -> String
  (if (<= n 0) s (str s (stringRepeat " " n)))

fn padCell cell: String width: Int64 align: String -> String
  (let [(pad (- width (stringLength cell)))]
    (if (<= pad 0)
      cell
      (if (= align "r")
        (padLeft cell pad)
        (if (= align "c")
          (let [(left (/ pad 2)) (right (- pad left))]
            (str (stringRepeat " " left) cell (stringRepeat " " right)))
          (padRight cell pad)))))

fn minWidth align: String -> Int64
  (if (= align "r") 2 (if (= align "c") 3 1))

fn alignMarker width: Int64 align: String -> String
  (if (= align "r")
    (str (stringRepeat "-" (max 1 (- width 1))) ":")
    (if (= align "c")
      (str ":" (stringRepeat "-" (max 1 (- width 2))) ":")
      (stringRepeat "-" (max 1 width))))

fn joinCells cells: (List String) widths: (List Int64) aligns: (List String) -> String
  (stringJoin (map (fn [(i Int64)] -> String
                     (padCell (optionOr (listGet cells i) "")
                              (optionOr (listGet widths i) 0)
                              (optionOr (listGet aligns i) "")))
                   (range 0 (listLength widths)))
              " | ")

fn joinMarkers widths: (List Int64) aligns: (List String) -> String
  (stringJoin (map (fn [(i Int64)] -> String
                     (alignMarker (optionOr (listGet widths i) 0)
                                  (optionOr (listGet aligns i) "")))
                   (range 0 (listLength widths)))
              " | ")

fn renderRow cells: (List String) widths: (List Int64) aligns: (List String) -> String
  (str "| " (joinCells cells widths aligns) " |")

fn renderSeparator widths: (List Int64) aligns: (List String) -> String
  (str "| " (joinMarkers widths aligns) " |")

fn renderTable rows: (List (List String)) aligns: (List String) -> String
  (if (listEmpty? rows)
    ""
    (let [(first (optionOr (listHead rows) (list)))
          (ncols (listLength first))
          (widths (map (fn [(i Int64)] -> Int64
                         (max (colWidth rows i)
                              (minWidth (optionOr (listGet aligns i) ""))))
                       (range 0 ncols)))
          (rest (optionOr (listTail rows) (list)))
          (body (map (fn [(row (List String))] -> String (renderRow row widths aligns)) rest))]
      (stringJoin (cons (renderRow first widths aligns)
                        (cons (renderSeparator widths aligns) body))
                  "\n")))

fn splitCells line: String -> (List String)
  (let [(t (stringTrim line))
        (parts (map (fn [(p String)] -> String (stringTrim p)) (stringSplit line "|")))
        (noLead (if (stringStartsWith? t "|")
                  (optionOr (listTail parts) (list))
                  parts))
        (noTrail (if (stringEndsWith? t "|")
                   (listReverse (optionOr (listTail (listReverse noLead)) (list)))
                   noLead))]
    noTrail)

fn isDashCell c: String -> Bool
  (and (not (stringEmpty? c))
       (and (stringContains? c "-")
            (listAll? (fn [(ch String)] -> Bool (or (= ch "-") (= ch ":"))) (stringChars c))))

fn isSeparator line: String -> Bool
  (let [(cells (splitCells line))]
    (and (not (listEmpty? cells))
         (listAll? (fn [(c String)] -> Bool (isDashCell c)) cells)))

fn alignOfCell c: String -> String
  (let [(left (stringStartsWith? c ":"))
        (right (stringEndsWith? c ":"))]
    (if (and left right) "c" (if right "r" "l")))

fn nonEmptyLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit text "\n"))

fn parseTable text: String -> (Result (List (List String)) String)
  (let [(lines (nonEmptyLines text))]
    (if (< (listLength lines) 2)
      (err "parseTable: expected a header row and a separator row")
      (let [(header (optionOr (listHead lines) ""))
            (second (optionOr (listGet lines 1) ""))]
        (if (not (isSeparator second))
          (err "parseTable: second row is not a separator")
          (ok (map splitCells (cons header (listDrop lines 2))))))))

fn parseAligns text: String -> (Result (List String) String)
  (let [(lines (nonEmptyLines text))]
    (if (< (listLength lines) 2)
      (err "parseAligns: expected a header row and a separator row")
      (let [(second (optionOr (listGet lines 1) ""))]
        (if (not (isSeparator second))
          (err "parseAligns: second row is not a separator")
          (ok (map alignOfCell (splitCells second)))))))
