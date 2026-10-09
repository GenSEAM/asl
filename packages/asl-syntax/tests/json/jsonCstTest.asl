(module asl-syntax/tests/json/jsonCstTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a otl)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/core/bench :a bn)
      (asl-syntax/json :a jcst)
      (asl-json/json :a j)])

fn checkSingleRoundTrip text: String -> Bool
  (let [(root (jcst/parseJson text))
        (len (stringLength text))]
    (do
      (assert (jcst/isValid root) (str "valid CST for: " text))
      (assert (ok? (tr/checkTilingRoot root)) (str "tree tiles for: " text))
      (assert (= (pr/print text root) text) (str "print matches text for: " text))
      (let [(lowered (jcst/lower root text))
            (expected (j/jsonParse text))]
        (do
          (assert (ok? lowered) (str "lowering succeeds for: " text))
          (assert (= lowered expected) (str "lowered equals jsonParse for: " text))
          true))))

fn testCstBasics -> Bool
  (do
    (assert (checkSingleRoundTrip "null") "literal null")
    (assert (checkSingleRoundTrip "true") "literal true")
    (assert (checkSingleRoundTrip "false") "literal false")
    (assert (checkSingleRoundTrip "0") "zero")
    (assert (checkSingleRoundTrip "-0") "minus zero")
    (assert (checkSingleRoundTrip "42") "int 42")
    (assert (checkSingleRoundTrip "-42") "negative int")
    (assert (checkSingleRoundTrip "123456789") "large int")
    (assert (checkSingleRoundTrip "0.0") "float 0.0")
    (assert (checkSingleRoundTrip "-0.5") "float -0.5")
    (assert (checkSingleRoundTrip "12.34") "float 12.34")
    (assert (checkSingleRoundTrip "1e5") "exp 1e5")
    (assert (checkSingleRoundTrip "1.5e-2") "exp 1.5e-2")
    (assert (checkSingleRoundTrip "\"\"") "empty string")
    (assert (checkSingleRoundTrip "\"hello world\"") "simple string")
    (assert (checkSingleRoundTrip "\"hello\\nworld\\t\\\"quotes\\\"\"") "escaped string")
    (assert (checkSingleRoundTrip "\"\\u0041\\u0042\\u0043\"") "unicode hex string")
    (assert (checkSingleRoundTrip "[]") "empty array")
    (assert (checkSingleRoundTrip "[1, 2, 3]") "int array")
    (assert (checkSingleRoundTrip "[\"a\", true, null, 42]") "mixed array")
    (assert (checkSingleRoundTrip "{}") "empty object")
    (assert (checkSingleRoundTrip "{\"a\": 1}") "single property object")
    (assert (checkSingleRoundTrip "{\"name\": \"asex\", \"version\": 1, \"active\": true}") "multi property object")
    (assert (checkSingleRoundTrip "{\n  \"items\": [\n    {\"id\": 1, \"val\": \"a\"},\n    {\"id\": 2, \"val\": \"b\"}\n  ]\n}") "nested formatted json")
    true)

fn testJsoncFeatures -> Bool
  (let [(lcText "// line comment\n{\"a\": 1}")
        (bcText "/* block comment */ {\"a\": 1}")
        (innerCommentText "{\n  // key a\n  \"a\": 1 /* trailing inline */\n}")
        (trailCommaObj "{\"a\": 1, \"b\": 2,}")
        (trailCommaArr "[1, 2, 3,]")]
    (do
      (let [(lcRoot (jcst/parseJsonc lcText))]
        (do
          (assert (jcst/isValid lcRoot) "jsonc line comment is valid in jsonc")
          (assert (ok? (tr/checkTilingRoot lcRoot)) "jsonc line comment tiles")
          (assert (= (pr/print lcText lcRoot) lcText) "jsonc line comment round-trips")
          (assert (ok? (jcst/lower lcRoot lcText)) "jsonc line comment lowers")))
      (let [(bcRoot (jcst/parseJsonc bcText))]
        (do
          (assert (jcst/isValid bcRoot) "jsonc block comment is valid in jsonc")
          (assert (ok? (tr/checkTilingRoot bcRoot)) "jsonc block comment tiles")
          (assert (= (pr/print bcText bcRoot) bcText) "jsonc block comment round-trips")
          (assert (ok? (jcst/lower bcRoot bcText)) "jsonc block comment lowers")))
      (let [(inRoot (jcst/parseJsonc innerCommentText))]
        (do
          (assert (jcst/isValid inRoot) "jsonc inner comments valid in jsonc")
          (assert (ok? (tr/checkTilingRoot inRoot)) "jsonc inner comments tile")
          (assert (= (pr/print innerCommentText inRoot) innerCommentText) "jsonc inner comments round-trip")
          (assert (ok? (jcst/lower inRoot innerCommentText)) "jsonc inner comments lower")))
      (let [(toRoot (jcst/parseJsonc trailCommaObj))]
        (do
          (assert (jcst/isValid toRoot) "jsonc trailing comma obj valid in jsonc")
          (assert (ok? (tr/checkTilingRoot toRoot)) "jsonc trailing comma obj tiles")
          (assert (= (pr/print trailCommaObj toRoot) trailCommaObj) "jsonc trailing comma obj round-trips")
          (assert (ok? (jcst/lower toRoot trailCommaObj)) "jsonc trailing comma obj lowers")))
      (let [(taRoot (jcst/parseJsonc trailCommaArr))]
        (do
          (assert (jcst/isValid taRoot) "jsonc trailing comma arr valid in jsonc")
          (assert (ok? (tr/checkTilingRoot taRoot)) "jsonc trailing comma arr tiles")
          (assert (= (pr/print trailCommaArr taRoot) trailCommaArr) "jsonc trailing comma arr round-trips")
          (assert (ok? (jcst/lower taRoot trailCommaArr)) "jsonc trailing comma arr lowers")))
      (let [(strictLc (jcst/parseJson lcText))
            (strictTo (jcst/parseJson trailCommaObj))
            (strictTa (jcst/parseJson trailCommaArr))]
        (do
          (assert (not (jcst/isValid strictLc)) "line comment rejected in strict mode")
          (assert (not (jcst/isValid strictTo)) "trailing comma obj rejected in strict mode")
          (assert (not (jcst/isValid strictTa)) "trailing comma arr rejected in strict mode")
          (assert (= (pr/print lcText strictLc) lcText) "lossless even on strict error lc")
          (assert (= (pr/print trailCommaObj strictTo) trailCommaObj) "lossless even on strict error to")
          (assert (= (pr/print trailCommaArr strictTa) trailCommaArr) "lossless even on strict error ta")))
      true))

fn checkInvalidJson text: String msg: String -> Bool
  (let [(root (jcst/parseJson text))]
    (do
      (assert (not (jcst/isValid root)) (str "invalid JSON recognized: " msg))
      (assert (err? (jcst/parse text)) (str "parse returns err: " msg))
      (assert (= (pr/print text root) text) (str "lossless round-trip of invalid JSON: " msg))
      true))

fn testSyntaxErrors -> Bool
  (do
    (assert (checkInvalidJson "" "empty string") "empty string")
    (assert (checkInvalidJson "   \t\n  " "whitespace only") "whitespace only")
    (assert (checkInvalidJson "{\"a\": \"unclosed}" "unclosed string") "unclosed string")
    (assert (checkInvalidJson "0123" "leading zero number") "leading zero number")
    (assert (checkInvalidJson "{\"a\": 1" "unclosed object") "unclosed object")
    (assert (checkInvalidJson "[1, 2" "unclosed array") "unclosed array")
    (assert (checkInvalidJson "{\"a\" 1}" "missing colon") "missing colon")
    (assert (checkInvalidJson "{\"a\": 1} trailing" "trailing garbage") "trailing garbage")
    (assert (checkInvalidJson "{\"a\": 1,, \"b\": 2}" "double comma") "double comma")
    (assert (checkInvalidJson "1e" "invalid exponent") "invalid exponent")
    (assert (checkInvalidJson "1." "invalid decimal") "invalid decimal")
    (assert (checkInvalidJson "-.5" "negative dot") "negative dot")
    true)

fn testSymbolsAndOutline -> Bool
  (let [(text "{\n  \"service\": {\n    \"name\": \"auth\",\n    \"port\": 8080,\n    \"tags\": [\"prod\", \"v1\"]\n  }\n}")
        (root (jcst/parseJson text))
        (syms (jcst/extractSymbols root text))]
    (do
      (assert (jcst/isValid root) "valid test doc")
      (assert (>= (listLength syms) 4) "extracted at least 4 symbols")
      (let [(sService (jcst/findSymbolByPath root text "service"))
            (sName (jcst/findSymbolByPath root text "service.name"))
            (sPort (jcst/findSymbolByPath root text "service.port"))
            (sTags (jcst/findSymbolByPath root text "service.tags"))
            (sTag0 (jcst/findSymbolByPath root text "service.tags.0"))
            (sNone (jcst/findSymbolByPath root text "nonexistent"))]
        (do
          (assert (some? sService) "found service symbol")
          (assert (some? sName) "found service.name symbol")
          (assert (some? sPort) "found service.port symbol")
          (assert (some? sTags) "found service.tags symbol")
          (assert (some? sTag0) "found service.tags.0 symbol")
          (assert (not (some? sNone)) "nonexistent symbol returns none")
          (let [(serviceSym (optionOr sService (sym/makeSymbolDef "" "" 0 0)))
                (nameSym (optionOr sName (sym/makeSymbolDef "" "" 0 0)))]
            (do
              (assert (= (sym/symbolName serviceSym) "service") "service symbol name")
              (assert (= (sym/symbolKind serviceSym) "object") "service symbol kind")
              (assert (= (sym/symbolDepth serviceSym) 1) "service symbol depth is 1")
              (assert (= (sym/symbolName nameSym) "name") "name symbol name")
              (assert (= (sym/symbolKind nameSym) "string") "name symbol kind")
              (assert (= (sym/symbolDepth nameSym) 2) "name symbol depth is 2")))))
      (let [(s (src/sourceFromString "test.json" text))
            (items (jcst/jsonOutlineItems root s text))]
        (do
          (assert (= (listLength items) 4) "4 outline items at depth <= 2")
          (let [(rcpt (jcst/jsonOutlineReceipt "test.json" text))]
            (do
              (assert (stringContains? rcpt ":outline") "outline receipt contains :outline")
              (assert (stringContains? rcpt ":language \"json\"") "outline receipt language json")
              (assert (stringContains? rcpt ":name \"service\"") "receipt contains service")
              (assert (stringContains? rcpt ":name \"name\"") "receipt contains name")
              true))))))

fn filterTrackedJson files: (List String) acc: (List String) -> (List String)
  (if (listEmpty? files)
    (listReverse acc)
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))]
      (if (or (stringContains? head "fixtures/upstream")
              (or (stringContains? head "cdx_arxiv_0704_0023.json")
                  (stringContains? head "cdx_arxiv_limit3.json")))
        (filterTrackedJson tail acc)
        (filterTrackedJson tail (cons head acc)))))

fn checkTrackedFilesLoop! files: (List String) idx: Int64 total: Int64 -> Bool
  (if (listEmpty? files)
    true
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))
          (readRes (fileReadBytes head))
          (strRes (fileReadString head))]
      (do
        (assert (ok? readRes) (str "read bytes: " head))
        (assert (ok? strRes) (str "read string: " head))
        (let [(bs (resultOr readRes (stringToBytes "")))
              (text (resultOr strRes ""))
              (root (jcst/parseJsonBytes bs))
              (len (bytesLength bs))]
          (do
            (assert (jcst/isValid root) (str "valid CST: " head))
            (assert (ok? (tr/checkTilingRoot root)) (str "tiles: " head))
            (let [(printed (pr/printTreeBytes! bs root))]
              (assert (= printed bs) (str "round-trip bytes match: " head)))
            (let [(lowered (jcst/lower root text))
                  (expected (j/jsonParse text))]
              (do
                (assert (ok? lowered) (str "lowering succeeds: " head))
                (assert (= lowered expected) (str "lowering equals jsonParse: " head))))
            (checkTrackedFilesLoop! tail (+ idx 1) total))))))

fn testTrackedJsonFiles! -> Bool
  (let [(allFiles (resultOr (crp/gitTrackedFiles! "json") (list)))
        (jsonFiles (filterTrackedJson allFiles (list)))
        (count (listLength jsonFiles))]
    (do
      (assert (>= count 94) (str "at least 94 tracked json files (found " (stringFromInt64 count) ")"))
      (checkTrackedFilesLoop! jsonFiles 0 count)
      true))

fn pad3 n: Int64 -> String
  (if (< n 10)
    (str "00" (stringFromInt64 n))
    (if (< n 100)
      (str "0" (stringFromInt64 n))
      (stringFromInt64 n)))

fn checkUpstreamYLoop! files: (List String) passCount: Int64 -> Int64
  (if (listEmpty? files)
    passCount
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))
          (readRes (fileReadBytes head))
          (strRes (fileReadString head))]
      (if (or (err? readRes) (err? strRes))
        (checkUpstreamYLoop! tail passCount)
        (let [(bs (resultOr readRes (stringToBytes "")))
              (text (resultOr strRes ""))
              (root (jcst/parseJsonBytes bs))]
          (if (and (jcst/isValid root) (ok? (jcst/lower root text)))
            (checkUpstreamYLoop! tail (+ passCount 1))
            (do
              (println (str "Unexpected y_ failure on: " head))
              (checkUpstreamYLoop! tail passCount)))))))

fn checkUpstreamNLoop! files: (List String) passCount: Int64 -> Int64
  (if (listEmpty? files)
    passCount
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))
          (readRes (fileReadBytes head))]
      (if (err? readRes)
        (checkUpstreamNLoop! tail passCount)
        (let [(bs (resultOr readRes (stringToBytes "")))
              (root (jcst/parseJsonBytes bs))]
          (if (not (jcst/isValid root))
            (checkUpstreamNLoop! tail (+ passCount 1))
            (do
              (println (str "Unexpected n_ acceptance on: " head))
              (checkUpstreamNLoop! tail passCount)))))))

fn getUpstreamFiles! dir: String ext: String -> (List String)
  (let [(cmd (str "ls " dir "/*." ext))
        (res (processRun cmd))]
    (if (!= res.exitCode 0)
      (list)
      (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
              (stringSplit res.stdout "\n"))))

fn testUpstreamJsonTestSuite! -> Bool
  (let [(indexPath "asl/packages/asl-syntax/tests/fixtures/upstream/json/index.asn.sample")
        (readRes (fileReadBytes indexPath))]
    (do
      (assert (ok? readRes) "json index.asn readable")
      (let [(bs (resultOr readRes (stringToBytes "")))
            (actualSha (bytesSha256 bs))
            (expectedSha "6838359d34c0d077162b7e7ca70a0890e3395b8d3c28eff9aab5c8c9c112391d")]
        (do
          (assert (= actualSha expectedSha) "json index.asn sha matches manifest")
          (let [(entry (crp/makeUpstreamEntry
                         "https://github.com/nst/JSONTestSuite"
                         "1ef36fa01286573e846ac449e8683f8833c5b26a"
                         expectedSha
                         "MIT"
                         indexPath))]
            (assert (ok? (crp/verifyUpstreamEntry! entry)) "manifest-verifier verifyUpstreamEntry passes"))))
      (let [(yFiles (getUpstreamFiles! "asl/packages/asl-syntax/tests/fixtures/upstream/json/y" "json.sample"))
            (nFiles (getUpstreamFiles! "asl/packages/asl-syntax/tests/fixtures/upstream/json/n" "json.sample"))
            (totalY (listLength yFiles))
            (totalN (listLength nFiles))]
        (do
          (assert (= totalY 95) "exactly 95 upstream y_ cases vendored")
          (assert (= totalN 50) "exactly 50 upstream n_ cases vendored")
          (let [(passY (checkUpstreamYLoop! yFiles 0))
                (passN (checkUpstreamNLoop! nFiles 0))]
            (do
              (println (str "JSONTestSuite: " (stringFromInt64 passY) "/" (stringFromInt64 totalY) " y_ accepted (0 excluded), " (stringFromInt64 passN) "/" (stringFromInt64 totalN) " n_ rejected (0 excluded)"))
              (assert (= passY 95) "all 95 y_ cases accepted")
              (assert (= passN 50) "all 50 n_ cases rejected")
              true))))))

fn benchParseJson bs: Bytes -> Unit
  (let [(root (jcst/parseJsonBytes bs))]
    ())

fn testPreflightInventoryPerf! -> Bool
  (let [(path ".asl/mem/audits/preflight_inventory.json")
        (readRes (fileReadBytes path))]
    (do
      (assert (ok? readRes) "preflight_inventory.json readable")
      (let [(bs (resultOr readRes (stringToBytes "")))
            (bytesCount (bytesLength bs))
            (workload (fn [] -> Unit (benchParseJson bs)))
            (fig (bn/benchMedian5! workload
                                  bytesCount
                                  "1 MB JSON preflight_inventory"
                                  "2026-09-26"))
            (msPer100Kb (bn/figureMsPer100Kb fig))]
        (do
          (println (bn/renderBenchFigure fig))
          (assert (> (bn/figureMedianNs fig) 0) "median ns > 0")
          (assert (<= msPer100Kb 60.0) (str "ms per 100 KB <= 60.0 target, measured: " (stringFromFloat64 msPer100Kb)))
          true))))

fn ! runTests -> Bool
  (do
    (assert (testCstBasics) "cst basics")
    (assert (testJsoncFeatures) "jsonc features")
    (assert (testSyntaxErrors) "syntax errors")
    (assert (testSymbolsAndOutline) "symbols and outline")
    (assert (testTrackedJsonFiles!) "tracked json round-trip and lowering")
    (assert (testUpstreamJsonTestSuite!) "upstream json test suite")
    (assert (testPreflightInventoryPerf!) "preflight inventory benchmark")
    true)
