(module asl-forms/bench/parenMutants
  :x [Lex Site Mutant lexOf opener? closer? openerFor balanced? segments trailSites setLine stepRng draw mutate eligible?]
  :i [(asl-forms/indent :a ind)])

; (:m :ref PAREN-BENCH :do "port of scratchpad/paren/guided.py mutant half: a segment is a column-0 form, a mutant deletes, duplicates or moves one closer of a line trail; the lexer is the one of asl-forms/indent (indent exports only guide), so the bench and the repair read delimiters the same way")
(schema Lex (:f first Int64) (:f codeEnd Int64) (:f delims (List (Pair Int64 Int64))) (:f inStr Bool))

(schema Site (:f line Int64) (:f col Int64) (:f ch Int64))

(schema Mutant (:f kind String) (:f text String))

fn opener? c: Int64 -> Bool
  (or (= c 40) (or (= c 91) (= c 123)))

fn closer? c: Int64 -> Bool
  (or (= c 41) (or (= c 93) (= c 125)))

fn openerFor c: Int64 -> Int64
  (cond ((= c 41) 40) ((= c 93) 91) (else 123))

fn closerText c: Int64 -> String
  (cond ((= c 40) ")") ((= c 91) "]") (else "}"))

fn lexLoop b: Bytes n: Int64 i: Int64 inStr: Bool first: Int64 codeEnd: Int64 acc: (List (Pair Int64 Int64)) -> Lex
  (if (>= i n)
    (Lex :first first :codeEnd (if inStr n codeEnd) :delims (listReverse acc) :inStr inStr)
    (let [(c (bytesGet b i))]
      (cond
        (inStr
          (cond
            ((= c 92) (lexLoop b n (+ i 2) true first codeEnd acc))
            ((= c 34) (lexLoop b n (+ i 1) false first (+ i 1) acc))
            (else (lexLoop b n (+ i 1) true first codeEnd acc))))
        ((= c 34) (lexLoop b n (+ i 1) true (if (< first 0) i first) (+ i 1) acc))
        ((= c 59) (Lex :first first :codeEnd codeEnd :delims (listReverse acc) :inStr false))
        ((or (= c 32) (or (= c 9) (= c 13))) (lexLoop b n (+ i 1) false first codeEnd acc))
        (else
          (lexLoop b n (+ i 1) false (if (< first 0) i first) (+ i 1)
                   (if (or (opener? c) (closer? c)) (cons (pair i c) acc) acc))))))

fn lexOf ln: String inStr: Bool -> Lex
  (let [(b (stringToBytes ln))]
    (lexLoop b (bytesLength b) 0 inStr (if inStr 0 -1) 0 (list)))

fn balStep acc: (Option (List Int64)) d: (Pair Int64 Int64) -> (Option (List Int64))
  (match acc
    ((none) (none))
    ((some st)
     (let [(c (pairSecond d))]
       (cond
         ((opener? c) (some (cons c st)))
         ((= (optionOr (listHead st) 0) (openerFor c)) (some (listDrop st 1)))
         (else (none))))))

fn balancedLines lines: (List String) inStr: Bool st: (List Int64) -> Bool
  (match (listHead lines)
    ((none) (listEmpty? st))
    ((some ln)
     (let [(lx (lexOf ln inStr))]
       (match (fold balStep (some st) lx.delims)
         ((none) false)
         ((some st1) (balancedLines (listDrop lines 1) lx.inStr st1))))))

fn balanced? text: String -> Bool
  (balancedLines (stringSplit text "\n") false (list))

; (:m :ref PAREN-BENCH :do "a new segment starts at a line whose first character is not blank, a comment or a closer, once the current one has lines")
fn segStart? ln: String -> Bool
  (not (listContains? (list "" " " "\t" ";" ")" "]" "}") (optionOr (stringSlice ln 0 1) "")))

fn segLoop lines: (List String) cur: (List String) out: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse (if (listEmpty? cur) out (cons (stringJoin (listReverse cur) "\n") out))))
    ((some ln)
     (if (and (segStart? ln) (not (listEmpty? cur)))
       (segLoop (listDrop lines 1) (list ln) (cons (stringJoin (listReverse cur) "\n") out))
       (segLoop (listDrop lines 1) (cons ln cur) out))))

fn segments text: String -> (List String)
  (segLoop (stringSplit text "\n") (list) (list))

fn trailOnly? b: Bytes i: Int64 end: Int64 -> Bool
  (cond
    ((>= i end) true)
    ((let [(c (bytesGet b i))] (or (= c 32) (closer? c))) (trailOnly? b (+ i 1) end))
    (else false))

fn lineSites ln: String li: Int64 lx: Lex -> (List Site)
  (let [(b (stringToBytes ln))]
    (map (fn [(d (Pair Int64 Int64))] -> Site (Site :line li :col (pairFirst d) :ch (pairSecond d)))
         (filter (fn [(d (Pair Int64 Int64))] -> Bool (and (closer? (pairSecond d)) (trailOnly? b (pairFirst d) lx.codeEnd))) lx.delims)))

fn sitesLoop lines: (List String) li: Int64 inStr: Bool acc: (List Site) -> (List Site)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some ln)
     (let [(lx (lexOf ln inStr))]
       (sitesLoop (listDrop lines 1) (+ li 1) lx.inStr
                  (if (< lx.first 0) acc (fold (fn [(a (List Site)) (s Site)] -> (List Site) (cons s a)) acc (lineSites ln li lx)))))))

; (:m :ref PAREN-BENCH :do "closers that end a line's code (only blanks and closers after them), in source order")
fn trailSites seg: String -> (List Site)
  (sitesLoop (stringSplit seg "\n") 0 false (list))

fn setLine lines: (List String) i: Int64 new: String -> (List String)
  (if (= i 0)
    (cons new (listDrop lines 1))
    (match (listHead lines)
      ((none) (list))
      ((some ln) (cons ln (setLine (listDrop lines 1) (- i 1) new)))))

fn cutAt ln: String col: Int64 -> String
  (str (optionOr (stringSlice ln 0 col) "") (optionOr (stringSlice ln (+ col 1) (stringLength ln)) ""))

fn putAt ln: String col: Int64 tok: String -> String
  (str (optionOr (stringSlice ln 0 col) "") tok (optionOr (stringSlice ln col (stringLength ln)) ""))

; (:m :ref PAREN-BENCH :do "32-bit LCG; a draw joins the high half of two steps, so ranges to 2^31 stay near uniform; the same seed gives the same mutants on every host")
fn stepRng s: Int64 -> Int64
  (& (+ (* s 1664525) 1013904223) 4294967295)

fn draw s: Int64 n: Int64 -> (Pair Int64 Int64)
  (let [(s1 (stepRng s)) (s2 (stepRng s1))]
    (pair (mod (+ (* (/ s1 65536) 65536) (/ s2 65536)) n) s2))

fn siteAt sites: (List Site) i: Int64 -> Site
  (optionOr (listGet sites i) (Site :line 0 :col 0 :ch 41))

; (:m :ref PAREN-BENCH :do "delete one trail closer, duplicate one in place, or move one to another line's trail; none when the segment has under two trail closers or a move has no other line")
fn mutate seg: String s: Int64 -> (Pair (Option Mutant) Int64)
  (let [(lines (stringSplit seg "\n"))
        (sites (trailSites seg))]
    (if (< (listLength sites) 2)
      (pair (none) s)
      (let [(dk (draw s 3))
            (ds (draw (pairSecond dk) (listLength sites)))
            (a (siteAt sites (pairFirst ds)))
            (ln (optionOr (listGet lines a.line) ""))]
        (cond
          ((= (pairFirst dk) 0)
           (pair (some (Mutant :kind "delete" :text (stringJoin (setLine lines a.line (cutAt ln a.col)) "\n"))) (pairSecond ds)))
          ((= (pairFirst dk) 1)
           (pair (some (Mutant :kind "insert" :text (stringJoin (setLine lines a.line (putAt ln a.col (closerText (openerFor a.ch)))) "\n"))) (pairSecond ds)))
          (else
            (let [(others (filter (fn [(x Site)] -> Bool (not (= x.line a.line))) sites))]
              (if (listEmpty? others)
                (pair (none) (pairSecond ds))
                (let [(dj (draw (pairSecond ds) (listLength others)))
                      (b (siteAt others (pairFirst dj)))
                      (cut (setLine lines a.line (cutAt ln a.col)))
                      (lb (optionOr (listGet cut b.line) ""))]
                  (pair (some (Mutant :kind "move" :text (stringJoin (setLine cut b.line (putAt lb b.col ")")) "\n"))) (pairSecond dj))))))))))

; (:m :ref PAREN-BENCH :do "a mutant source is a balanced segment of 4+ lines that indentation repair leaves unchanged, so any change guide makes to the mutant is a response to the mutation")
fn eligible? seg: String -> Bool
  (and (>= (listLength (stringSplit seg "\n")) 4)
       (and (balanced? seg)
            (= (ind/guide seg).text seg)))
