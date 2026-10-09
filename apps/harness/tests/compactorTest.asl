(module aslHarness/compactorTest :x [testStripCodeFences testTruncateOutput testExtractSexpr testCompactHistory testCompactAtWatermark runTests] :i [(compactor :a comp)])

fn testStripCodeFences -> Bool
  (let [(raw "```asl\n(fn add [(a I64) (b I64)] (+ a b))\n```") (stripped (comp/stripCodeFences raw))] (assert (= stripped "(fn add [(a I64) (b I64)] (+ a b))") "fences stripped") (assert (not (stringContains? stripped "```")) "no backticks remain") true)

fn testTruncateOutput -> Bool
  (let [(lines (list "line 1" "line 2" "line 3" "line 4" "line 5" "line 6" "line 7" "line 8" "line 9" "line 10")) (text (stringJoin lines "\n")) (truncated (comp/truncateOutput text 4))] (assert (stringContains? truncated "line 1") "contains head line 1") (assert (stringContains? truncated "line 10") "contains tail line 10") (assert (stringContains? truncated "lines omitted") "contains omitted receipt") true)

fn testExtractSexpr -> Bool
  (let [(chatter "Here is the code to fix the issue:\n(fn fix [] true)") (extracted (comp/extractSexpr chatter))] (assert (stringStartsWith? extracted "(fn fix") "starts with (fn fix") (assert (stringEndsWith? extracted "true)") "ends with true)") true)

fn testCompactHistory -> Bool
  (let [(hist (list "recent 1" "recent 2" "exec-cmd: test gate passed" "fs-read: src/paged.asl")) (compacted (comp/compactHistory hist 2))] (assert (= (listLength compacted) 4) "compacted list length is 4") (assert (stringStartsWith? (optionOr (listHead compacted) "") "[Turn: recent 1") "head is compacted") (assert (= (optionOr (listLast compacted) "") "fs-read: src/paged.asl") "last item is kept verbatim") true)

fn testCompactAtWatermark -> Bool
  (let [(hist (list "recent 1" "recent 2" "recent 3" "recent 4" "recent 5" "ast-patch: src/main.asl" "exec-cmd: test gate passed")) (underWatermark (comp/compactAtWatermark hist 50 100)) (softWatermark (comp/compactAtWatermark hist 65 100)) (hardWatermark (comp/compactAtWatermark hist 85 100))] (assert (= (listLength underWatermark) 7) "under watermark retains verbatim length") (assert (= (optionOr (listLast underWatermark) "") "exec-cmd: test gate passed") "under watermark retains verbatim last item") (assert (= (listLength softWatermark) 7) "soft watermark retains total length") (assert (stringContains? (optionOr (listHead softWatermark) "") "[Turn: recent 1") "soft watermark compacts older turns to receipt") (assert (stringContains? (optionOr (listHead hardWatermark) "") "[Turn: recent 1") "hard watermark compacts older turns to receipt") (assert (= (optionOr (listLast hardWatermark) "") "exec-cmd: test gate passed") "hard watermark keeps recent verbatim") true)

fn runTests -> Bool
  (do (testStripCodeFences) (testTruncateOutput) (testExtractSexpr) (testCompactHistory) (testCompactAtWatermark) true)
