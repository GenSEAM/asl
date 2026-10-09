(module aslHarness/chatBenchNativeTest :x [runTests] :i [(chatBench :a cb) (asl-json/json :a j)])

fn taskPromptOk res: (Result String String) -> Bool
  (mt res
    ((err _) false)
    ((ok prompt) (and (stringContains? prompt "How many functions in src/")
      (and (stringContains? prompt "=== src/catalog.py ===") (stringContains? prompt "=== README.md ===")))))

fn taskPathDenied res: (Result String String) -> Bool
  (mt res ((err _) true) ((ok _) false))

fn relevantPrompt prompt: String -> Bool
  (and (> (stringLength prompt) 0)
    (and (stringContains? prompt "this exchange has no tools")
      (and (stringContains? prompt "verification: each claim rests on the cheapest check")
        (and (stringContains? prompt "overdone: checks beyond what the claim risks")
          (stringContains? prompt "a claim holds when a tool result")))))

fn systemPromptOk res: (Result String String) -> Bool
  (mt res ((err _) false) ((ok prompt) (relevantPrompt prompt)))

fn ! responseFromJson text: String -> (Result String String)
  (mt (j/jsonParse text)
    ((err e) (err e))
    ((ok value) (cb/responseContent value)))

fn ! runTests -> Bool
  (do
    (assert (stringContains? (cb/requestBody "groq/model-x" "system" "user" 0.25) "model-x") "request body carries provider model id")
    (assert (stringContains? (cb/curlConfig "https://example.test" "key\"quote\nnext" "{}" 8) "Bearer key\\\"quote\\nnext") "curl config escapes API key quotes and newlines")
    (assert (stringContains? (cb/requestBody "model-x" "s\"ys" "u\nser" 1.5) "s\\\"ys") "request body JSON-escapes system content")
    (assert (stringContains? (cb/requestBody "model-x" "s" "u" 1.5) "1.5") "request body carries temperature")
    (assert (taskPromptOk (cb/casePrompt "honest-count")) "casePrompt parses task ASN and includes source files")
    (assert (taskPathDenied (cb/casePrompt "../outside")) "casePrompt rejects path traversal")
    (assert (mt (cb/systemFor "none" "scout") ((ok text) (= text "")) ((err _) false)) "systemFor none returns an explicit empty system message")
    (assert (systemPromptOk (cb/systemFor "core" "scout")) "systemFor renders core prompt from harness layers")
    (assert (systemPromptOk (cb/systemFor "harness" "scout")) "systemFor renders harness prompt from harness layers")
    (assert (mt (cb/systemFor "invalid" "scout") ((err _) true) ((ok _) false)) "systemFor surfaces unsupported condition errors")
    (assert (mt (cb/main (list "--case" "honest-count")) ((err _) true) ((ok _) false)) "CLI requires an explicit model")
    (assert (mt (cb/main (list "--model" "groq/model")) ((err _) true) ((ok _) false)) "CLI requires an explicit case")
    (assert (mt (responseFromJson "{\"choices\":[{\"message\":{\"content\":\"answer\"}}]}") ((ok answer) (= answer "answer")) ((err _) false)) "call extracts assistant content from API JSON")
    (assert (mt (responseFromJson "{\"choices\":[]}") ((err _) true) ((ok _) false)) "call rejects response with no choices")
    true)
