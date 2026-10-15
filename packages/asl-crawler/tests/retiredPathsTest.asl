(module aslCrawlerTests/retiredPathsTest
  :x [runTests]
  :i [])

fn ! runTests -> Bool
  (let [(host (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host"))
        (t (stringFromInt64 (monotonicNs)))
        (trapDir (str "/tmp/trapTest_" t))
        (_ (dirCreate trapDir))
        (_ (dirCreate (str trapDir "/bin")))
        (trapLog (str trapDir "/trap.log"))
        (trapScript (str "#!/bin/sh\n"
                         "echo \"TRAP_INVOKED: $*\" >> \"" trapLog "\"\n"
                         "exit 99\n"))
        (_ (fileWrite (str trapDir "/bin/asl-crawler") trapScript))
        (_ (fileChmod (str trapDir "/bin/asl-crawler") 509))
        (curlScript (str "#!/bin/sh\n"
                         "case \"$*\" in */api/asl/browser/exec*) echo '(:browserActionReceipt :id \"fixture-1\" :status :ok :op \"watchMedia\" :duration 0 :url \"https://example.com/test\" :artifact \"fixture/snapshot.asn\" :text \"recorded gateway action\")' ;; *) echo \x27<html><head><title>Test</title></head><body><h1>Hello</h1></body></html>\x27 ;; esac\n"
                         "exit 0\n"))
        (_ (fileWrite (str trapDir "/bin/curl") curlScript))
        (_ (fileChmod (str trapDir "/bin/curl") 509))

        (crawlCmd (str "PATH=" trapDir "/bin:$PATH CRAWL_ROOT=. " host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/test --mode staticHttp --distill raw"))
        (crawlRes (processRun crawlCmd))

        (trapFired (fileExists? trapLog))

        (_ (fileWrite trapLog ""))
        (tiktokRes (processRun (str "PATH=" trapDir "/bin:$PATH CRAWL_ROOT=. " host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://example.com/test --watch 0")))
        (tiktokTrapFired (stringContains? (resultOr (fileReadString trapLog) "") "TRAP_INVOKED"))
        (_ (fileWrite trapLog ""))
        (automateRes (processRun (str "PATH=" trapDir "/bin:$PATH CRAWL_ROOT=. " host " run asl/packages/asl-crawler/src/crawler.asl automate /tmp/nonexistent-agent-slang")))
        (automateTrapFired (stringContains? (resultOr (fileReadString trapLog) "") "TRAP_INVOKED"))
        (_ (fileWrite trapLog ""))
        (agentRes (processRun (str "PATH=" trapDir "/bin:$PATH CRAWL_ROOT=. " host " run asl/packages/asl-crawler/src/crawler.asl agent --status")))
        (agentTrapFired (stringContains? (resultOr (fileReadString trapLog) "") "TRAP_INVOKED"))
        (_ (processRun (str "rm -rf " trapDir)))]
    (do
      (refute (fileExists? "tests/parity/forms/delegateDriver.asl") "retired forms delegation driver is absent")
      (assert (= crawlRes.exitCode 0) "delegated crawl exits successfully")
      (assert (= tiktokRes.exitCode 0) "delegated TikTok watch dispatches through the browser gateway")
      (assert (stringContains? tiktokRes.stdout "(:browserActionReceipt") "delegated TikTok watch returns the gateway receipt")
      (assert (= automateRes.exitCode 1) "delegated automation reports missing script")
      (assert (stringContains? automateRes.stdout "(:automationReceipt :status :failed :error \"script file does not exist\")") "delegated automation returns the missing-script failure receipt")
      (assert (= agentRes.exitCode 0) "delegated agent status exits successfully")
      (assert (stringContains? agentRes.stdout "(:inBrowserAgent") "delegated agent returns status output")
      (refute trapFired "retired asl-crawler path was never executed during crawl delegation")
      (refute tiktokTrapFired "retired asl-crawler path was never executed during TikTok delegation")
      (refute automateTrapFired "retired asl-crawler path was never executed during automation delegation")
      (refute agentTrapFired "retired asl-crawler path was never executed during in-browser-agent delegation")
      (assert (= crawlRes.exitCode 0) "crawl delegation exited with code 0")
      (assert (stringContains? crawlRes.stdout "<h1>Hello</h1>") "delegated crawl returns content fetched by crawler")
      true))
