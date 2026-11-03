(module asl-forms/indent
  :x [IndentEdit Guided guide guideBroken editsAsn]
  :i [])

; (:m :ref PAREN-DESIGN :do "indentation-guided closer repair: every closer the indentation agrees with is kept; a line at column x closes the open frames whose column is >= x (a missing closer, inserted at the previous code line's trail) and reopens the frames the previous trail closed whose column + 2 <= x (an extra closer, removed); a closer with nothing open is deleted and a closer of the wrong kind is replaced; each edit names its opener and the line that decided it")

(schema Frame (:f col Int64) (:f ch Int64) (:f line Int64) (:f at Int64) (:f head String))

(schema Closed (:f frame Frame) (:f line Int64) (:f col Int64))

(schema LineLex (:f first Int64) (:f codeEnd Int64) (:f delims (List (Pair Int64 Int64))) (:f inStr Bool))

(schema IndentEdit (:f kind String) (:f line Int64) (:f col Int64) (:f tok String) (:f was String) (:f openLine Int64) (:f openCol Int64) (:f head String) (:f byLine Int64))

(schema Guided (:f text String) (:f edits (List IndentEdit)) (:f skipped (List IndentEdit)))

(schema St (:f stack (List Frame)) (:f lastCode Int64) (:f lastEnd Int64) (:f lastClosed (List Closed)) (:f edits (List IndentEdit)) (:f inStr Bool))

fn opener? c: Int64 -> Bool
  (or (= c 40) (or (= c 91) (= c 123)))

fn closer? c: Int64 -> Bool
  (or (= c 41) (or (= c 93) (= c 125)))

fn closerOf c: Int64 -> String
  (cond ((= c 40) ")") ((= c 91) "]") (else "}"))

fn openerFor c: Int64 -> Int64
  (cond ((= c 41) 40) ((= c 93) 91) (else 123))

fn charText c: Int64 -> String
  (closerOf (openerFor c))

fn lexLoop b: Bytes n: Int64 i: Int64 inStr: Bool first: Int64 codeEnd: Int64 acc: (List (Pair Int64 Int64)) -> LineLex
  (if (>= i n)
    (LineLex :first first :codeEnd (if inStr n codeEnd) :delims (listReverse acc) :inStr inStr)
    (let [(c (bytesGet b i))]
      (cond
        (inStr
          (cond
            ((= c 92) (lexLoop b n (+ i 2) true first codeEnd acc))
            ((= c 34) (lexLoop b n (+ i 1) false first (+ i 1) acc))
            (else (lexLoop b n (+ i 1) true first codeEnd acc))))
        ((= c 34) (lexLoop b n (+ i 1) true (if (< first 0) i first) (+ i 1) acc))
        ((= c 59) (LineLex :first first :codeEnd codeEnd :delims (listReverse acc) :inStr false))
        ((or (= c 32) (or (= c 9) (= c 13))) (lexLoop b n (+ i 1) false first codeEnd acc))
        (else
          (lexLoop b n (+ i 1) false (if (< first 0) i first) (+ i 1)
                   (if (or (opener? c) (closer? c)) (cons (pair i c) acc) acc))))))

fn trailFrom? b: Bytes i: Int64 end: Int64 -> Bool
  (cond
    ((>= i end) true)
    ((let [(c (bytesGet b i))] (or (= c 32) (closer? c))) (trailFrom? b (+ i 1) end))
    (else false))

fn headEnd b: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (let [(c (bytesGet b j))] (not (or (or (= c 32) (= c 9)) (or (opener? c) (or (closer? c) (= c 34)))))))
    (headEnd b n (+ j 1))
    j)

fn edit kind: String line: Int64 col: Int64 tok: String was: String f: (Option Frame) by: Int64 -> IndentEdit
  (match f
    ((some fr) (IndentEdit :kind kind :line line :col col :tok tok :was was :openLine fr.line :openCol fr.at :head fr.head :byLine by))
    ((none) (IndentEdit :kind kind :line line :col col :tok tok :was was :openLine -1 :openCol -1 :head "" :byLine by)))

fn reopenLoop st: St closed: (List Closed) x: Int64 li: Int64 -> St
  (match (listHead closed)
    ((none) st)
    ((some c)
     (if (<= (+ c.frame.at 2) x)
       (reopenLoop (with st :stack (cons c.frame st.stack) :edits (cons (edit "delete" c.line c.col "" (closerOf c.frame.ch) (some c.frame) li) st.edits))
                   (optionOr (listTail closed) (list)) x li)
       st)))

fn closeLoop st: St x: Int64 li: Int64 -> St
  (match (listHead st.stack)
    ((none) st)
    ((some f)
     (if (>= f.col x)
       (closeLoop (with st :stack (optionOr (listTail st.stack) (list))
                           :edits (cons (edit "insert" st.lastCode st.lastEnd (closerOf f.ch) "" (some f) li) st.edits))
                  x li)
       st)))

fn scanDelims ln: String st: St b: Bytes lx: LineLex li: Int64 cont: Bool ds: (List (Pair Int64 Int64)) -> St
  (match (listHead ds)
    ((none) st)
    ((some d)
     (let [(col (pairFirst d))
           (c (pairSecond d))
           (rest (optionOr (listTail ds) (list)))]
       (if (opener? c)
         (let [(eol (and (not cont) (= lx.codeEnd (+ col 1))))
               (fr (Frame :col (if eol lx.first col) :ch c :line li :at col :head (optionOr (stringSlice ln (+ col 1) (min (headEnd b lx.codeEnd (+ col 1)) (+ col 25))) "")))]
           (scanDelims ln (with st :stack (cons fr st.stack)) b lx li cont rest))
         (match (listHead st.stack)
           ((none) (scanDelims ln (with st :edits (cons (edit "delete" li col "" (charText c) (none) li) st.edits)) b lx li cont rest))
           ((some top)
            (let [(popped (with st :stack (optionOr (listTail st.stack) (list))))]
              (cond
                ((= top.ch (openerFor c))
                 (scanDelims ln (if (trailFrom? b col lx.codeEnd) (with popped :lastClosed (cons (Closed :frame top :line li :col col) popped.lastClosed)) popped) b lx li cont rest))
                (else (scanDelims ln (with popped :edits (cons (edit "replace" li col (closerOf top.ch) (charText c) (some top) li) popped.edits)) b lx li cont rest))))))))))

fn step st: St li: Int64 ln: String -> St
  (let [(b (stringToBytes ln))
        (lx (lexLoop b (bytesLength b) 0 st.inStr (if st.inStr 0 -1) 0 (list)))]
    (if (< lx.first 0)
      (with st :inStr lx.inStr)
      (let [(cont st.inStr)
            (judged (and (not cont) (and (>= st.lastCode 0) (not (closer? (bytesGet b lx.first))))))
            (st1 (if judged (closeLoop (reopenLoop st st.lastClosed lx.first li) lx.first li) st))
            (st2 (scanDelims ln (with st1 :lastClosed (list)) b lx li cont lx.delims))]
        (with st2 :lastCode li :lastEnd lx.codeEnd :inStr lx.inStr))))

fn walk st: St li: Int64 lines: (List String) -> St
  (match (listHead lines)
    ((none) st)
    ((some ln) (walk (step st li ln) (+ li 1) (optionOr (listTail lines) (list)))))

fn atCol? e: IndentEdit kind: String col: Int64 -> Bool
  (and (= e.kind kind) (= e.col col))

fn insertsAt es: (List IndentEdit) col: Int64 -> String
  (stringJoin (map (fn [(e IndentEdit)] -> String e.tok) (filter (fn [(e IndentEdit)] -> Bool (atCol? e "insert" col)) es)) "")

fn byteOut ln: String es: (List IndentEdit) i: Int64 -> String
  (match (listHead (filter (fn [(e IndentEdit)] -> Bool (and (!= e.kind "insert") (= e.col i))) es))
    ((some e) e.tok)
    ((none) (optionOr (stringSlice ln i (+ i 1)) "")))

fn applyLine ln: String es: (List IndentEdit) -> String
  (if (listEmpty? es)
    ln
    (let [(n (bytesLength (stringToBytes ln)))]
      (str (stringJoin (map (fn [(i Int64)] -> String (str (insertsAt es i) (byteOut ln es i))) (range 0 n)) "") (insertsAt es n))))

fn applyLines lines: (List String) li: Int64 edits: (List IndentEdit) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some ln) (applyLines (optionOr (listTail lines) (list)) (+ li 1) edits
                           (cons (applyLine ln (filter (fn [(e IndentEdit)] -> Bool (= e.line li)) edits)) acc))))

fn allEdits lines: (List String) -> (List IndentEdit)
  (let [(st0 (St :stack (list) :lastCode -1 :lastEnd 0 :lastClosed (list) :edits (list) :inStr false))
        (st1 (walk st0 0 lines))
        (st2 (if (>= st1.lastCode 0) (closeLoop st1 -1 -1) st1))]
    (listReverse st2.edits))

fn applied text: String lines: (List String) edits: (List IndentEdit) skipped: (List IndentEdit) -> Guided
  (if (listEmpty? edits)
    (Guided :text text :edits edits :skipped skipped)
    (Guided :text (stringJoin (applyLines lines 0 edits (list)) "\n") :edits edits :skipped skipped))

; (:m :ref PAREN-DESIGN :do "closers still open at the end of the text go to the last code line; with no code line there is nothing to close")
fn guide text: String -> Guided
  (let [(lines (stringSplit text "\n"))]
    (applied text lines (allEdits lines) (list)))

; (:m :ref PAREN-DESIGN :do "a segment starts at a column-0 code line outside a string that is not a closer; its delimiters balance when a plain stack check of its own lines passes")
fn segWalk lines: (List String) inStr: Bool seg: Int64 stack: (List Int64) bad: Bool acc: (List Int64) badAcc: (List Int64) -> (Pair (List Int64) (List Int64))
  (match (listHead lines)
    ((none) (pair (listReverse acc) (if (or bad (not (listEmpty? stack))) (cons seg badAcc) badAcc)))
    ((some ln)
     (let [(b (stringToBytes ln))
           (lx (lexLoop b (bytesLength b) 0 inStr (if inStr 0 -1) 0 (list)))
           (starts (and (not inStr) (and (= lx.first 0) (not (closer? (bytesGet b 0))))))
           (closing (and starts (or bad (not (listEmpty? stack)))))
           (seg1 (if starts (+ seg 1) seg))
           (bad0 (if starts false bad))
           (stack0 (if starts (list) stack))
           (res (fold (fn [(sb (Pair (List Int64) Bool)) (d (Pair Int64 Int64))] -> (Pair (List Int64) Bool)
                        (let [(c (pairSecond d)) (st (pairFirst sb))]
                          (cond
                            ((opener? c) (pair (cons c st) (pairSecond sb)))
                            ((= (optionOr (listHead st) 0) (openerFor c)) (pair (optionOr (listTail st) (list)) (pairSecond sb)))
                            (else (pair st true)))))
                      (pair stack0 bad0) lx.delims))]
       (segWalk (optionOr (listTail lines) (list)) lx.inStr seg1 (pairFirst res) (pairSecond res) (cons seg1 acc) (if closing (cons seg badAcc) badAcc)))))

fn segOf segs: (List Int64) line: Int64 -> Int64
  (optionOr (listGet segs line) -1)

; (:m :ref PAREN-DESIGN :do "applies only the edits inside segments whose delimiters do not balance; edits in balanced segments, where the parens are right and the indentation is house style or a misnest the parens hide, come back as skipped")
fn guideBroken text: String -> Guided
  (let [(lines (stringSplit text "\n"))
        (sb (segWalk lines false -1 (list) false (list) (list)))
        (segs (pairFirst sb))
        (broken (pairSecond sb))
        (es (allEdits lines))
        (inBroken (fn [(e IndentEdit)] -> Bool (listContains? broken (segOf segs e.line))))]
    (applied text lines (filter inBroken es) (filter (fn [(e IndentEdit)] -> Bool (not (inBroken e))) es)))

fn quoteTok s: String -> String
  (str "\"" s "\"")

fn editAsn e: IndentEdit -> String
  (str "(:" e.kind " " (quoteTok (if (= e.kind "insert") e.tok e.was))
       (if (= e.kind "replace") (str " :with " (quoteTok e.tok)) "")
       " :line " (stringFromInt64 (+ e.line 1)) " :col " (stringFromInt64 (+ e.col 1))
       (if (>= e.openLine 0)
         (str " :opener (:line " (stringFromInt64 (+ e.openLine 1)) " :col " (stringFromInt64 (+ e.openCol 1)) " :head " (quoteTok e.head) ")")
         " :stray true")
       (cond ((< e.byLine 0) " :by :eof") ((= e.byLine e.line) "") (else (str " :by (:line " (stringFromInt64 (+ e.byLine 1)) ")")))
       ")")

fn editsAsn es: (List IndentEdit) -> String
  (str "(" (stringJoin (map editAsn es) " ") ")")
