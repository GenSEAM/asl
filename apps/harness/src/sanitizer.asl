(module aslHarness/sanitizer
  :x [SanitizedIntent makeSanitizedIntent isPhaticWord calculateTokenSavings calculateSanitizedSud compileRawPromptToIntent repairAsrAcousticToken isAcousticHesitation repairGluedVoicePunctuation fuzzyMatchSymbol SanitizedTrace sanitizeTrace formatSanitizedTrace isFrameworkNoise? estimateTraceTokens]
  :i [])

(schema SanitizedIntent
  (:f id Str)
  (:f domain Str)
  (:f action Str)
  (:f targets (List Str))
  (:f exceptions (List Str))
  (:f rawTokenCount I64)
  (:f compiledTokenCount I64)
  (:f tokenSavingsPct F64)
  (:f sudScore F64))

(schema SanitizedTrace
  (:f targetFile Str)
  (:f lineNumber I64)
  (:f errorMessage Str)
  (:f sanitizedOutput Str)
  (:f tokenCount I64))

(schema TraceAccumulator
  (:f targetFile Str)
  (:f lineNumber I64)
  (:f errorMessage Str)
  (:f keptLines (List Str)))

fn makeSanitizedIntent id: Str domain: Str action: Str targets: (List Str) exceptions: (List Str) rawTokens: I64 compiledTokens: I64 savings: F64 sud: F64 -> SanitizedIntent
  (SanitizedIntent :id id :domain domain :action action :targets targets :exceptions exceptions :rawTokenCount rawTokens :compiledTokenCount compiledTokens :tokenSavingsPct savings :sudScore sud)

fn isPhaticWord word: Str -> Bool
  (or (= word "привет") (or (= word "пожалуйста") (or (= word "спасибо") (or (= word "кажется") (or (= word "слушай") (or (= word "короче") (or (= word "hello") (or (= word "please") (or (= word "thanks") (or (= word "maybe") (= word "basically")))))))))))

fn repairAsrAcousticToken spoken: Str -> Str
  (let [(clean (stringTrim (stringLower spoken)))] (cond ((or (= clean "вог") (or (= clean "ВОГ") (or (= clean "vog") (or (= clean "VOG") (or (= clean "асн") (or (= clean "АСН") (or (= clean "аес") (= clean "ог")))))))) "ASN") ((or (= clean "асел") (or (= clean "асил") (or (= clean "асеэль") (= clean "эйсел")))) "ASL") ((or (= clean "edgends") (or (= clean "edgendс") (or (= clean "эджендс") (or (= clean "агендс") (= clean "агенты"))))) "agents") ((or (= clean "тоузловины") (or (= clean "тоу зловины") (or (= clean "тулзовины") (or (= clean "тулзбелт") (= clean "тулс"))))) "tools") ((or (= clean "клотку") (or (= clean "клод") (= clean "клоуд"))) "claude") ((or (= clean "села и") (or (= clean "селай") (= clean "сила и"))) "cli") ((or (= clean "search-пати") (or (= clean "серч пати") (= clean "серч-пати"))) "thirdparty") ((or (= clean "хайнесс") (or (= clean "ханес") (or (= clean "хайнес") (= clean "харнесс")))) "harness") ((or (= clean "мультиленс") (or (= clean "мульти ленс") (= clean "мульти-ленс"))) "multilens") (else spoken)))

fn isAcousticHesitation token: Str -> Bool
  (let [(clean (stringTrim (stringLower token)))] (or (= clean "бо что") (or (= clean "ну и") (or (= clean "вот это вот все") (or (= clean "как бы") (or (= clean "короче") (= clean "я не знаю")))))))

fn repairGluedVoicePunctuation raw: Str -> Str
  (let [(s1 (stringReplace raw "в.edgendс" "в .agents")) (s2 (stringReplace s1 "в.agents" "в .agents")) (s3 (stringReplace s2 "edgends md" "AGENTS.md")) (s4 (stringReplace s3 "edgends.md" "AGENTS.md")) (s5 (stringReplace s4 "тоу зловины" "тулзовины")) (s6 (stringReplace s5 "села и" "cli")) (s7 (stringReplace s6 "клотку" "claude")) (s8 (stringReplace s7 "search-пати" "thirdparty")) (s9 (stringReplace s8 "в ВОГ" "в ASN")) (s10 (stringReplace s9 "в вог" "в ASN"))] s10)

fn fuzzyMatchSymbol spoken: Str target: Str -> Bool
  (let [(sClean (stringTrim (stringLower spoken))) (tClean (stringTrim (stringLower target)))] (or (= sClean tClean) (or (stringContains? tClean sClean) (stringContains? sClean tClean))))

fn calculateTokenSavings rawTokens: I64 compiledTokens: I64 -> F64
  (if (<= rawTokens 0) 0.0 (let [(diff (- rawTokens compiledTokens))] (* (/ (int64ToFloat64 diff) (int64ToFloat64 rawTokens)) 100.0)))

fn calculateSanitizedSud constraints: I64 compiledTokens: I64 -> F64
  (if (<= compiledTokens 0) 0.0 (/ (int64ToFloat64 constraints) (int64ToFloat64 compiledTokens)))

fn compileRawPromptToIntent id: Str domain: Str action: Str targets: (List Str) exceptions: (List Str) rawTokens: I64 compiledTokens: I64 constraints: I64 -> SanitizedIntent
  (let [(savings (calculateTokenSavings rawTokens compiledTokens)) (sud (calculateSanitizedSud constraints compiledTokens))] (makeSanitizedIntent id domain action targets exceptions rawTokens compiledTokens savings sud))

fn isFrameworkNoise? line: Str -> Bool
  (let [(clean (stringLower line))] (or (stringContains? clean "site-packages") (or (stringContains? clean "pluggy") (or (stringContains? clean "pytest") (or (stringContains? clean "core::panicking") (or (stringContains? clean "/rustc/") (or (stringContains? clean "node_modules") (or (stringContains? clean "runner.py") (or (stringContains? clean "_hookexec") (stringContains? clean "result = call()"))))))))))

fn estimateTraceTokens text: Str -> I64
  (let [(len (stringLength text))] (if (<= len 0) 0 (let [(toks (/ len 4))] (if (<= toks 0) 1 toks))))

fn extractTraceTargetFile line: Str -> Str
  (if (stringContains? line "File \"") (let [(parts (stringSplit line "File \""))] (if (>= (listLength parts) 2) (let [(subparts (stringSplit (optionOr (listGet parts 1) "") "\""))] (if (>= (listLength subparts) 1) (optionOr (listGet subparts 0) "") "")) "")) "")

fn extractTraceLineNumber line: Str -> I64
  (if (stringContains? line ", line ") (let [(p1 (optionOr (listGet (stringSplit line ", line ") 1) "")) (p2 (optionOr (listGet (stringSplit p1 ",") 0) "")) (p3 (optionOr (listGet (stringSplit p2 " ") 0) ""))] (optionOr (stringToInt64 (stringTrim p3)) 0)) (if (stringContains? line ": line ") (let [(p1 (optionOr (listGet (stringSplit line ": line ") 1) "")) (p2 (optionOr (listGet (stringSplit p1 ",") 0) "")) (p3 (optionOr (listGet (stringSplit p2 " ") 0) ""))] (optionOr (stringToInt64 (stringTrim p3)) 0)) (if (stringContains? line ", line:") (let [(p1 (optionOr (listGet (stringSplit line ", line:") 1) "")) (p2 (optionOr (listGet (stringSplit p1 ",") 0) "")) (p3 (optionOr (listGet (stringSplit p2 " ") 0) ""))] (optionOr (stringToInt64 (stringTrim p3)) 0)) 0)))

fn extractTraceErrorMessage line: Str -> Str
  (let [(t (stringTrim line))] (if (or (stringStartsWith? t "AssertionError") (or (stringContains? t "Error:") (or (stringContains? t "Exception:") (or (stringStartsWith? t "panic:") (stringContains? t "AssertionError:"))))) t ""))

fn sanitizeTrace rawTrace: Str maxTokens: I64 -> SanitizedTrace
  (if (stringEmpty? (stringTrim rawTrace)) (SanitizedTrace :targetFile "" :lineNumber 0 :errorMessage "" :sanitizedOutput "" :tokenCount 0) (let [(lines (stringSplit rawTrace "\n"))] (let [(init (TraceAccumulator :targetFile "" :lineNumber 0 :errorMessage "" :keptLines (list)))] (let [(filtered (fold (fn [(acc TraceAccumulator) (ln Str)] -> TraceAccumulator (let [(isNoise (isFrameworkNoise? ln)) (tf acc.targetFile) (lnNum acc.lineNumber) (err acc.errorMessage) (kept acc.keptLines)] (let [(newTf (if (and (= tf "") (not isNoise) (stringContains? ln "File \"")) (extractTraceTargetFile ln) tf)) (newLine (if (and (= lnNum 0) (not isNoise) (or (stringContains? ln ", line ") (stringContains? ln ": line "))) (extractTraceLineNumber ln) lnNum)) (newErr (if (not isNoise) (let [(e (extractTraceErrorMessage ln))] (if (not (stringEmpty? e)) e err)) err)) (newKept (if (and (not isNoise) (not (stringEmpty? (stringTrim ln)))) (listAppend kept (list ln)) kept))] (TraceAccumulator :targetFile newTf :lineNumber newLine :errorMessage newErr :keptLines newKept)))) init lines))] (let [(targetFile filtered.targetFile) (lineNumber filtered.lineNumber) (errMsg filtered.errorMessage) (keptLines filtered.keptLines)] (let [(joined (stringJoin keptLines "\n"))] (let [(budgetLimit (min maxTokens 250))] (let [(charCap (* budgetLimit 4))] (let [(boundedOutput (if (> (stringLength joined) charCap) (optionOr (stringSlice joined 0 charCap) joined) joined))] (let [(rawToks (estimateTraceTokens boundedOutput))] (let [(finalTokens (min budgetLimit (max 1 rawToks)))] (SanitizedTrace :targetFile targetFile :lineNumber lineNumber :errorMessage errMsg :sanitizedOutput boundedOutput :tokenCount finalTokens))))))))))))

fn formatSanitizedTrace trace: SanitizedTrace -> Str
  (str "(:sanitized-trace :target \"" trace.targetFile "\" :line " (stringFromInt64 trace.lineNumber) " :error \"" trace.errorMessage "\" :tokens " (stringFromInt64 trace.tokenCount) ")\n" trace.sanitizedOutput)
