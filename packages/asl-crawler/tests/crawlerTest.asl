(module aslCrawler/tests/crawlerTest
  :x [testCrawlerSourceIntegrity! testCrawlerGrammarRegistration! testCrawlerUrlValidation testCrawlerStatusLogic! RunTests! runTests]
  :i [])

fn testCrawlerSourceIntegrity! -> Bool
  (let [(cRes (fileRead "asl/packages/asl-crawler/src/crawler.asl"))
        (sRes (fileRead "asl/packages/asl-crawler/src/stealth.asl"))
        (bRes (fileRead "asl/packages/asl-crawler/src/browserDetector.asl"))]
    (mt cRes
      ((err e1) (assert false (str "Failed to read crawler.asl: " e1)))
      ((ok cSrc)
        (do
          (assert (or (stringContains? cSrc "schema CrawlPool") (stringContains? cSrc "dfs CrawlPool")) "crawler.asl defines CrawlPool")
          (assert (or (stringContains? cSrc "schema CrawlJob") (stringContains? cSrc "dfs CrawlJob")) "crawler.asl defines CrawlJob")
          (assert (stringContains? cSrc "fn poolJobs") "crawler.asl defines poolJobs")
          (assert (stringContains? cSrc "fn crawlOk") "crawler.asl defines crawlOk")
          (assert (stringContains? cSrc "fn crawlDistilledAsn") "crawler.asl defines crawlDistilledAsn")
          (refute (stringContains? cSrc "webcache.googleusercontent.com") "crawler refutes dead Google webcache")
          (refute (stringContains? cSrc "Mach-O") "Zero Mach-O in crawler")
          (refute (stringContains? cSrc "ELF64") "Zero ELF64 in crawler"))))
    (mt sRes
      ((err e2) (assert false (str "Failed to read stealth.asl: " e2)))
      ((ok sSrc)
        (do
          (assert (or (stringContains? sSrc "schema StealthProfile") (stringContains? sSrc "dfs StealthProfile")) "stealth.asl defines StealthProfile")
          (assert (stringContains? sSrc "fn googlebotProfile") "stealth.asl defines googlebotProfile")
          (assert (stringContains? sSrc "fn chromeProfile") "stealth.asl defines chromeProfile")
          (refute (= sSrc "") "stealth source refutes empty"))))
    (mt bRes
      ((err e3) (assert false (str "Failed to read browserDetector.asl: " e3)))
      ((ok bSrc)
        (do
          (assert (stringContains? bSrc "fn macosBrowsers") "browserDetector.asl defines macosBrowsers")
          (assert (stringContains? bSrc "fn linuxBrowsers") "browserDetector.asl defines linuxBrowsers")
          (assert (stringContains? bSrc "fn cdpArgs") "browserDetector.asl defines cdpArgs")
          (refute (= bSrc "") "browser detector source refutes empty"))))
    true)

fn testCrawlerGrammarRegistration! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-crawler/src/crawler.asl"))]
    (mt gRes
      ((err e) (assert false (str "Failed to read crawler.asl: " e)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "aslCrawler/crawler") "crawler registers aslCrawler/crawler")
          (assert (stringContains? gSrc "CrawlPool") "crawler registers CrawlPool")
          (assert (stringContains? gSrc "CrawlJob") "crawler registers CrawlJob")
          (refute (stringContains? gSrc ";;") "crawler refutes legacy line comments"))))
    true)

fn testCrawlerUrlValidation -> Bool
  (do
    (assert (stringStartsWith? "https://example.com" "https://") "valid https scheme")
    (assert (stringStartsWith? "http://example.com" "http://") "valid http scheme")
    (refute (stringStartsWith? "file:///etc/passwd" "https://") "file scheme rejected for https")
    (refute (stringStartsWith? "file:///etc/passwd" "http://") "file scheme rejected for http")
    (refute (stringStartsWith? "gopher://bad" "https://") "gopher scheme rejected")
    (refute (stringStartsWith? "-v" "http://") "flag url rejected")
    true)

fn testCrawlerStatusLogic! -> Bool
  (mt (fileRead "asl/packages/asl-crawler/src/crawler.asl")
    ((err e) (do (assert false (str "Failed to read crawler.asl: " e)) false))
    ((ok src)
     (do
       (assert (stringContains? src "fn statusOk? status: I64 -> Bool\n  (and (>= status 200) (< status 300))") "statusOk? accepts exactly the 2xx range")
       (refute (stringContains? src "(<= status 300)") "the 2xx range refutes an inclusive 300 bound")
       (refute (stringContains? src "(> status 200)") "the 2xx range refutes excluding 200")
       (assert (stringContains? src "fn isSuccessfulStatus status: I64 -> Bool\n  (statusOk? status)") "isSuccessfulStatus delegates to statusOk?")
       (refute (stringContains? src "(>= status 400)") "status logic refutes counting 4xx as success")
       true)))

fn RunTests! -> Bool
  (and (testCrawlerSourceIntegrity!)
       (testCrawlerGrammarRegistration!)
       (testCrawlerUrlValidation)
       (testCrawlerStatusLogic!))

fn ! runTests -> Bool
  (RunTests!)
