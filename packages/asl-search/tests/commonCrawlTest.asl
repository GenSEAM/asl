(module aslWebApiSearch/tests/commonCrawlTest
  :x [runTests]
  :i [(aslWebApiSearch/commonCrawl :a cc)])

fn testCdxParsing! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_limit3.json"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading cdx fixture: " e)) false))
      ((ok src)
       (let [(parseRes (cc/ccParseCdxLines src "CC-MAIN-2026-39"))]
         (mt parseRes
           ((err pe) (do (assert false (str "Failed parsing cdx lines: " pe)) false))
           ((ok caps)
            (do
              (assert (= (listLength caps) 3) "Parsed 3 captures from fixture")
              (mt (listHead caps)
                ((none) (assert false "Capture 0 missing"))
                ((some c0)
                 (do
                   (assert (= c0.crawl "CC-MAIN-2026-39") "c0 crawl matches")
                   (assert (= c0.url "http://arxiv.org/abs/$page") "c0 url matches")
                   (assert (= c0.timestamp "20260914171547") "c0 timestamp matches")
                   (assert (= c0.status 301) "c0 status 301")
                   (assert (= c0.mime "unk") "c0 mime unk")
                   (assert (= c0.digest "3I42H3S6NNFQ2MSVX7XZKYAYSCX5QBYJ") "c0 digest matches")
                   (assert (= c0.offset 101528) "c0 offset 101528")
                   (assert (= c0.length 588) "c0 length 588")
                   (assert (= c0.filename "crawl-data/CC-MAIN-2026-39/segments/1788492991828.95/crawldiagnostics/CC-MAIN-20260914170406-20260914200406-00200.warc.gz") "c0 filename matches"))))
              (mt (listGet caps 1)
                ((none) (assert false "Capture 1 missing"))
                ((some c1)
                 (do
                   (assert (= c1.status 404) "c1 status 404")
                   (assert (= c1.length 2847) "c1 length 2847")
                   (assert (= c1.offset 3111223) "c1 offset 3111223"))))
              (let [(readRes2 (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_arxiv_0704_0023.json"))]
                (mt readRes2
                  ((err e2) (do (assert false (str "Failed reading cdx 0704.0023 fixture: " e2)) false))
                  ((ok src2)
                   (let [(parseRes2 (cc/ccParseCdxLines src2 "CC-MAIN-2026-39"))]
                     (mt parseRes2
                       ((err pe2) (do (assert false (str "Failed parsing cdx 0704.0023 lines: " pe2)) false))
                       ((ok caps2)
                        (do
                          (assert (= (listLength caps2) 2) "Parsed 2 captures for 0704.0023")
                          (mt (listGet caps2 1)
                            ((none) (assert false "Missing capture 1 for 0704.0023"))
                            ((some cap200)
                             (do
                               (assert (= cap200.status 200) "cap200 status 200")
                               (assert (= cap200.length 10058) "cap200 length 10058")
                               (assert (= cap200.offset 76711107) "cap200 offset 76711107"))))
                          true))))))))))))))

fn testCdxErrorBodyReturnsErr! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/tests/fixtures/commonCrawl/cdx_no_captures.json"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading no_captures fixture: " e)) false))
      ((ok src)
       (let [(parseRes (cc/ccParseCdxLines src "CC-MAIN-2026-39"))]
         (do
           (assert (err? parseRes) "CDX message fixture returns error")
           (refute (ok? parseRes) "CDX message fixture refutes ok")
           (mt parseRes
             ((err msg)
              (do
                (assert (stringContains? msg "No Captures found") "Error message preserves cause")
                true))
             ((ok _) false)))))))

fn testCdxGenuineEmptyReturnsEmptyList -> Bool
  (let [(parseRes (cc/ccParseCdxLines "" "CC-MAIN-2026-39"))
        (parseResWs (cc/ccParseCdxLines "   \n\r\n  " "CC-MAIN-2026-39"))]
    (do
      (assert (ok? parseRes) "Empty body returns ok")
      (mt parseRes
        ((ok caps)
         (assert (listEmpty? caps) "Empty body returns empty list"))
        ((err _) (assert false "expected ok")))
      (assert (ok? parseResWs) "Whitespace body returns ok")
      (mt parseResWs
        ((ok capsWs)
         (assert (listEmpty? capsWs) "Whitespace body returns empty list"))
        ((err _) (assert false "expected ok")))
      true))

fn testCdxNonJsonReturnsErr -> Bool
  (let [(nonJson "<html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1></body></html>")
        (parseRes (cc/ccParseCdxLines nonJson "CC-MAIN-2026-39"))]
    (do
      (assert (err? parseRes) "Non-JSON body returns error")
      (refute (ok? parseRes) "Non-JSON body refutes ok")
      true))

fn testGunzipAndParseWarc! -> Bool
  (let [(readRes (fileReadBytes "asl/packages/asl-search/tests/fixtures/commonCrawl/arxiv_0704_0023.warc.gz"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading warc.gz fixture: " e)) false))
      ((ok raw)
       (do
         (assert (= (bytesLength raw) 10058) "Fixture byte length is exactly 10058")
         (let [(gzRes (cc/ccGunzip! raw))]
           (mt gzRes
             ((err ge) (do (assert false (str "ccGunzip! failed on fixture: " ge)) false))
             ((ok warcText)
              (do
                (assert (stringContains? warcText "WARC/1.0") "WARC text contains WARC/1.0 header")
                (assert (stringContains? warcText "WARC-Target-URI: https://arxiv.org/abs/0704.0023") "WARC text contains target URI")
                (let [(parseRes (cc/ccParseWarc warcText))]
                  (mt parseRes
                    ((err we) (do (assert false (str "ccParseWarc failed: " we)) false))
                    ((ok rec)
                     (do
                       (assert (= rec.targetUri "https://arxiv.org/abs/0704.0023") "Record targetUri matches")
                       (assert (= rec.warcDate "2026-09-15T03:08:56Z") "Record warcDate matches")
                       (assert (= rec.httpStatus 200) "Record httpStatus is 200")
                       (assert (stringStartsWith? rec.contentType "text/html") "Record contentType is text/html")
                       (assert (stringContains? rec.htmlBody "<title>[0704.0023] ALMA as the ideal probe of the solar chromosphere</title>") "HTML body contains paper title")
                       true))))))))))))

fn testQuoteVerification! -> Bool
  (let [(readRes (fileReadBytes "asl/packages/asl-search/tests/fixtures/commonCrawl/arxiv_0704_0023.warc.gz"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading warc.gz fixture: " e)) false))
      ((ok raw)
       (let [(gzRes (cc/ccGunzip! raw))]
         (mt gzRes
           ((err ge) (do (assert false (str "ccGunzip! failed: " ge)) false))
           ((ok warcText)
            (let [(parseRes (cc/ccParseWarc warcText))]
              (mt parseRes
                ((err we) (do (assert false (str "ccParseWarc failed: " we)) false))
                ((ok rec)
                 (do
                   (assert (cc/ccQuoteInPage? rec "ALMA as the ideal probe of the solar chromosphere") "Quote in title matches")
                   (assert (cc/ccQuoteInPage? rec "The very nature of the solar chromosphere, its structuring and dynamics, remains far from being properly understood") "Quote in abstract matches")
                   (assert (cc/ccQuoteInPage? rec "M. A. Loukitcheva") "Author name matches")
                   (refute (cc/ccQuoteInPage? rec "Quantum gravity warp drive teleportation verified") "Fabricated quote is refuted")
                   (refute (cc/ccQuoteInPage? rec "This text does not exist anywhere in arxiv 0704.0023") "Nonexistent quote is refuted")
                   (let [(mockRec (cc/CcRecord
                                    :targetUri "https://example.org"
                                    :warcDate "2026-09-25T00:00:00Z"
                                    :httpStatus 200
                                    :contentType "text/html"
                                    :htmlBody "<div class=\"content\">Alpha &amp; Beta &lt;gamma&gt; &quot;delta&quot; &#39;epsilon&#39;</div>"))]
                     (do
                       (assert (cc/ccQuoteInPage? mockRec "Alpha & Beta <gamma> \"delta\" 'epsilon'") "Decodes entities and strips tags")
                       (refute (cc/ccQuoteInPage? mockRec "Alpha & Beta <gamma> zeta") "Refutes missing content in mock")
                       true))))))))))))

fn testTruncatedGzipFails! -> Bool
  (let [(readRes (fileReadBytes "asl/packages/asl-search/tests/fixtures/commonCrawl/truncated.warc.gz"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading truncated fixture: " e)) false))
      ((ok raw)
       (let [(gzRes (cc/ccGunzip! raw))]
         (do
           (assert (err? gzRes) "Truncated gzip must return error")
           (refute (ok? gzRes) "Truncated gzip must refute ok")
           true)))))


fn testGunzipHasNoProcessRun! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-search/src/commonCrawl.asl"))]
    (mt readRes
      ((err e) (do (assert false (str "Failed reading commonCrawl.asl: " e)) false))
      ((ok src)
       (let [(idxStart (stringIndexOf src "fn ccGunzip!"))]
         (mt idxStart
           ((none) (do (assert false "fn ccGunzip! not found in commonCrawl.asl") false))
           ((some sPos)
            (let [(rest (optionOr (stringSlice src sPos (stringLength src)) ""))
                  (idxNextFn (stringIndexOf (optionOr (stringSlice rest 12 (stringLength rest)) "") "\nfn "))]
              (mt idxNextFn
                ((none) (do (assert false "next fn not found after ccGunzip!") false))
                ((some ePos)
                 (let [(fnBody (optionOr (stringSlice rest 0 (+ ePos 12)) ""))]
                   (do
                     (refute (stringContains? fnBody "processRun") "ccGunzip! must not contain processRun")
                     (refute (stringContains? fnBody "mktemp") "ccGunzip! must not contain mktemp")
                     (assert (stringContains? fnBody "gz/gunzip") "ccGunzip! must use pure-ASL gz/gunzip")
                     true)))))))))))

fn testRfc3986Encoding -> Bool
  (do
    (assert (= (cc/rfc3986Encode "& = \"$`é") "%26%20%3D%20%22%24%60%C3%A9") "rfc3986Encode encodes & = space quote dollar backtick and non-ASCII")
    (assert (= (cc/rfc3986Encode "a-z_A-Z.0-9~") "a-z_A-Z.0-9~") "rfc3986Encode preserves unreserved characters")
    true)

fn testLookupArgsKeepHostileUrlAsData -> Bool
  (let [(hostile "x\"; touch /tmp/marker; echo \"")
        (cmd (optionOr (listGet (cc/ccBuildLookupArgs "CC-MAIN-2026-39" hostile 1) 3) ""))]
    (do
      (refute (stringContains? cmd "\";") "Lookup URL does not contain raw quote-semicolon data")
      (refute (stringContains? cmd "; touch") "Lookup URL does not contain raw shell separator")
      (assert (stringContains? cmd "%22%3B%20touch") "Hostile characters are percent-encoded in lookup URL")
      (assert (stringContains? cmd "&output=json&limit=1") "Lookup URL contains JSON and requested limit parameters")
            true))

fn ! runTests -> Bool
  (do
    (assert (testGunzipHasNoProcessRun!) "testGunzipHasNoProcessRun passes")
    (assert (testCdxParsing!) "testCdxParsing passes")
    (assert (testCdxErrorBodyReturnsErr!) "testCdxErrorBodyReturnsErr passes")
    (assert (testCdxGenuineEmptyReturnsEmptyList) "testCdxGenuineEmptyReturnsEmptyList passes")
    (assert (testCdxNonJsonReturnsErr) "testCdxNonJsonReturnsErr passes")
    (assert (testGunzipAndParseWarc!) "testGunzipAndParseWarc passes")
    (assert (testQuoteVerification!) "testQuoteVerification passes")
    (assert (testTruncatedGzipFails!) "testTruncatedGzipFails passes")
    (assert (testRfc3986Encoding) "testRfc3986Encoding passes")
    (assert (testLookupArgsKeepHostileUrlAsData) "testLookupArgsKeepHostileUrlAsData passes")
    true)
