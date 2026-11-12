(module asl-media/captions
  :x [Cue Word GroupLimits parseSrt parseVtt writeSrt writeVtt groupWords cueOverlaps cueViolations formatTime parseTime msFromSeconds escapeVtt unescapeVtt]
  :i [])

; (:m :ref workspace-20261031-subtitleWriter :do "times are whole milliseconds: Int64 all the way, so a write never rounds and parse then write is a fixed point; seconds from a Float64 go through msFromSeconds, half up")
schema Cue
  (:f startMs Int64)
  (:f endMs Int64)
  (:f text String)
  (:f settings String)

schema Word
  (:f text String)
  (:f startMs Int64)
  (:f endMs Int64)

schema GroupLimits
  (:f maxChars Int64)
  (:f maxLines Int64)
  (:f minMs Int64)
  (:f maxMs Int64)
  (:f maxCps Int64)
  (:f pauseMs Int64)

fn msFromSeconds s: Float64 -> Int64
  (optionOr (float64ToInt64 (floor (+ (* s 1000.0) 0.5))) 0)

fn pad n: Int64 width: Int64 -> String
  (let [(t (stringFromInt64 n))]
    (if (>= (stringLength t) width) t (str (stringJoin (zeros (- width (stringLength t))) "") t)))

fn zeros n: Int64 -> (List String)
  (if (<= n 0) (list) (cons "0" (zeros (- n 1))))

fn formatTime ms: Int64 sep: String -> String
  (let [(h (/ ms 3600000))
        (m (mod (/ ms 60000) 60))
        (s (mod (/ ms 1000) 60))
        (f (mod ms 1000))]
    (str (pad h 2) ":" (pad m 2) ":" (pad s 2) sep (pad f 3)))

; (:m :ref workspace-20261031-subtitleWriter :do "a timestamp is HH:MM:SS or MM:SS then , or . then exactly three digits; anything else is an err naming the text, never a guess")
fn parseTime t: String -> (Result Int64 String)
  (let [(norm (stringReplace t "," "."))
        (halves (stringSplit norm "."))
        (hms (stringSplit (optionOr (listGet halves 0) "") ":"))
        (frac (optionOr (listGet halves 1) ""))]
    (if (or (!= (listLength halves) 2) (!= (stringLength frac) 3) (< (listLength hms) 2) (> (listLength hms) 3))
      (err (str "captionTime: " t))
      (let [(nums (map (fn [(x String)] -> Int64 (optionOr (stringToInt64 x) -1)) (listAppend hms (list frac))))]
        (if (listAny? (fn [(n Int64)] -> Bool (< n 0)) nums)
          (err (str "captionTime: " t))
          (let [(f (optionOr (listGet nums (- (listLength nums) 1)) 0))
                (s (optionOr (listGet nums (- (listLength nums) 2)) 0))
                (m (optionOr (listGet nums (- (listLength nums) 3)) 0))
                (h (if (= (listLength hms) 3) (optionOr (listGet nums 0) 0) 0))
                (mm (if (= (listLength hms) 3) m (optionOr (listGet nums 0) 0)))]
            (ok (+ (* h 3600000) (+ (* mm 60000) (+ (* s 1000) f)))))))))

fn normalise raw: String -> String
  (let [(noBom (if (stringStartsWith? raw "\xef\xbb\xbf") (optionOr (stringSlice raw 3 (stringLength raw)) raw) raw))]
    (stringReplace (stringReplace noBom "\r\n" "\n") "\r" "\n"))

fn blocks text: String -> (List (List String))
  (let [(lines (stringLines text))]
    (listReverse (blockLoop lines (list) (list))))

fn blockLoop lines: (List String) cur: (List String) out: (List (List String)) -> (List (List String))
  (match (listHead lines)
    ((none) (if (listEmpty? cur) out (cons (listReverse cur) out)))
    ((some l)
      (let [(rest (optionOr (listTail lines) (list)))]
        (if (stringEmpty? (stringTrim l))
          (blockLoop rest (list) (if (listEmpty? cur) out (cons (listReverse cur) out)))
          (blockLoop rest (cons l cur) out)))))

fn arrow? l: String -> Bool
  (stringContains? l " --> ")

fn cueOfBlock b: (List String) -> (Result (Option Cue) String)
  (let [(timeIdx (optionOr (listIndexOf2 b) -1))]
    (if (< timeIdx 0)
      (ok none)
      (let [(tl (optionOr (listGet b timeIdx) ""))
            (parts (stringSplit tl " --> "))
            (a (stringTrim (optionOr (listGet parts 0) "")))
            (rest (stringTrim (optionOr (listGet parts 1) "")))
            (endTok (optionOr (listHead (stringSplit rest " ")) ""))
            (settings (stringTrim (optionOr (stringSlice rest (stringLength endTok) (stringLength rest)) "")))]
        (match (parseTime a)
          ((err e) (err e))
          ((ok s)
            (match (parseTime endTok)
              ((err e) (err e))
              ((ok e)
                (ok (some (Cue :startMs s :endMs e :text (stringJoin (listDrop b (+ timeIdx 1)) "\n") :settings settings))))))))))

fn listIndexOf2 b: (List String) -> (Option Int64)
  (let [(first (optionOr (listHead (filter (fn [(l String)] -> Bool (arrow? l)) (listTake b 2))) ""))]
    (if (stringEmpty? first) none
      (if (arrow? (optionOr (listGet b 0) "")) (some 0) (some 1))))

fn cuesOf bs: (List (List String)) acc: (List Cue) skip: (List String) -> (Result (List Cue) String)
  (match (listHead bs)
    ((none) (ok (listReverse acc)))
    ((some b)
      (let [(rest (optionOr (listTail bs) (list)))
            (head (optionOr (listHead b) ""))]
        (if (or (stringStartsWith? head "NOTE") (stringStartsWith? head "STYLE") (stringStartsWith? head "REGION") (stringStartsWith? head "WEBVTT"))
          (cuesOf rest acc skip)
          (match (cueOfBlock b)
            ((err e) (err e))
            ((ok oc)
              (match oc
                ((none) (cuesOf rest acc skip))
                ((some c) (cuesOf rest (cons c acc) skip)))))))))

; (:m :ref workspace-20261031-subtitleWriter :do "BOM and CRLF are accepted on input; NOTE, STYLE and REGION blocks and cue ids are dropped; cue settings after the end time are kept verbatim; an index line before an SRT time line is dropped and rewritten by the writer")
fn parseSrt raw: String -> (Result (List Cue) String)
  (cuesOf (blocks (normalise raw)) (list) (list))

fn parseVtt raw: String -> (Result (List Cue) String)
  (let [(t (normalise raw))]
    (if (not (stringStartsWith? t "WEBVTT"))
      (err "captionFormat: a WebVTT file starts with WEBVTT")
      (match (cuesOf (blocks t) (list) (list))
        ((err e) (err e))
        ((ok cs) (ok (map (fn [(c Cue)] -> Cue (with c :text (unescapeVtt c.text))) cs))))))

fn escapeVtt s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace s "&" "&amp;") "<" "&lt;") ">" "&gt;") "\n\n" "\n")

fn unescapeVtt s: String -> String
  (stringReplace (stringReplace (stringReplace s "&lt;" "<") "&gt;" ">") "&amp;" "&")

fn cleanSrt s: String -> String
  (stringReplace s "\n\n" "\n")

fn writeSrt cues: (List Cue) -> (Result String String)
  (match (listHead (filter (fn [(c Cue)] -> Bool (stringContains? c.text "-->")) cues))
    ((some c) (err (str "captionText: a cue text contains -->: " c.text)))
    ((none)
      (ok (stringJoin (map (fn [(p (Pair Int64 Cue))] -> String
                              (srtBlock (pairFirst p) (pairSecond p)))
                            (numbered cues)) "\n"))))

fn srtBlock i: Int64 c: Cue -> String
  (str (stringFromInt64 (+ i 1)) "\n" (formatTime c.startMs ",") " --> " (formatTime c.endMs ",") "\n" (cleanSrt c.text) "\n")

fn writeVtt cues: (List Cue) -> String
  (str "WEBVTT\n\n"
       (stringJoin (map (fn [(c Cue)] -> String
                          (str (formatTime c.startMs ".") " --> " (formatTime c.endMs ".")
                               (if (stringEmpty? c.settings) "" (str " " c.settings)) "\n"
                               (escapeVtt c.text) "\n"))
                        cues) "\n"))

fn numbered xs: (List Cue) -> (List (Pair Int64 Cue))
  (enumLoop xs 0 (list))

fn enumLoop xs: (List Cue) i: Int64 acc: (List (Pair Int64 Cue)) -> (List (Pair Int64 Cue))
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some c) (enumLoop (optionOr (listTail xs) (list)) (+ i 1) (cons (pair i c) acc))))

; (:m :ref workspace-20261031-subtitleWriter :do "indexes of cues that start before the previous cue ends")
fn cueOverlaps cues: (List Cue) -> (List Int64)
  (overlapLoop cues 0 -1 (list))

fn overlapLoop cues: (List Cue) i: Int64 prevEnd: Int64 acc: (List Int64) -> (List Int64)
  (match (listHead cues)
    ((none) (listReverse acc))
    ((some c)
      (overlapLoop (optionOr (listTail cues) (list)) (+ i 1) c.endMs (if (and (>= prevEnd 0) (< c.startMs prevEnd)) (cons i acc) acc))))


fn charsOf words: (List Word) -> Int64
  (if (listEmpty? words) 0
    (+ (fold (fn [(a Int64) (w Word)] -> Int64 (+ a (stringLength w.text))) 0 words) (- (listLength words) 1)))

; (:m :ref workspace-20261031-subtitleWriter :do "lines break greedily at spaces so no line passes maxChars unless one word alone does; the words are never reordered or dropped")
fn wrapLines words: (List Word) maxChars: Int64 -> (List String)
  (wrapLoop words maxChars "" (list))

fn wrapLoop words: (List Word) maxChars: Int64 cur: String out: (List String) -> (List String)
  (match (listHead words)
    ((none) (listReverse (if (stringEmpty? cur) out (cons cur out))))
    ((some w)
      (let [(rest (optionOr (listTail words) (list)))]
        (cond
          ((stringEmpty? cur) (wrapLoop rest maxChars w.text out))
          ((<= (+ (stringLength cur) (+ 1 (stringLength w.text))) maxChars) (wrapLoop rest maxChars (str cur " " w.text) out))
          (else (wrapLoop rest maxChars w.text (cons cur out)))))))

fn lastWord ws: (List Word) -> Word
  (optionOr (listLast ws) (Word :text "" :startMs 0 :endMs 0))

fn firstWord ws: (List Word) -> Word
  (optionOr (listHead ws) (Word :text "" :startMs 0 :endMs 0))

fn sentenceEnd? w: Word -> Bool
  (or (stringEndsWith? w.text ".") (stringEndsWith? w.text "?") (stringEndsWith? w.text "!"))

fn fits? words: (List Word) lim: GroupLimits -> Bool
  (let [(lines (wrapLines words lim.maxChars))
        (dur (- (lastWord words).endMs (firstWord words).startMs))]
    (and (<= (listLength lines) lim.maxLines)
         (<= dur lim.maxMs)
         (or (<= dur 0) (<= (* (charsOf words) 1000) (* lim.maxCps dur)))))

fn cueOf words: (List Word) lim: GroupLimits -> Cue
  (Cue :startMs (firstWord words).startMs :endMs (lastWord words).endMs :text (stringJoin (wrapLines words lim.maxChars) "\n") :settings "")

fn ! groupLoop ws: (List Word) cur: (List Word) lim: GroupLimits out: (List Cue) -> (List Cue)
  (match (listHead ws)
    ((none) (listReverse (if (listEmpty? cur) out (cons (cueOf cur lim) out))))
    ((some w)
      (let [(rest (optionOr (listTail ws) (list)))
            (cand (listAppend cur (list w)))
            (breakHere (and (not (listEmpty? cur))
                            (or (not (fits? cand lim))
                                (and (sentenceEnd? (lastWord cur)) (>= (- (lastWord cur).endMs (firstWord cur).startMs) lim.minMs))
                                (>= (- w.startMs (lastWord cur).endMs) lim.pauseMs))))]
        (if breakHere
          (groupLoop rest (list w) lim (cons (cueOf cur lim) out))
          (groupLoop rest cand lim out)))))

fn settle cues: (List Cue) lim: GroupLimits -> (List Cue)
  (settleLoop cues lim (list))

fn settleLoop cues: (List Cue) lim: GroupLimits out: (List Cue) -> (List Cue)
  (match (listHead cues)
    ((none) (listReverse out))
    ((some c)
      (let [(rest (optionOr (listTail cues) (list)))
            (want (+ c.startMs lim.minMs))
            (limit (match (listHead rest) ((some n) n.startMs) ((none) want)))
            (endMs (if (< c.endMs want) (if (< want limit) want (if (< c.endMs limit) limit c.endMs)) c.endMs))]
        (settleLoop rest lim (cons (Cue :startMs c.startMs :endMs endMs :text c.text :settings c.settings) out)))))

; (:m :ref workspace-20261031-subtitleWriter :do "greedy cue grouping: a cue closes when the next word would break maxLines, maxMs or maxCps, after a sentence end once minMs is reached, or at a pause of pauseMs; a cue shorter than minMs is stretched up to the next cue's start; no word is moved or dropped, and a word that alone breaks a limit still gets its own cue (cueViolations names it)")
fn ! groupWords words: (List Word) lim: GroupLimits -> (List Cue)
  (settle (groupLoop words (list) lim (list)) lim)

fn cueViolations cues: (List Cue) lim: GroupLimits -> (List Int64)
  (violationLoop cues lim 0 (list))

fn violationLoop cues: (List Cue) lim: GroupLimits i: Int64 acc: (List Int64) -> (List Int64)
  (match (listHead cues)
    ((none) (listReverse acc))
    ((some c)
      (let [(lines (stringLines c.text))
            (dur (- c.endMs c.startMs))
            (chars (stringLength (stringReplace c.text "\n" " ")))
            (bad (or (> (listLength lines) lim.maxLines)
                     (listAny? (fn [(l String)] -> Bool (> (stringLength l) lim.maxChars)) lines)
                     (> dur lim.maxMs)
                     (< dur lim.minMs)
                     (and (> dur 0) (> (* chars 1000) (* lim.maxCps dur))))) ]
        (violationLoop (optionOr (listTail cues) (list)) lim (+ i 1) (if bad (cons i acc) acc)))))
