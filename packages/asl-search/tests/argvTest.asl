(module aslWebApiSearch/tests/argvTest
  :x [runTests]
  :i [(asl-proc/coreProcess :a proc)])

fn ! testCommonCrawlCallsCurlSafely! -> Bool
  (mt (proc/exec! (proc/cmd "mktemp" (list "-d" "/tmp/asl-search-argv.XXXXXX")))
    ((err e) (do (assert false (str "mktemp failed for argv test: " e)) false))
    ((ok tmpOut)
     (let [(tmpDir (stringTrim tmpOut.stdout))
           (stubPath (str tmpDir "/curl"))
           (logPath (str tmpDir "/curl.args"))
           (stdinPath (str logPath ".stdin"))
           (childPath (str "asl/packages/asl-search/tests/argvChild-" (stringFromInt64 (monotonicNs)) ".asl"))
           (path (str tmpDir ":" (optionOr (envGet "PATH") "/usr/bin:/bin")))
           (script "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$CC_LOG\"\nout=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-o\" ]; then shift; out=\"$1\"; fi\n  shift\ndone\ncat > \"$CC_LOG.stdin\"\nif [ -n \"$out\" ]; then\n  printf 'DATA' > \"$out\"\nelse\n  printf '%s\\n' '{\"url\":\"https://example.test/a b?x=quoted\",\"timestamp\":\"20250101000000\",\"status\":200,\"mime\":\"text/html\",\"digest\":\"abc\",\"filename\":\"crawl.warc.gz\",\"offset\":7,\"length\":4}'\nfi\n")
           (childSource "(module aslWebApiSearch/tests/argvChild\n  :x [runTests]\n  :i [(aslWebApiSearch/commonCrawl :a cc)])\n\nfn runTests -> Bool\n  (let [(lookupRes (cc/ccLookup! \"CC-MAIN-2025-01\" \"https://example.test/a b?x='quoted'\" 1))\n        (capture (cc/CcCapture :crawl \"CC-MAIN-2025-01\" :url \"https://example.test/a b?x=quoted\" :timestamp \"20250101000000\" :status 200 :mime \"text/html\" :digest \"abc\" :filename \"crawl.warc.gz\" :offset 7 :length 4))\n        (fetchRes (cc/ccFetchRaw! capture))]\n    (do\n      (assert (mt lookupRes ((err _) false) ((ok caps) (= (listLength caps) 1))) \"ccLookup! parses the stub CDX response\")\n      (assert (mt fetchRes ((err _) false) ((ok bs) (= (bytesToBase64 bs) \"REFUQQ==\"))) \"ccFetchRaw! returns the response bytes\")\n      true))\n")
           (writeScript (fileWrite stubPath script))]
       (mt writeScript
         ((err e) (do (assert false (str "writing curl stub failed: " e)) false))
         ((ok _)
          (mt (fileChmod stubPath 493)
            ((err e) (do (assert false (str "chmod failed for curl stub: " e)) false))
            ((ok _)
             (mt (fileWrite childPath childSource)
               ((err e) (do (assert false (str "writing child test failed: " e)) false))
               ((ok _)
                (let [(setup (proc/exec! (proc/cmd "ln" (list "-s" "/usr/bin/mktemp" (str tmpDir "/mktemp")))))
                      (setupRm (proc/exec! (proc/cmd "ln" (list "-s" "/bin/rm" (str tmpDir "/rm")))))
                      (childCmd (proc/withEnv (proc/withEnv (proc/cmd "asl/host/out/asl-host" (list "test" childPath)) "PATH" path) "CC_LOG" logPath))
                      (childRes (proc/exec! childCmd))
                      (argsRes (fileRead logPath))
                      (stdinRes (fileRead stdinPath))
                      (cleanup (proc/exec! (proc/cmd "rm" (list "-rf" tmpDir childPath))))]
                  (do
                   (assert (mt childRes ((err _) false) ((ok output) (= output.exitCode 0)))
                     (str "child Common Crawl test failed: "
                       (mt childRes ((err _) "spawn error") ((ok output) (str output.stdout output.stderr)))))
                   (mt argsRes
                    ((err e) (do (assert false (str "curl args log missing: " e)) false))
                    ((ok argsText)
                     (mt stdinRes
                       ((err e) (do (assert false (str "curl stdin log missing: " e)) false))
                       ((ok stdinText)
                        (do
                          (assert (mt childRes ((err _) false) ((ok output) (= output.exitCode 0))) "child Common Crawl test passes")
                          (assert (stringContains? argsText "https://index.commoncrawl.org/CC-MAIN-2025-01-index?url=https%3A%2F%2Fexample.test%2Fa%20b%3Fx%3D%27quoted%27&output=json&limit=1") "ccLookup! passes encoded URL and output=json as curl argument")
                          (assert (stringContains? argsText "--config\n-\n") "ccFetchRaw! configures curl stdin mode")
                          (assert (stringContains? argsText "https://data.commoncrawl.org/crawl.warc.gz") "ccFetchRaw! passes the WARC URL as an argument")
                          (assert (stringContains? stdinText "header = \"Range: bytes=7-10\"") "ccFetchRaw! sends the byte Range header on stdin")
                          true))))))))))))))))

fn ! runTests -> Bool
  (do
    (assert (testCommonCrawlCallsCurlSafely!) "testCommonCrawlCallsCurlSafely must pass")
    true)
