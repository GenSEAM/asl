(module aslCrawlerTests/argvTest
  :x [runTests main]
  :i [(asl-proc/coreProcess :a procCore) (aslCrawler/crawler :a c)])

fn ! runTests -> Bool
  (runCrawlerArgvParent)

fn checkLine name: String ok: Bool -> String
  (str "check " name " " (if ok "1" "0"))

fn childPassed out: String name: String -> Bool
  (listContains? (stringLines out) (checkLine name true))

fn fileHas! path: String parts: (List String) -> Bool
  (mt (fileRead path)
    ((err _) false)
    ((ok text) (listAll? (fn [(p String)] -> Bool (stringContains? text p)) parts)))

fn shown r: (Result String String) -> String
  (mt r ((err e) (str "err " e)) ((ok b) (str "ok " b)))

fn ! crawlerChecks dir: String -> (List String)
  (let [(curl (c/fetchCurl! "https://example.test/path" 2))
        (browser (c/fetchStealthBrowser! "https://example.test/path" 2))
        (failed (c/fetchStealthBrowser! "https://example.test/fail" 2))]
    (list (checkLine "curlBody" (= curl (ok "curl fixture response")))
          (checkLine "curlConfig" (fileHas! (str dir "/curl-config") (list "User-Agent: Mozilla" "Accept-Language")))
          (checkLine "curlArgv" (fileHas! (str dir "/curl-args") (list "--config\n-\n" "--max-time\n2\n" "--\nhttps://example.test/path")))
          (checkLine "browserBody" (= browser (ok "browser fixture response")))
          (checkLine "browserArgv" (fileHas! (str dir "/browser-args") (list "--headless=new" "--dump-dom" "https://example.test/path")))
          (checkLine "browserFailure" (= failed (err "Stealth browser execution failed: exit 3: stub browser crashed")))
          (str "detail curl " (shown curl) "; browser " (shown browser) "; failed " (shown failed))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (envGet "CRAWLER_ARGV_DIR")
    ((none) (err "CRAWLER_ARGV_DIR is not set"))
    ((some dir) (do (println (stringJoin (crawlerChecks dir) "\n")) (ok 0))))

fn ! runCrawlerArgvParent -> Bool
  (let [(t (stringFromInt64 (monotonicNs)))
        (dir (str "/tmp/crawlArgv_" t))
        (made (dirCreate dir))
        (curlPath (str dir "/curl"))
        (browserPath (str dir "/browser"))
        (curlConfig (str dir "/curl-config"))
        (curlArgs (str dir "/curl-args"))
        (browserArgs (str dir "/browser-args"))
        (curlScript (str "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" curlArgs "\"\ncat > \"" curlConfig "\"\nprintf 'curl fixture response'\n"))
        (browserScript (str "#!/bin/sh\ncase \"$*\" in *example.test/fail*) printf 'stub browser crashed' >&2; exit 3;; esac\nprintf '%s\\n' \"$@\" > \"" browserArgs "\"\nprintf 'browser fixture response'\n"))
        (curlWritten (fileWrite curlPath curlScript))
        (browserWritten (fileWrite browserPath browserScript))
        (curlChmod (fileChmod curlPath 493))
        (browserChmod (fileChmod browserPath 493))
        (path (mt (envGet "PATH") ((some p) p) ((none) "/usr/bin:/bin")))
        (cwd (mt (envGet "PWD") ((some p) p) ((none) ".")))
        (baseCmd (procCore/withCwd (procCore/cmd "bin/asl" (list "run" "asl/packages/asl-crawler/tests/argvTest.asl")) cwd))
        (pathCmd (procCore/withEnv baseCmd "PATH" (str dir ":" path)))
        (browserCmd (procCore/withEnv pathCmd "CHROME_BIN" browserPath))
        (childCmd (procCore/withEnv browserCmd "CRAWLER_ARGV_DIR" dir))
        (run (procCore/exec! childCmd))
        (cleanup (procCore/exec! (procCore/cmd "rm" (list "-rf" dir))))]
    (do
      (assert (ok? made) "temporary argv fixture directory created")
      (assert (ok? curlWritten) "curl stub written")
      (assert (ok? browserWritten) "browser stub written")
      (assert (ok? curlChmod) "curl stub executable")
      (assert (ok? browserChmod) "browser stub executable")
      (mt run
        ((err e) (do (assert false (str "nested production argv test failed to launch: " e)) false))
        ((ok result)
          (do
            (assert (= result.exitCode 0) (str "production argv child failed: " result.stderr))
            (assert (childPassed result.stdout "curlBody") (str "fetchCurl! returns curl stub response: " result.stdout))
            (assert (childPassed result.stdout "curlConfig") "fetchCurl! sends configured headers on stdin")
            (assert (childPassed result.stdout "curlArgv") "fetchCurl! preserves curl argv and URL boundary")
            (assert (childPassed result.stdout "browserBody") (str "fetchStealthBrowser! returns configured browser output: " result.stdout))
            (assert (childPassed result.stdout "browserArgv") "fetchStealthBrowser! invokes configured browser with safe argv")
            (assert (childPassed result.stdout "browserFailure") (str "a failing browser reports its exit code and stderr: " result.stdout))
            (assert (ok? cleanup) "temporary crawler argv fixtures removed")
            true)))))
