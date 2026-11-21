(module asl-gateway/tests/agyModelIdsTest
  :x [runTests]
  :i [(cliDispatch :a cli)])

fn argAfterFlagAt cmd: (List String) flag: String i: Int64 -> String
  (if (< i (listLength cmd))
    (if (= (optionOr (listGet cmd i) "") flag)
      (optionOr (listGet cmd (+ i 1)) "")
      (argAfterFlagAt cmd flag (+ i 1)))
    "")

fn argAfterFlag cmd: (List String) flag: String -> String
  (argAfterFlagAt cmd flag 0)

fn testAgyModelIds! -> Bool
  (do
    (let [(cmdOpus (cli/agyBuildCmd! "agy" "/tmp/ws" "/tmp/tmp" "/tmp/root" 120 (some "opus") (some "high") none (list) "Prompt" false))]
      (assert (= (argAfterFlag cmdOpus "--model") "claude-opus-5-5-high") "AGY-MODEL-IDS-55 opus+high -> claude-opus-5-5-high"))
    (let [(cmdSonnet (cli/agyBuildCmd! "agy" "/tmp/ws" "/tmp/tmp" "/tmp/root" 120 (some "sonnet") none none (list) "Prompt" false))]
      (assert (= (argAfterFlag cmdSonnet "--model") "claude-sonnet-5-5-medium") "sonnet no effort -> claude-sonnet-5-5-medium"))
    (let [(cmdCop (cli/agyBuildCmd! "agy" "/tmp/ws" "/tmp/tmp" "/tmp/root" 120 (some "claude-opus-medium") none none (list) "Prompt" false))]
      (assert (= (argAfterFlag cmdCop "--model") "claude-opus-5-5-medium") "claude-opus-medium -> claude-opus-5-5-medium"))
    (let [(cmdGem (cli/agyBuildCmd! "agy" "/tmp/ws" "/tmp/tmp" "/tmp/root" 120 (some "gemini-3.8-flash") none none (list) "Prompt" false))]
      (assert (= (argAfterFlag cmdGem "--model") "gemini-3.8-flash") "gemini unchanged")
      (assert (= (argAfterFlag cmdGem "--effort") "low") "gemini keeps low effort"))
    true)

fn runTests -> Bool
  (do
    (assert (testAgyModelIds!) "agy model id mapping via agyBuildCmd!")
    true)
