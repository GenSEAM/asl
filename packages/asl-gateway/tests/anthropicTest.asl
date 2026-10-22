(module aslGateway/tests/anthropicTest
  :x [runTests]
  :i [(chat :a ch)
      (pyText :a pt)
      (asl-json/json :a j)])

; (:m :tags (anthropic) :do "hand-written coverage for GW-ANTHROPIC-KIND: chat.asl's anthropicBody/anthropicMessagesOf request-shape conversion (incl. a tool_use/tool_result round trip through history) and anthropicToChat/anthropicStopReasonToFinish response-shape conversion (incl. thinking blocks and cache-token usage); these functions do not exist before this unit so every assertion below is red (ERR_UNDEFINED_SYMBOL) on the prior commit")

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

; (:m :tags (anthropic) :do "an OpenAI-shaped chat body: system + user + an assistant tool call + its tool result + a trailing user turn, plus tools/max_tokens/temperature/stop, mirroring a real multi-turn tool-use conversation")
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

fn testAnthropicBodyMapsModelAndSystem -> Bool
  (let [(out (ch/anthropicBody (sampleOpenAiBody) "claude-haiku-5-5"))]
    (do
      (assert (= (text (get out "model")) "claude-haiku-5-5") "model is carried into the Anthropic body")
      (assert (= (text (get out "system")) "You are a helpful bot.") "the system message is pulled out into :system, not left in :messages")
      true))

fn testAnthropicBodyMapsSamplingAndStop -> Bool
  (let [(out (ch/anthropicBody (sampleOpenAiBody) "claude-haiku-5-5"))]
    (do
      (assert (= (int (get out "max_tokens")) 512) "max_tokens carries through")
      (assert (= (num (get out "temperature")) 0.3) "temperature carries through")
      (assert (= (text (nth (items (get out "stop_sequences")) 0)) "STOP") "a scalar :stop becomes a one-element stop_sequences array")
      true))

fn testAnthropicBodyMapsTools -> Bool
  (let [(out (ch/anthropicBody (sampleOpenAiBody) "claude-haiku-5-5"))
        (tool (nth (items (get out "tools")) 0))]
    (do
      (assert (= (text (get tool "name")) "add") "a tool's name is lifted out of the OpenAI function wrapper")
      (assert (= (text (get tool "description")) "adds two numbers") "a tool's description carries through")
      (assert (= (text (get (get tool "input_schema") "type")) "object") "a tool's parameters become input_schema verbatim")
      true))

; (:m :tags (anthropic) :do "the core round trip: OpenAI's {assistant tool_calls} + {role:tool} pair becomes Anthropic's {assistant tool_use} + {user tool_result} pair, with the system message dropped from :messages and the two plain user turns passed through untouched")
fn testAnthropicBodyGroupsToolResultIntoUserMessage -> Bool
  (let [(msgs (items (get (ch/anthropicBody (sampleOpenAiBody) "claude-haiku-5-5") "messages")))]
    (do
      (assert (= (listLength msgs) 4) (str "system dropped, 4 messages remain (user, assistant/tool_use, user/tool_result, user), got " (listLength msgs)))
      (let [(m0 (nth msgs 0)) (m1 (nth msgs 1)) (m2 (nth msgs 2)) (m3 (nth msgs 3))]
        (do
          (assert (= (text (get m0 "role")) "user") "message 0 is the plain user turn")
          (assert (= (text (get m0 "content")) "What is 2+2?") "message 0's content passes through as plain text")
          (assert (= (text (get m1 "role")) "assistant") "message 1 is the assistant's tool call")
          (let [(block1 (nth (items (get m1 "content")) 0))]
            (do
              (assert (= (text (get block1 "type")) "tool_use") "the assistant's tool_calls entry becomes a tool_use content block")
              (assert (= (text (get block1 "id")) "call_1") "the tool_use block keeps the original call id")
              (assert (= (text (get block1 "name")) "add") "the tool_use block keeps the function name")
              (assert (= (int (get (get block1 "input") "a")) 2) "the tool_use block's input is the parsed (not re-stringified) arguments object")))
          (assert (= (text (get m2 "role")) "user") "message 2 is a user message carrying the tool_result (Anthropic has no tool role)")
          (let [(block2 (nth (items (get m2 "content")) 0))]
            (do
              (assert (= (text (get block2 "type")) "tool_result") "the role:tool message becomes a tool_result content block")
              (assert (= (text (get block2 "tool_use_id")) "call_1") "the tool_result points back at the same call id")
              (assert (= (text (get block2 "content")) "4") "the tool result text carries through")))
          (assert (= (text (get m3 "role")) "user") "message 3 is the trailing plain user turn")
          (assert (= (text (get m3 "content")) "Thanks!") "message 3's content passes through as plain text")
          true))))

; (:m :tags (anthropic) :do "two consecutive tool results (answering two parallel tool_use calls in one assistant turn) must land in ONE Anthropic user message with two tool_result blocks, not two separate user messages")
fn testAnthropicBodyGroupsConsecutiveToolResultsTogether -> Bool
  (let [(body (j/jobj (list (pair "messages" (j/jarr (list
                (j/jobj (list (pair "role" (j/jstr "tool")) (pair "tool_call_id" (j/jstr "a")) (pair "content" (j/jstr "1"))))
                (j/jobj (list (pair "role" (j/jstr "tool")) (pair "tool_call_id" (j/jstr "b")) (pair "content" (j/jstr "2"))))))))))
        (msgs (ch/anthropicMessagesOf (items (get body "messages"))))]
    (do
      (assert (= (listLength msgs) 1) (str "both tool results collapse into exactly one user message, got " (listLength msgs)))
      (assert (= (listLength (items (get (nth msgs 0) "content"))) 2) "that one message carries both tool_result blocks")
      true))

; (:m :tags (anthropic) :do "an Anthropic response mixing thinking + text + tool_use content blocks, with a tool_use stop_reason and both cache_read and cache_creation usage fields")
fn sampleAnthropicResponse -> String
  (str
    "{\"content\":["
      "{\"type\":\"thinking\",\"thinking\":\"let me add them\"},"
      "{\"type\":\"text\",\"text\":\"The answer is \"},"
      "{\"type\":\"text\",\"text\":\"4.\"},"
      "{\"type\":\"tool_use\",\"id\":\"call_9\",\"name\":\"add\",\"input\":{\"a\":2,\"b\":2}}"
    "],"
    "\"stop_reason\":\"tool_use\","
    "\"usage\":{\"input_tokens\":10,\"output_tokens\":20,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":3}}")

fn testAnthropicToChatMapsContentBlocks -> Bool
  (match (ch/anthropicToChat (sampleAnthropicResponse))
    ((none) (assert false "anthropicToChat must parse a well-formed Anthropic response"))
    ((some text_)
     (match (pt/jsonLoads text_)
       ((err e) (assert false (str "anthropicToChat must produce valid JSON: " e)))
       ((ok chat)
        (let [(choice (nth (items (get chat "choices")) 0))
              (msg (get choice "message"))]
          (do
            (assert (= (text (get msg "content")) "The answer is 4.") "the two text blocks are joined into one content string")
            (assert (= (text (get msg "reasoning_content")) "let me add them") "a thinking block becomes reasoning_content, same key other reasoning providers use")
            (let [(call (nth (items (get msg "tool_calls")) 0))]
              (do
                (assert (= (text (get call "id")) "call_9") "a tool_use block's id becomes the tool_calls entry's id")
                (assert (= (text (get (get call "function") "name")) "add") "a tool_use block's name becomes function.name")
                (assert (= (text (get (get call "function") "arguments")) "{\"a\": 2, \"b\": 2}") "a tool_use block's input object is re-stringified into function.arguments, same shape OpenAI uses")))
            (assert (= (text (get choice "finish_reason")) "tool_calls") "stop_reason tool_use becomes finish_reason tool_calls")
            true))))))

fn testAnthropicToChatMapsCacheUsage -> Bool
  (match (ch/anthropicToChat (sampleAnthropicResponse))
    ((none) (assert false "anthropicToChat must parse a well-formed Anthropic response"))
    ((some text_)
     (match (pt/jsonLoads text_)
       ((err e) (assert false (str "anthropicToChat must produce valid JSON: " e)))
       ((ok chat)
        (let [(usage (get chat "usage"))]
          (do
            (assert (= (int (get usage "prompt_tokens")) 18) "prompt_tokens is input_tokens + cache_read + cache_creation (10+5+3)")
            (assert (= (int (get usage "completion_tokens")) 20) "completion_tokens is output_tokens, unchanged")
            (assert (= (int (get usage "cached_tokens")) 5) "cached_tokens is only cache_read_input_tokens (the discount), not cache_creation (which still costs full price)")
            true))))))

fn testAnthropicStopReasonToFinish -> Bool
  (do
    (assert (= (ch/anthropicStopReasonToFinish (j/jstr "end_turn")) "stop") "end_turn maps to stop")
    (assert (= (ch/anthropicStopReasonToFinish (j/jstr "stop_sequence")) "stop") "stop_sequence maps to stop")
    (assert (= (ch/anthropicStopReasonToFinish (j/jstr "max_tokens")) "length") "max_tokens maps to length")
    (assert (= (ch/anthropicStopReasonToFinish (j/jstr "tool_use")) "tool_calls") "tool_use maps to tool_calls")
    true)

fn ! runTests -> Bool
  (do
    (assert (testAnthropicBodyMapsModelAndSystem) "testAnthropicBodyMapsModelAndSystem passed")
    (assert (testAnthropicBodyMapsSamplingAndStop) "testAnthropicBodyMapsSamplingAndStop passed")
    (assert (testAnthropicBodyMapsTools) "testAnthropicBodyMapsTools passed")
    (assert (testAnthropicBodyGroupsToolResultIntoUserMessage) "testAnthropicBodyGroupsToolResultIntoUserMessage passed")
    (assert (testAnthropicBodyGroupsConsecutiveToolResultsTogether) "testAnthropicBodyGroupsConsecutiveToolResultsTogether passed")
    (assert (testAnthropicToChatMapsContentBlocks) "testAnthropicToChatMapsContentBlocks passed")
    (assert (testAnthropicToChatMapsCacheUsage) "testAnthropicToChatMapsCacheUsage passed")
    (assert (testAnthropicStopReasonToFinish) "testAnthropicStopReasonToFinish passed")
    true)
