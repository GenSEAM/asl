(module aslCrawlerTests/crawlerCliRegressionTest
  :x [runTests]
  :i [])

fn ! runTests -> Bool
  (let [(host (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host"))
        (t (stringFromInt64 (monotonicNs)))
        (stubDir (str "/tmp/crawlStubs_" t))
        (_ (dirCreate stubDir))
        (stubLog (str stubDir "/stub.log"))
        (curlScript (str "#!/bin/sh\n"
                         "echo \"curl $*\" >> \"$CRAWL_STUB_LOG\"\n"
                         "case \"$*\" in\n"
                         "  */api/asl/browser/exec*)\n"
                         "    echo '(:browserActionReceipt :id \"act-exec-001\" :status :ok :op \"navigate\" :duration 45 :url \"https://example.test\" :artifact \"artifacts/snapshot.asn\" :snapshot \"(:pageSnapshot :status :ok)\" :text \"Browser action navigate executed successfully\")'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *1111111111*)\n"
                         "    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"9876543210\":{\"id\":\"9876543210\",\"desc\":\"Measured caption\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"diggCount\":\"321\",\"commentCount\":\"17\"},\"music\":{\"title\":\"Measured sound\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *9876543210*)\n"
                         "    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"9876543210\":{\"id\":\"9876543210\",\"desc\":\"Measured caption\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"diggCount\":\"321\",\"commentCount\":\"17\"},\"music\":{\"title\":\"Measured sound\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *2222222222*)\n"
                         "    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"2222222222\":{\"id\":\"2222222222\",\"desc\":\"\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"diggCount\":\"321\",\"commentCount\":\"17\"},\"music\":{\"title\":\"Measured sound\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *3333333333*)\n"
                         "    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"3333333333\":{\"id\":\"3333333333\",\"desc\":\"Caption without likes\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"commentCount\":\"17\"},\"music\":{\"title\":\"Measured sound\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *4444444444*)\n"
                         "    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"4444444444\":{\"id\":\"4444444444\",\"desc\":\"Caption without comments\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"diggCount\":\"321\"},\"music\":{\"title\":\"Measured sound\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *5555555555*)\n    echo '<script id=\"SIGI_STATE\" type=\"application/json\">{\"ItemModule\":{\"5555555555\":{\"id\":\"5555555555\",\"desc\":\"Caption with no sound title\",\"author\":{\"uniqueId\":\"creator\"},\"stats\":{\"diggCount\":\"321\",\"commentCount\":\"17\"},\"music\":{\"title\":\"\"}}}}</script>'\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *fail*|*invalid*)\n"
                         "    echo \"curl: (28) Connection timed out\" >&2\n"
                         "    exit 28\n"
                         "    ;;\n"
                         "  *raw*)\n"
                         "    echo \"<html><body><pre>Raw content</pre></body></html>\"\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "  *)\n"
                         "    echo \"<!DOCTYPE html><html><head><title>Parity Test Page</title></head><body><h1>Parity Header</h1><p>Parity body paragraph text.</p></body></html>\"\n"
                         "    exit 0\n"
                         "    ;;\n"
                         "esac\n"))
        (chromeScript (str "#!/bin/sh\n"
                           "echo \"chrome $*\" >> \"$CRAWL_STUB_LOG\"\n"
                           "echo \"<!DOCTYPE html><html><head><title>Chrome Headless DOM</title></head><body><main>Chrome dynamic content</main></body></html>\"\n"
                           "exit 0\n"))
        (_ (fileWrite (str stubDir "/curl") curlScript))
        (_ (fileWrite (str stubDir "/chrome") chromeScript))
        (_ (fileWrite (str stubDir "/google-chrome") chromeScript))
        (_ (fileChmod (str stubDir "/curl") 509))
        (_ (fileChmod (str stubDir "/chrome") 509))
        (_ (fileChmod (str stubDir "/google-chrome") 509))
        (envPrefix (str "PATH=" stubDir ":$PATH CHROME_BIN=" stubDir "/chrome CRAWL_STUB_LOG=" stubLog " "))

        (cmd1 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/test --mode staticHttp --distill asn"))
        (out1 (processRun cmd1))
        (log1 (resultOr (fileReadString stubLog) ""))

        (cmd2 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/test --mode patchright --distill asn"))
        (out2 (processRun cmd2))
        (log2 (resultOr (fileReadString stubLog) ""))
        (autoCmd (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/test --mode auto --distill asn"))
        (autoOut (processRun autoCmd))
        (autoLog (resultOr (fileReadString stubLog) ""))

        (cmd3 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/raw --mode staticHttp --distill raw"))
        (out3 (processRun cmd3))

        (cmd4 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/test --mode staticHttp --distill text"))
        (out4 (processRun cmd4))

        (cmd5 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/fail --mode staticHttp"))
        (out5 (processRun cmd5))

        (cmd6 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --status"))
        (out6 (processRun cmd6))

        (exportPath (str stubDir "/new/nested/parent/bundle.js"))
        (cmd7 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --export " exportPath))
        (out7 (processRun cmd7))
        (exportedOk (fileExists? exportPath))
        (exportBlocker (str stubDir "/file-parent"))
        (_ (fileWrite exportBlocker "not a directory"))
        (failedExportPath (str exportBlocker "/bundle.js"))
        (outFailedExport (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --export " failedExportPath)))

        (cmd8 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/9876543210 --extract"))
        (out8 (processRun cmd8))

        (cmd9 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl status"))
        (out9 (processRun cmd9))
        (cloudProxyRaw (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/cloud --mode cloudProxy --distill raw")))
        (cloudProxyFailed (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/fail-cloud --mode cloudProxy --distill asn")))
        (maxNodesPath (str stubDir "/max-nodes.js"))
        (maxNodesRun (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --export " maxNodesPath " --max-nodes 7")))
        (maxNodesScript (resultOr (fileReadString maxNodesPath) ""))
        (invalidMaxNodesRun (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --max-nodes invalid --export " stubDir "/invalid.js")))
        (missingMaxNodesRun (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --max-nodes")))
        (outDispatchProbe (processRun (str "ASL_HOST=" host " ./bin/asl crawler __dispatch_probe__")))

        (cmd10 (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl session tiktok"))
        (out10 (processRun cmd10))
        (scriptPath (str stubDir "/automation.sh"))
        (_ (fileWrite scriptPath "(:automationAction :id \"fixture-auto\" :op \"navigate\" :target \"https://example.test\")\n"))
        (out11 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl automate " scriptPath)))
        (failedScriptPath (str stubDir "/automation-fail.sh"))
        (_ (fileWrite failedScriptPath "(:automationAction :id \"fixture-fail\" :op \"click\" :target \"#missing\")\n"))
        (out12 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl automate " failedScriptPath)))
        (out14 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/0000000000 --extract")))
        (out13 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/9876543210 --watch 2")))
        (out15 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl 'https://example.invalid/$(touch " stubDir "/injected)' --mode staticHttp")))
        (out16 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl 'file:///etc/hosts\";touch " stubDir "/browser-injected;\"' --mode patchright")))
        (out17 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://user:pass@example.com/ --mode staticHttp")))
        (out18 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/ --target 'foo bar&x=y' --mode staticHttp")))
        (out19 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/ --browser chrome --mode staticHttp")))
        (out20 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/ --mode extension")))
        (asnPath (str stubDir "/action.asn"))
        (_ (fileWrite asnPath "(:action :op :navigate :target \\\"https://example.com\\\")"))
        (out21 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl automate " asnPath)))
        (out22 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/1111111111 --extract")))
        (out23 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/2222222222 --extract")))
        (out26 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/3333333333 --extract")))
        (out27 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/4444444444 --extract")))
        (out28 (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/5555555555 --extract")))
        (unknownCrawl (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl https://example.com/ --mystery --mode staticHttp")))
        (unknownTikTok (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl tiktok https://www.tiktok.com/@creator/video/9876543210 --mystery")))
        (dollarUrl (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl 'https://example.com/items?$filter=name' --mode staticHttp")))
        (quoteExportPath (str stubDir "/bundle\"quoted.js"))
        (quoteExport (processRun (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl agent --export '" quoteExportPath "'")))
        (manifest (resultOr (fileReadString "asl/packages/asl-crawler/manifest.asn") ""))
        (quoteMarker (str "/tmp/crawlQuoteMarker_" t))
        (quoteCmd (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl \"https://example.com/';touch " quoteMarker ";'\" --mode staticHttp"))
        (out24 (processRun quoteCmd))
        (quoteAmpMarker (str "/tmp/crawlQuoteAmpMarker_" t))
        (quoteAmpCmd (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl \"https://example.com/';touch " quoteAmpMarker ";echo '&\" --mode staticHttp"))
        (outQuoteAmp (processRun quoteAmpCmd))
        (quoteAmpLog (resultOr (fileReadString stubLog) ""))
        (backtickMarker (str "/tmp/crawlBacktickMarker_" t))
        (backtickCmd (str envPrefix host " run asl/packages/asl-crawler/src/crawler.asl crawl 'https://example.com/`touch " backtickMarker "`' --mode staticHttp"))
        (out25 (processRun backtickCmd))
        (dispatchLog (resultOr (fileReadString stubLog) ""))
        (staticInjected (fileExists? (str stubDir "/injected")))
        (browserInjected (fileExists? (str stubDir "/browser-injected")))
        (quoteInjected (fileExists? quoteMarker))
        (quoteAmpInjected (fileExists? quoteAmpMarker))
        (backtickInjected (fileExists? backtickMarker))

        (_ (processRun (str "rm -rf " stubDir " " quoteMarker " " quoteAmpMarker " " backtickMarker)))]
    (do
      (assert (= out1.exitCode 0) "crawl staticHttp exit 0")
      (assert (stringContains? out1.stdout "(:pageSnapshot") "staticHttp snapshot tag")
      (assert (stringContains? out1.stdout ":title \"Parity Test Page\"") "staticHttp title match")
      (assert (stringContains? out1.stdout ":status :ok") "staticHttp status ok")
      (assert (stringContains? log1 "curl") "stub curl invoked")

      (assert (= out2.exitCode 0) "crawl patchright exit 0")
      (assert (stringContains? out2.stdout "(:pageSnapshot") "patchright snapshot tag")
      (assert (stringContains? out2.stdout ":title \"Chrome Headless DOM\"") "patchright title match")
      (assert (stringContains? log2 "chrome") "stub chrome invoked")
      (assert (= autoOut.exitCode 0) "auto crawl succeeds with available stealth browser")
      (assert (stringContains? autoOut.stdout ":title \"Chrome Headless DOM\"") "auto mode selects the available stealth browser")
      (assert (stringContains? autoLog "chrome") "auto mode invokes the available stealth browser")

      (assert (= out3.exitCode 0) "crawl raw exit 0")
      (assert (stringContains? out3.stdout "<pre>Raw content</pre>") "crawl raw content match")

      (assert (= out4.exitCode 0) "crawl text exit 0")
      (assert (stringContains? out4.stdout "[Parity Test Page] https://example.com/test") "crawl text format match")

      (assert (= out5.exitCode 1) "crawl fail exits 1")
      (assert (stringContains? out5.stdout ":status :failed") "crawl fail status failed")

      (assert (not staticInjected) "static crawler rejects shell metacharacters")
      (assert (stringContains? out15.stdout "Invalid URL") "static crawler reports invalid injected URL")
      (assert (not browserInjected) "browser crawler validates URL before shell execution")
      (assert (stringContains? out16.stdout "Invalid URL") "browser crawler reports invalid URL")
      (assert (stringContains? out17.stdout "Invalid URL") "crawler rejects URL credentials")
      (assert (= out18.exitCode 0) "target crawl dispatches through the browser gateway")
      (assert (stringContains? out18.stdout "(:browserActionReceipt") "target crawl returns the recorded gateway receipt")
      (assert (stringContains? dispatchLog "?target=foo%20bar%26x%3Dy") "target selector is encoded as one gateway query value")
      (assert (= out19.exitCode 0) "browser-family crawl dispatches through the browser gateway")
      (assert (stringContains? out19.stdout "(:browserActionReceipt") "browser crawl returns the recorded gateway receipt")
      (assert (stringContains? dispatchLog "?browser=chrome") "browser selector is sent to the gateway")
      (assert (!= unknownCrawl.exitCode 0) "unknown crawl option is rejected")
      (assert (stringContains? unknownCrawl.stderr "Unsupported crawl option: --mystery") "unknown crawl option reports its name")
      (assert (!= unknownTikTok.exitCode 0) "unknown TikTok option is rejected")
      (assert (stringContains? unknownTikTok.stderr "Unsupported tiktok option: --mystery") "unknown TikTok option reports its name")
      (assert (= dollarUrl.exitCode 0) "valid OData dollar-filter URL is accepted")
      (assert (stringContains? dollarUrl.stdout ":status :ok") "OData dollar-filter crawl completes")
      (assert (stringContains? quoteExport.stdout "bundle\\\"quoted.js") "agent export receipt escapes quotes in path")
      (assert (stringContains? manifest "\"asl-json\"") "crawler manifest declares its JSON dependency")
      (assert (stringContains? manifest "\"aslCrawler/crawler\"") "crawler manifest uses declared module names")
      (assert (stringContains? out20.stdout "(:browserActionReceipt") "extension mode returns the gateway action receipt")
      (assert (= out6.exitCode 0) "agent status query succeeds when runtime readiness is unknown")
      (assert (stringContains? out6.stdout "(:inBrowserAgent") "agent status tag")
      (assert (stringContains? out6.stdout ":runtime :unverified") "agent status does not claim runtime state")

      (assert (= out7.exitCode 0) "agent export exit 0")
      (assert (stringContains? out7.stdout "(:agentBundle :exported") "agent export tag")
      (assert exportedOk "agent exported file exists")
      (assert (!= outFailedExport.exitCode 0) "agent export reports a parent-directory creation failure")
      (assert (stringContains? outFailedExport.stderr "Export failed:") "agent export exposes the directory creation error")

      (assert (= out8.exitCode 0) "tiktok extract exit 0")
      (assert (stringContains? out8.stdout "(:mediaMetadataReceipt") "tiktok receipt tag")
      (assert (stringContains? out8.stdout ":videoId \"9876543210\"") "tiktok videoId match")
      (assert (stringContains? out8.stdout ":author \"@creator\"") "tiktok author match")
      (assert (stringContains? out8.stdout ":caption \"Measured caption\"") "TikTok caption extracted from page")
      (assert (stringContains? out8.stdout ":likesCount 321") "TikTok likes extracted from page")
      (assert (stringContains? out8.stdout ":commentsCount 17") "TikTok comments extracted from page")
      (assert (stringContains? out8.stdout ":soundTitle \"Measured sound\"") "TikTok sound extracted from page")
      (assert (!= out14.exitCode 0) "TikTok extraction fails when page metadata is absent")
      (assert (not (stringContains? out14.stdout ":mediaMetadataReceipt")) "missing TikTok data does not produce a fabricated receipt")
      (assert (stringContains? out13.stdout "(:browserActionReceipt") "watch returns the recorded gateway action receipt")
      (assert (stringContains? dispatchLog "watchMedia") "watch dispatches its media action to the gateway")
      (assert (stringContains? dispatchLog ":duration 2") "watch forwards the requested duration")

      (assert (= out9.exitCode 0) "status exit 0")
      (assert (stringContains? out9.stdout "(:crawlerStatus") "crawler status tag")
      (assert (stringContains? out9.stdout ":inBrowserAgentReady :unknown") "crawler status does not claim agent readiness")

      (assert (= out10.exitCode 1) "session is unverified without a live browser session")
      (assert (stringContains? out10.stdout ":status :unverified") "session does not claim unverified authentication")
      (assert (= out11.exitCode 0) "automation script is submitted to the gateway")
      (assert (stringContains? out11.stdout "(:browserActionReceipt") "automation returns the recorded gateway receipt")
      (assert (stringContains? dispatchLog "fixture-auto") "automation sends its script content to the gateway")
      (assert (= out12.exitCode 0) "second automation action is dispatched rather than executed locally")
      (assert (stringContains? out12.stdout "(:browserActionReceipt") "second automation action receives the gateway result")
      (assert (stringContains? dispatchLog "fixture-fail") "second automation action content reaches the gateway")
      (assert (stringContains? out21.stdout "(:browserActionReceipt") "ASN automation action reaches the gateway")
      (assert (stringContains? dispatchLog "action :op") "ASN action body is forwarded without shell execution")
      (assert (!= out22.exitCode 0) "TikTok metadata for a different video id is not returned")
      (assert (!= out23.exitCode 0) "TikTok extraction rejects an empty caption")
      (assert (!= out26.exitCode 0) "TikTok extraction rejects missing diggCount")
      (assert (!= out27.exitCode 0) "TikTok extraction rejects missing commentCount")
      (assert (!= out28.exitCode 0) "TikTok extraction rejects an empty sound title")
      (assert (not (stringContains? out28.stdout ":mediaMetadataReceipt")) "empty TikTok sound does not produce a metadata receipt")
      (assert (not quoteInjected) "crawler shell-quotes apostrophes in URLs")
      (assert (not quoteAmpInjected) "crawler shell-quotes apostrophe, semicolon, and ampersand in URLs")
      (assert (= outQuoteAmp.exitCode 0) "quoted shell metacharacter URL completes crawl")
      (assert (stringContains? quoteAmpLog (str "https://example.com/';touch " quoteAmpMarker ";echo '&")) "curl receives the complete quoted metacharacter URL")
      (assert (!= out25.exitCode 0) "crawler rejects backticks in URLs")
      (assert (not backtickInjected) "crawler does not execute backticks from URLs")
      (assert (stringContains? out9.stdout ":supportedModes [:patchright :staticHttp :cloudProxy :auto :extension]") "status lists gateway-backed extension mode")
      (assert (stringContains? out9.stdout ":unavailableModes []") "status identifies no unsupported modes")
      (refute (stringContains? out9.stdout ":gatewayUrl") "status does not imply configurable dispatch")
      (assert (= cloudProxyRaw.exitCode 0) "cloudProxy raw crawl succeeds")
      (assert (stringContains? cloudProxyRaw.stdout "<h1>Parity Header</h1>") "cloudProxy honors raw distillation")
      (assert (= cloudProxyFailed.exitCode 1) "cloudProxy failure exits 1")
      (assert (stringContains? cloudProxyFailed.stdout ":errors (") "failed cloudProxy snapshot includes errors")
      (assert (stringContains? cloudProxyFailed.stdout "(:engine cloudProxy :error \"curl: (28) Connection timed out\")") "failed snapshot retains cloudProxy engine error")
      (assert (= maxNodesRun.exitCode 0) "agent max-nodes export succeeds")
      (assert (stringContains? maxNodesScript "if (count >= 7) break;") "max-nodes reaches generated snapshot limit")
      (refute (stringContains? maxNodesScript "if (count >= 100) break;") "max-nodes overrides default limit")
      (assert (= invalidMaxNodesRun.exitCode 2) "invalid max-nodes input is rejected")
      (assert (stringContains? invalidMaxNodesRun.stderr "Invalid --max-nodes") "invalid max-nodes reports its value")
      (assert (= missingMaxNodesRun.exitCode 2) "missing max-nodes value is rejected")
      (assert (stringContains? missingMaxNodesRun.stderr "Missing value for --max-nodes") "missing max-nodes value reports its option")
      (assert (stringContains? outDispatchProbe.stderr "Unknown crawler subcommand: __dispatch_probe__") "bin/asl crawler dispatches to ASL entry")
      true))
