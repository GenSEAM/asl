(module asl-know/knowCardsTest
  :x [runTests]
  :i [(asl-know/know :a kn) (asl-know/render :a r) (asl-know/query :a qy) (asl-tokenizer/tokenizer :a tok)
      (asl-know/examples/coreLang :a exLang) (asl-know/examples/coreList :a exList) (asl-know/examples/coreMap :a exMap)
      (asl-know/examples/coreString :a exString) (asl-know/examples/coreIo :a exIo) (asl-know/examples/coreBytes :a exBytes)
      (asl-know/examples/coreOption :a exOption) (asl-know/examples/aslJson :a exJson) (asl-know/examples/aslZip :a exZip)
      (asl-know/examples/aslRegex :a exRegex) (asl-know/examples/aslCsv :a exCsv) (asl-know/examples/aslParquet :a exParquet)
      (asl-know/examples/aslCrypto :a exCrypto) (asl-know/examples/aslHttp :a exHttp)])

fn ! examplesRun -> Bool
  (do
    (assert (exLang/selfTest) "core/lang example runs")
    (assert (exList/selfTest) "core/list example runs")
    (assert (exMap/selfTest) "core/map example runs")
    (assert (exString/selfTest) "core/string example runs")
    (assert (exIo/selfTest) "core/io example runs")
    (assert (exBytes/selfTest) "core/bytes example runs")
    (assert (exOption/selfTest) "core/option example runs")
    (assert (exJson/selfTest) "asl-json example runs")
    (assert (exZip/selfTest) "asl-zip example runs")
    (assert (exRegex/selfTest) "asl-regex example runs")
    (assert (exCsv/selfTest) "asl-csv example runs")
    (assert (exParquet/selfTest) "asl-parquet example runs")
    (assert (exCrypto/selfTest) "asl-crypto example runs")
    (assert (exHttp/selfTest) "asl-http example runs")
    true)

fn ! cardsFresh root: String -> Bool
  (let [(stale (kn/staleFiles! root))]
    (do (assert (listEmpty? stale) (str "cards regenerate byte-identical from source; stale: " (stringJoin (listTake stale 5) ", ") "; run: asl run asl/packages/asl-know/src/know.asl gen ."))
        true))

fn ! ratchetShrinks root: String -> Bool
  (let [(listed (kn/ratchetRows! root))
        (computed (r/missingOf (r/allCards! root)))
        (d (kn/ratchetDiff listed computed))]
    (do
      (assert (> (listLength listed) 0) "missing.asn lists rows")
      (assert (listEmpty? (pairFirst d)) (str "new exported symbols without declaration or doc.asn contract: " (stringJoin (listTake (pairFirst d) 5) ", ")))
      (assert (listEmpty? (pairSecond d)) (str "fixed rows still listed in missing.asn, remove them so the ratchet shrinks: " (stringJoin (listTake (pairSecond d) 5) ", ")))
      true))

fn ! examplesEmbedded root: String -> Bool
  (let [(es (qy/loadEntries! (kn/cardsDir root)))
        (withEx (filter (fn [(e qy/Entry)] -> Bool (not (stringContains? e.line ":example none"))) es))]
    (do
      (assert (= (listLength withEx) 14) (str "14 cards carry a checked example, got " (listLength withEx)))
      true))

fn ! budgets root: String -> Bool
  (mt (tok/loadTokenizer! (str root "/data/tokenizers"))
    ((err e) (do (assert false (str "o200k tokenizer loads: " e)) false))
    ((ok t)
      (let [(index (resultOr (fileReadString (str (kn/cardsDir root) "/index.asn")) ""))
            (lang (resultOr (fileReadString (str (kn/cardsDir root) "/core-lang.asn")) ""))
            (indexTokens (tok/countTokens! t index))
            (langTokens (tok/countTokens! t lang))]
        (do
          (assert (> indexTokens 0) "index is non-empty")
          (assert (<= indexTokens 2000) (str "L0 index fits 2000 o200k tokens, got " indexTokens))
          (assert (<= langTokens 1500) (str "language card fits 1500 o200k tokens, got " langTokens))
          true))))

fn ! queries root: String -> Bool
  (let [(es (qy/loadEntries! (kn/cardsDir root)))
        (exact (qy/answer es "jsonParse" 400))
        (intent (qy/answer es "decompress gzip data" 800))
        (byCard (qy/answer es "asl-zip" 800))
        (tight (qy/answer es "split a string" 300))]
    (do
      (assert (stringStartsWith? exact "(:know :q \"jsonParse\" :match exact") "an exact symbol answers :match exact")
      (assert (stringContains? exact "(:sym \"jsonParse\" :mod \"asl-json/json\"") "the exact answer carries the L2 row")
      (assert (stringContains? intent "(:card \"asl-zip\"") "an intent query ranks the asl-zip card")
      (assert (stringContains? byCard "(:card \"asl-zip\"") "a card id returns its card")
      (assert (stringContains? tight "stringSplit") "split a string finds stringSplit")
      (assert (<= (r/tokensOf tight) 330) (str "answer respects the budget, got " (r/tokensOf tight)))
      true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))]
    (and (examplesRun) (cardsFresh root) (ratchetShrinks root) (examplesEmbedded root) (budgets root) (queries root)))
