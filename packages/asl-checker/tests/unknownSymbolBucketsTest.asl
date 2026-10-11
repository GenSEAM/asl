(module asl-checker/tests/unknownSymbolBucketsTest
  :x [runTests]
  :i [(types :a ty) (check :a c)])

fn unknownDiags src: String -> (List ty/Diagnostic)
  (filter (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "rule-1") (= d.code "rule-2"))) (c/checkSource src (mapEmpty) "unknownBucket.asl"))

fn texts ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code "@" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " " d.message)) ds) "; ")

fn accepts? src: String -> Bool
  (let [(ds (unknownDiags src))] (do (assert (listEmpty? ds) (str "host-accepted source has no unknown-symbol diagnostic: " (texts ds))) true))

fn rejects? src: String needle: String -> Bool
  (let [(ds (unknownDiags src))] (do (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.message needle)) ds) (str "a real unknown symbol is still reported: " (texts ds))) true))

fn testMissingBuiltinSig -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f b: Bytes -> String\n  (bytesSha256 b)\n") "bytesSha256 is a direct builtin, not only the sha256 generic alias")
      (assert (accepts? "(module b :x [f])\nfn ! f -> (Result Unit String)\n  (fileChmod \"x\" 420)\n") "fileChmod is Bytes-free Int64 mode over String path")
      (assert (accepts? "(module b :x [f])\nfn ! f -> (Result Unit String)\n  (fileFsync \"x\")\n") "fileFsync takes a path")
      (assert (accepts? "(module b :x [f])\nfn ! f -> (Result String String)\n  (getHomeDir)\n") "getHomeDir takes no arguments")
      (assert (accepts? "(module b :x [f])\nfn ! f -> (Result String String)\n  (localDate)\n") "localDate takes no arguments")
      (assert (accepts? "(module b :x [f])\nfn ! f -> (Result Rusage String)\n  (procRusage)\n") "procRusage takes no arguments")
      (assert (accepts? "(module b :x [f])\nfn f b: Bytes -> (Result Bytes String)\n  (zstdDecompress b)\n") "zstdDecompress takes Bytes")
      (assert (accepts? "(module b :x [f])\nfn f n: Int64 -> Int64\n  (popcount64 n)\n") "popcount64 takes Int64")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> Int64\n  (mt (parquetOpen p) ((ok h) (+ (parquetNumRows h) (parquetNumRowGroups h))) ((err _) 0))\n") "parquetOpen/parquetNumRows/parquetNumRowGroups take a ParquetHandle")
      (assert (accepts? "(module b :x [f])\nfn ! f p: String -> String\n  (mt (parquetOpen p) ((ok h) (parquetColumnType h \"c\")) ((err _) \"\"))\n") "parquetColumnType takes a ParquetHandle and a column name")
      true)

fn testCmpAliasOperators -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f a: Int64 b: Int64 -> Bool\n  (== a b)\n") "== is the same operator as =, not a bare-value reference to it")
      (assert (accepts? "(module b :x [f])\nfn f a: Int64 b: Int64 -> Bool\n  (not= a b)\n") "not= is the same operator as !=")
      true)

fn testKeywordLiteral -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f -> Keyword\n  :full\n") "a bare keyword atom is a Keyword value")
      (assert (accepts? "(module b :x [f])\nfn f -> (List Keyword)\n  [:essential :hot :full]\n") "keywords inside a vector literal are each a Keyword value")
      true)

fn testPreludeSourcedBuiltins -> Bool
  (do (assert (accepts? "(module b :x [f])\nfn f m: String -> IoError\n  (preludeIoError m)\n") "preludeIoError is a prelude.asl top-level fn (:x []), visible like a builtin, not only via isPreludeTag?'s IoError constructors")
      (assert (accepts? "(module b :x [f])\nfn f bs: Bytes i: Int64 n: Int64 h: Int64 -> Int64\n  (preludeFnvStep bs i n h)\n") "preludeFnvStep is a prelude.asl top-level fn")
      (assert (accepts? "(module b :x [f])\nfn f a: Int64 b: Int64 -> Int64\n  (zstdAslPack64 a b)\n") "zstdAslPack64 is a prelude.asl top-level fn")
      (assert (accepts? "(module b :x [f])\nfn f b: Bytes -> Int64\n  (zstdAslXxhHash b)\n") "zstdAslXxhHash is a prelude.asl top-level fn")
      (assert (accepts? "(module b :x [f])\nfn f b: Bytes -> (Result Bytes String)\n  (zstdAslDecompress b)\n") "zstdAslDecompress is a prelude.asl top-level fn")
      true)

fn testStillCatchesRealUnknowns -> Bool
  (rejects? "(module b :x [f])\nfn f -> Int64\n  totallyMadeUpSymbolXyz\n" "not defined")

fn testWithIsResolvedAsSpecialForm -> Bool
  (let [(ds (c/checkSource "(module b :x [Rec f])\n(schema Rec (:f count Int64))\nfn f r: Rec -> Rec\n  (with r :count 2)\n" (mapEmpty) "with.asl"))]
    (do (assert (listEmpty? ds) (str "with record copy resolves and preserves the record type: " (texts ds))) true))

fn ! runTests -> Bool
  (do (assert (testMissingBuiltinSig) "bucket missingBuiltinSig")
      (assert (testWithIsResolvedAsSpecialForm) "with is a record-copy special form, not an unknown callee")
      (assert (testCmpAliasOperators) "bucket cmpAliasOperators")
      (assert (testKeywordLiteral) "bucket keywordLiteral")
      (assert (testPreludeSourcedBuiltins) "bucket preludeSourcedBuiltins")
      (assert (testStillCatchesRealUnknowns) "sanity: a real unknown symbol is still caught")
      true)
