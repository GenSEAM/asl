(module asl-media/tests/captionsTest
  :x [runTests]
  :i [(asl-media/captions :a cp)])

fn srt -> String
  "1\n00:00:01,000 --> 00:00:02,500\nHello there\n\n2\n00:00:03,000 --> 00:00:04,250\nsecond line\nof two\n\n3\n01:02:03,004 --> 01:02:05,999\nlast & final\n"

fn vtt -> String
  "WEBVTT\n\n00:00:01.000 --> 00:00:02.500 align:start position:10%\nHello there\n\n00:00:03.000 --> 00:00:04.250\nsecond line\nof two\n\n01:02:03.004 --> 01:02:05.999\nlast &amp; final &lt;s&gt;\n"

fn vttNoisy -> String
  "\xef\xbb\xbfWEBVTT - header text\r\n\r\nNOTE a comment\r\nover two lines\r\n\r\nSTYLE\r\n::cue { color: red }\r\n\r\nintro\r\n00:00:01.000 --> 00:00:02.500 align:start position:10%\r\nHello there\r\n\r\n00:00:03.000 --> 00:00:04.250\r\nsecond line\r\nof two\r\n\r\n01:02:03.004 --> 01:02:05.999\r\nlast &amp; final &lt;s&gt;\r\n"

fn srtCrlf -> String
  (stringReplace (str "\xef\xbb\xbf" (srt)) "\n" "\r\n")

fn cuesOk r: (Result (List cp/Cue) String) -> (List cp/Cue)
  (match r
    ((ok cs) cs)
    ((err e) (do (assert false e) (list))))

fn textOf r: (Result String String) -> String
  (match r ((ok s) s) ((err e) e))

fn ! testRoundTrip! -> Bool
  (let [(a (cuesOk (cp/parseSrt (srt))))
        (b (cuesOk (cp/parseSrt (srtCrlf))))
        (v (cuesOk (cp/parseVtt (vtt))))
        (n (cuesOk (cp/parseVtt (vttNoisy))))]
    (do
      (assert (= (listLength a) 3) "three SRT cues")
      (assert (= (textOf (cp/writeSrt a)) (srt)) "SRT parse then write is a fixed point")
      (assert (= (textOf (cp/writeSrt b)) (srt)) "BOM and CRLF input give the same SRT")
      (assert (= (textOf (cp/writeVtt v)) (vtt)) "VTT parse then write is a fixed point, settings kept")
      (assert (= (textOf (cp/writeVtt n)) (vtt)) "NOTE, STYLE, the cue id, BOM and CRLF are tolerated and dropped")
      (assert (= (optionOr (listHead (map (fn [(c cp/Cue)] -> Int64 c.endMs) (listDrop a 2))) 0) 3725999) "1h 2m 5.999s is 3725999 ms")
      (assert (= (optionOr (listHead (map (fn [(c cp/Cue)] -> String c.text) (listDrop v 2))) "") "last & final <s>") "VTT escapes are undone on parse")
      (assert (= (optionOr (listHead (map (fn [(c cp/Cue)] -> String c.settings) v)) "") "align:start position:10%") "cue settings are kept")
      true))

fn ! testEscapes! -> Bool
  (let [(c (cp/Cue :startMs 0 :endMs 1000 :text "a & b <s>x</s> > y" :settings ""))
        (back (cuesOk (cp/parseVtt (textOf (cp/writeVtt (list c))))))]
    (do
      (assert (stringContains? (textOf (cp/writeVtt (list c))) "a &amp; b &lt;s&gt;x&lt;/s&gt; &gt; y") "VTT text is escaped")
      (assert (= back (list c)) "escaped text round-trips")
      (assert (stringStartsWith? (textOf (cp/writeSrt (list (cp/Cue :startMs 0 :endMs 1 :text "a --> b" :settings "")))) "captionText") "SRT refuses text that contains -->")
      true))

fn ! testTimes! -> Bool
  (do
    (assert (= (textOf (cp/formatTime 3723004 ",")) "01:02:03,004") "format keeps three digits")
    (assert (= (textOf (cp/formatTime 5 ".")) "00:00:00.005") "format pads")
    (assert (= (match (cp/parseTime "01:02.500") ((ok n) n) ((err _) -1)) 62500) "MM:SS.mmm parses")
    (assert (= (match (cp/parseTime "00:01:02,500") ((ok n) n) ((err _) -1)) 62500) "comma parses")
    (assert (err? (cp/parseTime "00:00:01,5")) "two fraction digits are refused")
    (assert (err? (cp/parseTime "1.5")) "a bare number is refused")
    (assert (err? (cp/parseTime "aa:00:01,500")) "non-digits are refused")
    (assert (= (cp/msFromSeconds 1.0006) 1001) "seconds round half up, not down")
    (assert (= (cp/msFromSeconds 1.0004) 1000) "and down below the half")
    (assert (err? (cp/parseSrt "1\n00:00:01,000 --> nope\nx\n")) "a bad end time is an err")
    (assert (err? (cp/parseVtt "no header\n")) "VTT needs its header")
    true)

fn cue a: Int64 b: Int64 t: String -> cp/Cue
  (cp/Cue :startMs a :endMs b :text t :settings "")

fn texts cs: (List cp/Cue) -> (List String)
  (map (fn [(c cp/Cue)] -> String c.text) cs)

fn ! testBlankLines! -> Bool
  (let [(c1 (cue 0 1000 "a\n\n\nb"))
        (c2 (cue 0 1000 "a\n   \nb"))
        (c3 (cue 2000 3000 "x\n\t\n\ny"))
        (srtTxt (textOf (cp/writeSrt (list c1 c2 c3))))
        (vttTxt (textOf (cp/writeVtt (list c1 c2 c3))))]
    (do
      (assert (= (texts (cuesOk (cp/parseSrt srtTxt))) (list "a\nb" "a\nb" "x\ny")) "SRT: a blank or whitespace-only line inside a cue is dropped, no text is lost after it")
      (assert (= (texts (cuesOk (cp/parseVtt vttTxt))) (list "a\nb" "a\nb" "x\ny")) "VTT: the same, nothing after the blank line is lost")
      (assert (not (stringContains? srtTxt "\n\n\n")) "SRT never holds two blank lines in a row")
      (assert (not (stringContains? vttTxt "\n   \n")) "VTT never holds a whitespace-only line")
      (assert (= (listLength (cuesOk (cp/parseSrt srtTxt))) 3) "all three cues come back")
      true))

fn ! testNegative! -> Bool
  (do
    (assert (stringStartsWith? (textOf (cp/formatTime -500 ",")) "captionTime") "formatTime of a negative ms is an err")
    (assert (stringStartsWith? (textOf (cp/formatTime -1 ",")) "captionTime") "minus one ms is already an err")
    (assert (= (textOf (cp/formatTime 0 ",")) "00:00:00,000") "zero is a valid time")
    (assert (stringStartsWith? (textOf (cp/writeSrt (list (cue -500 1000 "x")))) "captionTime") "writeSrt refuses a negative start")
    (assert (stringStartsWith? (textOf (cp/writeSrt (list (cue 0 -1 "x")))) "captionTime") "writeSrt refuses a negative end")
    (assert (stringStartsWith? (textOf (cp/writeVtt (list (cue -500 1000 "x")))) "captionTime") "writeVtt refuses a negative start")
    (assert (err? (cp/parseTime "-00:00:01,000")) "a leading minus is refused")
    (assert (err? (cp/parseTime "00:00:-1,000")) "a minus in the seconds is refused")
    (assert (err? (cp/parseTime "00:00:+1,000")) "a plus sign is refused")
    (assert (err? (cp/parseTime "00:75:00,000")) "75 minutes is refused")
    (assert (err? (cp/parseTime "00:00:75,000")) "75 seconds is refused")
    (assert (err? (cp/parseTime "75:00.000")) "MM:SS with 75 minutes is refused")
    (assert (= (match (cp/parseTime "100:59:59,999") ((ok n) n) ((err _) -1)) 363599999) "hours are not capped")
    true)

fn ! testBlocks! -> Bool
  (do
    (assert (err? (cp/parseSrt "1\n00:00:01,000 --> 00:00:02,000\nx\n\n2\nno time here\n")) "an SRT block without a timing line is an err, not a silent drop")
    (assert (err? (cp/parseVtt "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nx\n\nstray text\n")) "a VTT block without a timing line is an err")
    (assert (= (listLength (cuesOk (cp/parseVtt "WEBVTT\n\nNOTE c\n\nSTYLE\na{}\n\n00:00:01.000 --> 00:00:02.000\nx\n"))) 1) "NOTE and STYLE blocks are still dropped")
    (let [(t (cp/Cue :startMs 0 :endMs 1000 :text "<i>it</i> <b>b</b> <u>u</u> <c.x>y</c> a<b" :settings ""))
          (v (textOf (cp/writeVtt (list t))))]
      (do
        (assert (stringContains? v "<i>it</i> <b>b</b> <u>u</u> &lt;c.x&gt;y&lt;/c&gt; a&lt;b") "VTT keeps i, b and u tags and escapes every other angle bracket")
        (assert (= (cuesOk (cp/parseVtt v)) (list (cp/Cue :startMs 0 :endMs 1000 :text "<i>it</i> <b>b</b> <u>u</u> <c.x>y</c> a<b" :settings ""))) "tags round-trip")
        true)))

fn ! testOverlapRoundTrip! -> Bool
  (let [(cs (list (cue 1000 3000 "one") (cue 2500 4000 "two overlaps one") (cue 2500 2600 "same start") (cue 5000 5000 "zero length")))
        (srtBack (cuesOk (cp/parseSrt (textOf (cp/writeSrt cs)))))
        (vttBack (cuesOk (cp/parseVtt (textOf (cp/writeVtt cs)))))]
    (do
      (assert (= srtBack cs) "overlapping, same-start and zero-length cues round-trip through SRT unchanged")
      (assert (= vttBack cs) "and through VTT")
      (assert (= (cp/cueOverlaps srtBack) (list 1 2)) "the overlap report is the same after the round trip")
      true))

fn ! testOverlap! -> Bool
  (let [(cs (list (cp/Cue :startMs 0 :endMs 1000 :text "a" :settings "") (cp/Cue :startMs 900 :endMs 2000 :text "b" :settings "") (cp/Cue :startMs 2000 :endMs 3000 :text "c" :settings "")))]
    (do
      (assert (= (cp/cueOverlaps cs) (list 1)) "a cue that starts before the previous ends is flagged, one that starts at the end is not")
      true))

fn lim -> cp/GroupLimits
  (cp/GroupLimits :maxChars 20 :maxLines 2 :minMs 800 :maxMs 6000 :maxCps 25 :pauseMs 1000)

fn wordAt i: Int64 -> cp/Word
  (let [(start (+ (* i 300) (if (> i 150) 2500 0)))]
    (cp/Word :text (str "w" (stringFromInt64 i) (if (= (mod i 17) 16) "." "")) :startMs start :endMs (+ start 250)))

fn wordsUpTo i: Int64 n: Int64 -> (List cp/Word)
  (if (>= i n) (list) (cons (wordAt i) (wordsUpTo (+ i 1) n)))

fn ! testGroup! -> Bool
  (let [(words (wordsUpTo 0 300))
        (cues (cp/groupWords words (lim)))
        (flat (flatMap2 (fn [(c cp/Cue)] -> (List String) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace c.text "\n" " ") " "))) cues))]
    (do
      (assert (> (listLength cues) 20) "300 words make many cues")
      (assert (= flat (map (fn [(w cp/Word)] -> String w.text) words)) "the words of the cues are the input words, in order, none dropped")
      (assert (listEmpty? (cp/cueViolations cues (lim))) "every cue is within lines, chars, duration and reading speed")
      (assert (listEmpty? (cp/cueOverlaps cues)) "cues do not overlap")
      (assert (listAll? (fn [(c cp/Cue)] -> Bool (<= (listLength (stringLines c.text)) 2)) cues) "at most two lines")
      (assert (listAny? (fn [(c cp/Cue)] -> Bool (stringContains? c.text "w16.")) cues) "sentence ends are kept")
      (assert (not (listAny? (fn [(c cp/Cue)] -> Bool (and (stringContains? c.text "w150") (stringContains? c.text "w152"))) cues)) "the 2.5 s pause after word 150 splits the cue")
      true))

fn flatMap2 f: (fn [cp/Cue] -> (List String)) xs: (List cp/Cue) -> (List String)
  (fold (fn [(acc (List String)) (x cp/Cue)] -> (List String) (listAppend acc (f x))) (list) xs)

fn ! testStretch! -> Bool
  (let [(cues (cp/groupWords (list (cp/Word :text "hi" :startMs 0 :endMs 100) (cp/Word :text "yo" :startMs 5000 :endMs 5100)) (lim)))]
    (do
      (assert (= (listLength cues) 2) "a long gap splits")
      (assert (= (optionOr (listHead (map (fn [(c cp/Cue)] -> Int64 c.endMs) cues)) 0) 800) "a short cue is stretched to minMs when the next cue starts later")
      true))

fn ! runTests -> Bool
  (do
    (testRoundTrip!)
    (testEscapes!)
    (testTimes!)
    (testBlankLines!)
    (testNegative!)
    (testBlocks!)
    (testOverlapRoundTrip!)
    (testOverlap!)
    (testGroup!)
    (testStretch!)
    true)
