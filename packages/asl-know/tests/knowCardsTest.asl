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
  (match (tok/loadTokenizer! (str root "/data/tokenizers"))
    ((err e) (do (assert false (str "o200k tokenizer loads: " e)) false))
    ((ok t)
      (let [(index (resultOr (fileReadString (str (kn/cardsDir root) "/index.asn")) ""))
            (lang (resultOr (fileReadString (str (kn/cardsDir root) "/core-lang.asn")) ""))
            (indexTokens (tok/countTokens! t index))
            (langTokens (tok/countTokens! t lang))]
        (do
          (assert (> indexTokens 0) "index is non-empty")
          ; (:m :ref KNOW-INDEX-SCALE :do "L0 is one line per group: 82 cards measured 1766 o200k tokens as a flat index, the group index is a quarter of that, so 2x the packages still fits the 700 cap; the cap is adopted, the figure is measured at the 2026-11-13 render")
          (assert (<= indexTokens 700) (str "L0 group index fits 700 o200k tokens, got " indexTokens))
          (assert (<= langTokens 1500) (str "language card fits 1500 o200k tokens, got " langTokens))
          true))))

; (:m :ref KNOW-INDEX-BRANDING :do "words that name the language or praise a package and say nothing about what it does; an index purpose made only of them, or led by one, spends its few bytes on nothing a model can pick the card by")
fn brandOnly -> (List String)
  (list "100%" "Self-Hosted" "Self-Contained" "Pure" "AgentSlang" "ASL" "Aslany" "Native" "Standalone" "Sovereign" "Standard" "Universal" "Autonomous" "Unified")

fn indexPurposeOf line: String -> String
  (let [(parts (stringSplit line "\""))]
    (optionOr (listGet parts 3) ""))

fn bareIndexLine? line: String -> Bool
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (stringReplace (indexPurposeOf line) "..." "") ":" "") " ")))]
    (and (not (listEmpty? words)) (listAll? (fn [(w String)] -> Bool (listContains? (brandOnly) w)) words)))

fn brandLed? line: String -> Bool
  (listContains? (brandOnly) (optionOr (listHead (stringSplit (indexPurposeOf line) " ")) ""))

; (:m :ref KNOW-INDEX-FILLER :do "a fixed praise list, independent of render fillerWords, so dropping the render trim or emptying its list goes red here")
fn fillerOnly -> (List String)
  (list "high-performance" "high-frequency" "zero-cost")

fn fillerLed? line: String -> Bool
  (listContains? (fillerOnly) (stringLower (optionOr (listHead (stringSplit (indexPurposeOf line) " ")) "")))

fn ! groupIds root: String -> (List String)
  (let [(index (resultOr (fileReadString (str (kn/cardsDir root) "/index.asn")) ""))]
    (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l "\"") 1) ""))
         (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:g \"")) (stringSplit index "\n"))))

fn ! groupLines root: String gid: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:c \""))
          (stringSplit (resultOr (fileReadString (str (kn/cardsDir root) "/index-" gid ".asn")) "") "\n"))

fn ! cardLines root: String -> (List String)
  (listFlatMap (fn [(g String)] -> (List String) (groupLines root g)) (groupIds root))

; (:m :ref KNOW-INDEX-SCALE :do "every card is reachable L0 to its group file: each group named by L0 has a file, each card id appears in exactly one group file, the L0 group counts equal the file line counts, and no card fell into the other group (a package missing from groups.asn)")
fn ! tiersReach root: String -> Bool
  (let [(es (qy/loadEntries! (kn/cardsDir root)))
        (ids (map (fn [(e qy/Entry)] -> String e.id) es))
        (gids (groupIds root))
        (lines (cardLines root))
        (listed (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l "\"") 1) "")) lines))
        (index (resultOr (fileReadString (str (kn/cardsDir root) "/index.asn")) ""))
        (counts (listFlatMap (fn [(l String)] -> (List Int64) (if (stringStartsWith? l "(:g \"") (list (optionOr (stringToInt64 (stringTrim (optionOr (listGet (stringSplit l "\"") 2) ""))) -1)) (list))) (stringSplit index "\n")))
        (fileCounts (map (fn [(g String)] -> Int64 (listLength (groupLines root g))) gids))]
    (do
      (assert (> (listLength gids) 1) "L0 lists several groups")
      (assert (not (listContains? gids "other")) (str "every card has a group in groups.asn, other holds: " (stringJoin (filter (fn [(i String)] -> Bool (not (listContains? (listFlatMap (fn [(g String)] -> (List String) (if (= g "other") (list) (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l "\"") 1) "")) (groupLines root g)))) gids) i))) ids) ", ")))
      (assert (= (listLength listed) (listLength ids)) (str "group files list every card once: " (listLength listed) " lines for " (listLength ids) " cards"))
      (assert (listAll? (fn [(i String)] -> Bool (listContains? listed i)) ids) "each card id is reachable through one group file")
      (assert (= counts fileCounts) "L0 group counts equal the lines of each group file")
      (assert (> (listLength gids) 0) "L0 lists groups")
      true))

fn ! indexDistinct root: String -> Bool
  (let [(lines (cardLines root))
        (bare (filter bareIndexLine? lines))
        (led (filter brandLed? lines))
        (filler (filter fillerLed? lines))
        (empty (filter (fn [(l String)] -> Bool (stringEmpty? (stringTrim (indexPurposeOf l)))) lines))]
    (do
      (assert (> (listLength lines) 80) (str "index lists every card, got " (listLength lines)))
      (assert (listEmpty? bare) (str (listLength bare) " index lines show only a branding prefix: " (stringJoin (listTake bare 6) " ")))
      (assert (listEmpty? led) (str (listLength led) " index lines spend their purpose bytes on a branding word first: " (stringJoin (listTake led 6) " ")))
      (assert (listEmpty? filler) (str (listLength filler) " index lines lead with a praise word: " (stringJoin (listTake filler 6) " ")))
      (assert (= (r/indexPurpose "High-performance vector memory store") "vector memory store") "a leading praise word is dropped before the cut")
      (assert (= (r/indexPurpose "Pure AgentSlang Zero-Cost Schema, Codec") "Schema, Codec") "brand and praise words drop together")
      (assert (= (r/indexPurpose "Fast") "Fast") "a purpose of only a praise word is kept whole")
      ; (:m :ref KNOW-INTEL-PURPOSE :do "an empty purpose leaves a model only the card id: a description the scan blanks (it names a retired path) shows up here, not as a missing card")
      (assert (listEmpty? empty) (str (listLength empty) " index lines carry an empty purpose: " (stringJoin (listTake empty 6) " ")))
      true))

; (:m :ref KNOW-TIER-LOWS :do "L0 member names are unique across groups (core/parquet and asl-parquet both keep their full id), the word memory leads exactly one group purpose, and gen's dropStaleIndexes! deletes an index-GROUP.asn whose group is gone while keeping rendered index files and other card files")
fn ! memberNames root: String -> (List String)
  (let [(index (resultOr (fileReadString (str (kn/cardsDir root) "/index.asn")) ""))]
    (listFlatMap (fn [(l String)] -> (List String)
                   (if (stringStartsWith? l "(:g \"")
                     (stringSplit (optionOr (listHead (stringSplit (optionOr (listLast (stringSplit l "(")) "") ")")) "") " ")
                     (list)))
                 (stringSplit index "\n")))

fn ! purposeLines root: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:group "))
          (stringSplit (resultOr (fileReadString (str root "/asl/packages/asl-know/groups.asn")) "") "\n"))

fn purposeOf l: String -> String
  (optionOr (listGet (stringSplit (optionOr (listHead (stringSplit l " :members ")) "") ":purpose ") 1) "")

fn ! tierLows root: String -> Bool
  (let [(names (filter (fn [(n String)] -> Bool (not (stringEmpty? n))) (memberNames root)))
        (dup (filter (fn [(n String)] -> Bool (> (listLength (filter (fn [(m String)] -> Bool (= m n)) names)) 1)) names))
        (memory (filter (fn [(l String)] -> Bool (stringContains? (stringLower (purposeOf l)) "memory")) (purposeLines root)))
        (dir (str (optionOr (envGet "TMPDIR") "/tmp") "/knowTierLows-" (stringFromInt64 (procSelf))))]
    (do (assert (> (listLength names) 60) (str "L0 lists the members of every group, got " (listLength names)))
        (assert (listEmpty? dup) (str "L0 member names are unique across groups: " (stringJoin dup " ")))
        (assert (stringContains? (stringJoin names " ") "core/parquet") "the colliding core card keeps its full id")
        (assert (stringContains? (stringJoin names " ") "asl-parquet") "the colliding package card keeps its full id")
        (assert (= (listLength memory) 1) (str "memory appears in exactly one group purpose, got " (listLength memory)))
        (assert (ok? (dirCreate dir)) "scratch dir made")
        (assert (and (ok? (fileWrite (str dir "/index-gone.asn") "x")) (and (ok? (fileWrite (str dir "/index-keep.asn") "x")) (ok? (fileWrite (str dir "/core-lang.asn") "x")))) "scratch files written")
        (assert (= (kn/dropStaleIndexes! dir (list (pair "index-keep.asn" "x") (pair "core-lang.asn" "x"))) (ok 2)) "dropStaleIndexes! reports the rendered count")
        (assert (not (fileExists? (str dir "/index-gone.asn"))) "the index file of a removed group is deleted")
        (assert (and (fileExists? (str dir "/index-keep.asn")) (fileExists? (str dir "/core-lang.asn"))) "rendered index and other card files stay")
        (assert (ok? (pathRemove dir)) "scratch dir removed")
        true))

fn ! queries root: String -> Bool
  (let [(es (qy/loadEntries! (kn/cardsDir root)))
        (exact (qy/answer es "jsonParse" 400))
        (intent (qy/answer es "decompress gzip data" 1000))
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
    (and (examplesRun) (cardsFresh root) (ratchetShrinks root) (examplesEmbedded root) (budgets root) (tiersReach root) (tierLows root) (indexDistinct root) (queries root)))
