(module asl-syntax/tests/core/incrementalTest
  :x [runTests]
  :i [(asl-syntax/core/incremental :a inc)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/paren :a prn)
      (asl-syntax/tests/asl/layoutCorpusLib :a lib)])

fn copySlice! src: Bytes srcIdx: Int64 dst: Bytes dstIdx: Int64 count: Int64 -> Unit
  (if (<= count 0)
    ()
    (do
      (bytesSet dst dstIdx (bytesGet src srcIdx))
      (copySlice! src (+ srcIdx 1) dst (+ dstIdx 1) (- count 1))))

fn sliceBytes! bs: Bytes start: Int64 count: Int64 -> Bytes
  (let [(out (bytesAlloc count))]
    (copySlice! bs start out 0 count)
    out)

fn feedChunksLoop! state: inc/IncrementalState bs: Bytes len: Int64 offset: Int64 chunkSize: Int64 -> inc/IncrementalState
  (if (>= offset len)
    state
    (let [(rem (- len offset))
          (n (if (< rem chunkSize) rem chunkSize))
          (chunk (sliceBytes! bs offset n))
          (nextState (inc/incrementalFeed! state chunk))]
      (feedChunksLoop! nextState bs len (+ offset n) chunkSize)))

fn feedInChunks! bs: Bytes chunkSize: Int64 -> inc/IncrementalState
  (feedChunksLoop! (inc/incrementalStart!) bs (bytesLength bs) 0 chunkSize)

fn firstFatalLoop! state: inc/IncrementalState bs: Bytes len: Int64 offset: Int64 chunkSize: Int64 chunkIdx: Int64 -> (Pair Int64 Int64)
  (if (>= offset len)
    (pair -1 -1)
    (let [(rem (- len offset))
          (n (if (< rem chunkSize) rem chunkSize))
          (nextState (inc/incrementalFeed! state (sliceBytes! bs offset n)))]
      (mt (inc/incrementalFatalError nextState)
        ((some fe) (pair chunkIdx (inc/fatalErrorOffset fe)))
        ((none) (firstFatalLoop! nextState bs len (+ offset n) chunkSize (+ chunkIdx 1))))))

fn firstFatal! text: String chunkSize: Int64 -> (Pair Int64 Int64)
  (let [(bs (stringToBytes text))]
    (firstFatalLoop! (inc/incrementalStart!) bs (bytesLength bs) 0 chunkSize 0))

fn assertFirstFatal! text: String chunkSize: Int64 wantChunk: Int64 wantOffset: Int64 label: String -> Bool
  (let [(got (firstFatal! text chunkSize))]
    (assert (= (pairFirst got) wantChunk)
            (str label ": fatal first reported at chunk " (stringFromInt64 wantChunk) " of size " (stringFromInt64 chunkSize) ", got " (stringFromInt64 (pairFirst got))))
    (assert (= (pairSecond got) wantOffset)
            (str label ": fatal offset " (stringFromInt64 wantOffset) ", got " (stringFromInt64 (pairSecond got))))
    true)

fn prefixMismatchLoop! state: inc/IncrementalState bs: Bytes len: Int64 offset: Int64 chunkSize: Int64 bad: Int64 -> Int64
  (if (>= offset len)
    bad
    (let [(rem (- len offset))
          (n (if (< rem chunkSize) rem chunkSize))
          (nextState (inc/incrementalFeed! state (sliceBytes! bs offset n)))
          (prefix (sliceBytes! bs 0 (+ offset n)))
          (same (= (inc/incrementalTree nextState) (prn/parseBytes prefix)))]
      (prefixMismatchLoop! nextState bs len (+ offset n) chunkSize (if same bad (+ bad 1)))))

fn assertPrefixTreesMatch! text: String chunkSize: Int64 label: String -> Bool
  (let [(bs (stringToBytes text))
        (bad (prefixMismatchLoop! (inc/incrementalStart!) bs (bytesLength bs) 0 chunkSize 0))]
    (assert (= bad 0) (str label ": every chunk-" (stringFromInt64 chunkSize) " prefix tree equals prn/parseBytes of the prefix, mismatches " (stringFromInt64 bad)))
    true)

fn checkNoErrorsAtAnyChunkLoop! state: inc/IncrementalState bs: Bytes len: Int64 offset: Int64 chunkSize: Int64 -> Bool
  (if (>= offset len)
    (inc/verdictOk? (inc/incrementalVerdict state))
    (let [(rem (- len offset))
          (n (if (< rem chunkSize) rem chunkSize))
          (chunk (sliceBytes! bs offset n))
          (nextState (inc/incrementalFeed! state chunk))]
      (if (inc/incrementalHasFatalError? nextState)
        false
        (checkNoErrorsAtAnyChunkLoop! nextState bs len (+ offset n) chunkSize))))

fn testFatalErrorUnmatchedCloser! -> Bool
  (let [(text "(module foo)\n)\n(fn bar -> Int64 1)\n")]
    (and (assertFirstFatal! text 4 3 13 "unmatched closer")
    (and (assertFirstFatal! text 1 13 13 "unmatched closer")
         (assertPrefixTreesMatch! text 1 "unmatched closer"))))

fn testFatalErrorMismatchedInnermostCloser! -> Bool
  (let [(text "(module foo :x ]\n(fn bar -> Int64 1)\n")]
    (and (assertFirstFatal! text 3 5 15 "mismatched innermost closer")
         (assertPrefixTreesMatch! text 1 "mismatched innermost closer")))

fn testFatalErrorNestedMismatchedCloser! -> Bool
  (let [(text "(module foo (let [(x 1) (y ) 2)] (+ x y)))\n")]
    (and (assertFirstFatal! text 5 6 30 "nested mismatched closer")
         (assertPrefixTreesMatch! text 1 "nested mismatched closer")))

fn testFatalErrorInvalidToken! -> Bool
  (and (assertFirstFatal! "(a \"b\\xZZ\" c)" 1 7 7 "bad hex escape, 1-byte chunks")
  (and (assertFirstFatal! "(a \"b\\xZZ\" c)" 3 2 7 "bad hex escape, 3-byte chunks")
  (and (assertFirstFatal! "(module foo :d \"bad \\xZZ escape\" :x [run])\n" 6 3 22 "bad hex escape in module doc")
  (and (assertFirstFatal! "\"\\x4Z\"" 1 4 4 "second hex digit invalid")
  (and (assertFirstFatal! "\"\\u12Z4\"" 1 5 5 "bad unicode escape")
  (and (assertFirstFatal! "\"\\x\"" 1 3 3 "hex escape cut by the closing quote")
  (and (assertFirstFatal! "(a \"\\x41\\u00e9\" b)" 1 -1 -1 "valid escapes split across chunks")
       (assertPrefixTreesMatch! "(a \"b\\xZZ\" c)" 1 "bad hex escape"))))))))

fn testUnclosedBracketPrefixNeverReported! -> Bool
  (let [(text "(module foo :x [1 2 {a: 3")
        (bs (stringToBytes text))
        (len (bytesLength bs))
        (clean (checkNoErrorsAtAnyChunkLoop! (inc/incrementalStart!) bs len 0 3))]
    (assert clean "unclosed bracket prefix is never reported as fatal error")
    true)

fn testUnclosedStringPrefixNeverReported! -> Bool
  (let [(text "(module foo :d \"docstring that is not closed at prefix end")
        (bs (stringToBytes text))
        (len (bytesLength bs))
        (clean (checkNoErrorsAtAnyChunkLoop! (inc/incrementalStart!) bs len 0 7))]
    (assert clean "unclosed string prefix is never reported as fatal error")
    true)

fn assertTreeKeepsPrefix! text: String chunkSize: Int64 label: String -> Bool
  (let [(bs (stringToBytes text))
        (state (feedInChunks! bs chunkSize))
        (tree (inc/incrementalTree state))
        (whole (prn/parseBytes bs))]
    (assert (= tree whole) (str label ": tree equals prn/parseBytes of the prefix"))
    (assert (= (pr/print text tree) text) (str label ": tree prints the prefix byte for byte, got " (pr/print text tree)))
    (assert (= (tr/nodeEnd tree) (bytesLength bs)) (str label ": tree spans every prefix byte"))
    true)

fn testTreeKeepsPendingAndErrorTokens! -> Bool
  (and (assertTreeKeepsPrefix! "(a \"bc" 1 "unclosed string")
  (and (assertTreeKeepsPrefix! "(a \"bc" 64 "unclosed string, one chunk")
  (and (assertTreeKeepsPrefix! "(module foo :x [1 2 {a: 3" 3 "unclosed brackets")
  (and (assertTreeKeepsPrefix! "(a \"b\\xZZ\" c)" 1 "invalid escape error token")
  (and (assertTreeKeepsPrefix! "(a \"b\\x4" 1 "string ending inside an escape")
  (and (assertTreeKeepsPrefix! "(a b\r" 1 "trailing carriage return")
  (and (assertPrefixTreesMatch! "(a \"bc" 1 "unclosed string")
  (and (assertPrefixTreesMatch! "(module foo :x [1 2 {a: 3" 1 "unclosed brackets")
       (assertPrefixTreesMatch! "(x 12.5e3 ; c\r\n  [y] {:k \"v\\n\"})\n" 1 "mixed tokens")))))))))

fn testStatesArePersistent! -> Bool
  (let [(s0 (inc/incrementalFeedString! (inc/incrementalStart!) "(1"))
        (s1 (inc/incrementalFeedString! s0 "23"))
        (s2 (inc/incrementalFeedString! s0 "x"))
        (t1 (inc/incrementalTree s1))
        (t2 (inc/incrementalTree s2))
        (c0 (inc/incrementalFeedString! (inc/incrementalStart!) "(a "))
        (c1 (inc/incrementalFeedString! c0 ")"))
        (c2 (inc/incrementalFeedString! c0 "]"))
        (c3 (inc/incrementalFeedString! c1 " (b)"))]
    (assert (= t1 (prn/parseBytes (stringToBytes "(123"))) "fork 1 of a state keeps its own bytes: (123")
    (assert (= t2 (prn/parseBytes (stringToBytes "(1x"))) "fork 2 of the same state keeps its own bytes: (1x")
    (assert (= (inc/incrementalTree s0) (prn/parseBytes (stringToBytes "(1"))) "the forked state itself is unchanged: (1")
    (assert (inc/verdictOk? (inc/incrementalVerdict c1)) "fork with a matching closer is not fatal")
    (assert (inc/incrementalHasFatalError? c2) "fork with a mismatched closer is fatal")
    (assert (= (inc/incrementalTree c3) (prn/parseBytes (stringToBytes "(a ) (b)"))) "feeding on after a sibling fork stays correct")
    (assert (inc/verdictOk? (inc/incrementalVerdict c3)) "feeding on after a sibling fork stays non-fatal")
    true)

fn fillBenchBytes! dst: Bytes dstIdx: Int64 targetLen: Int64 pattern: Bytes patLen: Int64 -> Unit
  (if (>= dstIdx targetLen)
    ()
    (let [(rem (- targetLen dstIdx))
          (n (if (< rem patLen) rem patLen))]
      (do
        (copySlice! pattern 0 dst dstIdx n)
        (fillBenchBytes! dst (+ dstIdx n) targetLen pattern patLen))))

fn testLinearPerformance200Kb! -> Bool
  (let [(pat (stringToBytes "(module ws/bench :x [run])\n(fn run x: Int64 -> Int64 (+ x 1))\n"))
        (patLen (bytesLength pat))
        (targetLen 204800)
        (buf (bytesAlloc targetLen))
        (_ (fillBenchBytes! buf 0 targetLen pat patLen))
        (t0 (nowNs))
        (state (feedInChunks! buf 1024))
        (t1 (nowNs))
        (elapsedNs (- t1 t0))
        (elapsedSec (/ elapsedNs 1000000000))
        (under10Sec (< elapsedSec 10))
        (tree (inc/incrementalTree state))]
    (assert under10Sec (str "200 KB input fed in 1 KB chunks finishes under 10 s (took " (stringFromInt64 elapsedSec) " s)"))
    (assert (= (tr/nodeKind tree) "asl") "200 KB tree parsed successfully")
    true)

fn atomBytes! n: Int64 -> Bytes
  (let [(buf (bytesAlloc n))
        (pat (stringToBytes "abcdefgh"))]
    (fillBenchBytes! buf 0 n pat 8)
    buf)

fn stringBytes! n: Int64 -> Bytes
  (let [(buf (bytesAlloc n))
        (pat (stringToBytes "ab\\x41c\\u00e9d\\n"))]
    (fillBenchBytes! buf 0 n pat (bytesLength pat))
    (bytesSet buf 0 34)
    (bytesSet buf (- n 2) 122)
    (bytesSet buf (- n 1) 34)
    buf)

(schema FeedClock
  (:f state inc/IncrementalState)
  (:f offset Int64)
  (:f times (List Int64)))

(schema StreamTiming
  (:f total Int64)
  (:f estimate Int64))

fn startClock! -> FeedClock
  (FeedClock :state (inc/incrementalStart!) :offset 0 :times (list))

fn timedChunks! clock: FeedClock buf: Bytes count: Int64 -> FeedClock
  (let [(len (bytesLength buf))
        (off clock.offset)]
    (if (or (<= count 0) (>= off len))
      clock
      (let [(n (min 1024 (- len off)))
            (chunk (sliceBytes! buf off n))
            (t0 (nowNs))
            (nextState (inc/incrementalFeed! clock.state chunk))
            (t1 (nowNs))]
        (timedChunks! (FeedClock :state nextState :offset (+ off n) :times (cons (- t1 t0) clock.times)) buf (- count 1)))))

fn sumInts xs: (List Int64) acc: Int64 -> Int64
  (if (listEmpty? xs)
    acc
    (sumInts (optionOr (listTail xs) (list)) (+ acc (optionOr (listHead xs) 0))))

fn medianInt xs: (List Int64) -> Int64
  (optionOr (listGet (listSort xs) (/ (listLength xs) 2)) 0)

fn timedFlush! clock: FeedClock buf: Bytes label: String -> StreamTiming
  (let [(t0 (nowNs))
        (tree (inc/incrementalTree clock.state))
        (t1 (nowNs))
        (times clock.times)]
    (assert (= tree (prn/parseBytes buf)) (str label ": " (stringFromInt64 (bytesLength buf)) " bytes chunked tree equals the whole parse"))
    (StreamTiming :total (+ (sumInts times 0) (- t1 t0))
                  :estimate (+ (* (listLength times) (medianInt times)) (- t1 t0))))

fn interleavedTimings! small: Bytes big: Bytes cs: FeedClock cb: FeedClock label: String -> (Pair StreamTiming StreamTiming)
  (if (and (>= cs.offset (bytesLength small)) (>= cb.offset (bytesLength big)))
    (pair (timedFlush! cs small label) (timedFlush! cb big label))
    (interleavedTimings! small big (timedChunks! cs small 1) (timedChunks! cb big 2) label))

fn assertLinearSingleToken! make: (fn [Int64] -> Bytes) label: String -> Bool
  (let [(small (make 204800))
        (big (make 409600))
        (timings (interleavedTimings! small big (startClock!) (startClock!) label))
        (ts (pairFirst timings))
        (tb (pairSecond timings))
        (msSmall (/ ts.total 1000000))
        (estSmall (/ ts.estimate 1000))
        (estBig (/ tb.estimate 1000))]
    (assert (< ts.total 10000000000) (str label ": 200 KB in 1 KB chunks under 10 s (took " (stringFromInt64 msSmall) " ms)"))
    (assert (< tb.total 20000000000) (str label ": 400 KB in 1 KB chunks under 20 s (took " (stringFromInt64 (/ tb.total 1000000)) " ms)"))
    (assert (<= (* tb.estimate 2) (* ts.estimate 5)) (str label ": 400 KB takes at most 2.5x the 200 KB time (" (stringFromInt64 estBig) " us vs " (stringFromInt64 estSmall) " us, median chunk time times chunk count plus flush)"))
    true)

fn testLinearSingleAtom! -> Bool
  (assertLinearSingleToken! (fn [(n Int64)] -> Bytes (atomBytes! n)) "single atom")

fn testLinearSingleString! -> Bool
  (assertLinearSingleToken! (fn [(n Int64)] -> Bytes (stringBytes! n)) "single string")

fn verifyCorpusChunkSize! path: String bs: Bytes whole: tr/Node chunkSize: Int64 -> Bool
  (let [(s (feedInChunks! bs chunkSize))
        (sameTree (= (inc/incrementalTree s) whole))
        (ok (inc/verdictOk? (inc/incrementalVerdict s)))]
    (assert sameTree (str path ": chunk size " (stringFromInt64 chunkSize) " tree equals the whole parse"))
    (assert ok (str path ": chunk size " (stringFromInt64 chunkSize) " verdict ok"))
    true)

fn verifyOneCorpusFile! path: String -> Bool
  (mt (fileReadBytes path)
    ((err msg)
     (do
       (assert false (str "Failed to read file " path ": " msg))
       false))
    ((ok bs)
     (let [(whole (prn/parseBytes bs))]
       (and (verifyCorpusChunkSize! path bs whole 1)
       (and (verifyCorpusChunkSize! path bs whole 7)
            (verifyCorpusChunkSize! path bs whole 64))))))

fn fileSizeOr! path: String -> Int64
  (mt (fileSize path)
    ((ok n) n)
    ((err _) -1))

fn spreadLoop xs: (List String) n: Int64 want: Int64 k: Int64 idx: Int64 acc: (List String) -> (List String)
  (if (or (>= k want) (listEmpty? xs))
    (listReverse acc)
    (let [(target (/ (* k n) want))
          (x (optionOr (listHead xs) ""))
          (rest (optionOr (listTail xs) (list)))]
      (if (= idx target)
        (spreadLoop rest n want (+ k 1) (+ idx 1) (cons x acc))
        (spreadLoop rest n want k (+ idx 1) acc))))

fn spread xs: (List String) want: Int64 -> (List String)
  (spreadLoop xs (listLength xs) want 0 0 (list))

fn verifyFilesLoop! files: (List String) -> Bool
  (if (listEmpty? files)
    true
    (and (verifyOneCorpusFile! (optionOr (listHead files) ""))
         (verifyFilesLoop! (optionOr (listTail files) (list)))))

fn testCorpusFiles! -> Bool
  (mt (lib/allCorpusFiles!)
    ((err e)
     (do
       (assert false (str "corpus listing failed: " e))
       false))
    ((ok files)
     (let [(big (filter (fn [(p String)] -> Bool (> (fileSizeOr! p) 5120)) files))
           (small (filter (fn [(p String)] -> Bool (let [(sz (fileSizeOr! p))] (and (>= sz 0) (<= sz 5120)))) files))
           (sample (listAppend (spread big 15) (spread small 15)))
           (bigCount (listLength (filter (fn [(p String)] -> Bool (> (fileSizeOr! p) 5120)) sample)))]
       (assert (= (listLength sample) 30) (str "corpus sample has 30 files, got " (stringFromInt64 (listLength sample))))
       (assert (>= bigCount 10) (str "corpus sample has at least 10 files over 5 KB, got " (stringFromInt64 bigCount)))
       (verifyFilesLoop! sample))))

fn ! runTests -> Bool
  (and (testFatalErrorUnmatchedCloser!)
  (and (testFatalErrorMismatchedInnermostCloser!)
  (and (testFatalErrorNestedMismatchedCloser!)
  (and (testFatalErrorInvalidToken!)
  (and (testUnclosedBracketPrefixNeverReported!)
  (and (testUnclosedStringPrefixNeverReported!)
  (and (testTreeKeepsPendingAndErrorTokens!)
  (and (testStatesArePersistent!)
  (and (testLinearPerformance200Kb!)
  (and (testLinearSingleAtom!)
  (and (testLinearSingleString!)
       (testCorpusFiles!))))))))))))
