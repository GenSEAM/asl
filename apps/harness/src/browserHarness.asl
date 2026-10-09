(module aslHarness/browserHarness :x [BrowserActionKind BrowserAction SlmCoherenceVerdict makeBrowserAction verifySlmCoherence executeHarnessTurn benchmarkSlmCoherence] :i [(asl-text/string :a s)])

(enum BrowserActionKind (:c actGetDom [] "Extract DOM or accessibility tree") (:c actClick [] "Click element selector") (:c actType [] "Type text into selector") (:c actEval [] "Evaluate JavaScript in tab") (:c actRunSlm [] "Dispatch prompt to on-device SLM"))

(schema BrowserAction (:f kind BrowserActionKind) (:f selector Str) (:f value Str) (:f tabId Str))

(schema SlmCoherenceVerdict (:f isCoherent Bool) (:f action (Option BrowserAction)) (:f errorReason Str) (:f rawOutput Str))

fn makeBrowserAction kind: BrowserActionKind selector: Str value: Str tabId: Str -> BrowserAction
  (BrowserAction :kind kind :selector selector :value value :tabId tabId)

fn countCharOccurrences text: Str target: Str -> I64
  (let [(parts (stringSplit text target))] (- (listLength parts) 1))

fn isDelimBalanced? text: Str -> Bool
  (let [(chars (stringChars text)) (finalSt (fold (fn [(st I64) (c Str)] -> I64 (if (< st 0) st (cond ((= c "(") (+ st 1)) ((= c ")") (- st 1)) ((= c "[") (+ st 1000)) ((= c "]") (- st 1000)) (else st)))) 0 chars))] (== finalSt 0))

fn extractSelectorField text: Str -> Str
  (let [(idx (stringIndexOf text ":selector"))] (mt idx ((none) "") ((some i) (let [(rest (optionOr (stringSlice text (+ i 9) (stringLength text)) "")) (trimmed (stringTrim rest)) (quoteIdx1 (stringIndexOf trimmed "\""))] (mt quoteIdx1 ((none) "") ((some q1) (let [(afterQ1 (optionOr (stringSlice trimmed (+ q1 1) (stringLength trimmed)) "")) (quoteIdx2 (stringIndexOf afterQ1 "\""))] (mt quoteIdx2 ((none) "") ((some q2) (optionOr (stringSlice afterQ1 0 q2) ""))))))))))

fn extractValueField text: Str keyword: Str -> Str
  (let [(idx (stringIndexOf text keyword))] (mt idx ((none) "") ((some i) (let [(rest (optionOr (stringSlice text (+ i (stringLength keyword)) (stringLength text)) "")) (trimmed (stringTrim rest)) (quoteIdx1 (stringIndexOf trimmed "\""))] (mt quoteIdx1 ((none) "") ((some q1) (let [(afterQ1 (optionOr (stringSlice trimmed (+ q1 1) (stringLength trimmed)) "")) (quoteIdx2 (stringIndexOf afterQ1 "\""))] (mt quoteIdx2 ((none) "") ((some q2) (optionOr (stringSlice afterQ1 0 q2) ""))))))))))

fn verifySlmCoherence rawOutput: Str tabId: Str -> SlmCoherenceVerdict
  (let [(trimmed (stringTrim rawOutput))] (cond ((stringEmpty? trimmed) (SlmCoherenceVerdict :isCoherent false :action (none) :errorReason "Empty model output" :rawOutput rawOutput)) ((not (isDelimBalanced? trimmed)) (SlmCoherenceVerdict :isCoherent false :action (none) :errorReason "Unbalanced delimiters in SLM completion" :rawOutput rawOutput)) ((or (stringContains? trimmed "hack-root") (or (stringContains? trimmed "shell-exec") (stringContains? trimmed "rm -rf"))) (SlmCoherenceVerdict :isCoherent false :action (none) :errorReason "Unregistered or hazardous ghost action detected" :rawOutput rawOutput)) ((or (stringContains? trimmed "click") (stringContains? trimmed "browser_click")) (let [(sel (extractSelectorField trimmed)) (finalSel (if (stringEmpty? sel) "#active-btn" sel)) (action (makeBrowserAction (actClick) finalSel "" tabId))] (SlmCoherenceVerdict :isCoherent true :action (some action) :errorReason "" :rawOutput rawOutput))) ((or (stringContains? trimmed "type") (stringContains? trimmed "browser_type")) (let [(sel (extractSelectorField trimmed)) (txt (extractValueField trimmed ":text")) (finalSel (if (stringEmpty? sel) "#input" sel)) (action (makeBrowserAction (actType) finalSel txt tabId))] (SlmCoherenceVerdict :isCoherent true :action (some action) :errorReason "" :rawOutput rawOutput))) ((or (stringContains? trimmed "eval") (stringContains? trimmed "browser_eval")) (let [(expr (extractValueField trimmed ":expression")) (action (makeBrowserAction (actEval) "" expr tabId))] (SlmCoherenceVerdict :isCoherent true :action (some action) :errorReason "" :rawOutput rawOutput))) ((or (stringContains? trimmed "get-dom") (stringContains? trimmed "browser_get_dom")) (let [(action (makeBrowserAction (actGetDom) "" "" tabId))] (SlmCoherenceVerdict :isCoherent true :action (some action) :errorReason "" :rawOutput rawOutput))) ((or (stringContains? trimmed "run-slm") (stringContains? trimmed "browser_run_slm")) (let [(prompt (extractValueField trimmed ":prompt")) (action (makeBrowserAction (actRunSlm) "" prompt tabId))] (SlmCoherenceVerdict :isCoherent true :action (some action) :errorReason "" :rawOutput rawOutput))) (true (SlmCoherenceVerdict :isCoherent false :action (none) :errorReason "No recognizable browser action found in output" :rawOutput rawOutput))))

fn executeHarnessTurn domSnapshot: Str modelCompletion: Str tabId: Str -> SlmCoherenceVerdict
  (let [(verdict (verifySlmCoherence modelCompletion tabId))] (if (not verdict.isCoherent) verdict (mt verdict.action ((none) verdict) ((some act) (let [(sel act.selector)] (if (stringEmpty? sel) verdict (let [(grounded? (or (stringContains? domSnapshot sel) (if (stringStartsWith? sel "#") (stringContains? domSnapshot (optionOr (stringSlice sel 1 (stringLength sel)) sel)) false)))] (if grounded? verdict (SlmCoherenceVerdict :isCoherent false :action (none) :errorReason (s/concat "Selector not grounded in active DOM snapshot: " sel) :rawOutput modelCompletion)))))))))

fn benchmarkSlmCoherence samples: (List Str) -> (Pair I64 F64)
  (let [(total (listLength samples))] (if (== total 0) (pair 0 0.0) (let [(coherentCount (fold (fn [(acc I64) (sample Str)] -> I64 (let [(res (verifySlmCoherence sample "tab-bench"))] (if res.isCoherent (+ acc 1) acc))) 0 samples)) (ratio (/ (int64ToFloat64 coherentCount) (int64ToFloat64 total))) (pct (* ratio 100.0))] (pair coherentCount pct))))
