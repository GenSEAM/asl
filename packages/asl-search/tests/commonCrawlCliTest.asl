(module aslWebApiSearch/tests/commonCrawlCliTest
  :x [runTests]
  :i [(aslWebApiSearch/commonCrawl :a cc)
      (aslWebApiSearch/commonCrawlCli :a cli)])

fn testEscapeAsn -> Bool
  (do
    (assert (= (cli/escapeAsn "simple") "simple") "Simple string unchanged")
    (assert (= (cli/escapeAsn "hello\"world") "hello\\\"world") "Escapes quotes")
    (assert (= (cli/escapeAsn "path\\to\\file") "path\\\\to\\\\file") "Escapes backslashes")
    (assert (= (cli/escapeAsn "line1\nline2") "line1\\nline2") "Escapes newlines")
    (assert (= (cli/escapeAsn "tab\tchar") "tab\\tchar") "Escapes tabs")
    (assert (= (cli/escapeAsn "return\rchar") "return\\rchar") "Escapes carriage returns")
    (assert (= (cli/escapeAsn "\x00") "\\u0000") "Escapes NUL as \\u0000")
    (assert (= (cli/escapeAsn "\x07") "\\u0007") "Escapes bell as \\u0007")
    (assert (= (cli/escapeAsn "\x1b") "\\u001B") "Escapes ESC as \\u001B")
    (assert (= (cli/escapeAsn "\x7f") "\\u007F") "Escapes DEL as \\u007F")
    (assert (= (cli/escapeAsn "mixed: \"hello\\world\"\n\x07") "mixed: \\\"hello\\\\world\\\"\\n\\u0007") "Escapes mixed characters")
    true)

fn testUnknownCommandErrorHead! -> Bool
  (let [(res (processRun "asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl bogus"))]
    (do
      (assert (= res.exitCode 1) "Exit code is 1 on unknown command")
      (assert (stringContains? res.stdout "(:ccQuote :err \"unknown command: bogus\")") "Error head is :ccQuote")
      (refute (stringContains? res.stdout ":ccError") "Must not contain :ccError")
      true))

fn testChooseNewestCaptureNo200! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_limit3.json"))]
    (mt readRes
      ((err e) (assert false (str "Failed reading fixture: " e)))
      ((ok src)
       (let [(parseRes (cc/ccParseCdxLines src "CC-MAIN-2026-39"))]
         (mt parseRes
           ((err pe) (assert false (str "Failed parsing lines: " pe)))
           ((ok caps)
            (let [(chosen (cli/chooseNewestCapture caps))]
              (do
                (assert (none? chosen) "Returns none when no status 200 exists")
                (refute (some? chosen) "Refutes some when no status 200 exists")
                true))))))))

fn testChooseNewestCaptureWith200! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_0704_0023.json"))]
    (mt readRes
      ((err e) (assert false (str "Failed reading fixture: " e)))
      ((ok src)
       (let [(parseRes (cc/ccParseCdxLines src "CC-MAIN-2026-39"))]
         (mt parseRes
           ((err pe) (assert false (str "Failed parsing lines: " pe)))
           ((ok caps)
            (let [(chosen (cli/chooseNewestCapture caps))]
              (mt chosen
                ((none) (assert false "Expected a status 200 capture"))
                ((some c)
                 (do
                   (assert (= c.status 200) "Chosen capture has status 200")
                   (assert (= c.url "https://arxiv.org/abs/0704.0023") "Chosen capture has correct url")
                   (assert (= c.timestamp "20260915030856") "Chosen capture has correct timestamp")
                   (assert (= c.offset 76711107) "Chosen capture has correct offset")
                   (assert (= c.length 10058) "Chosen capture has correct length")
                   true))))))))))

fn testChooseNewestCaptureMultiple200 -> Bool
  (let [(cOld (cc/CcCapture
                :crawl "CC-MAIN-2026-39"
                :url "https://example.com"
                :timestamp "20260901120000"
                :status 200
                :mime "text/html"
                :digest "DIGESTOLD"
                :filename "warc/old.warc.gz"
                :offset 100
                :length 200))
        (cNew (cc/CcCapture
                :crawl "CC-MAIN-2026-39"
                :url "https://example.com"
                :timestamp "20260915120000"
                :status 200
                :mime "text/html"
                :digest "DIGESTNEW"
                :filename "warc/new.warc.gz"
                :offset 300
                :length 400))
        (cNon200 (cc/CcCapture
                   :crawl "CC-MAIN-2026-39"
                   :url "https://example.com"
                   :timestamp "20260920120000"
                   :status 404
                   :mime "text/html"
                   :digest "DIGEST404"
                   :filename "warc/404.warc.gz"
                   :offset 500
                   :length 600))
        (caps (list cOld cNew cNon200))
        (chosen (cli/chooseNewestCapture caps))]
    (mt chosen
      ((none) (assert false "Expected newest 200 capture"))
      ((some c)
       (do
         (assert (= c.timestamp "20260915120000") "Picks newer timestamp 20260915120000 over 20260901120000")
         (assert (= c.digest "DIGESTNEW") "Digest matches newer capture")
         (refute (= c.status 404) "Ignores 404 even with newest timestamp")
         true))))

fn testFormatReceipt -> Bool
  (let [(cap (cc/CcCapture
               :crawl "CC-MAIN-2026-39"
               :url "https://arxiv.org/abs/0704.0023"
               :timestamp "20260915030856"
               :status 200
               :mime "text/html"
               :digest "4D64LMHL7SMBVN2C2PYJMJRKSSCUE7V2"
               :filename "crawl-data/CC-MAIN-2026-39/segments/1788492992222.68/warc/CC-MAIN-20260915021126-20260915051126-00866.warc.gz"
               :offset 76711107
               :length 10058))
        (receiptTrue (cli/formatQuoteReceipt true cap))
        (receiptFalse (cli/formatQuoteReceipt false cap))]
    (do
      (assert (stringStartsWith? receiptTrue "(:ccQuote :found true ") "Receipt starts with found true")
      (assert (stringStartsWith? receiptFalse "(:ccQuote :found false ") "Receipt starts with found false")
      (assert (stringContains? receiptTrue ":url \"https://arxiv.org/abs/0704.0023\"") "Contains url")
      (assert (stringContains? receiptTrue ":crawl \"CC-MAIN-2026-39\"") "Contains crawl")
      (assert (stringContains? receiptTrue ":file \"crawl-data/CC-MAIN-2026-39/segments/1788492992222.68/warc/CC-MAIN-20260915021126-20260915051126-00866.warc.gz\"") "Contains file")
      (assert (stringContains? receiptTrue ":offset 76711107") "Contains unquoted offset")
      (assert (stringContains? receiptTrue ":length 10058") "Contains unquoted length")
      (assert (stringContains? receiptTrue ":digest \"4D64LMHL7SMBVN2C2PYJMJRKSSCUE7V2\"") "Contains digest")
      (assert (stringContains? receiptTrue ":timestamp \"20260915030856\")") "Contains timestamp and closes")
      true))

fn testFormatCaptureLine -> Bool
  (let [(cap (cc/CcCapture
               :crawl "CC-MAIN-2026-39"
               :url "https://arxiv.org/abs/0704.0023"
               :timestamp "20260915030856"
               :status 200
               :mime "text/html"
               :digest "DIG123"
               :filename "file.warc.gz"
               :offset 1000
               :length 2000))
        (line (cli/formatCaptureLine cap))]
    (do
      (assert (stringStartsWith? line "(:ccCapture ") "Line starts with :ccCapture")
      (assert (stringContains? line ":url \"https://arxiv.org/abs/0704.0023\"") "Contains url")
      (assert (stringContains? line ":crawl \"CC-MAIN-2026-39\"") "Contains crawl")
      (assert (stringContains? line ":file \"file.warc.gz\"") "Contains file")
      (assert (stringContains? line ":offset 1000") "Contains offset")
      (assert (stringContains? line ":length 2000") "Contains length")
      (assert (stringContains? line ":digest \"DIG123\"") "Contains digest")
      (assert (stringContains? line ":timestamp \"20260915030856\"") "Contains timestamp")
      (assert (stringContains? line ":status 200") "Contains status")
      (assert (stringContains? line ":mime \"text/html\")") "Contains mime and closes")
      true))

fn testChooseNewestCaptureExactUrlMoreThan5 -> Bool
  (let [(c1 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260901000000" :status 200 :mime "text/html" :digest "D1" :filename "f1" :offset 0 :length 10))
        (c2 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260902000000" :status 200 :mime "text/html" :digest "D2" :filename "f2" :offset 0 :length 10))
        (c3 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260903000000" :status 200 :mime "text/html" :digest "D3" :filename "f3" :offset 0 :length 10))
        (c4 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260904000000" :status 200 :mime "text/html" :digest "D4" :filename "f4" :offset 0 :length 10))
        (c5 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260905000000" :status 200 :mime "text/html" :digest "D5" :filename "f5" :offset 0 :length 10))
        (cHttp (cc/CcCapture :crawl "C" :url "http://example.com/target" :timestamp "20260909999999" :status 200 :mime "text/html" :digest "D6" :filename "f6" :offset 0 :length 10))
        (c7 (cc/CcCapture :crawl "C" :url "https://example.com/target" :timestamp "20260907000000" :status 200 :mime "text/html" :digest "D7" :filename "f7" :offset 0 :length 10))
        (caps (list c1 c2 c3 c4 c5 cHttp c7))
        (chosen (cli/chooseNewestCaptureForUrl caps "https://example.com/target"))]
    (mt chosen
      ((none) (assert false "Expected a chosen capture"))
      ((some c)
       (do
         (assert (= c.timestamp "20260907000000") "Picks newest status-200 matching target URL exactly (beyond row 5)")
         (assert (= c.url "https://example.com/target") "Target URL matches exactly")
         (refute (= c.url "http://example.com/target") "Ignores http:// variant even with newer timestamp")
         (refute (= c.timestamp "20260905000000") "Does not stop at 5 rows")
         true))))

fn testQuoteLookupPlanLimit -> Bool
  (let [(plan (cli/quoteLookupPlan "https://example.com/target"))]
    (do
      (assert (= plan.limit 1000) "Quote lookup plan specifies limit 1000")
      (refute (= plan.limit 5) "Quote lookup plan limit is not 5")
      true))

fn testQuoteLookupPlanSelect -> Bool
  (let [(target "https://example.com/target")
        (plan (cli/quoteLookupPlan target))
        (cOther (cc/CcCapture
                  :crawl "C"
                  :url "http://example.com/target"
                  :timestamp "20260909999999"
                  :status 200
                  :mime "text/html"
                  :digest "D_OTHER"
                  :filename "f_other"
                  :offset 0
                  :length 10))
        (cTargetOld (cc/CcCapture
                      :crawl "C"
                      :url target
                      :timestamp "20260901000000"
                      :status 200
                      :mime "text/html"
                      :digest "D_TARGET_OLD"
                      :filename "f_target_old"
                      :offset 0
                      :length 10))
        (cTargetNew (cc/CcCapture
                      :crawl "C"
                      :url target
                      :timestamp "20260905000000"
                      :status 200
                      :mime "text/html"
                      :digest "D_TARGET_NEW"
                      :filename "f_target_new"
                      :offset 0
                      :length 10))
        (caps (list cTargetOld cOther cTargetNew))
        (chosen (plan.select caps))]
    (mt chosen
      ((none) (assert false "Expected chosen capture from plan"))
      ((some c)
       (do
         (assert (= c.url target) "Plan selector selects capture for exact URL")
         (assert (= c.timestamp "20260905000000") "Plan selector selects newest 200 for exact URL")
         (refute (= c.url "http://example.com/target") "Plan selector refutes other URL even with newer timestamp")
         true))))

fn testRunQuoteUsesQuoteLookupPlan! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_0704_0023.json"))]
    (mt readRes
      ((err e) (assert false (str "Failed reading fixture: " e)))
      ((ok src)
       (let [(url "https://arxiv.org/abs/0704.0023")
             (plan (cli/quoteLookupPlan url))
             (crawl "CC-MAIN-2026-39")
             (selRes (cli/selectQuoteCapture plan src crawl))
             (defLim (cli/parseLookupLimit (none)))
             (curlArgs (cc/ccBuildLookupArgs crawl url plan.limit))
             (curlUrl (optionOr (listGet curlArgs 3) ""))]
         (do
           (assert (= plan.limit 1000) "Quote lookup plan carries the requested fetch limit")
           (assert (stringContains? curlUrl "&limit=1000") "Quote lookup limit reaches the curl request arguments")
           (refute (stringContains? curlUrl "&limit=5") "Curl request does not use default limit instead of plan")
           (refute (= plan.limit 5) "Quote lookup plan does not hardcode the default limit")
           (refute (= plan.limit 7) "Quote lookup plan does not hardcode limit seven")
           (assert (ok? selRes) "selectQuoteCapture returns ok on fixture CDX text")
           (mt selRes
             ((err _) (assert false "selectQuoteCapture must not err on fixture"))
             ((ok chosen)
              (mt chosen
                ((none) (assert false "Expected a chosen capture via plan select"))
                ((some c)
                 (do
                   (assert (= c.url url) "Chosen capture matches exact target URL")
                   (assert (= c.timestamp "20260915030856") "Chosen capture is newest status 200 for URL")
                   (assert (= c.offset 76711107) "Chosen capture offset matches fixture")
                   (refute (= c.url "http://arxiv.org/abs/$page") "Does not pick unrelated capture"))))))
           (assert (= defLim 5) "Default lookup limit is 5")
           (refute (= defLim 7) "Default lookup limit is not 7")
           true)))))

fn testFormatCaptureError -> Bool
  (let [(errLine (cli/formatCaptureError "something failed"))]
    (do
      (assert (= errLine "(:ccCapture :err \"something failed\")") "formatCaptureError formats correctly")
      (refute (stringContains? errLine ":ccQuote") "formatCaptureError uses :ccCapture")
      true))

fn testLookupRecordedErrorBody! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_no_captures.json"))]
    (mt readRes
      ((err e) (assert false (str "Failed reading fixture: " e)))
      ((ok src)
       (let [(res (cli/executeLookupCdx! src "CC-MAIN-2026-39"))]
         (do
           (assert (ok? res) "executeLookupCdx returns ok result")
           (mt res
             ((ok code)
              (do
                (assert (= code 1) "Exit code is 1 on CDX error body")
                (refute (= code 0) "Exit code is not 0 on CDX error body")
                true))
             ((err _) false)))))))

fn testLookupRecordedNonJsonBody! -> Bool
  (let [(nonJson "<html><body>404 Not Found</body></html>")
        (res (cli/executeLookupCdx! nonJson "CC-MAIN-2026-39"))]
    (do
      (assert (ok? res) "executeLookupCdx returns ok result")
      (mt res
        ((ok code)
         (do
           (assert (= code 1) "Exit code is 1 on non-JSON error body")
           (refute (= code 0) "Exit code is not 0 on non-JSON error body")
           true))
        ((err _) false))))

fn testLookupRecordedGenuineEmpty! -> Bool
  (let [(res (cli/executeLookupCdx! "" "CC-MAIN-2026-39"))]
    (do
      (assert (ok? res) "executeLookupCdx returns ok result")
      (mt res
        ((ok code)
         (do
           (assert (= code 0) "Exit code is 0 on genuine empty result")
           (refute (= code 1) "Exit code is not 1 on genuine empty result")
           true))
        ((err _) false))))

fn testLookupRecordedValidCaptures! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_limit3.json"))]
    (mt readRes
      ((err e) (assert false (str "Failed reading fixture: " e)))
      ((ok src)
       (let [(res (cli/executeLookupCdx! src "CC-MAIN-2026-39"))]
         (do
           (assert (ok? res) "executeLookupCdx returns ok result")
           (mt res
             ((ok code)
              (do
                (assert (= code 0) "Exit code is 0 on valid captures")
                (refute (= code 1) "Exit code is not 1 on valid captures")
                true))
             ((err _) false)))))))

fn testRunLookupErrorExit! -> Bool
  (let [(res (cli/runLookup! "arxiv.org/abs/nonexistent-fixture-test-url-12345" 5))]
    (do
      (assert (= res (ok 1)) "runLookup returns exit code 1 on error")
      (refute (= res (ok 0)) "runLookup refutes exit code 0 on error")
      true))

fn ! runTests -> Bool
  (do
    (assert (testEscapeAsn) "testEscapeAsn passes")
    (assert (testUnknownCommandErrorHead!) "testUnknownCommandErrorHead passes")
    (assert (testChooseNewestCaptureNo200!) "testChooseNewestCaptureNo200 passes")
    (assert (testChooseNewestCaptureWith200!) "testChooseNewestCaptureWith200 passes")
    (assert (testChooseNewestCaptureMultiple200) "testChooseNewestCaptureMultiple200 passes")
    (assert (testChooseNewestCaptureExactUrlMoreThan5) "testChooseNewestCaptureExactUrlMoreThan5 passes")
    (assert (testQuoteLookupPlanLimit) "testQuoteLookupPlanLimit passes")
    (assert (testQuoteLookupPlanSelect) "testQuoteLookupPlanSelect passes")
    (assert (testRunQuoteUsesQuoteLookupPlan!) "testRunQuoteUsesQuoteLookupPlan passes")
    (assert (testFormatReceipt) "testFormatReceipt passes")
    (assert (testFormatCaptureLine) "testFormatCaptureLine passes")
    (assert (testFormatCaptureError) "testFormatCaptureError passes")
    (assert (testLookupRecordedErrorBody!) "testLookupRecordedErrorBody passes")
    (assert (testLookupRecordedNonJsonBody!) "testLookupRecordedNonJsonBody passes")
    (assert (testLookupRecordedGenuineEmpty!) "testLookupRecordedGenuineEmpty passes")
    (assert (testLookupRecordedValidCaptures!) "testLookupRecordedValidCaptures passes")
    (assert (testRunLookupErrorExit!) "testRunLookupErrorExit passes")
    true)
