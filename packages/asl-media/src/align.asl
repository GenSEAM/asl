(module asl-media/align
  :x [AlignOp WerResult AsrWord TimedWord AlignResult normaliseWords alignWords werOf werText cerText mapAsrTimes exactSame]
  :i [])

schema AlignOp
  (:f kind String)
  (:f refIdx Int64)
  (:f hypIdx Int64)

schema WerResult
  (:f subs Int64)
  (:f dels Int64)
  (:f ins Int64)
  (:f matches Int64)
  (:f refLen Int64)
  (:f hypLen Int64)
  (:f errors Int64)
  (:f wer Float64)

schema AsrWord
  (:f text String)
  (:f startMs Int64)
  (:f endMs Int64)

schema TimedWord
  (:f word String)
  (:f startMs Int64)
  (:f endMs Int64)
  (:f status String)

schema AlignResult
  (:f words (List TimedWord))
  (:f coverage Float64)

fn exactSame a: String b: String -> Bool
  (= a b)

; (:m :ref workspace-20261031-transcriptAlignAndWer :do "comparison text is lower-cased, apostrophes are removed inside words (don't = dont), every other ASCII punctuation mark is a space, multi-byte characters stay word characters; numerals are a caller-supplied map of word to spelling applied after tokenizing, never guessed")
fn keepChar? c: String -> Bool
  (or (> (stringLength c) 1) (stringContains? "abcdefghijklmnopqrstuvwxyz0123456789" c))

fn mapChar c: String -> String
  (cond
    ((or (= c "'") (= c "\xe2\x80\x99")) "")
    ((keepChar? c) c)
    (else " "))

fn normaliseWords text: String numerals: (List (Pair String String)) -> (List String)
  (let [(cleaned (stringJoin (map mapChar (stringChars (stringLower text))) ""))
        (toks (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit cleaned " ")))]
    (map (fn [(w String)] -> String (optionOr (listHead (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) w)) numerals))) w)) toks))

fn getCell m: Bytes i: Int64 -> Int64
  (+ (bytesGet m (* i 4)) (+ (* (bytesGet m (+ (* i 4) 1)) 256) (+ (* (bytesGet m (+ (* i 4) 2)) 65536) (* (bytesGet m (+ (* i 4) 3)) 16777216))))

fn setCell! m: Bytes i: Int64 v: Int64 -> Unit
  (do (bytesSet m (* i 4) (mod v 256)) (bytesSet m (+ (* i 4) 1) (mod (/ v 256) 256))
      (bytesSet m (+ (* i 4) 2) (mod (/ v 65536) 256)) (bytesSet m (+ (* i 4) 3) (mod (/ v 16777216) 256)))

fn min3 a: Int64 b: Int64 c: Int64 -> Int64
  (min a (min b c))

fn ! fillMatrix! m: Bytes ref: (List String) hyp: (List String) same: (fn [String String] -> Bool) cols: Int64 i: Int64 j: Int64 n: Int64 k: Int64 -> Unit
  (cond
    ((> i n) ())
    ((> j k) (fillMatrix! m ref hyp same cols (+ i 1) 0 n k))
    ((= i 0) (do (setCell! m j j) (fillMatrix! m ref hyp same cols i (+ j 1) n k)))
    ((= j 0) (do (setCell! m (* i cols) i) (fillMatrix! m ref hyp same cols i (+ j 1) n k)))
    (else
      (let [(cost (if (same (optionOr (listGet ref (- i 1)) "") (optionOr (listGet hyp (- j 1)) "")) 0 1))
            (diag (+ (getCell m (+ (* (- i 1) cols) (- j 1))) cost))
            (del (+ (getCell m (+ (* (- i 1) cols) j)) 1))
            (ins (+ (getCell m (+ (* i cols) (- j 1))) 1))]
        (do (setCell! m (+ (* i cols) j) (min3 diag del ins))
            (fillMatrix! m ref hyp same cols i (+ j 1) n k)))))

fn ! backtrace m: Bytes ref: (List String) hyp: (List String) same: (fn [String String] -> Bool) cols: Int64 i: Int64 j: Int64 acc: (List AlignOp) -> (List AlignOp)
  (cond
    ((and (= i 0) (= j 0)) acc)
    ((= i 0) (backtrace m ref hyp same cols i (- j 1) (cons (AlignOp :kind "ins" :refIdx -1 :hypIdx (- j 1)) acc)))
    ((= j 0) (backtrace m ref hyp same cols (- i 1) j (cons (AlignOp :kind "del" :refIdx (- i 1) :hypIdx -1) acc)))
    (else
      (let [(here (getCell m (+ (* i cols) j)))
            (isSame (same (optionOr (listGet ref (- i 1)) "") (optionOr (listGet hyp (- j 1)) "")))
            (diag (getCell m (+ (* (- i 1) cols) (- j 1))))
            (up (getCell m (+ (* (- i 1) cols) j)))]
        (cond
          ((= here (+ diag (if isSame 0 1)))
            (backtrace m ref hyp same cols (- i 1) (- j 1) (cons (AlignOp :kind (if isSame "match" "sub") :refIdx (- i 1) :hypIdx (- j 1)) acc)))
          ((= here (+ up 1))
            (backtrace m ref hyp same cols (- i 1) j (cons (AlignOp :kind "del" :refIdx (- i 1) :hypIdx -1) acc)))
          (else
            (backtrace m ref hyp same cols i (- j 1) (cons (AlignOp :kind "ins" :refIdx -1 :hypIdx (- j 1)) acc)))))))

; (:m :ref workspace-20261031-transcriptAlignAndWer :do "unit-cost Levenshtein over words with a full matrix at 4 bytes a cell, refused past 25 million cells; the backtrace prefers match or substitute, then delete, then insert, so equal-cost alignments are the same on every run; same decides equality, which is where a caller's fuzzy near-homophone test plugs in")
fn ! alignWords ref: (List String) hyp: (List String) same: (fn [String String] -> Bool) -> (Result (List AlignOp) String)
  (let [(n (listLength ref))
        (k (listLength hyp))
        (cols (+ k 1))]
    (if (> (* (+ n 1) cols) 25000000)
      (err "alignLimit: more than 25 million cells")
      (let [(m (bytesAlloc (* (* (+ n 1) cols) 4)))
            (_ (fillMatrix! m ref hyp same cols 0 0 n k))]
        (ok (backtrace m ref hyp same cols n k (list))))))

fn countKind ops: (List AlignOp) kind: String -> Int64
  (listLength (filter (fn [(o AlignOp)] -> Bool (= o.kind kind)) ops))

fn werFromOps ops: (List AlignOp) refLen: Int64 hypLen: Int64 -> WerResult
  (let [(s (countKind ops "sub"))
        (d (countKind ops "del"))
        (i (countKind ops "ins"))
        (e (+ s (+ d i)))]
    (WerResult :subs s :dels d :ins i :matches (countKind ops "match") :refLen refLen :hypLen hypLen :errors e
               :wer (if (= refLen 0) (if (= i 0) 0.0 1.0) (/ (int64ToFloat64 e) (int64ToFloat64 refLen)))))

fn ! werOf ref: (List String) hyp: (List String) -> (Result WerResult String)
  (match (alignWords ref hyp exactSame)
    ((err e) (err e))
    ((ok ops) (ok (werFromOps ops (listLength ref) (listLength hyp)))))

fn ! werText refText: String hypText: String numerals: (List (Pair String String)) -> (Result WerResult String)
  (werOf (normaliseWords refText numerals) (normaliseWords hypText numerals))

fn ! cerText refText: String hypText: String numerals: (List (Pair String String)) -> (Result WerResult String)
  (let [(r (stringChars (stringJoin (normaliseWords refText numerals) " ")))
        (h (stringChars (stringJoin (normaliseWords hypText numerals) " ")))]
    (werOf r h))



fn ! setTimed! st: Bytes en: Bytes code: Bytes ops: (List AlignOp) asr: (List AsrWord) -> Unit
  (match (listHead ops)
    ((none) ())
    ((some o)
      (do
        (if (or (= o.kind "match") (= o.kind "sub"))
          (let [(a (optionOr (listGet asr o.hypIdx) (AsrWord :text "" :startMs 0 :endMs 0)))]
            (do (bytesSetFloat64 st o.refIdx (int64ToFloat64 a.startMs))
                (bytesSetFloat64 en o.refIdx (int64ToFloat64 a.endMs))
                (bytesSet code o.refIdx (if (= o.kind "match") 1 2))))
          ())
        (setTimed! st en code (optionOr (listTail ops) (list)) asr))))

fn slotInt b: Bytes i: Int64 -> Int64
  (optionOr (float64ToInt64 (bytesGetFloat64 b i)) 0)

fn runEnd code: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (= (bytesGet code i) 0)) (runEnd code (+ i 1) n) i)

fn ! interpolate! st: Bytes en: Bytes code: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (if (!= (bytesGet code i) 0)
      (interpolate! st en code (+ i 1) n)
      (let [(b (runEnd code i n))
            (prevEnd (if (> i 0) (slotInt en (- i 1)) 0))
            (nextStart (if (< b n) (slotInt st b) prevEnd))
            (span (- nextStart prevEnd))
            (len (- b i))
            (_ (fillRun! st en i b i len prevEnd span))]
        (interpolate! st en code b n))))

fn ! fillRun! st: Bytes en: Bytes a: Int64 b: Int64 k: Int64 len: Int64 prevEnd: Int64 span: Int64 -> Unit
  (if (>= k b) ()
    (do (bytesSetFloat64 st k (int64ToFloat64 (+ prevEnd (/ (* span (- k a)) len))))
        (bytesSetFloat64 en k (int64ToFloat64 (+ prevEnd (/ (* span (+ (- k a) 1)) len))))
        (fillRun! st en a b (+ k 1) len prevEnd span)))

fn ! monotone! st: Bytes en: Bytes i: Int64 n: Int64 prevEnd: Int64 -> Unit
  (if (>= i n) ()
    (let [(s (max (slotInt st i) prevEnd))
          (e (max (slotInt en i) s))]
      (do (bytesSetFloat64 st i (int64ToFloat64 s))
          (bytesSetFloat64 en i (int64ToFloat64 e))
          (monotone! st en (+ i 1) n e))))

; (:m :ref workspace-20261031-transcriptAlignAndWer :do "ASR word times go onto the script words through the alignment: a matched or substituted word takes its ASR word's times, a deleted word is spread evenly across the gap between its neighbours, inserted ASR words only leave their time as gap; a final pass makes starts and ends monotonic and non-overlapping; coverage is the share of script words that got an ASR time; no ASR anchor at all is an err")
fn ! mapAsrTimes script: (List String) asr: (List AsrWord) numerals: (List (Pair String String)) same: (fn [String String] -> Bool) -> (Result AlignResult String)
  (let [(ref (map (fn [(w String)] -> String (optionOr (listHead (normaliseWords w numerals)) "")) script))
        (hyp (map (fn [(a AsrWord)] -> String (optionOr (listHead (normaliseWords a.text numerals)) "")) asr))
        (n (listLength script))]
    (match (alignWords ref hyp same)
      ((err e) (err e))
      ((ok ops)
        (let [(st (bytesAlloc (* (max n 1) 8)))
              (en (bytesAlloc (* (max n 1) 8)))
              (code (bytesAlloc (max n 1)))
              (_ (setTimed! st en code ops asr))
              (timed (listLength (filter (fn [(o AlignOp)] -> Bool (or (= o.kind "match") (= o.kind "sub"))) ops)))]
          (if (and (> n 0) (= timed 0))
            (err "alignNoAnchor: no script word matched an ASR word")
            (let [(_ (interpolate! st en code 0 n))
                  (_ (monotone! st en 0 n 0))]
              (ok (AlignResult :words (timedList script st en code 0 n)
                               :coverage (if (= n 0) 1.0 (/ (int64ToFloat64 timed) (int64ToFloat64 n)))))))))))

fn timedList script: (List String) st: Bytes en: Bytes code: Bytes i: Int64 n: Int64 -> (List TimedWord)
  (if (>= i n) (list)
    (cons (TimedWord :word (optionOr (listGet script i) "") :startMs (slotInt st i) :endMs (slotInt en i)
                     :status (cond ((= (bytesGet code i) 1) "match") ((= (bytesGet code i) 2) "sub") (else "interp")))
          (timedList script st en code (+ i 1) n)))
