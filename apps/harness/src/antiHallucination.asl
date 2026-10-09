(module aslHarness/antiHallucination :x [ThinkingResult ToolCallResult FsmRepairReport extractThinking stripMarkdownFences repairAndNormalize] :i [(asl-parser/balance :a bal)])

(schema ThinkingResult (:f thinking Str) (:f code Str))

(schema ToolCallResult (:f code Str) (:f toolKind Str))

(schema FsmRepairReport (:f raw Str) (:f cleanCode Str) (:f thinking Str) (:f toolKind Str) (:f openDelta I64) (:f repaired Bool))

fn extractThinking raw: Str -> ThinkingResult
  (if (and (stringContains? raw "<think>") (stringContains? raw "</think>")) (let [(p1 (stringSplit raw "<think>")) (pre (optionOr (listGet p1 0) "")) (rest (optionOr (listGet p1 1) "")) (p2 (stringSplit rest "</think>")) (think (optionOr (listGet p2 0) "")) (post (optionOr (listGet p2 1) "")) (code (str pre post))] (ThinkingResult :thinking (stringTrim think) :code (stringTrim code))) (if (stringContains? raw "<think>") (let [(p1 (stringSplit raw "<think>")) (think (optionOr (listGet p1 1) ""))] (ThinkingResult :thinking (stringTrim think) :code "")) (ThinkingResult :thinking "" :code raw)))

fn stripMarkdownFences raw: Str -> Str
  (let [(th (extractThinking raw)) (text (stringTrim th.code)) (clean1 (stringReplace text "```asn" "")) (clean2 (stringReplace clean1 "```asl" "")) (clean3 (stringReplace clean2 "```html" "")) (clean4 (stringReplace clean3 "```svg" "")) (clean5 (stringReplace clean4 "```javascript" "")) (clean6 (stringReplace clean5 "```js" "")) (clean7 (stringReplace clean6 "```css" "")) (clean8 (stringReplace clean7 "```json" "")) (clean9 (stringReplace clean8 "```" ""))] (stringTrim clean9))

fn extractToolcallKind raw: Str -> ToolCallResult
  (let [(clean (stripMarkdownFences raw))] (cond ((stringContains? clean "(:svg") (ToolCallResult :code clean :toolKind "svg")) ((stringContains? clean "<svg") (ToolCallResult :code clean :toolKind "svg")) ((or (stringContains? clean "<html") (stringContains? clean "<!DOCTYPE")) (ToolCallResult :code clean :toolKind "html")) ((stringContains? clean "<canvas") (ToolCallResult :code clean :toolKind "html")) ((stringContains? clean ":call") (ToolCallResult :code clean :toolKind "html")) (else (ToolCallResult :code clean :toolKind "direct"))))

fn repairAndNormalize raw: Str -> FsmRepairReport
  (let [(th (extractThinking raw)) (stripped (stripMarkdownFences th.code)) (tc (extractToolcallKind stripped)) (delta (bal/countUnclosedParens tc.code)) (balanced (bal/balanceDelimiters tc.code)) (wasRepaired (or (> delta 0) (not (= raw balanced))))] (FsmRepairReport :raw raw :cleanCode balanced :thinking th.thinking :toolKind tc.toolKind :openDelta delta :repaired wasRepaired))
