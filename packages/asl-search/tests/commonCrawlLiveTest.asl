(module aslWebApiSearch/tests/commonCrawlLiveTest
  :x [runTests]
  :i [(aslWebApiSearch/commonCrawl :a cc)
      (aslWebApiSearch/commonCrawlCli :a cli)])

fn testLiveQuotePythonAndAbsent! -> Bool
  (mt (cc/ccLatestCrawl!)
    ((err e) (assert false (str "ccLatestCrawl! failed: " e)))
    ((ok crawl)
     (mt (cc/ccLookup! crawl "https://www.python.org/" 1000)
       ((err e) (assert false (str "ccLookup! failed: " e)))
       ((ok caps)
        (mt (cli/chooseNewestCaptureForUrl caps "https://www.python.org/")
          ((none) (assert false "Expected newest status-200 capture for python.org"))
          ((some newestCap)
           (let [(expectedTimestamp newestCap.timestamp)
                 (quoteRes (processRun "asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl quote https://www.python.org/ Python"))
                 (absentRes (processRun "asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl quote https://www.python.org/ xyz_nonexistent_quote_987654321"))]
             (do
               (assert (= quoteRes.exitCode 0) "Quote command exited with code 0")
               (assert (stringContains? quoteRes.stdout ":found true") "Quote output contains :found true")
               (assert (stringContains? quoteRes.stdout (str ":timestamp \"" expectedTimestamp "\"")) "Quote picked newest status-200 timestamp")
               (assert (= absentRes.exitCode 0) "Absent quote command exited with code 0")
               (assert (stringContains? absentRes.stdout ":found false") "Absent quote output contains :found false")
               (assert (stringContains? absentRes.stdout (str ":timestamp \"" expectedTimestamp "\"")) "Absent quote picked newest status-200 timestamp")
               true))))))))

fn testLiveNeverCrawledUrlFails! -> Bool
  (let [(res (processRun "asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl quote https://www.python.org/this-never-crawled-path-xyz-1234567890 Python"))]
    (do
      (assert (= res.exitCode 1) "Never-crawled URL exits with code 1")
      (assert (stringContains? res.stdout ":err") "Never-crawled URL outputs :err")
      true))

fn testLiveInjectionRefutation! -> Bool
  (let [(marker "/tmp/cc_live_injection_marker.tmp")
        (_clean1 (processRun (str "rm -f " marker)))
        (cmd (str "asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl lookup 'x\"; touch " marker "; echo \"' 1"))
        (res (processRun cmd))
        (chk (processRun (str "test -f " marker)))
        (_clean2 (processRun (str "rm -f " marker)))]
    (do
      (assert (!= chk.exitCode 0) "Marker file must not be created by shell injection")
      (refute (= chk.exitCode 0) "Refute existence of injection marker")
      true))

fn ! runTests -> Bool
  (do
    (assert (testLiveQuotePythonAndAbsent!) "testLiveQuotePythonAndAbsent passes")
    (assert (testLiveNeverCrawledUrlFails!) "testLiveNeverCrawledUrlFails passes")
    (assert (testLiveInjectionRefutation!) "testLiveInjectionRefutation passes")
    true)
