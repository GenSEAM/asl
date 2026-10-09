(module asl-transpile/shTranspile :x [ShTranspileResult asnToSh shToAsn makeCmd makePipe makeScript measureShSavings] :i [(asl-text/string :a s) (asl-text/escape :a esc) (asl-text/text :a txt)])

(schema ShTranspileResult (:f output Str) (:f originalTokens I64) (:f asnTokens I64) (:f savingsPercent F64) (:f success Bool))

fn makeCmd bin: Str args: (List Str) -> Str
  (let [(argsStr (fold (fn [(acc Str) (arg Str)] -> Str (let [(quoted (s/concat (s/concat "\"" arg) "\""))] (if (stringEmpty? acc) quoted (s/concat (s/concat acc " ") quoted)))) "" args))] (s/concat (s/concat (s/concat "(:cmd \"" bin) "\" :args [") (s/concat argsStr "])")))

fn makePipe stages: (List Str) -> Str
  (let [(stagesStr (fold (fn [(acc Str) (stg Str)] -> Str (if (stringEmpty? acc) stg (s/concat (s/concat acc " ") stg))) "" stages))] (s/concat (s/concat "(:pipe " stagesStr) ")"))

fn makeScript cmds: (List Str) strict: Bool -> Str
  (let [(body (fold (fn [(acc Str) (cmd Str)] -> Str (if (stringEmpty? acc) cmd (s/concat (s/concat acc "\n  ") cmd))) "" cmds))] (if strict (s/concat (s/concat "(:script :strict true\n  " body) "\n)") (s/concat (s/concat "(:script\n  " body) "\n)")))

(schema ScanArgState (:f inQuote Bool) (:f escaped Bool) (:f cur Str) (:f tokens (List Str)))

fn scanArgChar st: ScanArgState ch: Str -> ScanArgState
  (if st.inQuote (if st.escaped (with st :inQuote true :escaped false :cur (str st.cur ch)) (if (= ch "\\") (with st :inQuote true :escaped true :cur (str st.cur ch)) (if (= ch "\"") (ScanArgState :inQuote false :escaped false :cur "" :tokens (cons st.cur st.tokens)) (with st :inQuote true :escaped false :cur (str st.cur ch))))) (if (= ch "\"") (with st :inQuote true :escaped false :cur "") st))

fn extractCmdTokens s: Str -> (List Str)
  (let [(finalSt (fold scanArgChar (ScanArgState :inQuote false :escaped false :cur "" :tokens (list)) (stringChars s)))] (listReverse finalSt.tokens))

fn formatShArg arg: Str -> Str
  (cond ((stringEmpty? arg) "''") ((or (and (stringStartsWith? arg "\"") (stringEndsWith? arg "\"")) (and (stringStartsWith? arg "'") (stringEndsWith? arg "'"))) arg) (true (esc/escapeShCompact arg)))

fn extractShLiteral s: Str -> Str
  (let [(firstQ (stringIndexOf s "\""))] (mt firstQ ((none) (stringTrim (stringReplace (stringReplace s "(:sh" "") ")" ""))) ((some q1) (let [(restS (optionOr (stringSlice s (+ q1 1) (stringLength s)) "")) (revS (stringReverse restS)) (revQ (stringIndexOf revS "\""))] (mt revQ ((none) (esc/unescapeAsnStr restS)) ((some q2) (let [(len (- (stringLength restS) (+ q2 1))) (body (optionOr (stringSlice restS 0 len) ""))] (esc/unescapeAsnStr body))))))))

fn transpileSingleCmd cmdStr: Str -> Str
  (let [(trimmed (stringTrim cmdStr))] (cond ((stringStartsWith? trimmed "(:sh") (extractShLiteral trimmed)) ((stringStartsWith? trimmed "(:cmd") (let [(toks (extractCmdTokens trimmed))] (if (listEmpty? toks) "" (let [(formatted (map (fn [(tok Str)] -> Str (formatShArg (esc/unescapeAsnStr tok))) toks))] (stringJoin formatted " "))))) (true (let [(toks (extractCmdTokens trimmed))] (if (listEmpty? toks) trimmed (let [(formatted (map (fn [(tok Str)] -> Str (formatShArg (esc/unescapeAsnStr tok))) toks))] (stringJoin formatted " ")))))))

fn asnToSh asnText: Str -> ShTranspileResult
  (let [(trimmed (stringTrim asnText))] (cond ((stringEmpty? trimmed) (ShTranspileResult :output "" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((not (or (stringStartsWith? trimmed "(:") (stringStartsWith? trimmed "("))) (ShTranspileResult :output "Syntax error: invalid ASN shell root (expected (:cmd, (:pipe, (:seq, (:script, or (:sh))" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((stringStartsWith? trimmed "(:sh") (let [(asnTok (txt/estimateTokens trimmed)) (cleaned (extractShLiteral trimmed)) (rawTok (txt/estimateTokens cleaned)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output cleaned :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true))) ((stringStartsWith? trimmed "(:pipe") (let [(asnTok (txt/estimateTokens trimmed)) (parts (stringSplit trimmed "(:cmd")) (cmdParts (filter (fn [(p Str)] -> Bool (stringContains? p "\"")) parts)) (transpiledCmds (map (fn [(p Str)] -> Str (transpileSingleCmd (str "(:cmd" p))) cmdParts)) (cleaned (stringJoin transpiledCmds " | ")) (rawTok (txt/estimateTokens cleaned)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output cleaned :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true))) ((stringStartsWith? trimmed "(:script") (let [(asnTok (txt/estimateTokens trimmed)) (isStrict (stringContains? trimmed ":strict true")) (parts (stringSplit trimmed "(:cmd")) (cmdParts (filter (fn [(p Str)] -> Bool (stringContains? p "\"")) parts)) (transpiledCmds (map (fn [(p Str)] -> Str (transpileSingleCmd (str "(:cmd" p))) cmdParts)) (body (stringJoin transpiledCmds "\n")) (cleaned (if isStrict (str "set -euo pipefail\n" body) body)) (rawTok (txt/estimateTokens cleaned)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output cleaned :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true))) ((stringStartsWith? trimmed "(:seq") (let [(asnTok (txt/estimateTokens trimmed)) (parts (stringSplit trimmed "(:cmd")) (cmdParts (filter (fn [(p Str)] -> Bool (stringContains? p "\"")) parts)) (transpiledCmds (map (fn [(p Str)] -> Str (transpileSingleCmd (str "(:cmd" p))) cmdParts)) (cleaned (stringJoin transpiledCmds " && ")) (rawTok (txt/estimateTokens cleaned)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output cleaned :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true))) (true (let [(asnTok (txt/estimateTokens trimmed)) (cleaned (transpileSingleCmd trimmed)) (rawTok (txt/estimateTokens cleaned)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output cleaned :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true)))))

fn shToAsn shText: Str -> ShTranspileResult
  (let [(trimmed (stringTrim shText))] (cond ((stringEmpty? trimmed) (ShTranspileResult :output "" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (true (let [(rawTok (txt/estimateTokens trimmed)) (asnOut (s/concat (s/concat "(:cmd \"" trimmed) "\")")) (asnTok (txt/estimateTokens asnOut)) (savings (txt/calcSavings rawTok asnTok))] (ShTranspileResult :output asnOut :originalTokens rawTok :asnTokens asnTok :savingsPercent savings :success true)))))

fn measureShSavings cmd: Str -> F64
  (let [(res (shToAsn cmd))] res.savingsPercent)
