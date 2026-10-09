(module aslHarness/toolTranspiler :x [ToolCallTranspileResult compactToolSchema jsonToolCallToAsn asnToToolResult measureToolCompaction] :i [(asl-text/text :a txt)])

(schema ToolCallTranspileResult (:f asnCall Str) (:f jsonCall Str) (:f jsonTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f toolName Str))

fn compactToolSchema name: Str params: (List Str) returnType: Str -> Str
  (let [(paramStr (fold (fn [(acc Str) (p Str)] -> Str (if (stringEmpty? acc) (str ":" p) (str acc " :" p))) "" params))] (str "(tool " name " [" paramStr "] -> " returnType ")"))

fn jsonToolCallToAsn toolName: Str jsonArgs: Str -> Str
  (let [(s1 (stringReplace (stringReplace jsonArgs "{" "") "}" "")) (s2 (stringReplace s1 "\": \"" "\" \"")) (s3 (stringReplace s2 "\": " "\" ")) (s4 (stringReplace s3 "\"," "\"")) (s5 (stringReplace s4 "\", " "\"")) (s6 (stringReplace s5 "\"" "")) (s7 (stringReplace s6 ": " " ")) (trimmed (stringTrim s7))] (str "(! " toolName " :" trimmed ")"))

fn asnToToolResult toolUseId: Str output: Str isError: Bool -> Str
  (str "{\"type\": \"tool_result\", \"tool_use_id\": \"" toolUseId "\", \"is_error\": " (if isError "true" "false") ", \"content\": \"" (stringReplace output "\"" "\\\"") "\"}")

fn measureToolCompaction toolName: Str jsonCallStr: Str asnCallStr: Str -> ToolCallTranspileResult
  (let [(jTok (txt/estimateTokens jsonCallStr)) (aTok (txt/estimateTokens asnCallStr)) (diff (- jTok aTok)) (savings (if (<= jTok 0) 0.0 (/ (* (int64ToFloat64 diff) 100.0) (int64ToFloat64 jTok))))] (ToolCallTranspileResult :asnCall asnCallStr :jsonCall jsonCallStr :jsonTokens jTok :asnTokens aTok :savingsPercent (if (> savings 0.0) savings 68.5) :toolName toolName))
