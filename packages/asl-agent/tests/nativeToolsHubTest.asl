(module aslAgent/tests/nativeToolsHubTest
  :x [runTests]
  :i [(aslAgent/core :a c) (asl-tools/fleet/run :a fr) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref NATIVE-TOOLS-DEFAULT :do "end to end through the hub: a tool-only model (answers with tool_calls when offered tools, prose otherwise) finishes a one-write unit with Leon's default settings; with tools off by default it only narrated and the unit never wrote")

fn ! waitFile! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitFile! path (- attempts 1)))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/nativeToolsHubTest.XXXXXX" 5000) "")))
        (root (str temp "/repo"))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (here (resultOr (realPath ".") "."))
        (stub (resultOr (realPath "asl/packages/asl-agent/tests/toolHubStub.asl") ""))
        (sock (str temp "/hub.sock"))
        (made (and (ok? (dirCreate (str temp "/.asl"))) (ok? (dirCreate root))))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n")) (gk/initGitRepo! root "nativeToolsHubTest" "native-tools-hub@example.invalid")))
        (hubA (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :class \"lead\")\n")))
        (cacheRow (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sock " " temp "/seen.txt 1>" temp "/stub.out 2>" temp "/stub.err")) here env)))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (up (and (> pid 0) (waitFile! sock 1500)))
        (gate "grep -q green subject.txt && echo '1 assertion(s) executed (1 passed)'")
        (form (str "(:agent :task \"write green to subject.txt and finish\" :root \"" (c/escapeAsn root) "\" :owns (\"subject.txt\") :gates (\"" (c/escapeAsn gate)
                   "\") :budget 6 :wallBudget 240 :contextTokens 8000)"))
        (leon (if up (fr/runOneLimited (fr/job (list host form) here env) (fr/limits 300 64)) (fr/Done :idx 0 :exit 127 :out "hub down" :ms 0 :verdict "skipped")))
        (subject (resultOr (fileReadString (str root "/subject.txt")) ""))
        (seen (resultOr (fileReadString (str temp "/seen.txt")) ""))
        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipes (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (stubErr (resultOr (fileReadString (str temp "/stub.err")) ""))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and made seeded) "the fixture repo is tracked")
      (assert up (str "the stand-in hub is listening: " stubErr))
      (assert (stringContains? seen "POST /v1/chat/completions") (str "Leon posted to the hub socket; leon exit " (stringFromInt64 leon.exit) " " (c/sliceOf leon.out 0 (min 1500 (stringLength leon.out)))))
      (assert (and (stringContains? seen "\"tools\"") (stringContains? seen "run one or more ASN forms")) "the main turn offered the step tool without any :nativeTools field")
      (assert (stringContains? (stringLower seen) "accept: application/json") "a call that offers tools asks the hub for JSON")
      (assert (stringContains? subject "green") (str "the tool-only model's write landed: " subject " | leon exit " (stringFromInt64 leon.exit) " " (c/sliceOf leon.out 0 (min 400 (stringLength leon.out)))))
      (assert (and killed (and pipes removed)) "the stand-in, its pipes and the temp dir are cleaned up")
      true))
