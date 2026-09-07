(module asl-harness/anti-hallucination
  :d "Pure AgentScript In-Memory Anti-Hallucination FSM and Delimiter Balancer"
  :x [ThinkingResult ToolCallResult FsmRepairReport repair-and-normalize]
  :i [])

(dfs ThinkingResult
  (:f thinking Str "Chain-of-thought tokens extracted from <think>")
  (:f code Str "Clean executable code without thinking preamble"))

(dfs ToolCallResult
  (:f code Str "Extracted payload or raw code")
  (:f tool-kind Str "Detected format: svg, html, or direct"))

(dfs FsmRepairReport
  (:f raw Str "Original raw streaming response from LLM")
  (:f clean-code Str "Sanitized, balanced and normalized code")
  (:f thinking Str "Isolated chain-of-thought analysis")
  (:f tool-kind Str "Target execution environment")
  (:f open-delta I64 "Parentheses balance delta")
  (:f repaired Bool "Whether structural repairs were applied"))

(df extract-thinking [(raw Str)] -> ThinkingResult
  :d "Separates reasoning thoughts inside <think>...</think> from code"
  (if (string-contains? raw "<think>")
    (if (string-contains? raw "</think>")
      (let [(parts (string-split raw "</think>"))
            (think-part (string-replace (list-head parts) "<think>" ""))
            (code-part (if (> (list-len parts) 1) (string-join "</think>" (list-tail parts 1)) ""))]
        (ThinkingResult :thinking (string-trim think-part) :code (string-trim code-part)))
      (let [(parts (string-split raw "<think>"))
            (think-part (if (> (list-len parts) 1) (list-ref parts 1) ""))]
        (ThinkingResult :thinking (string-trim think-part) :code "")))
    (ThinkingResult :thinking "" :code raw)))

(df strip-markdown-fences [(raw Str)] -> Str
  :d "Cleans code blocks and extracts raw content from markdown code fences"
  (let [(th (extract-thinking raw))
        (text (string-trim (.-code th)))
        (clean1 (string-replace text "```asn" ""))
        (clean2 (string-replace clean1 "```asl" ""))
        (clean3 (string-replace clean2 "```html" ""))
        (clean4 (string-replace clean3 "```svg" ""))
        (clean5 (string-replace clean4 "```javascript" ""))
        (clean6 (string-replace clean5 "```js" ""))
        (clean7 (string-replace clean6 "```css" ""))
        (clean8 (string-replace clean7 "```json" ""))
        (clean9 (string-replace clean8 "```" ""))]
    (string-trim clean9)))

(df balance-delimiters [(raw Str)] -> Str
  :d "Balances unclosed parentheses in S-expressions"
  (let [(open-count (string-count-char raw "("))
        (close-count (string-count-char raw ")"))
        (delta (- open-count close-count))]
    (if (> delta 0)
      (string-concat raw (string-repeat ")" delta))
      raw)))

(df extract-toolcall-kind [(raw Str)] -> ToolCallResult
  :d "Identifies format: svg, html, or direct"
  (let [(clean (strip-markdown-fences raw))]
    (cond
      [(string-contains? clean "(:svg") (ToolCallResult :code clean :tool-kind "svg")]
      [(string-contains? clean "<svg") (ToolCallResult :code clean :tool-kind "svg")]
      [(or (string-contains? clean "<html") (string-contains? clean "<!DOCTYPE")) (ToolCallResult :code clean :tool-kind "html")]
      [(string-contains? clean "<canvas") (ToolCallResult :code clean :tool-kind "html")]
      [(string-contains? clean ":call") (ToolCallResult :code clean :tool-kind "html")]
      [true (ToolCallResult :code clean :tool-kind "direct")])))

(df repair-and-normalize [(raw Str)] -> FsmRepairReport
  :d "Full anti-hallucination normalization pipeline"
  (let [(th (extract-thinking raw))
        (stripped (strip-markdown-fences (.-code th)))
        (tc (extract-toolcall-kind stripped))
        (balanced (balance-delimiters (.-code tc)))
        (open-count (string-count-char stripped "("))
        (close-count (string-count-char stripped ")"))
        (delta (- open-count close-count))
        (was-repaired (or (> delta 0) (not (= raw balanced))))]
    (FsmRepairReport
      :raw raw
      :clean-code balanced
      :thinking (.-thinking th)
      :tool-kind (.-tool-kind tc)
      :open-delta delta
      :repaired was-repaired)))
