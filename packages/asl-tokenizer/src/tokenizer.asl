(module asl-tokenizer/tokenizer
  :x [Tokenizer loadTokenizer! countTokens! countTokensBytes!]
  :i [])

schema Tokenizer
  tokenBytes: Bytes
  table: Bytes
  mask: Int64
  asciiTable: Bytes
  unicodeTable: Bytes
  nUnicodeRanges: Int64
  scratchOff: Bytes
  scratchLen: Bytes

fn toLower b: Int64 -> Int64
  (if (and (>= b 65) (<= b 90)) (+ b 32) b)

fn isSpace c: Int64 -> Bool
  (or (= c 1) (= c 2))

fn isUpperOrMark c: Int64 -> Bool
  (or (= c 3) (or (= c 5) (= c 6)))

fn isLowerOrMark c: Int64 -> Bool
  (or (= c 4) (or (= c 5) (= c 6)))

fn isLetterOrMark c: Int64 -> Bool
  (or (or (= c 3) (= c 4)) (or (= c 5) (= c 6)))

fn isPunctOrSymbol c: Int64 -> Bool
  (or (= c 6) (= c 8))

fn isOptLead c: Int64 -> Bool
  (or (= c 2) (or (= c 6) (= c 8)))

fn initAsciiTable! t: Bytes i: Int64 -> Bytes
  (if (>= i 128) t
    (let [(c (cond
               ((or (= i 10) (= i 13)) 1)
               ((or (= i 32) (or (= i 9) (or (= i 11) (= i 12)))) 2)
               ((and (>= i 65) (<= i 90)) 3)
               ((and (>= i 97) (<= i 122)) 4)
               ((and (>= i 48) (<= i 57)) 7)
               (else 8)))]
      (do
        (bytesSet t i c)
        (initAsciiTable! t (+ i 1)))))

fn bsearchClass unicodeTable: Bytes lo: Int64 hi: Int64 cp: Int64 -> Int64
  (if (> lo hi) 8
    (let [(mid (/ (+ lo hi) 2))
          (midOff (* mid 7))
          (s (+ (+ (* (bytesGet unicodeTable midOff) 65536)
                   (* (bytesGet unicodeTable (+ midOff 1)) 256))
                (bytesGet unicodeTable (+ midOff 2))))
          (e (+ (+ (* (bytesGet unicodeTable (+ midOff 3)) 65536)
                   (* (bytesGet unicodeTable (+ midOff 4)) 256))
                (bytesGet unicodeTable (+ midOff 5))))]
      (cond
        ((< cp s) (bsearchClass unicodeTable lo (- mid 1) cp))
        ((> cp e) (bsearchClass unicodeTable (+ mid 1) hi cp))
        (else (bytesGet unicodeTable (+ midOff 6))))))

fn getClass asciiTable: Bytes unicodeTable: Bytes nRanges: Int64 cp: Int64 -> Int64
  (if (< cp 128)
    (bytesGet asciiTable cp)
    (bsearchClass unicodeTable 0 (- nRanges 1) cp))

fn decodeUtf8 bs: Bytes i: Int64 n: Int64 -> (Pair Int64 Int64)
  (let [(b0 (bytesGet bs i))]
    (cond
      ((< b0 128) (pair b0 1))
      ((and (>= b0 192) (< b0 224))
        (if (< (+ i 1) n)
          (let [(b1 (bytesGet bs (+ i 1)))]
            (pair (+ (* (- b0 192) 64) (- b1 128)) 2))
          (pair b0 1)))
      ((and (>= b0 224) (< b0 240))
        (if (< (+ i 2) n)
          (let [(b1 (bytesGet bs (+ i 1)))
                (b2 (bytesGet bs (+ i 2)))]
            (pair (+ (+ (* (- b0 224) 4096) (* (- b1 128) 64)) (- b2 128)) 3))
          (pair b0 1)))
      ((>= b0 240)
        (if (< (+ i 3) n)
          (let [(b1 (bytesGet bs (+ i 1)))
                (b2 (bytesGet bs (+ i 2)))
                (b3 (bytesGet bs (+ i 3)))]
            (pair (+ (+ (+ (* (- b0 240) 262144) (* (- b1 128) 4096)) (* (- b2 128) 64)) (- b3 128)) 4))
          (pair b0 1)))
      (else (pair b0 1))))

fn checkContraction bs: Bytes j: Int64 n: Int64 -> Int64
  (if (>= j n) j
    (if (!= (bytesGet bs j) 39) j
      (let [(rem (- n (+ j 1)))]
        (cond
          ((>= rem 2)
            (let [(c0 (toLower (bytesGet bs (+ j 1))))
                  (c1 (toLower (bytesGet bs (+ j 2))))]
              (if (or (and (= c0 114) (= c1 101))
                      (or (and (= c0 118) (= c1 101))
                          (and (= c0 108) (= c1 108))))
                (+ j 3)
                (if (or (= c0 115) (or (= c0 116) (or (= c0 109) (= c0 100))))
                  (+ j 2)
                  j))))
          ((>= rem 1)
            (let [(c0 (toLower (bytesGet bs (+ j 1))))]
              (if (or (= c0 115) (or (= c0 116) (or (= c0 109) (= c0 100))))
                (+ j 2)
                j)))
          (else j)))))

fn scanUpper bs: Bytes j: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 -> Int64
  (if (>= j n) j
    (let [(b0 (bytesGet bs j))]
      (if (< b0 128)
        (if (= (bytesGet at b0) 3)
          (scanUpper bs (+ j 1) n at ut nr)
          j)
        (let [(p (decodeUtf8 bs j n))]
          (mt p
            ((pair cp charLen)
              (if (isUpperOrMark (getClass at ut nr cp))
                (scanUpper bs (+ j charLen) n at ut nr)
                j)))))))

fn scanLower bs: Bytes j: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 -> Int64
  (if (>= j n) j
    (let [(b0 (bytesGet bs j))]
      (if (< b0 128)
        (if (= (bytesGet at b0) 4)
          (scanLower bs (+ j 1) n at ut nr)
          j)
        (let [(p (decodeUtf8 bs j n))]
          (mt p
            ((pair cp charLen)
              (if (isLowerOrMark (getClass at ut nr cp))
                (scanLower bs (+ j charLen) n at ut nr)
                j)))))))

fn scanNum bs: Bytes j: Int64 n: Int64 count: Int64 at: Bytes ut: Bytes nr: Int64 -> Int64
  (if (or (>= j n) (>= count 3)) j
    (let [(b0 (bytesGet bs j))]
      (if (< b0 128)
        (if (= (bytesGet at b0) 7)
          (scanNum bs (+ j 1) n (+ count 1) at ut nr)
          j)
        (let [(p (decodeUtf8 bs j n))]
          (mt p
            ((pair cp charLen)
              (if (= (getClass at ut nr cp) 7)
                (scanNum bs (+ j charLen) n (+ count 1) at ut nr)
                j)))))))

fn scanOther bs: Bytes j: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 -> Int64
  (if (>= j n) j
    (let [(b0 (bytesGet bs j))]
      (if (< b0 128)
        (if (= (bytesGet at b0) 8)
          (scanOther bs (+ j 1) n at ut nr)
          j)
        (let [(p (decodeUtf8 bs j n))]
          (mt p
            ((pair cp charLen)
              (if (isPunctOrSymbol (getClass at ut nr cp))
                (scanOther bs (+ j charLen) n at ut nr)
                j)))))))

fn scanSlashNl bs: Bytes j: Int64 n: Int64 -> Int64
  (if (>= j n) j
    (let [(b (bytesGet bs j))]
      (if (or (= b 10) (or (= b 13) (= b 47)))
        (scanSlashNl bs (+ j 1) n)
        j)))

fn scanSpaceWithNl bs: Bytes j: Int64 n: Int64 lastNl: Int64 at: Bytes ut: Bytes nr: Int64 -> (Pair Int64 Int64)
  (if (>= j n) (pair j lastNl)
    (let [(b (bytesGet bs j))]
      (if (or (= b 10) (= b 13))
        (scanSpaceWithNl bs (+ j 1) n (+ j 1) at ut nr)
        (if (< b 128)
          (if (= (bytesGet at b) 2)
            (scanSpaceWithNl bs (+ j 1) n lastNl at ut nr)
            (pair j lastNl))
          (let [(p (decodeUtf8 bs j n))]
            (mt p
              ((pair cp charLen)
                (if (= (getClass at ut nr cp) 2)
                  (scanSpaceWithNl bs (+ j charLen) n lastNl at ut nr)
                  (pair j lastNl)))))))))

fn tryOtherBranches bs: Bytes i: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 c0: Int64 charLen0: Int64 -> Int64
  (cond
    ((= c0 7)
      (scanNum bs (+ i charLen0) n 1 at ut nr))
    ((or (isPunctOrSymbol c0)
         (and (= (bytesGet bs i) 32)
              (and (< (+ i 1) n)
                   (let [(pSp (decodeUtf8 bs (+ i 1) n))]
                     (mt pSp
                       ((pair cpSp _)
                         (isPunctOrSymbol (getClass at ut nr cpSp))))))))
      (let [(hasSp (= (bytesGet bs i) 32))
            (pStart (if hasSp (+ i 1) i))
            (jP (scanOther bs pStart n at ut nr))]
        (scanSlashNl bs jP n)))
    ((isSpace c0)
      (let [(pairSp (scanSpaceWithNl bs i n -1 at ut nr))]
        (mt pairSp
          ((pair endSp lastNl)
            (if (> lastNl 0)
              lastNl
              (if (= endSp n)
                n
                (if (>= (- endSp i) 2)
                  (- endSp 1)
                  endSp)))))))
    (else (+ i charLen0)))

fn matchNextChunk bs: Bytes i: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 -> Int64
  (if (>= i n) i
    (let [(p0 (decodeUtf8 bs i n))]
      (mt p0
        ((pair cp0 charLen0)
          (let [(c0 (getClass at ut nr cp0))]
            (if (or (isLetterOrMark c0) (isOptLead c0))
              (let [(optLead (isOptLead c0))
                    (letStart (if optLead (+ i charLen0) i))]
                (if (< letStart n)
                  (let [(p1 (decodeUtf8 bs letStart n))]
                    (mt p1
                      ((pair cp1 len1)
                        (let [(c1 (getClass at ut nr cp1))]
                          (if (isLetterOrMark c1)
                            (let [(jUp (scanUpper bs letStart n at ut nr))
                                  (jLow (scanLower bs jUp n at ut nr))]
                              (if (> jLow jUp)
                                (checkContraction bs jLow n)
                                (if (> jUp letStart)
                                  (checkContraction bs jUp n)
                                  (tryOtherBranches bs i n at ut nr c0 charLen0))))
                            (tryOtherBranches bs i n at ut nr c0 charLen0))))))
                  (tryOtherBranches bs i n at ut nr c0 charLen0)))
              (tryOtherBranches bs i n at ut nr c0 charLen0)))))))

fn initB64Table! t: Bytes i: Int64 chars: String -> Bytes
  (if (>= i 64) t
    (let [(c (bytesGet (stringToBytes chars) i))]
      (do
        (bytesSet t c i)
        (initB64Table! t (+ i 1) chars))))

fn parseRank bs: Bytes i: Int64 acc: Int64 -> (Pair Int64 Int64)
  (let [(c (bytesGet bs i))]
    (if (or (= c 10) (= c 13))
      (pair acc (+ i (if (and (= c 13) (= (bytesGet bs (+ i 1)) 10)) 2 1)))
      (parseRank bs (+ i 1) (+ (* acc 10) (- c 48)))))

fn findSpace bs: Bytes i: Int64 -> Int64
  (if (= (bytesGet bs i) 32) i (findSpace bs (+ i 1)))

fn decodeB64! bs: Bytes i: Int64 endI: Int64 b64t: Bytes out: Bytes outOff: Int64 -> Int64
  (if (>= i endI) outOff
    (let [(c0 (bytesGet bs i))
          (c1 (bytesGet bs (+ i 1)))
          (c2 (bytesGet bs (+ i 2)))
          (c3 (bytesGet bs (+ i 3)))
          (v0 (bytesGet b64t c0))
          (v1 (bytesGet b64t c1))
          (b0 (+ (* v0 4) (/ v1 16)))]
      (do
        (bytesSet out outOff b0)
        (if (= c2 61)
          (+ outOff 1)
          (let [(v2 (bytesGet b64t c2))
                (b1 (+ (* (mod v1 16) 16) (/ v2 4)))]
            (do
              (bytesSet out (+ outOff 1) b1)
              (if (= c3 61)
                (+ outOff 2)
                (let [(v3 (bytesGet b64t c3))
                      (b2 (+ (* (mod v2 4) 64) v3))]
                  (do
                    (bytesSet out (+ outOff 2) b2)
                    (decodeB64! bs (+ i 4) endI b64t out (+ outOff 3)))))))))))

fn hashBytes bs: Bytes off: Int64 len: Int64 i: Int64 h: Int64 -> Int64
  (if (>= i len) h
    (let [(b (bytesGet bs (+ off i)))
          (hNext (mod (+ (* h 31) b) 524287))]
      (hashBytes bs off len (+ i 1) hNext)))

fn insertTable! table: Bytes mask: Int64 slot: Int64 off: Int64 len: Int64 rank: Int64 -> Bool
  (let [(slotOff (* slot 8))
        (status (bytesGet table (+ slotOff 7)))]
    (if (= status 0)
      (do
        (bytesSet table slotOff (mod off 256))
        (bytesSet table (+ slotOff 1) (mod (/ off 256) 256))
        (bytesSet table (+ slotOff 2) (mod (/ off 65536) 256))
        (bytesSet table (+ slotOff 3) len)
        (bytesSet table (+ slotOff 4) (mod rank 256))
        (bytesSet table (+ slotOff 5) (mod (/ rank 256) 256))
        (bytesSet table (+ slotOff 6) (mod (/ rank 65536) 256))
        (bytesSet table (+ slotOff 7) 1)
        true)
      (insertTable! table mask (mod (+ slot 1) mask) off len rank)))

fn parseAll! bs: Bytes i: Int64 n: Int64 b64t: Bytes tokenBytes: Bytes tbOff: Int64 table: Bytes mask: Int64 count: Int64 -> (Pair Int64 Int64)
  (if (>= i n) (pair count tbOff)
    (let [(c (bytesGet bs i))]
      (if (or (= c 10) (= c 13))
        (parseAll! bs (+ i 1) n b64t tokenBytes tbOff table mask count)
        (let [(sp (findSpace bs i))
              (pRank (parseRank bs (+ sp 1) 0))]
          (mt pRank
            ((pair rank nextI)
              (let [(newTbOff (decodeB64! bs i sp b64t tokenBytes tbOff))
                    (tokLen (- newTbOff tbOff))
                    (h (hashBytes tokenBytes tbOff tokLen 0 2166136261))
                    (slot (mod h mask))]
                (do
                  (insertTable! table mask slot tbOff tokLen rank)
                  (parseAll! bs nextI n b64t tokenBytes newTbOff table mask (+ count 1))))))))))

fn bytesEqual a: Bytes aOff: Int64 b: Bytes bOff: Int64 len: Int64 i: Int64 -> Bool
  (if (>= i len) true
    (if (!= (bytesGet a (+ aOff i)) (bytesGet b (+ bOff i)))
      false
      (bytesEqual a aOff b bOff len (+ i 1))))

fn lookupRank tokenBytes: Bytes table: Bytes mask: Int64 key: Bytes keyOff: Int64 keyLen: Int64 slot: Int64 -> Int64
  (let [(slotOff (* slot 8))
        (status (bytesGet table (+ slotOff 7)))]
    (if (= status 0)
      -1
      (let [(slotLen (bytesGet table (+ slotOff 3)))]
        (if (= slotLen keyLen)
          (let [(slotTbOff (+ (+ (bytesGet table slotOff)
                                 (* (bytesGet table (+ slotOff 1)) 256))
                              (* (bytesGet table (+ slotOff 2)) 65536)))]
            (if (bytesEqual tokenBytes slotTbOff key keyOff keyLen 0)
              (+ (+ (bytesGet table (+ slotOff 4))
                    (* (bytesGet table (+ slotOff 5)) 256))
                 (* (bytesGet table (+ slotOff 6)) 65536))
              (lookupRank tokenBytes table mask key keyOff keyLen (mod (+ slot 1) mask))))
          (lookupRank tokenBytes table mask key keyOff keyLen (mod (+ slot 1) mask))))))

fn getI32 b: Bytes off: Int64 -> Int64
  (+ (+ (+ (bytesGet b off)
           (* (bytesGet b (+ off 1)) 256))
        (* (bytesGet b (+ off 2)) 65536))
     (* (bytesGet b (+ off 3)) 16777216))

fn setI32! b: Bytes off: Int64 val: Int64 -> Unit
  (do
    (bytesSet b off (mod val 256))
    (bytesSet b (+ off 1) (mod (/ val 256) 256))
    (bytesSet b (+ off 2) (mod (/ val 65536) 256))
    (bytesSet b (+ off 3) (mod (/ val 16777216) 256)))

fn piecePrev pieces: Bytes i: Int64 -> Int64
  (- (getI32 pieces (* i 16)) 1)

fn pieceNext pieces: Bytes i: Int64 -> Int64
  (- (getI32 pieces (+ (* i 16) 4)) 1)

fn pieceOff pieces: Bytes i: Int64 -> Int64
  (getI32 pieces (+ (* i 16) 8))

fn pieceLen pieces: Bytes i: Int64 -> Int64
  (getI32 pieces (+ (* i 16) 12))

fn setPiecePrev! pieces: Bytes i: Int64 p: Int64 -> Unit
  (setI32! pieces (* i 16) (+ p 1))

fn setPieceNext! pieces: Bytes i: Int64 nxt: Int64 -> Unit
  (setI32! pieces (+ (* i 16) 4) (+ nxt 1))

fn setPieceOff! pieces: Bytes i: Int64 off: Int64 -> Unit
  (setI32! pieces (+ (* i 16) 8) off)

fn setPieceLen! pieces: Bytes i: Int64 len: Int64 -> Unit
  (setI32! pieces (+ (* i 16) 12) len)

fn heapRank heap: Bytes k: Int64 -> Int64
  (getI32 heap (* k 12))

fn heapIdx heap: Bytes k: Int64 -> Int64
  (getI32 heap (+ (* k 12) 4))

fn heapLen heap: Bytes k: Int64 -> Int64
  (getI32 heap (+ (* k 12) 8))

fn setHeapNode! heap: Bytes k: Int64 rank: Int64 idx: Int64 len: Int64 -> Unit
  (do
    (setI32! heap (* k 12) rank)
    (setI32! heap (+ (* k 12) 4) idx)
    (setI32! heap (+ (* k 12) 8) len))

fn copyHeapNode! heap: Bytes dst: Int64 src: Int64 -> Unit
  (setHeapNode! heap dst (heapRank heap src) (heapIdx heap src) (heapLen heap src))

fn isHeapLess heap: Bytes a: Int64 b: Int64 -> Bool
  (let [(ra (heapRank heap a))
        (rb (heapRank heap b))]
    (if (< ra rb) true
      (if (> ra rb) false
        (< (heapIdx heap a) (heapIdx heap b)))))

fn siftUp! heap: Bytes k: Int64 -> Unit
  (if (<= k 0) ()
    (let [(p (/ (- k 1) 2))]
      (if (isHeapLess heap k p)
        (let [(rK (heapRank heap k))
              (iK (heapIdx heap k))
              (lK (heapLen heap k))]
          (do
            (copyHeapNode! heap k p)
            (setHeapNode! heap p rK iK lK)
            (siftUp! heap p)))
        ())))

fn siftDown! heap: Bytes k: Int64 size: Int64 -> Unit
  (let [(l (+ (* k 2) 1))
        (r (+ (* k 2) 2))]
    (if (>= l size) ()
      (let [(smallest (if (and (< r size) (isHeapLess heap r l)) r l))]
        (if (isHeapLess heap smallest k)
          (let [(rK (heapRank heap k))
                (iK (heapIdx heap k))
                (lK (heapLen heap k))]
            (do
              (copyHeapNode! heap k smallest)
              (setHeapNode! heap smallest rK iK lK)
              (siftDown! heap smallest size)))
          ()))))

fn heapPush! heap: Bytes size: Int64 rank: Int64 idx: Int64 len: Int64 -> Int64
  (do
    (setHeapNode! heap size rank idx len)
    (siftUp! heap size)
    (+ size 1))

fn heapPop! heap: Bytes size: Int64 -> Int64
  (if (<= size 1) 0
    (do
      (copyHeapNode! heap 0 (- size 1))
      (siftDown! heap 0 (- size 1))
      (- size 1)))

fn initPiecesLoop! pieces: Bytes k: Int64 n: Int64 -> Unit
  (if (>= k n) ()
    (do
      (setPiecePrev! pieces k (- k 1))
      (setPieceNext! pieces k (if (= k (- n 1)) -1 (+ k 1)))
      (setPieceOff! pieces k k)
      (setPieceLen! pieces k 1)
      (initPiecesLoop! pieces (+ k 1) n)))

fn initHeapLoop! tb: Bytes tbl: Bytes mask: Int64 textBytes: Bytes baseOff: Int64 heap: Bytes size: Int64 i: Int64 n: Int64 -> Int64
  (if (>= i (- n 1)) size
    (let [(pairOff (+ baseOff i))
          (h (hashBytes textBytes pairOff 2 0 2166136261))
          (rank (lookupRank tb tbl mask textBytes pairOff 2 (mod h mask)))]
      (if (>= rank 0)
        (let [(newSize (heapPush! heap size rank i 1))]
          (initHeapLoop! tb tbl mask textBytes baseOff heap newSize (+ i 1) n))
        (initHeapLoop! tb tbl mask textBytes baseOff heap size (+ i 1) n))))

fn pushPairIfRanked! tb: Bytes tbl: Bytes mask: Int64 textBytes: Bytes baseOff: Int64 pieces: Bytes heap: Bytes size: Int64 leftIdx: Int64 rightIdx: Int64 -> Int64
  (if (or (< leftIdx 0) (< rightIdx 0)) size
    (let [(lLen (pieceLen pieces leftIdx))
          (rLen (pieceLen pieces rightIdx))
          (pairLen (+ lLen rLen))
          (pairOff (+ baseOff (pieceOff pieces leftIdx)))
          (h (hashBytes textBytes pairOff pairLen 0 2166136261))
          (rank (lookupRank tb tbl mask textBytes pairOff pairLen (mod h mask)))]
      (if (>= rank 0)
        (heapPush! heap size rank leftIdx lLen)
        size)))

fn bpeHeapLoop! tb: Bytes tbl: Bytes mask: Int64 textBytes: Bytes baseOff: Int64 pieces: Bytes heap: Bytes size: Int64 count: Int64 -> Int64
  (if (<= size 0) count
    (let [(topRank (heapRank heap 0))
          (topIdx (heapIdx heap 0))
          (topLen (heapLen heap 0))
          (newSize (heapPop! heap size))]
      (if (!= (pieceLen pieces topIdx) topLen)
        (bpeHeapLoop! tb tbl mask textBytes baseOff pieces heap newSize count)
        (let [(nxt (pieceNext pieces topIdx))]
          (if (< nxt 0)
            (bpeHeapLoop! tb tbl mask textBytes baseOff pieces heap newSize count)
            (let [(pairLen (+ topLen (pieceLen pieces nxt)))
                  (pairOff (+ baseOff (pieceOff pieces topIdx)))
                  (h (hashBytes textBytes pairOff pairLen 0 2166136261))
                  (curRank (lookupRank tb tbl mask textBytes pairOff pairLen (mod h mask)))]
              (if (!= curRank topRank)
                (bpeHeapLoop! tb tbl mask textBytes baseOff pieces heap newSize count)
                (let [(nxtNext (pieceNext pieces nxt))
                      (prev (piecePrev pieces topIdx))]
                  (do
                    (setPieceLen! pieces topIdx pairLen)
                    (setPieceNext! pieces topIdx nxtNext)
                    (if (>= nxtNext 0)
                      (setPiecePrev! pieces nxtNext topIdx)
                      ())
                    (setPieceLen! pieces nxt 0)
                    (let [(s1 (pushPairIfRanked! tb tbl mask textBytes baseOff pieces heap newSize prev topIdx))
                          (s2 (pushPairIfRanked! tb tbl mask textBytes baseOff pieces heap s1 topIdx nxtNext))]
                      (bpeHeapLoop! tb tbl mask textBytes baseOff pieces heap s2 (- count 1))))))))))))

fn bpeCountChunk! tokenBytes: Bytes table: Bytes mask: Int64 textBytes: Bytes i: Int64 chunkLen: Int64 sOff: Bytes sLen: Bytes -> Int64
  (cond
    ((<= chunkLen 0) 0)
    ((= chunkLen 1) 1)
    (else
      (let [(h (hashBytes textBytes i chunkLen 0 2166136261))
            (wholeRank (lookupRank tokenBytes table mask textBytes i chunkLen (mod h mask)))]
        (if (>= wholeRank 0)
          1
          (let [(pieces (if (<= chunkLen 1024) sOff (bytesAlloc (* chunkLen 16))))
                (heap (if (<= chunkLen 1024) sLen (bytesAlloc (* chunkLen 36))))]
            (do
              (initPiecesLoop! pieces 0 chunkLen)
              (let [(initSize (initHeapLoop! tokenBytes table mask textBytes i heap 0 0 chunkLen))]
                (bpeHeapLoop! tokenBytes table mask textBytes i pieces heap initSize chunkLen))))))))

fn countTokensLoop! bs: Bytes i: Int64 n: Int64 at: Bytes ut: Bytes nr: Int64 tb: Bytes tbl: Bytes mask: Int64 sOff: Bytes sLen: Bytes total: Int64 -> Int64
  (if (>= i n) total
    (let [(nextI (matchNextChunk bs i n at ut nr))]
      (if (<= nextI i)
        (do (assert (> nextI i) "ERR_CHUNK_STALL: matchNextChunk failed to advance") total)
        (let [(chunkLen (- nextI i))
              (toks (bpeCountChunk! tb tbl mask bs i chunkLen sOff sLen))]
          (countTokensLoop! bs nextI n at ut nr tb tbl mask sOff sLen (+ total toks))))))

fn loadTokenizer! dataDir: String -> (Result Tokenizer String)
  (let [(tiktokenPath (str dataDir "/o200k_base.tiktoken"))
        (classesPath (str dataDir "/unicode_classes.bin"))
        (resUt (fileReadBytes classesPath))]
    (mt resUt
      ((err e) (err (str "loadTokenizer: cannot read " classesPath ": " e)))
      ((ok ut)
        (let [(resTk (fileReadBytes tiktokenPath))]
          (mt resTk
            ((err e) (err (str "loadTokenizer: cannot read " tiktokenPath ": " e)))
            ((ok bsTk)
              (let [(nr (/ (bytesLength ut) 7))
                    (at (bytesAlloc 128))
                    (_ (initAsciiTable! at 0))
                    (b64t (bytesAlloc 256))
                    (_ (initB64Table! b64t 0 "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))
                    (tokenBytes (bytesAlloc 3000000))
                    (mask 524288)
                    (table (bytesAlloc (* mask 8)))
                    (_ (parseAll! bsTk 0 (bytesLength bsTk) b64t tokenBytes 0 table mask 0))
                    (sOff (bytesAlloc 16384))
                    (sLen (bytesAlloc 36864))]
                (ok (Tokenizer :tokenBytes tokenBytes
                               :table table
                               :mask mask
                               :asciiTable at
                               :unicodeTable ut
                               :nUnicodeRanges nr
                               :scratchOff sOff
                               :scratchLen sLen)))))))))

fn countTokensBytes! tok: Tokenizer bs: Bytes -> Int64
  (let [(n (bytesLength bs))]
    (if (<= n 0) 0
      (countTokensLoop! bs 0 n
                       tok.asciiTable
                       tok.unicodeTable
                       tok.nUnicodeRanges
                       tok.tokenBytes
                       tok.table
                       tok.mask
                       tok.scratchOff
                       tok.scratchLen
                       0)))

fn countTokens! tok: Tokenizer text: String -> Int64
  (countTokensBytes! tok (stringToBytes text))
