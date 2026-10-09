(module aslHarness/llmClient :x [ModelOptions CompletionResult makeDefaultOptions formatModelRequest parseModelResponse compileAsnGrammarConstraint calculateTokSec computeDynamicTemperature jsonEscapeStr] :i [])

(schema ModelOptions (:f model Str) (:f temperature F64) (:f maxTokens I64) (:f system Str) (:f grammarConstraint (Option Str)))

(schema CompletionResult (:f text Str) (:f inputTokens I64) (:f outputTokens I64) (:f durationMs I64) (:f tokSec F64))

fn makeDefaultOptions model: Str -> ModelOptions
  (ModelOptions :model model :temperature 0.2 :maxTokens 4096 :system "" :grammarConstraint (none))

fn calculateTokSec outputTokens: I64 durationMs: I64 -> F64
  (if (<= durationMs 0) 0.0 (/ (* (int64ToFloat64 outputTokens) 1000.0) (int64ToFloat64 durationMs)))

fn jsonEscapeStr s: Str -> Str
  (let [(s1 (stringReplace s "\\" "\\\\")) (s2 (stringReplace s1 "\"" "\\\"")) (s3 (stringReplace s2 "\n" "\\n")) (s4 (stringReplace s3 "\r" "\\r"))] (stringReplace s4 "\t" "\\t"))

fn formatModelRequest opts: ModelOptions prompt: Str -> Str
  (let [(grammarPart (mt opts.grammarConstraint ((some g) (str ", \"grammar\": \"" (jsonEscapeStr g) "\"")) ((none) ""))) (escSys (jsonEscapeStr opts.system)) (escPrompt (jsonEscapeStr prompt))] (str "{\"model\": \"" opts.model "\", \"temperature\": " (stringFromFloat64 opts.temperature) ", \"max_tokens\": " (stringFromInt64 opts.maxTokens) ", \"system\": \"" escSys "\", \"prompt\": \"" escPrompt "\"" grammarPart "}"))

fn extractFirstDigits chars: (List Str) acc: Str -> Str
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if (stringContains? "0123456789" c) (extractFirstDigits rst (str acc c)) (if (stringEmpty? acc) (if (or (= c " ") (or (= c ":") (or (= c "\t") (= c "\n")))) (extractFirstDigits rst "") acc) acc))))

fn extractIntByKey raw: Str key: Str -> I64
  (let [(idxOpt (stringIndexOf raw key))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength key)) (stringLength raw))) (tail (optionOr tailOpt "")) (digits (extractFirstDigits (stringChars tail) ""))] (optionOr (stringToInt64 digits) 0))) ((none) 0)))

fn extractStrByKey raw: Str key: Str -> Str
  (let [(idxOpt (stringIndexOf raw key))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength key)) (stringLength raw))) (tail (optionOr tailOpt "")) (q1Opt (stringIndexOf tail "\""))] (mt q1Opt ((some q1) (let [(restOpt (stringSlice tail (+ q1 1) (stringLength tail))) (restStr (optionOr restOpt "")) (q2Opt (stringIndexOf restStr "\""))] (mt q2Opt ((some q2) (optionOr (stringSlice restStr 0 q2) "")) ((none) "")))) ((none) "")))) ((none) "")))

fn parseModelResponse raw: Str durationMs: I64 -> CompletionResult
  (let [(txtJson (extractStrByKey raw "\"text\"")) (txtContent (if (stringEmpty? txtJson) (extractStrByKey raw "\"content\"") txtJson)) (txtAsn (if (stringEmpty? txtContent) (extractStrByKey raw ":text") txtContent)) (finalText (if (stringEmpty? txtAsn) raw txtAsn)) (inTok1 (extractIntByKey raw "\"prompt_tokens\"")) (inTok2 (if (= inTok1 0) (extractIntByKey raw "\"input_tokens\"") inTok1)) (finalIn (if (= inTok2 0) (extractIntByKey raw ":input-tokens") inTok2)) (outTok1 (extractIntByKey raw "\"completion_tokens\"")) (outTok2 (if (= outTok1 0) (extractIntByKey raw "\"output_tokens\"") outTok1)) (finalOut (if (= outTok2 0) (extractIntByKey raw ":output-tokens") outTok2)) (speed (calculateTokSec finalOut durationMs))] (CompletionResult :text finalText :inputTokens finalIn :outputTokens finalOut :durationMs durationMs :tokSec speed))

fn compileAsnGrammarConstraint schemaSpec: Str -> (Option Str)
  (let [(trimmed (stringTrim schemaSpec))] (if (stringEmpty? trimmed) (none) (some "root ::= \"(\" ws [a-zA-Z0-9_-]+ (ws \":\" [a-zA-Z0-9_-]+ ws value)* ws \")\"\nvalue ::= string | number | symbol | list\nstring ::= \"\\\"\" [^\\\"]* \"\\\"\"\nnumber ::= [0-9]+\nsymbol ::= [a-zA-Z0-9_-]+\nlist ::= \"[\" (ws value)* ws \"]\"\nws ::= [ \\t\\n\\r]*")))

fn roundFloat4 v: F64 -> F64
  (mt (float64ToInt64 (+ (* v 10000.0) 0.5))
    ((some n) (/ (int64ToFloat64 n) 10000.0))
    ((none) v))


fn computeDynamicTemperature attempt: I64 maxAttempts: I64 baseTemp: F64 -> F64
  (let [(clampedBase (if (< baseTemp 0.0) 0.0 (if (> baseTemp 1.0) 1.0 baseTemp)))] (if (or (<= maxAttempts 1) (<= attempt 0)) clampedBase (let [(clampedAttempt (if (> attempt maxAttempts) maxAttempts attempt)) (step (/ (- 1.0 clampedBase) (int64ToFloat64 maxAttempts))) (temp (+ clampedBase (* (int64ToFloat64 clampedAttempt) step))) (rounded (roundFloat4 temp))] (if (> rounded 1.0) 1.0 (if (< rounded 0.0) 0.0 rounded)))))
