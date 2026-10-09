(module asl-syntax/tests/core/sourceTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)])

fn unwrapPos opt: (Option src/SourcePos) -> src/SourcePos
  (mt opt
    ((some p) p)
    ((none) (src/SourcePos :line -1 :byteCol -1 :charCol -1)))

fn testEmptyFile -> Bool
  (let [(b (bytesAlloc 0))
        (s (src/sourceFromBytes "empty.txt" b))]
    (assert (= (src/sourceLength s) 0) "empty file length is 0")
    (assert (= (src/sourceLineCount s) 1) "empty file has 1 line")
    (assert (not (src/sourceHasBom s)) "empty file has no BOM")
    (assert (= (src/binaryKind b) "") "empty file is text")
    (let [(p (unwrapPos (src/sourcePosAt s 0)))]
      (assert (= p.line 1) "pos at 0 line is 1")
      (assert (= p.byteCol 1) "pos at 0 byteCol is 1")
      (assert (= p.charCol 1) "pos at 0 charCol is 1"))
    (assert (= (src/sourceOffsetAt s 1 1) (some 0)) "offset at 1 1 is 0")
    (assert (= (src/sourceCharOffsetAt s 1 1) (some 0)) "char offset at 1 1 is 0")
    true)

fn testCrlf -> Bool
  (let [(s (src/sourceFromString "crlf.txt" "hello\r\nworld\r\n"))]
    (assert (= (src/sourceLineCount s) 3) "crlf text has 3 lines")
    (assert (= (src/sourceLineStart s 1) (some 0)) "line 1 starts at 0")
    (assert (= (src/sourceLineStart s 2) (some 7)) "line 2 starts at 7")
    (assert (= (src/sourceLineStart s 3) (some 14)) "line 3 starts at 14")
    (let [(pW (unwrapPos (src/sourcePosAt s 7)))]
      (assert (= pW.line 2) "w line is 2")
      (assert (= pW.byteCol 1) "w byteCol is 1")
      (assert (= pW.charCol 1) "w charCol is 1"))
    (let [(pCr (unwrapPos (src/sourcePosAt s 5)))]
      (assert (= pCr.line 1) "cr line is 1")
      (assert (= pCr.byteCol 6) "cr byteCol is 6")
      (assert (= pCr.charCol 6) "cr charCol is 6"))
    (let [(pLf (unwrapPos (src/sourcePosAt s 6)))]
      (assert (= pLf.line 1) "lf line is 1")
      (assert (= pLf.byteCol 7) "lf byteCol is 7")
      (assert (= pLf.charCol 7) "lf charCol is 7"))
    (assert (= (src/sourceOffsetAt s 2 1) (some 7)) "offset of line 2 col 1 is 7")
    (assert (= (src/sourceCharOffsetAt s 2 1) (some 7)) "char offset of line 2 col 1 is 7")
    true)

fn testLoneCr -> Bool
  (let [(s (src/sourceFromString "cr.txt" "foo\rbar\rbaz"))]
    (assert (= (src/sourceLineCount s) 3) "lone cr text has 3 lines")
    (assert (= (src/sourceLineStart s 1) (some 0)) "line 1 starts at 0")
    (assert (= (src/sourceLineStart s 2) (some 4)) "line 2 starts at 4")
    (assert (= (src/sourceLineStart s 3) (some 8)) "line 3 starts at 8")
    (let [(pB (unwrapPos (src/sourcePosAt s 4)))]
      (assert (= pB.line 2) "bar b line is 2")
      (assert (= pB.byteCol 1) "bar b byteCol is 1")
      (assert (= pB.charCol 1) "bar b charCol is 1"))
    (let [(pA (unwrapPos (src/sourcePosAt s 9)))]
      (assert (= pA.line 3) "baz a line is 3")
      (assert (= pA.byteCol 2) "baz a byteCol is 2")
      (assert (= pA.charCol 2) "baz a charCol is 2"))
    (assert (= (src/sourceOffsetAt s 3 2) (some 9)) "offset of line 3 col 2 is 9")
    (assert (= (src/sourceCharOffsetAt s 3 2) (some 9)) "char offset of line 3 col 2 is 9")
    true)

fn testMixedNewlines -> Bool
  (let [(s (src/sourceFromString "mixed.txt" "line1\nline2\r\nline3\rline4"))]
    (assert (= (src/sourceLineCount s) 4) "mixed text has 4 lines")
    (assert (= (src/sourceLineStart s 1) (some 0)) "line 1 starts at 0")
    (assert (= (src/sourceLineStart s 2) (some 6)) "line 2 starts at 6")
    (assert (= (src/sourceLineStart s 3) (some 13)) "line 3 starts at 13")
    (assert (= (src/sourceLineStart s 4) (some 19)) "line 4 starts at 19")
    true)

fn testInvalidBytes -> Bool
  (let [(b (bytesAlloc 7))]
    (bytesSet b 0 65)
    (bytesSet b 1 255)
    (bytesSet b 2 66)
    (bytesSet b 3 192)
    (bytesSet b 4 67)
    (bytesSet b 5 128)
    (bytesSet b 6 68)
    (let [(s (src/sourceFromBytes "invalid.txt" b))]
      (assert (= (src/sourceLength s) 7) "invalid bytes kept length 7")
      (assert (= (src/binaryKind b) "") "invalid bytes without NUL is text")
      (let [(p0 (unwrapPos (src/sourcePosAt s 0)))
            (p1 (unwrapPos (src/sourcePosAt s 1)))
            (p2 (unwrapPos (src/sourcePosAt s 2)))
            (p3 (unwrapPos (src/sourcePosAt s 3)))
            (p4 (unwrapPos (src/sourcePosAt s 4)))
            (p5 (unwrapPos (src/sourcePosAt s 5)))
            (p6 (unwrapPos (src/sourcePosAt s 6)))]
        (assert (= p0.line 1) "p0 line is 1")
        (assert (= p0.byteCol 1) "p0 byteCol is 1")
        (assert (= p0.charCol 1) "p0 charCol is 1")
        (assert (= p1.line 1) "p1 line is 1")
        (assert (= p1.byteCol 2) "p1 byteCol is 2")
        (assert (= p1.charCol 2) "p1 charCol is 2")
        (assert (= p2.byteCol 3) "p2 byteCol is 3")
        (assert (= p2.charCol 3) "p2 charCol is 3")
        (assert (= p3.byteCol 4) "p3 byteCol is 4")
        (assert (= p3.charCol 4) "p3 charCol is 4")
        (assert (= p4.byteCol 5) "p4 byteCol is 5")
        (assert (= p4.charCol 5) "p4 charCol is 5")
        (assert (= p5.byteCol 6) "p5 byteCol is 6")
        (assert (= p5.charCol 6) "p5 charCol is 6")
        (assert (= p6.byteCol 7) "p6 byteCol is 7")
        (assert (= p6.charCol 7) "p6 charCol is 7"))
      (assert (= (src/sourceOffsetAt s 1 6) (some 5)) "offset of line 1 col 6 is 5")
      (assert (= (src/sourceCharOffsetAt s 1 6) (some 5)) "char offset of line 1 col 6 is 5")
      true))

fn testMultiByteUtf8 -> Bool
  (let [(b (bytesAlloc 7))]
    (bytesSet b 0 65)
    (bytesSet b 1 226)
    (bytesSet b 2 130)
    (bytesSet b 3 172)
    (bytesSet b 4 66)
    (bytesSet b 5 10)
    (bytesSet b 6 67)
    (let [(s (src/sourceFromBytes "euro.txt" b))]
      (assert (= (src/sourceLineCount s) 2) "2 lines in euro text")
      (let [(pA (unwrapPos (src/sourcePosAt s 0)))
            (pEuro (unwrapPos (src/sourcePosAt s 1)))
            (pB (unwrapPos (src/sourcePosAt s 4)))
            (pC (unwrapPos (src/sourcePosAt s 6)))]
        (assert (= pA.byteCol 1) "A byteCol is 1")
        (assert (= pA.charCol 1) "A charCol is 1")
        (assert (= pEuro.byteCol 2) "Euro byteCol is 2")
        (assert (= pEuro.charCol 2) "Euro charCol is 2")
        (assert (= pB.byteCol 5) "B byteCol is 5")
        (assert (= pB.charCol 3) "B charCol is 3")
        (assert (= pC.line 2) "C line is 2")
        (assert (= pC.byteCol 1) "C byteCol is 1")
        (assert (= pC.charCol 1) "C charCol is 1"))
      (assert (= (src/sourceOffsetAt s 1 5) (some 4)) "offset at byteCol 5 is 4")
      (assert (= (src/sourceCharOffsetAt s 1 3) (some 4)) "offset at charCol 3 is 4")
      true))

fn testBom -> Bool
  (let [(b (bytesAlloc 6))]
    (bytesSet b 0 239)
    (bytesSet b 1 187)
    (bytesSet b 2 191)
    (bytesSet b 3 65)
    (bytesSet b 4 10)
    (bytesSet b 5 66)
    (let [(s (src/sourceFromBytes "bom.txt" b))]
      (assert (src/sourceHasBom s) "file has BOM")
      (assert (= (src/sourceLineCount s) 2) "bom file has 2 lines")
      (let [(pBom (unwrapPos (src/sourcePosAt s 0)))
            (pA (unwrapPos (src/sourcePosAt s 3)))
            (pB (unwrapPos (src/sourcePosAt s 5)))]
        (assert (= pBom.line 1) "bom line is 1")
        (assert (= pBom.byteCol 1) "bom byteCol is 1")
        (assert (= pBom.charCol 1) "bom charCol is 1")
        (assert (= pA.line 1) "A line is 1")
        (assert (= pA.byteCol 4) "A byteCol is 4")
        (assert (= pA.charCol 2) "A charCol is 2")
        (assert (= pB.line 2) "B line is 2")
        (assert (= pB.byteCol 1) "B byteCol is 1")
        (assert (= pB.charCol 1) "B charCol is 1"))
      (assert (= (src/sourceOffsetAt s 1 4) (some 3)) "offset of A is 3")
      (assert (= (src/sourceCharOffsetAt s 1 2) (some 3)) "char offset of A is 3")
      true))

fn testOneMbSingleLine -> Bool
  (let [(b (bytesAlloc 1048576))
        (s (src/sourceFromBytes "single_line_1mb.txt" b))]
    (assert (= (src/sourceLength s) 1048576) "1 MB length is 1048576")
    (assert (= (src/sourceLineCount s) 1) "1 MB single line has 1 line")
    (let [(pMid (unwrapPos (src/sourcePosAt s 500000)))]
      (assert (= pMid.line 1) "midpoint line is 1")
      (assert (= pMid.byteCol 500001) "midpoint byteCol is 500001")
      (assert (= pMid.charCol 500001) "midpoint charCol is 500001"))
    (assert (= (src/sourceOffsetAt s 1 500001) (some 500000)) "offset roundtrip at 500000")
    true)

fn testBinaryMagicCases -> Bool
  (let [(machoLe64 (bytesAlloc 4))
        (machoLe32 (bytesAlloc 4))
        (machoBe64 (bytesAlloc 4))
        (machoBe32 (bytesAlloc 4))
        (machofat (bytesAlloc 4))
        (elf (bytesAlloc 4))
        (wasm (bytesAlloc 4))
        (gzip (bytesAlloc 2))
        (zip (bytesAlloc 4))
        (png (bytesAlloc 8))
        (jpeg (bytesAlloc 3))
        (pe (bytesAlloc 3))
        (mzText (bytesAlloc 4))
        (genericBin (bytesAlloc 4))
        (plainText (bytesAlloc 4))
        (nulAt8191 (bytesAlloc 8192))
        (nulAt8192 (bytesAlloc 8193))]
    (bytesSet machoLe64 0 207)
    (bytesSet machoLe64 1 250)
    (bytesSet machoLe64 2 237)
    (bytesSet machoLe64 3 254)
    (assert (= (src/binaryKind machoLe64) "machO") "macho 64 LE")

    (bytesSet machoLe32 0 206)
    (bytesSet machoLe32 1 250)
    (bytesSet machoLe32 2 237)
    (bytesSet machoLe32 3 254)
    (assert (= (src/binaryKind machoLe32) "machO") "macho 32 LE")

    (bytesSet machoBe64 0 254)
    (bytesSet machoBe64 1 237)
    (bytesSet machoBe64 2 250)
    (bytesSet machoBe64 3 207)
    (assert (= (src/binaryKind machoBe64) "machO") "macho 64 BE")

    (bytesSet machoBe32 0 254)
    (bytesSet machoBe32 1 237)
    (bytesSet machoBe32 2 250)
    (bytesSet machoBe32 3 206)
    (assert (= (src/binaryKind machoBe32) "machO") "macho 32 BE")

    (bytesSet machofat 0 202)
    (bytesSet machofat 1 254)
    (bytesSet machofat 2 186)
    (bytesSet machofat 3 190)
    (assert (= (src/binaryKind machofat) "machOFat") "machoFat")

    (bytesSet elf 0 127)
    (bytesSet elf 1 69)
    (bytesSet elf 2 76)
    (bytesSet elf 3 70)
    (assert (= (src/binaryKind elf) "elf") "elf")

    (bytesSet wasm 0 0)
    (bytesSet wasm 1 97)
    (bytesSet wasm 2 115)
    (bytesSet wasm 3 109)
    (assert (= (src/binaryKind wasm) "wasm") "wasm")

    (bytesSet gzip 0 31)
    (bytesSet gzip 1 139)
    (assert (= (src/binaryKind gzip) "gzip") "gzip")

    (bytesSet zip 0 80)
    (bytesSet zip 1 75)
    (bytesSet zip 2 3)
    (bytesSet zip 3 4)
    (assert (= (src/binaryKind zip) "zip") "zip")

    (bytesSet png 0 137)
    (bytesSet png 1 80)
    (bytesSet png 2 78)
    (bytesSet png 3 71)
    (bytesSet png 4 13)
    (bytesSet png 5 10)
    (bytesSet png 6 26)
    (bytesSet png 7 10)
    (assert (= (src/binaryKind png) "png") "png")

    (bytesSet jpeg 0 255)
    (bytesSet jpeg 1 216)
    (bytesSet jpeg 2 255)
    (assert (= (src/binaryKind jpeg) "jpeg") "jpeg")

    (bytesSet pe 0 77)
    (bytesSet pe 1 90)
    (bytesSet pe 2 0)
    (assert (= (src/binaryKind pe) "pe") "pe")

    (bytesSet mzText 0 77)
    (bytesSet mzText 1 90)
    (bytesSet mzText 2 65)
    (bytesSet mzText 3 66)
    (assert (= (src/binaryKind mzText) "") "MZ without NUL is text")

    (bytesSet genericBin 0 65)
    (bytesSet genericBin 1 66)
    (bytesSet genericBin 2 0)
    (bytesSet genericBin 3 67)
    (assert (= (src/binaryKind genericBin) "binary") "generic binary with NUL")

    (bytesSet plainText 0 65)
    (bytesSet plainText 1 66)
    (bytesSet plainText 2 67)
    (bytesSet plainText 3 10)
    (assert (= (src/binaryKind plainText) "") "plain text")

    (let [(init8192 (fn [(i Int64)] -> Unit (bytesSet nulAt8191 i 65)))]
      (map init8192 (range 0 8191)))
    (bytesSet nulAt8191 8191 0)
    (assert (= (src/binaryKind nulAt8191) "binary") "NUL at 8191 is binary")

    (let [(init8193 (fn [(i Int64)] -> Unit (bytesSet nulAt8192 i 65)))]
      (map init8193 (range 0 8192)))
    (bytesSet nulAt8192 8192 0)
    (assert (= (src/binaryKind nulAt8192) "") "NUL at 8192 is text")
    true)

fn testPositionQueryBounds -> Bool
  (let [(s (src/sourceFromString "test.txt" "hello
world"))]
    (assert (= (src/sourcePosAt s -1) (none)) "sourcePosAt negative offset")
    (assert (= (src/sourcePosAt s 12) (none)) "sourcePosAt past-end offset")
    (assert (= (src/sourceLineStart s 0) (none)) "sourceLineStart line 0")
    (assert (= (src/sourceLineStart s -1) (none)) "sourceLineStart negative line")
    (assert (= (src/sourceLineStart s 3) (none)) "sourceLineStart line > count")
    (assert (= (src/sourceOffsetAt s 0 1) (none)) "sourceOffsetAt line 0")
    (assert (= (src/sourceOffsetAt s -1 1) (none)) "sourceOffsetAt negative line")
    (assert (= (src/sourceOffsetAt s 3 1) (none)) "sourceOffsetAt line > count")
    (assert (= (src/sourceCharOffsetAt s 0 1) (none)) "sourceCharOffsetAt line 0")
    (assert (= (src/sourceCharOffsetAt s -1 1) (none)) "sourceCharOffsetAt negative line")
    (assert (= (src/sourceCharOffsetAt s 3 1) (none)) "sourceCharOffsetAt line > count")
    true)

fn testLineEndColBounds -> Bool
  (let [(s (src/sourceFromString "abcd.txt" "ab\ncd"))]
    (assert (= (src/sourceOffsetAt s 1 99) (none)) "offset at col 99 is none")
    (assert (= (src/sourceCharOffsetAt s 1 99) (none)) "char offset at col 99 is none")
    (assert (= (src/sourceOffsetAt s 1 3) (some 2)) "offset at col len+1 is lineEnd 2")
    (assert (= (src/sourceCharOffsetAt s 1 3) (some 2)) "char offset at col len+1 is lineEnd 2")
    (assert (= (src/sourceOffsetAt s 3 1) (none)) "offset line > count agrees with sourceLineStart")
    (assert (= (src/sourceCharOffsetAt s 3 1) (none)) "char offset line > count agrees with sourceLineStart")
    (assert (= (src/sourceLineStart s 3) (none)) "sourceLineStart line > count is none")
    true)

fn testBinaryKindFileError! -> Bool
  (let [(res (src/binaryKindFile! "nonexistent/file/path/that/does/not/exist.bin"))]
    (assert (err? res) "missing file returns err")
    true)

fn buildLineRepeat acc: String s: String count: Int64 -> String
  (if (<= count 0)
    acc
    (buildLineRepeat (stringConcat acc s) s (- count 1)))

fn testThreeHundredLines -> Bool
  (let [(s1 (buildLineRepeat "" "a\n" 150))
        (s2 (buildLineRepeat s1 "b\r" 70))
        (text (buildLineRepeat s2 "c\r\n" 80))
        (s (src/sourceFromString "300lines.txt" text))]
    (assert (>= (src/sourceLineCount s) 300) "at least 300 lines")
    (assert (= (src/sourceLineStart s 128) (some 254)) "line 128 starts at 254")
    (assert (= (src/sourceLineStart s 129) (some 256)) "line 129 starts at 256")
    (assert (= (src/sourceLineStart s 300) (some 677)) "line 300 starts at 677")
    (assert (= (src/sourceLineAt s 254) (some 128)) "sourceLineAt 254 is line 128")
    (assert (= (src/sourceLineAt s 256) (some 129)) "sourceLineAt 256 is line 129")
    (assert (= (src/sourceLineAt s 677) (some 300)) "sourceLineAt 677 is line 300")
    true)

fn testSourceLineEndVariations -> Bool
  (let [(s (src/sourceFromString "line_ends.txt" "hello\nworld\r\nfoo\rbar"))]
    (assert (= (src/sourceLineCount s) 4) "line count is 4")
    (assert (= (src/sourceLineEnd s 1) 5) "lf line end is 5")
    (assert (= (src/sourceLineEnd s 2) 11) "crlf line end is 11")
    (assert (= (src/sourceLineEnd s 3) 16) "lone cr line end is 16")
    (assert (= (src/sourceLineEnd s 4) 20) "last line end is 20")
    true)

fn testBinaryPredicatesAndFile! -> Bool
  (let [(binBytes (bytesAlloc 4))
        (textBytes (stringToBytes "not binary content"))]
    (bytesSet binBytes 0 127)
    (bytesSet binBytes 1 69)
    (bytesSet binBytes 2 76)
    (bytesSet binBytes 3 70)
    (assert (src/isBinary binBytes) "ELF bytes isBinary is true")
    (assert (not (src/isBinary textBytes)) "text bytes isBinary is false")
    (let [(binSrc (src/sourceFromBytes "test.bin" binBytes))
          (txtSrc (src/sourceFromBytes "test.txt" textBytes))]
      (assert (src/sourceIsBinary binSrc) "ELF source sourceIsBinary is true")
      (assert (not (src/sourceIsBinary txtSrc)) "text source sourceIsBinary is false"))
    (let [(missingRes (src/binaryKindFile! "nonexistent_file_path_12345.xyz"))
          (textRes (src/binaryKindFile! "asl/packages/asl-syntax/manifest.asn"))
          (binRes (src/binaryKindFile! "asl/host/out/asl-host"))]
      (assert (err? missingRes) "missing file binaryKindFile is err")
      (assert (ok? textRes) "manifest binaryKindFile is ok")
      (assert (= (resultOr textRes "FAIL") "") "manifest binaryKindFile is empty string")
      (assert (ok? binRes) "host binaryKindFile is ok")
      (assert (!= (resultOr binRes "") "") "host binaryKindFile is non-empty"))
    true)

fn ! runTests -> Bool
  (do
    (assert (testBinaryPredicatesAndFile!) "binary predicates and file suite")
    (assert (testSourceLineEndVariations) "source line end variations suite")
    (assert (testThreeHundredLines) "300 lines suite")
    (assert (testBinaryKindFileError!) "binary kind file error suite")
    (assert (testLineEndColBounds) "line end col bounds suite")
    (assert (testPositionQueryBounds) "position query bounds suite")
    (assert (testEmptyFile) "empty file suite")
    (assert (testCrlf) "crlf suite")
    (assert (testLoneCr) "lone cr suite")
    (assert (testMixedNewlines) "mixed newlines suite")
    (assert (testInvalidBytes) "invalid bytes suite")
    (assert (testMultiByteUtf8) "multibyte utf8 suite")
    (assert (testBom) "bom suite")
    (assert (testOneMbSingleLine) "1mb single line suite")
    (assert (testBinaryMagicCases) "binary magic suite")
    true)
