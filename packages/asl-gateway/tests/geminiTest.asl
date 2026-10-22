(module aslGateway/tests/geminiTest
  :x [runTests]
  :i [(chat :a ch)
      (pyText :a pt)
      (asl-json/json :a j)])

; (:m :tags (gemini) :do "hand-written coverage for GW-GEMINI-KIND: chat.asl's geminiBody/geminiMessagesOf request-shape conversion (incl. a functionCall/functionResponse round trip through history, where the functionResponse's :name is recovered from the preceding assistant tool_calls, not carried by the tool message itself) and geminiToChat/geminiFinishReasonToFinish response-shape conversion (incl. a thought part and Gemini's STOP-even-on-tool-call finishReason quirk); these functions do not exist before this unit so every assertion below is red (ERR_UNDEFINED_SYMBOL) on the prior commit")

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn text v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

fn int v: j/Json -> Int64
  (match v ((j/jint n) n) (_ -1))

fn num v: j/Json -> Float64
  (match v ((j/jfloat f) f) ((j/jint n) (int64ToFloat64 n)) (_ -1.0))

fn items v: j/Json -> (List j/Json)
  (match v ((j/jarr xs) xs) (_ (list)))

fn nth v: (List j/Json) i: Int64 -> j/Json
  (optionOr (listGet v i) (j/jnull))

; (:m :tags (gemini) :do "an OpenAI-shaped chat body: system + user + an assistant tool call + its tool result + a trailing user turn, plus tools/max_tokens/temperature/stop")
fn sampleOpenAiBody -> j/Json
  (j/jobj (list
    (pair "messages" (j/jarr (list
      (j/jobj (list (pair "role" (j/jstr "system")) (pair "content" (j/jstr "You are a helpful bot."))))
      (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr "What is 2+2?"))))
      (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jnull))
                    (pair "tool_calls" (j/jarr (list (j/jobj (list (pair "id" (j/jstr "call_1")) (pair "type" (j/jstr "function"))
                                                                    (pair "function" (j/jobj (list (pair "name" (j/jstr "add"))
                                                                                                    (pair "arguments" (j/jstr "{\"a\":2,\"b\":2}"))))))))))))
      (j/jobj (list (pair "role" (j/jstr "tool")) (pair "tool_call_id" (j/jstr "call_1")) (pair "content" (j/jstr "4"))))
      (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr "Thanks!")))))))
    (pair "tools" (j/jarr (list (j/jobj (list (pair "type" (j/jstr "function"))
                                               (pair "function" (j/jobj (list (pair "name" (j/jstr "add"))
                                                                               (pair "description" (j/jstr "adds two numbers"))
                                                                               (pair "parameters" (j/jobj (list (pair "type" (j/jstr "object")))))))))))))
    (pair "max_tokens" (j/jint 512))
    (pair "temperature" (j/jfloat 0.3))
    (pair "stop" (j/jstr "STOP"))))

fn testGeminiBodyMapsSystemAndSampling -> Bool
  (let [(out (ch/geminiBody (sampleOpenAiBody) "gemini-4-argon-contributor"))
        (gc (get out "generationConfig"))]
    (do
      (assert (= (text (get (nth (items (get (get out "systemInstruction") "parts")) 0) "text")) "You are a helpful bot.") "the system message becomes systemInstruction.parts[0].text, not a :contents entry")
      (assert (= (int (get gc "maxOutputTokens")) 512) "max_tokens becomes generationConfig.maxOutputTokens")
      (assert (= (num (get gc "temperature")) 0.3) "temperature carries through generationConfig")
      (assert (= (text (nth (items (get gc "stopSequences")) 0)) "STOP") "a scalar :stop becomes a one-element stopSequences array")
      true))

fn testGeminiBodyMapsTools -> Bool
  (let [(out (ch/geminiBody (sampleOpenAiBody) "gemini-4-argon-contributor"))
        (decl (nth (items (get (nth (items (get out "tools")) 0) "functionDeclarations")) 0))]
    (do
      (assert (= (text (get decl "name")) "add") "a tool's name is lifted out of the OpenAI function wrapper into one functionDeclarations entry")
      (assert (= (text (get decl "description")) "adds two numbers") "a tool's description carries through")
      (assert (= (text (get (get decl "parameters") "type")) "object") "Gemini keeps :parameters as the key name (unlike Anthropic's input_schema rename)")
      true))

; (:m :tags (gemini) :do "the core round trip: OpenAI's {assistant tool_calls} + {role:tool} pair becomes Gemini's {model functionCall} + {user functionResponse} pair; the functionResponse's :name is recovered from the assistant's tool_calls (the tool message itself only carries tool_call_id, no name)")
fn testGeminiBodyMapsFunctionCallRoundTrip -> Bool
  (let [(contents (items (get (ch/geminiBody (sampleOpenAiBody) "gemini-4-argon-contributor") "contents")))]
    (do
      (assert (= (listLength contents) 4) (str "system dropped into systemInstruction, 4 contents remain (user, model/functionCall, user/functionResponse, user), got " (listLength contents)))
      (let [(c0 (nth contents 0)) (c1 (nth contents 1)) (c2 (nth contents 2)) (c3 (nth contents 3))]
        (do
          (assert (= (text (get c0 "role")) "user") "content 0 is the plain user turn")
          (assert (= (text (get (nth (items (get c0 "parts")) 0) "text")) "What is 2+2?") "content 0's text passes through")
          (assert (= (text (get c1 "role")) "model") "content 1 is the assistant's turn, role model (not assistant)")
          (let [(fc (get (nth (items (get c1 "parts")) 0) "functionCall"))]
            (do
              (assert (= (text (get fc "name")) "add") "the functionCall part keeps the function name")
              (assert (= (int (get (get fc "args") "a")) 2) "the functionCall part's args is the parsed (not re-stringified) arguments object")))
          (assert (= (text (get c2 "role")) "user") "content 2 is a user turn carrying the functionResponse (Gemini has no tool role)")
          (let [(fr (get (nth (items (get c2 "parts")) 0) "functionResponse"))]
            (do
              (assert (= (text (get fr "name")) "add") "the functionResponse's name is recovered from the assistant's tool_calls, not from the tool message (which never carries a name)")
              (assert (= (int (get (get fr "response") "content")) 4) "the tool result (here a bare integer after JSON parse) lands in response.content")))
          (assert (= (text (get c3 "role")) "user") "content 3 is the trailing plain user turn")
          (assert (= (text (get (nth (items (get c3 "parts")) 0) "text")) "Thanks!") "content 3's text passes through")
          true))))

; (:m :tags (gemini) :do "two consecutive tool results answering two parallel functionCalls in one assistant turn must land in ONE Gemini user content with two functionResponse parts, not two separate user contents")
fn testGeminiBodyGroupsConsecutiveFunctionResponsesTogether -> Bool
  (let [(body (j/jobj (list (pair "messages" (j/jarr (list
                (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jnull))
                              (pair "tool_calls" (j/jarr (list
                                (j/jobj (list (pair "id" (j/jstr "a")) (pair "type" (j/jstr "function")) (pair "function" (j/jobj (list (pair "name" (j/jstr "f1")) (pair "arguments" (j/jstr "{}")))))))
                                (j/jobj (list (pair "id" (j/jstr "b")) (pair "type" (j/jstr "function")) (pair "function" (j/jobj (list (pair "name" (j/jstr "f2")) (pair "arguments" (j/jstr "{}"))))))))))))
                (j/jobj (list (pair "role" (j/jstr "tool")) (pair "tool_call_id" (j/jstr "a")) (pair "content" (j/jstr "1"))))
                (j/jobj (list (pair "role" (j/jstr "tool")) (pair "tool_call_id" (j/jstr "b")) (pair "content" (j/jstr "2"))))))))))
        (contents (ch/geminiMessagesOf (items (get body "messages"))))]
    (do
      (assert (= (listLength contents) 2) (str "model turn plus one grouped user turn, got " (listLength contents)))
      (let [(toolContent (nth contents 1))]
        (do
          (assert (= (text (get toolContent "role")) "user") "the grouped functionResponse turn has role user")
          (assert (= (listLength (items (get toolContent "parts"))) 2) "both functionResponse parts land in that one content's parts")
          (assert (= (text (get (get (nth (items (get toolContent "parts")) 0) "functionResponse") "name")) "f1") "the first functionResponse keeps its own recovered name")
          (assert (= (text (get (get (nth (items (get toolContent "parts")) 1) "functionResponse") "name")) "f2") "the second functionResponse keeps its own recovered name")
          true))))

; (:m :tags (gemini) :do "a Gemini response mixing a thought part, two text parts and a functionCall part, with finishReason STOP (Gemini's quirk of reporting STOP even for a tool call) and full usageMetadata incl. cached and thinking tokens")
fn sampleGeminiResponse -> String
  (str
    "{\"candidates\":[{\"finishReason\":\"STOP\",\"content\":{\"role\":\"model\",\"parts\":["
      "{\"text\":\"let me add them\",\"thought\":true},"
      "{\"text\":\"The answer is \"},"
      "{\"text\":\"4.\"},"
      "{\"functionCall\":{\"name\":\"add\",\"args\":{\"a\":2,\"b\":2}}}"
    "]}}],"
    "\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":20,\"cachedContentTokenCount\":5,\"thoughtsTokenCount\":3}}")

fn testGeminiToChatMapsContentBlocks -> Bool
  (match (ch/geminiToChat (sampleGeminiResponse))
    ((none) (assert false "geminiToChat must parse a well-formed Gemini response"))
    ((some text_)
     (match (pt/jsonLoads text_)
       ((err e) (assert false (str "geminiToChat must produce valid JSON: " e)))
       ((ok chatJson)
        (let [(choice (nth (items (get chatJson "choices")) 0))
              (msg (get choice "message"))]
          (do
            (assert (= (text (get msg "content")) "The answer is 4.") "the two text parts are joined into one content string, the thought part excluded")
            (assert (= (text (get msg "reasoning_content")) "let me add them") "a :thought true part becomes reasoning_content")
            (let [(call (nth (items (get msg "tool_calls")) 0))]
              (do
                (assert (= (text (get call "id")) "call_0") "a functionCall part gets a synthesized tool_calls id (Gemini sends none)")
                (assert (= (text (get (get call "function") "name")) "add") "a functionCall part's name becomes function.name")
                (assert (= (text (get (get call "function") "arguments")) "{\"a\": 2, \"b\": 2}") "a functionCall part's args object is re-stringified into function.arguments, same shape OpenAI uses")))
            (assert (= (text (get choice "finish_reason")) "tool_calls") "finishReason STOP is overridden to tool_calls because a functionCall part was present")
            true))))))

fn testGeminiToChatMapsUsage -> Bool
  (match (ch/geminiToChat (sampleGeminiResponse))
    ((none) (assert false "geminiToChat must parse a well-formed Gemini response"))
    ((some text_)
     (match (pt/jsonLoads text_)
       ((err e) (assert false (str "geminiToChat must produce valid JSON: " e)))
       ((ok chatJson)
        (let [(usage (get chatJson "usage"))]
          (do
            (assert (= (int (get usage "prompt_tokens")) 10) "prompt_tokens is promptTokenCount as-is (it already includes any cached subset, same OpenAI semantic)")
            (assert (= (int (get usage "completion_tokens")) 23) "completion_tokens is candidatesTokenCount + thoughtsTokenCount (20+3): thinking tokens are billed as output")
            (assert (= (int (get usage "cached_tokens")) 5) "cached_tokens is cachedContentTokenCount")
            true))))))

fn testGeminiFinishReasonToFinish -> Bool
  (do
    (assert (= (ch/geminiFinishReasonToFinish "STOP" false) "stop") "STOP with no call maps to stop")
    (assert (= (ch/geminiFinishReasonToFinish "MAX_TOKENS" false) "length") "MAX_TOKENS maps to length")
    (assert (= (ch/geminiFinishReasonToFinish "STOP" true) "tool_calls") "STOP with a call present is overridden to tool_calls")
    (assert (= (ch/geminiFinishReasonToFinish "MAX_TOKENS" true) "tool_calls") "a call present wins over MAX_TOKENS too")
    true)

fn ! runTests -> Bool
  (do
    (assert (testGeminiBodyMapsSystemAndSampling) "testGeminiBodyMapsSystemAndSampling passed")
    (assert (testGeminiBodyMapsTools) "testGeminiBodyMapsTools passed")
    (assert (testGeminiBodyMapsFunctionCallRoundTrip) "testGeminiBodyMapsFunctionCallRoundTrip passed")
    (assert (testGeminiBodyGroupsConsecutiveFunctionResponsesTogether) "testGeminiBodyGroupsConsecutiveFunctionResponsesTogether passed")
    (assert (testGeminiToChatMapsContentBlocks) "testGeminiToChatMapsContentBlocks passed")
    (assert (testGeminiToChatMapsUsage) "testGeminiToChatMapsUsage passed")
    (assert (testGeminiFinishReasonToFinish) "testGeminiFinishReasonToFinish passed")
    true)
