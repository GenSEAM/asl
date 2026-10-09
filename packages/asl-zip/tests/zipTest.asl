(module asl-zip/tests/zipTest
  :x [runTests]
  :i [(asl-zip/gzip :a gz) (asl-zip/inflate :a inf)])

fn readFixture! path: String -> Bytes
  (resultOr (fileReadBytes path) (bytesAlloc 0))

fn assertShaMatches! pathPlain: String decoded: Bytes label: String -> Bool
  (let [(plainBytes (readFixture! pathPlain))
        (plainSha (bytesSha256 plainBytes))
        (decodedSha (bytesSha256 decoded))]
    (do
      (assert (= plainSha decodedSha) (str label ": SHA-256 digest match"))
      (assert (= (bytesLength plainBytes) (bytesLength decoded)) (str label ": byte length match"))
      true))

fn testEmpty! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/empty.txt")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/empty.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/empty.txt.gz")))]
    (do
      (assert (ok? defRes) "empty deflate ok")
      (assert (ok? gzRes) "empty gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "empty deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "empty gunzip")))
      true))

fn testShort! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/short.txt")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/short.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/short.txt.gz")))]
    (do
      (assert (ok? defRes) "short deflate ok")
      (assert (ok? gzRes) "short gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "short deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "short gunzip")))
      true))

fn testRepeats! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/repeats.txt")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/repeats.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/repeats.txt.gz")))]
    (do
      (assert (ok? defRes) "repeats deflate ok")
      (assert (ok? gzRes) "repeats gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "repeats deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "repeats gunzip")))
      true))

fn testLarge64k! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/large_64k.txt")
        (defBytes (readFixture! "asl/packages/asl-zip/tests/fixtures/large_64k.deflate"))
        (gzBytes (readFixture! "asl/packages/asl-zip/tests/fixtures/large_64k.txt.gz"))
        (t0 (monotonicNs))
        (gzRes (gz/gunzip! gzBytes))
        (t1 (monotonicNs))
        (defRes (inf/inflate! defBytes))
        (gzMs (/ (- t1 t0) 1000000))]
    (do
      (assert (ok? defRes) "large 64k deflate ok")
      (assert (ok? gzRes) "large 64k gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "large 64k deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "large 64k gunzip")))
      (let [(t1 (monotonicNs))
            (elapsedMs (/ (- t1 t0) 1000000))]
        (do
          (println (str "large_64k (68 KiB) gunzip decode time on asl-host: " (stringFromInt64 gzMs) " ms"))
          true))
      true))

fn testRandomStored! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/random_stored.bin")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/random_stored.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/random_stored.bin.gz")))]
    (do
      (assert (ok? defRes) "random stored deflate ok")
      (assert (ok? gzRes) "random stored gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "random stored deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "random stored gunzip")))
      true))

fn testLevel1! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/level1.txt")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/level1.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/level1.txt.gz")))]
    (do
      (assert (ok? defRes) "level 1 deflate ok")
      (assert (ok? gzRes) "level 1 gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "level 1 deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "level 1 gunzip")))
      true))

fn testLevel9! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/level9.txt")
        (defRes (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/level9.deflate")))
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/level9.txt.gz")))]
    (do
      (assert (ok? defRes) "level 9 deflate ok")
      (assert (ok? gzRes) "level 9 gunzip ok")
      (mt defRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "level 9 deflate")))
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "level 9 gunzip")))
      true))

fn testConcatGzip! -> Bool
  (let [(plainPath "asl/packages/asl-zip/tests/fixtures/concat.txt")
        (gzRes (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/concat.gz")))]
    (do
      (assert (ok? gzRes) "concatenated gunzip ok")
      (mt gzRes
        ((err _) false)
        ((ok b) (assertShaMatches! plainPath b "concatenated gunzip")))
      true))

fn testCrc32Standalone! -> Bool
  (let [(cEmpty (gz/crc32 (bytesAlloc 0)))
        (c123 (gz/crc32 (stringToBytes "123456789")))
        (shortBytes (readFixture! "asl/packages/asl-zip/tests/fixtures/short.txt"))
        (cShort (gz/crc32 shortBytes))]
    (do
      (assert (= cEmpty 0) "empty CRC-32 is 0")
      (assert (= c123 3421780262) "123456789 CRC-32 is 3421780262")
      (assert (> cShort 0) "short text CRC-32 > 0")
      true))

fn testCorruptedVariants! -> Bool
  (let [(resBit (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_bit.gz")))
        (resCrc (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_crc.gz")))
        (resIsize (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_isize.gz")))
        (resTruncGz (gz/gunzip! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_truncated.gz")))
        (resBadBlock (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_bad_block.deflate")))
        (resBadDist (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_bad_dist.deflate")))
        (resTruncDef (inf/inflate! (readFixture! "asl/packages/asl-zip/tests/fixtures/corrupt_truncated.deflate")))]
    (do
      (assert (err? resBit) "corrupt bit returns err")
      (mt resBit ((ok _) (assert false "expected err")) ((err m) (assert (stringContains? m "offset") "corrupt bit mentions offset")))
      (assert (err? resCrc) "corrupt CRC returns err")
      (mt resCrc ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "CRC") "corrupt CRC mentions CRC") (assert (stringContains? m "offset") "corrupt CRC mentions offset"))))
      (assert (err? resIsize) "corrupt ISIZE returns err")
      (mt resIsize ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "ISIZE") "corrupt ISIZE mentions ISIZE") (assert (stringContains? m "offset") "corrupt ISIZE mentions offset"))))
      (assert (err? resTruncGz) "truncated gzip returns err")
      (mt resTruncGz ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "truncated") "truncated gzip mentions truncated") (assert (stringContains? m "offset") "truncated gzip mentions offset"))))
      (assert (err? resBadBlock) "bad block type returns err")
      (mt resBadBlock ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "block") "bad block mentions block") (assert (stringContains? m "offset") "bad block mentions offset"))))
      (assert (err? resBadDist) "distance beyond window returns err")
      (mt resBadDist ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "distance") "bad dist mentions distance") (assert (stringContains? m "offset") "bad dist mentions offset"))))
      (assert (err? resTruncDef) "truncated deflate returns err")
      (mt resTruncDef ((ok _) (assert false "expected err")) ((err m) (do (assert (stringContains? m "truncated") "truncated deflate mentions truncated") (assert (stringContains? m "offset") "truncated deflate mentions offset"))))
      true))

fn testDistanceEqualsOutput! -> Bool
  (let [(raw (bytesAlloc 4))
        (fill (do (bytesSet raw 0 75) (bytesSet raw 1 4) (bytesSet raw 2 2) (bytesSet raw 3 0) true))
        (res (inf/inflate! raw))]
    (do
      (assert fill "fixed block bytes built")
      (assert (ok? res) "match distance equal to decoded length so far is accepted")
      (mt res ((err m) (assert false m)) ((ok b) (do (assert (= (bytesLength b) 4) "literal plus overlapping match decodes four bytes") (assert (= (bytesGet b 3) 97) "last byte copied from distance one"))))
      true))

fn testGunzipLimit! -> Bool
  (let [(gzBytes (readFixture! "asl/packages/asl-zip/tests/fixtures/repeats.txt.gz"))
        (size (bytesLength (readFixture! "asl/packages/asl-zip/tests/fixtures/repeats.txt")))
        (over (gz/gunzipWithLimit! gzBytes (- size 1)))
        (exact (gz/gunzipWithLimit! gzBytes size))
        (shortGz (readFixture! "asl/packages/asl-zip/tests/fixtures/short.txt.gz"))
        (shortSize (bytesLength (readFixture! "asl/packages/asl-zip/tests/fixtures/short.txt")))
        (overShort (gz/gunzipWithLimit! shortGz (- shortSize 1)))
        (exactShort (gz/gunzipWithLimit! shortGz shortSize))]
    (do
      (assert (err? over) "output above the limit returns err")
      (mt over ((ok _) (assert false "expected err")) ((err m) (assert (stringContains? m "limit") "limit error mentions limit")))
      (assert (err? overShort) "literal output above the limit returns err")
      (assert (ok? exactShort) "literal output at exactly the limit is accepted")
      (assert (ok? exact) "output at exactly the limit is accepted")
      (mt exact ((err m) (assert false m)) ((ok b) (assert (= (bytesLength b) size) "output at the limit has full length")))
      true))

fn ! runTests -> Bool
  (do
    (assert (testEmpty!) "empty fixture")
    (assert (testShort!) "short fixture")
    (assert (testRepeats!) "repeats fixture")
    (assert (testLarge64k!) "large 64k fixture")
    (assert (testRandomStored!) "random stored fixture")
    (assert (testLevel1!) "level 1 fixture")
    (assert (testLevel9!) "level 9 fixture")
    (assert (testConcatGzip!) "concatenated gzip fixture")
    (assert (testCrc32Standalone!) "CRC-32 standalone")
    (assert (testCorruptedVariants!) "corrupted variants")
    (assert (testDistanceEqualsOutput!) "distance equals output length")
    (assert (testGunzipLimit!) "gunzip output limit")
    true)
