(module asl-syntax/tests/asl/escapeDiffTest
  :x [runTests]
  :i [(asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/asn :a asn)])

fn hostBin -> String
  "asl/host/out/asl-host"

fn escapeCases -> (List (Pair String Bool))
  (list
    (pair "plain" true)
    (pair "\\n\\t\\r" true)
    (pair "\\\\" true)
    (pair "\\\"" true)
    (pair "\\x41" true)
    (pair "\\xff" true)
    (pair "\\x00" true)
    (pair "\\u0041" true)
    (pair "\\u00e9" true)
    (pair "\\uD7FF" true)
    (pair "\\uE000" true)
    (pair "\\uFFFF" true)
    (pair "\\u{62}" true)
    (pair "\\u{0}" true)
    (pair "\\u{00e9}" true)
    (pair "\\u{000041}" true)
    (pair "\\u{1F600}" true)
    (pair "\\u{10FFFF}" true)
    (pair "a\\u{62}b\\x41\\n" true)
    (pair "\\u{1g}" false)
    (pair "\\u{110000}" false)
    (pair "\\u{}" false)
    (pair "\\u{D800}" false)
    (pair "\\u{DFFF}" false)
    (pair "\\u{1234567}" false)
    (pair "\\u{62 x" false)
    (pair "\\u{-1}" false)
    (pair "\\u{ 1}" false)
    (pair "\\u{" false)
    (pair "\\xZZ" false)
    (pair "\\x-1" false)
    (pair "\\x 1" false)
    (pair "\\x4" false)
    (pair "\\x" false)
    (pair "\\a" false)
    (pair "\\q" false)
    (pair "\\0" false)
    (pair "\\e" false)
    (pair "\\b" false)
    (pair "\\f" false)
    (pair "\\v" false)
    (pair "\\{" false)
    (pair "\\U0010ffff" false)
    (pair "\\u12" false)
    (pair "\\u +1a" false)
    (pair "\\u+1a2" false)
    (pair "\\u-001" false)
    (pair "\\uD800" false)
    (pair "\\uDFFF" false)
    (pair "\\\n" false))

fn makeTempDir! -> (Result String String)
  (let [(res (processRun "mktemp -d"))
        (dir (stringTrim res.stdout))]
    (if (and (= res.exitCode 0) (not (stringEmpty? dir)))
      (ok dir)
      (err (str "mktemp -d failed: " res.stderr))))

fn lexAccepts? text: String -> Bool
  (let [(toks (lx/tokenize text))]
    (and (= (listLength (filter (fn [(t tr/Token)] -> Bool (tr/isErrorToken t)) toks)) 0)
         (= (listLength (filter (fn [(t tr/Token)] -> Bool (lx/isStringToken t)) toks)) 1)))

fn lexErrorFound? text: String -> Bool
  (>= (lx/stringErrorAt (stringToBytes text) (stringLength text) 1) 0)

fn checkCase! dir: String index: Int64 body: String expected: Bool -> Bool
  (let [(path (str dir "/case" (stringFromInt64 index) ".asl"))
        (text (str "\"" body "\"\n"))
        (written (fileWrite path text))
        (label (str "case " (stringFromInt64 index) " " body))]
    (do
      (assert (ok? written) (str label ": temp file written"))
      (let [(res (processRun (str (hostBin) " parse " path)))
            (hostAccepts (= res.exitCode 0))
            (lexAccepts (lexAccepts? text))]
        (do
          (assert (= hostAccepts expected) (str label ": host verdict " (if hostAccepts "accept" "reject")))
          (assert (= lexAccepts expected) (str label ": lexer verdict " (if lexAccepts "accept" "reject")))
          (assert (= (lexErrorFound? text) (not expected)) (str label ": stringErrorAt agrees"))
          (assert (or expected (stringContains? res.stderr (str path ":1:2: ERR_BAD_ESCAPE"))) (str label ": host names ERR_BAD_ESCAPE at FILE:1:2, got " res.stderr))
          (and (= hostAccepts expected) (= lexAccepts expected))))))

fn checkCases! dir: String cases: (List (Pair String Bool)) index: Int64 agreed: Int64 -> Int64
  (match (listHead cases)
    ((none) agreed)
    ((some c)
     (checkCases! dir (listDrop cases 1) (+ index 1)
       (if (checkCase! dir index (pairFirst c) (pairSecond c)) (+ agreed 1) agreed))))

fn testDifferentialTable! -> Bool
  (match (makeTempDir!)
    ((err e) (do (assert false e) false))
    ((ok dir)
     (let [(cases (escapeCases))
           (agreed (checkCases! dir cases 0 0))
           (cleanup (processRun (str "rm -rf '" dir "'")))]
       (do
         (assert (= agreed (listLength cases)) (str "host and lexer agree with the expected verdict on every case: " (stringFromInt64 agreed) "/" (stringFromInt64 (listLength cases))))
         (assert (= cleanup.exitCode 0) "temp dir removed")
         true))))

fn testDecodedValues! -> Bool
  (let [(res (processRun (str (hostBin) " eval '(stringLength \"\\u{62}\")'")))]
    (do
      (assert (= res.exitCode 0) "asl-host eval of a braced escape succeeds")
      (assert (= (stringTrim res.stdout) "1") (str "asl-host eval (stringLength \"\\u{62}\") is 1, got " res.stdout))
      (assert (= (str "\u{62}") "b") "braced escape decodes to one character")
      (assert (= (map (fn [(k Int64)] -> Int64 (bytesGet (stringToBytes "\u{1F600}") k)) (range 0 4)) (list 240 159 152 128)) "braced escape above U+FFFF is 4-byte UTF-8")
      (assert (= (stringLength "\u{10FFFF}") 4) "U+10FFFF is 4 bytes")
      (assert (= (str "\u00e9") "é") "legacy 4-digit escape decodes")
      (assert (= (bytesGet (stringToBytes "\xff") 0) 255) "\\xHH is one raw byte")
      (assert (= (stringLength "\u{0}") 1) "U+0000 is one byte")
      (assert (= (stringLength "\u{7FF}") 2) "U+07FF is 2 bytes")
      (assert (= (stringLength "\u{800}") 3) "U+0800 is 3 bytes")
      (assert (= (stringLength "\uFFFF") 3) "U+FFFF is 3 bytes")
      (assert (= (stringLength "\u{10000}") 4) "U+10000 is 4 bytes")
      true))

fn byteList s: String -> String
  (str "(" (stringJoin (map (fn [(k Int64)] -> String (stringFromInt64 (bytesGet (stringToBytes s) k))) (range 0 (stringLength s))) " ") ")")

fn hostBytes! body: String -> String
  (let [(res (processRun (str (hostBin) " eval '(map (fn [(k Int64)] -> Int64 (bytesGet (stringToBytes \"" body "\") k)) (range 0 (stringLength \"" body "\")))'")))]
    (if (= res.exitCode 0) (stringTrim res.stdout) (str "host eval failed: " res.stderr)))

fn asnDecoded text: String -> (Result String String)
  (mt (asn/asnRead text)
    ((err e) (err e))
    ((ok v) (mt (asn/asnStringValue v) ((some d) (ok d)) ((none) (err "not a string value")))))

fn checkAsnCase! body: String expected: Bool -> Bool
  (let [(text (str "\"" body "\""))
        (decoded (asnDecoded text))
        (step (asn/parseStep (str "(:x " text ")")))]
    (if expected
      (let [(want (hostBytes! body))
            (got (mt decoded ((ok d) (byteList d)) ((err e) (str "asnRead failed: " e))))]
        (do
          (assert (= got want) (str body ": asn bytes " got ", asl-host bytes " want))
          (assert (ok? step) (str body ": parseStep accepts it"))
          (= got want)))
      (let [(why (mt decoded ((ok d) (str "accepted as " (byteList d))) ((err e) e)))
            (stepWhy (mt step ((ok _) "accepted") ((err e) e)))
            (readResult (asn/asnRead text))]
        (do
          (assert (err? readResult) (str body ": asnRead rejects invalid escape"))
          (assert (stringContains? why "ERR_BAD_ESCAPE") (str body ": asnRead names ERR_BAD_ESCAPE, got " why))
          (assert (stringContains? stepWhy "ERR_BAD_ESCAPE") (str body ": parseStep names ERR_BAD_ESCAPE, got " stepWhy))
          (and (stringContains? why "ERR_BAD_ESCAPE") (stringContains? stepWhy "ERR_BAD_ESCAPE"))))))

fn checkAsnCases! cases: (List (Pair String Bool)) agreed: Int64 -> Int64
  (match (listHead cases)
    ((none) agreed)
    ((some c)
     (checkAsnCases! (listDrop cases 1)
       (if (checkAsnCase! (pairFirst c) (pairSecond c)) (+ agreed 1) agreed))))

fn testAsnDecodesAsHost! -> Bool
  (let [(cases (escapeCases))
        (agreed (checkAsnCases! cases 0))]
    (do
      (assert (= agreed (listLength cases)) (str "asn.asl matches asl-host on every case: " (stringFromInt64 agreed) "/" (stringFromInt64 (listLength cases))))
      true))

fn ! runTests -> Bool
  (and (testDifferentialTable!)
  (and (testDecodedValues!)
       (testAsnDecodesAsHost!)))
