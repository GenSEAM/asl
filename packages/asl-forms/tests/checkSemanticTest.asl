(module asl-forms/tests/checkSemanticTest
  :x [runTests]
  :i [(asl-forms/check :a chk)])

fn checkFileClean! path: String -> Bool
  (mt (fileReadString path)
    ((err e) (do (assert false (str "read error for " path ": " e)) false))
    ((ok content)
     (mt (chk/checkSemantic! path content)
       ((ok items) (listEmpty? items))
       ((err e) (do (assert false (str "semantic check error for " path ": " e)) false)))))

fn testSeededAslUnknownSymbol! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (tmpPath (str tmpDir "/asl_test_seeded_" (stringFromInt64 (monotonicNs)) ".asl"))
        (content "(module test/seededTypeError :x [badFn])\n\nfn badFn a: Int64 -> Int64\n  (let [(x 1)]\n    nonExistentSymbol)\n")
        (wRes (fileWrite tmpPath content))]
    (do
      (assert (ok? wRes) "write temp asl seeded error file")
      (let [(semRes (chk/checkSemantic! tmpPath content))
            (items (resultOr semRes (list)))
            (itemCount (listLength items))
            (firstItem (optionOr (listHead items) (chk/makeLeftItem 0 0 "" "" "")))
            (receipt (chk/checkFileReceipt! 1 "check" tmpPath ":disk" content))
            (rmRes (pathRemove tmpPath))]
        (do
          (assert (ok? semRes) "seeded asl checkSemantic returns ok result")
          (assert (= itemCount 1) "seeded asl unknown symbol produces exactly one left item")
          (assert (= (chk/leftItemLine firstItem) 5) "seeded asl unknown symbol is at line 5")
          (assert (= (chk/leftItemKind firstItem) "semantic") "seeded asl unknown symbol kind is semantic")
          (assert (= (chk/leftItemExpected firstItem) "ERR_UNKNOWN_SYMBOL") "seeded asl unknown symbol expected is ERR_UNKNOWN_SYMBOL")
          (assert (stringContains? (chk/leftItemNear firstItem) "nonExistentSymbol") "seeded asl unknown symbol near contains snippet")
          (assert (stringContains? receipt ":status \"rejected\"") "seeded asl unknown symbol receipt is rejected")
          (assert (stringContains? receipt ":left ((:line 5") "seeded asl unknown symbol receipt contains left item at line 5")
          (assert (stringContains? receipt ":kind semantic") "seeded asl unknown symbol receipt contains kind semantic")
          (assert (ok? rmRes) "remove temp seeded asl file")
          true))))

fn testUnresolvedTsRelativeImport! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (tmpPath (str tmpDir "/asl_test_unres_" (stringFromInt64 (monotonicNs)) ".ts"))
        (content "import { missingHelper } from \"./nonexistentHelper\";\n\nexport const x = 1;\n")
        (wRes (fileWrite tmpPath content))]
    (do
      (assert (ok? wRes) "write temp ts unresolved import file")
      (let [(semRes (chk/checkSemantic! tmpPath content))
            (items (resultOr semRes (list)))
            (itemCount (listLength items))
            (firstItem (optionOr (listHead items) (chk/makeLeftItem 0 0 "" "" "")))
            (receipt (chk/checkFileReceipt! 2 "check" tmpPath ":disk" content))
            (rmRes (pathRemove tmpPath))]
        (do
          (assert (ok? semRes) "unresolved ts checkSemantic returns ok result")
          (assert (= itemCount 1) "unresolved ts import produces exactly one left item")
          (assert (= (chk/leftItemLine firstItem) 1) "unresolved ts import is at line 1")
          (assert (= (chk/leftItemKind firstItem) "semantic") "unresolved ts import kind is semantic")
          (assert (= (chk/leftItemExpected firstItem) "ERR_UNRESOLVED_IMPORT") "unresolved ts import expected is ERR_UNRESOLVED_IMPORT")
          (assert (stringContains? (chk/leftItemNear firstItem) "missingHelper") "unresolved ts import near contains snippet")
          (assert (stringContains? receipt ":status \"rejected\"") "unresolved ts import receipt is rejected")
          (assert (stringContains? receipt ":left ((:line 1") "unresolved ts import receipt contains left item at line 1")
          (assert (stringContains? receipt ":kind semantic") "unresolved ts import receipt contains kind semantic")
          (assert (ok? rmRes) "remove temp unresolved ts file")
          true))))

fn testResolvedTsRelativeImport! -> Bool
  (let [(code "import { aslPlugin } from './plugins/vitePluginAsl.js';\nexport const ok = true;\n")
        (semRes (chk/checkSemantic! "asl/web/vite.config.js" code))
        (items (resultOr semRes (list)))
        (receipt (chk/checkFileReceipt! 3 "check" "asl/web/vite.config.js" ":disk" code))]
    (do
      (assert (ok? semRes) "resolved relative import checkSemantic is ok")
      (assert (listEmpty? items) "resolved relative import produces no left items")
      (assert (stringContains? receipt ":status \"ok\"") "resolved relative import receipt is ok")
      (assert (stringContains? receipt ":left ()") "resolved relative import receipt has empty left")
      true))

fn testLeftItemCapping -> Bool
  (let [(d1 (chk/makeLeftItem 1 1 "ERR_UNRESOLVED_IMPORT" "import 1" "semantic"))
        (d2 (chk/makeLeftItem 2 1 "ERR_UNRESOLVED_IMPORT" "import 2" "semantic"))
        (d3 (chk/makeLeftItem 3 1 "ERR_UNRESOLVED_IMPORT" "import 3" "semantic"))
        (d4 (chk/makeLeftItem 4 1 "ERR_UNRESOLVED_IMPORT" "import 4" "semantic"))
        (d5 (chk/makeLeftItem 5 1 "ERR_UNRESOLVED_IMPORT" "import 5" "semantic"))
        (d6 (chk/makeLeftItem 6 1 "ERR_UNRESOLVED_IMPORT" "import 6" "semantic"))
        (d7 (chk/makeLeftItem 7 1 "ERR_UNRESOLVED_IMPORT" "import 7" "semantic"))
        (formatted (chk/formatLeftList (list d1 d2 d3 d4 d5 d6 d7)))]
    (do
      (assert (stringContains? formatted ":more 2") "capping at 5 produces :more 2 for 7 items")
      (assert (stringContains? formatted ":line 1") "formatted includes line 1")
      (assert (stringContains? formatted ":line 5") "formatted includes line 5")
      (assert (not (stringContains? formatted ":line 6")) "formatted omits line 6 past cap")
      true))

fn testAbsolutePathImportingFile! -> Bool
  (let [(canon (resultOr (realPath "asl/web/vite.config.js") ""))
        (code "import { aslPlugin } from './plugins/vitePluginAsl.js';\nexport const ok = true;\n")
        (semRes (chk/checkSemantic! canon code))
        (items (resultOr semRes (list)))
        (receipt (chk/checkFileReceipt! 4 "check" canon ":disk" code))]
    (do
      (assert (not (stringEmpty? canon)) "canonical absolute path is non-empty")
      (assert (ok? semRes) "absolute path checkSemantic is ok")
      (assert (listEmpty? items) "absolute path importing file produces no semantic items")
      (assert (stringContains? receipt ":status \"ok\"") "absolute path importing file receipt is ok")
      true))

fn testDirectoryIndexResolution! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (baseDir (str tmpDir "/asl_test_idx_" (stringFromInt64 (monotonicNs))))
        (dirTs (str baseDir "/dir_ts"))
        (dirJs (str baseDir "/dir_js"))
        (_c1 (dirCreate dirTs))
        (_c2 (dirCreate dirJs))
        (_w1 (fileWrite (str dirTs "/index.ts") "export const tsVal = 10;\n"))
        (_w2 (fileWrite (str dirJs "/index.js") "export const jsVal = 20;\n"))
        (importerPath (str baseDir "/importer.ts"))
        (importerCode "import { tsVal } from './dir_ts';\nimport { jsVal } from './dir_js';\nexport const sum = tsVal + jsVal;\n")
        (semRes (chk/checkSemantic! importerPath importerCode))
        (items (resultOr semRes (list)))
        (receipt (chk/checkFileReceipt! 5 "check" importerPath ":disk" importerCode))
        (_rm (pathRemove baseDir))]
    (do
      (assert (ok? semRes) "directory index checkSemantic is ok")
      (assert (listEmpty? items) "directory index resolution produces no left items")
      (assert (stringContains? receipt ":status \"ok\"") "directory index resolution receipt is ok")
      true))

fn testDynamicImportAndRequire! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (baseDir (str tmpDir "/asl_test_dyn_" (stringFromInt64 (monotonicNs))))
        (_cd (dirCreate baseDir))
        (helperTs (str baseDir "/helper.ts"))
        (_w1 (fileWrite helperTs "export const val = 42;\n"))
        (testPath (str baseDir "/testModule.ts"))
        (codeMissImp "export async function load() { const m = await import('./missingMod'); return m; }\n")
        (itemsMissImp (resultOr (chk/checkSemantic! testPath codeMissImp) (list)))
        (item1 (optionOr (listHead itemsMissImp) (chk/makeLeftItem 0 0 "" "" "")))
        (codeMissReq "export function load() { const m = require('./missingMod'); return m; }\n")
        (itemsMissReq (resultOr (chk/checkSemantic! testPath codeMissReq) (list)))
        (item2 (optionOr (listHead itemsMissReq) (chk/makeLeftItem 0 0 "" "" "")))
        (codeResImp "export async function load() { const m = await import('./helper'); return m; }\n")
        (itemsResImp (resultOr (chk/checkSemantic! testPath codeResImp) (list)))
        (codeResReq "export function load() { const m = require('./helper'); return m; }\n")
        (itemsResReq (resultOr (chk/checkSemantic! testPath codeResReq) (list)))
        (_rm (pathRemove baseDir))]
    (do
      (assert (= (listLength itemsMissImp) 1) "missing dynamic import produces exactly one item")
      (assert (= (chk/leftItemExpected item1) "ERR_UNRESOLVED_IMPORT") "missing dynamic import expected is ERR_UNRESOLVED_IMPORT")
      (assert (= (listLength itemsMissReq) 1) "missing require produces exactly one item")
      (assert (= (chk/leftItemExpected item2) "ERR_UNRESOLVED_IMPORT") "missing require expected is ERR_UNRESOLVED_IMPORT")
      (assert (listEmpty? itemsResImp) "resolving dynamic import produces no items")
      (assert (listEmpty? itemsResReq) "resolving require produces no items")
      true))

fn testHostCheckPathShellQuoting! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (nonce (stringFromInt64 (monotonicNs)))
        (baseDir (str tmpDir "/asl_test_sh_" nonce))
        (_cd (dirCreate baseDir))
        (badCode "(module test/badPath :x [badFn])\n\nfn badFn a: Int64 -> Int64\n  nonExistentSymbol\n")
        (spacePath (str baseDir "/sp ace.asl"))
        (_w1 (fileWrite spacePath badCode))
        (itemsSpace (resultOr (chk/checkSemantic! spacePath badCode) (list)))
        (itemSpace1 (optionOr (listHead itemsSpace) (chk/makeLeftItem 0 0 "" "" "")))
        (injectPath (str baseDir "/test_$(touch PWNED).asl"))
        (_w2 (fileWrite injectPath badCode))
        (itemsInject (resultOr (chk/checkSemantic! injectPath badCode) (list)))
        (itemInject1 (optionOr (listHead itemsInject) (chk/makeLeftItem 0 0 "" "" "")))
        (pwnedExists (fileExists? "PWNED"))
        (_rmPwned (if pwnedExists (pathRemove "PWNED") (ok ())))
        (_rm (pathRemove baseDir))]
    (do
      (assert (= (listLength itemsSpace) 1) "space path produces exactly one left item")
      (assert (= (chk/leftItemExpected itemSpace1) "ERR_UNKNOWN_SYMBOL") "space path expected is ERR_UNKNOWN_SYMBOL")
      (assert (= (listLength itemsInject) 1) "inject path produces exactly one left item")
      (assert (= (chk/leftItemExpected itemInject1) "ERR_UNKNOWN_SYMBOL") "inject path expected is ERR_UNKNOWN_SYMBOL")
      (assert (not pwnedExists) "no PWNED file exists after check")
      true))

fn testWorkingDirectoryIndependence! -> Bool
  (let [(deepPath (resultOr (realPath "asl/packages/asl-forms/src/check.asl") ""))
        (hostBin (chk/findHostBinary! deepPath))]
    (do
      (assert (not (stringEmpty? deepPath)) "canonical deepPath is non-empty")
      (assert (fileExists? hostBin) "findHostBinary finds existing host executable")
      (assert (stringEndsWith? hostBin "asl/host/out/asl-host") "hostBin ends with asl/host/out/asl-host")
      (assert (not (fileExists? "asl/packages/asl-forms/tests/_chk_tmp.asl")) "no fixed temp file in tests directory")
      true))

fn testHostCheckFailureReporting! -> Bool
  (let [(nonHost "/nonexistent/path/to/asl-host")
        (testPath "asl/packages/asl-forms/src/check.asl")
        (res (chk/runHostCheckWithBinary! testPath "(module a)" nonHost))
        (errStr (mt res ((err e) e) ((ok _) "")))]
    (do
      (assert (err? res) "non-zero exit without ERR lines returns err result")
      (assert (stringStartsWith? errStr "hostCheck exit ") "err message starts with hostCheck exit")
      (assert (stringContains? errStr "127") "err message includes exit code 127")
      true))

fn testCleanCorpusFiles! -> Bool
  (do
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/source.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/source.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/tree.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/tree.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/print.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/print.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/cursor.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/cursor.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/symbols.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/symbols.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/outline.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/outline.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/core/bytesText.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/core/bytesText.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/lex.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/lex.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/expr.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/expr.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/stmt.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/stmt.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/module.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/module.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/symbols.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/symbols.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/js/recover.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/js/recover.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/ts/types.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/ts/types.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/ts/decl.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/ts/decl.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/ts/module.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/ts/module.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/ts/symbols.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/ts/symbols.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/json.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/json.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/xml.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/xml.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/text.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/text.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/markdown.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/markdown.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/jsx.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/jsx.asl")
    (assert (checkFileClean! "asl/packages/asl-syntax/src/tsx.asl") "clean corpus file yields no semantic items: asl/packages/asl-syntax/src/tsx.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/check.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/check.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/kernel.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/kernel.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/repair.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/repair.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/symbol.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/symbol.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/similarity.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/similarity.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/ops.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/ops.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/wire.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/wire.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/main.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/main.asl")
    (assert (checkFileClean! "asl/packages/asl-forms/src/rewrite.asl") "clean corpus file yields no semantic items: asl/packages/asl-forms/src/rewrite.asl")
    (assert (checkFileClean! "asl/packages/asl-parser/src/lexer.asl") "clean corpus file yields no semantic items: asl/packages/asl-parser/src/lexer.asl")
    (assert (checkFileClean! "asl/packages/asl-parser/src/reader.asl") "clean corpus file yields no semantic items: asl/packages/asl-parser/src/reader.asl")
    (assert (checkFileClean! "asl/packages/asl-parser/src/ast.asl") "clean corpus file yields no semantic items: asl/packages/asl-parser/src/ast.asl")
    (assert (checkFileClean! "asl/packages/asl-parser/src/indentLexer.asl") "clean corpus file yields no semantic items: asl/packages/asl-parser/src/indentLexer.asl")
    (assert (checkFileClean! "asl/web/plugins/vitePluginAsl.js") "clean corpus file yields no semantic items: asl/web/plugins/vitePluginAsl.js")
    (assert (checkFileClean! "asl/web/tailwind.config.js") "clean corpus file yields no semantic items: asl/web/tailwind.config.js")
    (assert (checkFileClean! "asl/web/vite.config.js") "clean corpus file yields no semantic items: asl/web/vite.config.js")
    (assert (checkFileClean! "tests/harnessBench/cases/attention-flood/svc/vendor/uploader.min.js") "clean corpus file yields no semantic items: tests/harnessBench/cases/attention-flood/svc/vendor/uploader.min.js")
    true)

fn lineOfSubstring text: String needle: String -> Int64
  (mt (stringIndexOf text needle)
    ((none) -1)
    ((some idx) (+ 1 (stringCountChar (optionOr (stringSlice text 0 idx) "") "\n"))))

fn testStagedEditPackageImports! -> Bool
  (let [(target "asl/packages/asl-forms/src/wire.asl")
        (orig (resultOr (fileReadString target) ""))
        (editedClean (str orig "
"))
        (resClean (chk/checkSemantic! target editedClean))
        (itemsClean (resultOr resClean (list)))
        (editedBad (str orig "
fn qqDummy -> Int64
  qqUnknown
"))
        (resBad (chk/checkSemantic! target editedBad))
        (itemsBad (resultOr resBad (list)))
        (itemBad1 (optionOr (listHead itemsBad) (chk/makeLeftItem 0 0 "" "" "")))]
    (do
      (assert (not (stringEmpty? orig)) "wire.asl read is non-empty")
      (assert (ok? resClean) "edited wire.asl checkSemantic is ok")
      (assert (listEmpty? itemsClean) "edited wire.asl plus newline gives 0 items")
      (assert (ok? resBad) "seeded unknown symbol checkSemantic is ok")
      (assert (= (listLength itemsBad) 1) "seeded unknown symbol gives exactly one item")
      (assert (= (chk/leftItemExpected itemBad1) "ERR_UNKNOWN_SYMBOL") "seeded unknown symbol expected is ERR_UNKNOWN_SYMBOL")
      (assert (= (chk/leftItemLine itemBad1) (lineOfSubstring editedBad "qqUnknown")) (str "seeded unknown symbol is at the line qqUnknown actually appears on in the edited fixture, got " (stringFromInt64 (chk/leftItemLine itemBad1)) " want " (stringFromInt64 (lineOfSubstring editedBad "qqUnknown"))))
      (assert (stringContains? (chk/leftItemNear itemBad1) "qqUnknown") "seeded unknown symbol near contains qqUnknown")
      true))

fn testTempFileWriteFailure! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (nonce (stringFromInt64 (monotonicNs)))
        (baseDir (str tmpDir "/asl_test_readonly_" nonce))
        (_cd (dirCreate baseDir))
        (target (str baseDir "/test.asl"))
        (orig "(module test/ro)
")
        (_w (fileWrite target orig))
        (_ch (processRun (str "chmod 500 " baseDir)))
        (modContent (str orig "fn extra -> Int64
  1
"))
        (semRes (chk/checkSemantic! target modContent))
        (receipt (chk/checkFileReceipt! 1 "check" target ":disk" modContent))
        (_res (processRun (str "chmod 700 " baseDir)))
        (_rm (pathRemove baseDir))]
    (do
      (assert (err? semRes) "file write failure returns err result")
      (assert (stringContains? receipt ":status \"rejected\"") "file write failure receipt is rejected")
      (assert (stringContains? receipt ":error-code \":ERR_HOST_CHECK\"") "file write failure error code is ERR_HOST_CHECK")
      (assert (stringContains? receipt "fileWrite failed") "file write failure message contains fileWrite failed")
      (assert (not (stringContains? receipt ":status \"ok\"")) "file write failure receipt does not contain ok")
      true))

fn testTemplateLiteralDynamicImports! -> Bool
  (let [(tmpDir (optionOr (envGet "TMPDIR") "/tmp"))
        (nonce (stringFromInt64 (monotonicNs)))
        (baseDir (str tmpDir "/asl_test_tmpl_" nonce))
        (_cd (dirCreate baseDir))
        (testPath (str baseDir "/testModule.ts"))
        (codeNoSub "export async function load() { const m = await import(`\x2e/nope`); return m; }
")
        (itemsNoSub (resultOr (chk/checkSemantic! testPath codeNoSub) (list)))
        (item1 (optionOr (listHead itemsNoSub) (chk/makeLeftItem 0 0 "" "" "")))]
    (let [(receiptNoSub (chk/checkFileReceipt! 1 "check" testPath ":disk" codeNoSub))
          (codeWithSub "export async function load(p: string) { const m = await import(`\x2e/nope/${p}`); return m; }
")
          (itemsWithSub (resultOr (chk/checkSemantic! testPath codeWithSub) (list)))
          (receiptWithSub (chk/checkFileReceipt! 2 "check" testPath ":disk" codeWithSub))
          (helperTs (str baseDir "/helper.ts"))
          (_wh (fileWrite helperTs "export const val = 100;
"))
          (codeResNoSub "export async function load() { const m = await import(`\x2e/helper`); return m; }
")
          (itemsResNoSub (resultOr (chk/checkSemantic! testPath codeResNoSub) (list)))
          (_rm (pathRemove baseDir))]
      (do
        (assert (= (listLength itemsNoSub) 1) "template literal import without sub gives one item")
        (assert (= (chk/leftItemExpected item1) "ERR_UNRESOLVED_IMPORT") "template literal without sub expected is ERR_UNRESOLVED_IMPORT")
        (assert (stringContains? receiptNoSub ":status \"rejected\"") "template literal without sub receipt is rejected")
        (assert (listEmpty? itemsWithSub) "template literal import with sub gives no error items")
        (assert (stringContains? receiptWithSub ":skippedImports 1") "template literal import with sub is counted in skipped field")
        (assert (stringContains? receiptWithSub ":status \"ok\"") "template literal import with sub receipt is ok")
        (assert (listEmpty? itemsResNoSub) "resolving template literal without sub gives no items")
        true)))

fn ! runTests -> Bool
  (do
    (assert (testSeededAslUnknownSymbol!) "testSeededAslUnknownSymbol")
    (assert (testUnresolvedTsRelativeImport!) "testUnresolvedTsRelativeImport")
    (assert (testResolvedTsRelativeImport!) "testResolvedTsRelativeImport")
    (assert (testLeftItemCapping) "testLeftItemCapping")
    (assert (testCleanCorpusFiles!) "testCleanCorpusFiles")
    (assert (testAbsolutePathImportingFile!) "testAbsolutePathImportingFile")
    (assert (testDirectoryIndexResolution!) "testDirectoryIndexResolution")
    (assert (testDynamicImportAndRequire!) "testDynamicImportAndRequire")
    (assert (testHostCheckPathShellQuoting!) "testHostCheckPathShellQuoting")
    (assert (testWorkingDirectoryIndependence!) "testWorkingDirectoryIndependence")
    (assert (testHostCheckFailureReporting!) "testHostCheckFailureReporting")
    (assert (testStagedEditPackageImports!) "testStagedEditPackageImports")
    (assert (testTempFileWriteFailure!) "testTempFileWriteFailure")
    (assert (testTemplateLiteralDynamicImports!) "testTemplateLiteralDynamicImports")
    true)
