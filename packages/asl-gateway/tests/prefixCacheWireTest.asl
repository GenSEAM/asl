(module aslGateway/tests/prefixCacheWireTest
  :x [runTests]
  :i [(chat :a ch)
      (config :a cfg)
      (wire :a w)
      (pyText :a pt)
      (asl-json/json :a j)])

; (:m :ref LEON-PREFIX-CACHE-20261026 :do "offline fixtures for the provider cache hints: cache_control breakpoints for Anthropic, cachedContent for Gemini, prompt_cache_key for declared OpenAI-compatible providers, and the cache-write count in the usage receipt")

fn get v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn items v: j/Json -> (List j/Json)
  (match v ((j/jarr xs) xs) (_ (list)))

fn msg role: String content: String -> j/Json
  (j/jobj (list (pair "role" (j/jstr role)) (pair "content" (j/jstr content))))

fn tool -> j/Json
  (j/jobj (list (pair "type" (j/jstr "function"))
                (pair "function" (j/jobj (list (pair "name" (j/jstr "add")) (pair "parameters" (j/jobj (list))))))))

fn turnBody extra: (List j/Json) -> j/Json
  (j/jobj (list (pair "messages" (j/jarr (listAppend (list (msg "system" "You are a bot.") (msg "user" "Task: sum")) extra)))
                (pair "tools" (j/jarr (list (tool))))))

fn dump v: j/Json -> String
  (pt/jsonDumps v -1)

fn hasMark v: j/Json -> Bool
  (match (pt/jget v "cache_control") ((some _) true) ((none) false))

fn turn1 -> j/Json
  (turnBody (list (msg "assistant" "read a") (msg "user" "result a")))

fn turn2 -> j/Json
  (turnBody (list (msg "assistant" "read a") (msg "user" "result a") (msg "assistant" "read b") (msg "user" "result b")))

fn hinted src: j/Json -> j/Json
  (ch/cacheHints "anthropic" "anthropic" none src (ch/anthropicBody src "claude-haiku-5-5"))

fn testAnthropicBreakpoints -> Bool
  (let [(up (hinted (turn1)))
        (sysBlocks (items (get up "system")))
        (msgs (items (get up "messages")))
        (n (listLength msgs))]
    (do
      (assert (hasMark (optionOr (listGet sysBlocks 0) (j/jnull))) "system carries a cache_control breakpoint")
      (assert (hasMark (optionOr (listLast (items (get up "tools"))) (j/jnull))) "the last tool carries a cache_control breakpoint")
      (assert (hasMark (optionOr (listGet (items (get (optionOr (listGet msgs (- n 2)) (j/jnull)) "content")) 0) (j/jnull))) "the message before the last user message carries the prefix breakpoint")
      (assert (match (pt/jget (optionOr (listGet msgs (- n 1)) (j/jnull)) "content") ((some (j/jstr _)) true) (_ false)) "the final user message stays an unmarked plain string")
      true))

fn testAnthropicSystemAndToolsStable -> Bool
  (let [(a (hinted (turn1)))
        (b (hinted (turn2)))]
    (do
      (assert (= (dump (get a "system")) (dump (get b "system"))) "system bytes are identical across consecutive turns")
      (assert (= (dump (get a "tools")) (dump (get b "tools"))) "tools bytes are identical across consecutive turns")
      true))

fn ! tableWith! -> (Option cfg/GatewayTable)
  (match (cfg/gatewayConfigParse! "(:gateway :v 2 :providers ((:provider :id openai :kind openai :base \"http://127.0.0.1:1\" :promptCacheKey true) (:provider :id deepseek :kind openai :base \"http://127.0.0.1:1\")) :models ((:model :id m :provider openai :name \"x\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))" "prefixCacheCfg" ".asl/mem/calibration/index.asn")
    ((ok t) (some t))
    ((err _) none))

fn testOpenAiKey -> Bool
  (let [(src (turn1))
        (srcNext (turn2))
        (oa (ch/cacheHints "chat" "openai" (tableWith!) src src))
        (oaNext (ch/cacheHints "chat" "openai" (tableWith!) srcNext srcNext))
        (ds (ch/cacheHints "chat" "deepseek" (tableWith!) src src))]
    (do
      (assert (some? (tableWith!)) "fixture config parses")
      (assert (match (pt/jget oa "prompt_cache_key") ((some (j/jstr k)) (stringStartsWith? k "asl-")) (_ false)) "a provider with :promptCacheKey true gets prompt_cache_key")
      (assert (= (dump (get oa "prompt_cache_key")) (dump (get oaNext "prompt_cache_key"))) "the key is the same on consecutive turns of one run")
      (assert (match (pt/jget ds "prompt_cache_key") ((none) true) (_ false)) "a provider without :promptCacheKey gets no prompt_cache_key")
      (assert (= (dump ds) (dump src)) "a provider without :promptCacheKey body is byte-identical to the input")
      true))

fn testGeminiCachedContent -> Bool
  (let [(src (pt/jset (turn1) "cached_content" (j/jstr "cachedContents/abc")))
        (up (ch/cacheHints "gemini" "google" none src (ch/anthropicBody src "m")))
        (plain (ch/cacheHints "gemini" "google" none (turn1) (ch/anthropicBody (turn1) "m")))]
    (do
      (assert (= (dump (get up "cachedContent")) "\"cachedContents/abc\"") "a named cache is passed as cachedContent")
      (assert (match (pt/jget plain "cachedContent") ((none) true) (_ false)) "no cachedContent without a named cache")
      true))

fn testUsageReceipt -> Bool
  (let [(anth (optionOr (ch/anthropicToChat "{\"content\":[{\"type\":\"text\",\"text\":\"x\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":3}}") ""))
        (deep "{\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":7,\"prompt_cache_hit_tokens\":64}}")]
    (do
      (assert (= (w/chatReplyUsageStr anth) (some "(:input 18 :cached 5 :cacheWrite 3 :output 20)")) "the usage receipt records cache read and cache write separately")
      (assert (= (w/chatReplyUsageStr deep) (some "(:input 100 :cached 64 :output 7)")) "DeepSeek prompt_cache_hit_tokens is recorded as cached")
      true))

fn marked text: String -> j/Json
  (j/jarr (list (j/jobj (list (pair "type" (j/jstr "text")) (pair "text" (j/jstr text)) (pair "cache_control" (j/jobj (list (pair "type" (j/jstr "ephemeral")))))))))

fn markCount v: j/Json -> Int64
  (- (listLength (stringSplit (dump v) "cache_control")) 1)

fn testClientMarksRespected -> Bool
  (let [(src (j/jobj (list (pair "messages" (j/jarr (list
               (msg "system" "sys")
               (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (marked "one"))))
               (msg "assistant" "a")
               (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (marked "two"))))
               (msg "assistant" "b")
               (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (marked "three"))))
               (msg "user" "final"))))
             (pair "tools" (j/jarr (list (tool)))))))
        (up (hinted src))]
    (do
      (assert (= (markCount (ch/anthropicBody src "m")) 3) "the client body carries 3 marks")
      (assert (<= (markCount up) 4) (str "marks after hints stay within 4, got " (stringFromInt64 (markCount up))))
      (assert (hasMark (optionOr (listLast (items (get up "tools"))) (j/jnull))) "the remaining room goes to the last tool first")
      true))

fn testUnmarkableBlockSkipped -> Bool
  (let [(content (j/jarr (list (j/jobj (list (pair "type" (j/jstr "tool_use")) (pair "id" (j/jstr "x")))))))
        (up (ch/anthropicCacheHints (j/jobj (list (pair "messages" (j/jarr (list (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" content))) (msg "user" "final"))))))))]
    (do
      (assert (= (markCount up) 0) "a tool_use block is never marked")
      true))

fn ! runTests -> Bool
  (do
    (assert (testAnthropicBreakpoints) "testAnthropicBreakpoints passed")
    (assert (testAnthropicSystemAndToolsStable) "testAnthropicSystemAndToolsStable passed")
    (assert (testOpenAiKey) "testOpenAiKey passed")
    (assert (testGeminiCachedContent) "testGeminiCachedContent passed")
    (assert (testUsageReceipt) "testUsageReceipt passed")
    (assert (testClientMarksRespected) "testClientMarksRespected passed")
    (assert (testUnmarkableBlockSkipped) "testUnmarkableBlockSkipped passed")
    true)
