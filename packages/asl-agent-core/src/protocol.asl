(module aslAgentCore/protocol :x [ToolParam ToolDef ToolArg ToolInvocation ToolResult formatToolParam formatToolDef formatInvocation formatResult getArgValue stripQuotes parseTokens parseInvocation] :i [])

(schema ToolParam (:f name Str) (:f paramType Str) (:f required Bool) (:f doc Str))

(schema ToolDef (:f name Str) (:f doc Str) (:f params (List ToolParam)))

(schema ToolArg (:f key Str) (:f val Str))

(schema ToolInvocation (:f toolName Str) (:f args (List ToolArg)) (:f rawCall Str))

(schema ToolResult (:f toolName Str) (:f success Bool) (:f output Str) (:f errorMsg Str))

(schema TokenizerState (:f tokens (List Str)) (:f currentBuf Str) (:f inQuote Bool))

fn formatToolParam p: ToolParam -> Str
  (let [(reqMarker (if p.required "!" ""))] (str ":" p.name reqMarker " " p.paramType))

fn formatToolDef d: ToolDef -> Str
  (let [(paramsStr (stringJoin (map (fn [(p ToolParam)] -> Str (formatToolParam p)) d.params) " "))] (str "(tool :" d.name " :d " " (.-doc d) " " [" paramsStr "])"))

fn formatInvocation inv: ToolInvocation -> Str
  (let [(argsStr (stringJoin (map (fn [(a ToolArg)] -> Str (str ":" a.key " " " (.-val a) " "")) inv.args) " "))] (if (stringEmpty? argsStr) (str "(call :tool " inv.toolName ")") (str "(call :tool " inv.toolName " " argsStr ")")))

fn formatResult res: ToolResult -> Str
  (if res.success (str "(result :tool " res.toolName " :ok true :out \"" res.output "\")") (str "(result :tool " res.toolName " :ok false :err \"" res.errorMsg "\")"))

fn getArgValue args: (List ToolArg) key: Str -> (Option Str)
  (let [(matches (filter (fn [(a ToolArg)] -> Bool (= a.key key)) args))] (mt (listHead matches) ((none) (none)) ((some matched) (some matched.val))))

fn stripQuotes s: Str -> Str
  (if (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")) (if (> (stringLength s) 1) (optionOr (stringSlice s 1 (- (stringLength s) 1)) "") s) s)

fn tokenizeChars chars: (List Str) state: TokenizerState -> (List Str)
  (let [(finalState (fold (fn [(st TokenizerState) (c Str)] -> TokenizerState (cond ((= c "\"") (TokenizerState :tokens st.tokens :currentBuf (str st.currentBuf c) :inQuote (not st.inQuote))) ((and (not st.inQuote) (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))) (if (stringEmpty? st.currentBuf) st (TokenizerState :tokens (cons st.currentBuf st.tokens) :currentBuf "" :inQuote false))) (else (TokenizerState :tokens st.tokens :currentBuf (str st.currentBuf c) :inQuote st.inQuote)))) state chars))] (let [(allRev (if (stringEmpty? finalState.currentBuf) finalState.tokens (cons finalState.currentBuf finalState.tokens)))] (listReverse allRev)))

fn parseTokens s: Str -> (List Str)
  (let [(trimmed (stringTrim s)) (noOpen (if (stringStartsWith? trimmed "(") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) trimmed) trimmed)) (noClose (if (stringEndsWith? noOpen ")") (optionOr (stringSlice noOpen 0 (- (stringLength noOpen) 1)) noOpen) noOpen)) (initState (TokenizerState :tokens (list) :currentBuf "" :inQuote false))] (tokenizeChars (stringChars noClose) initState))

fn parseArgPairs tokens: (List Str) -> (List ToolArg)
  (mt (listHead tokens) ((none) (list)) ((some keyToken) (mt (listTail tokens) ((none) (list)) ((some tail1) (mt (listHead tail1) ((none) (list)) ((some valToken) (let [(restTokens (optionOr (listTail tail1) (list))) (cleanKey (if (stringStartsWith? keyToken ":") (optionOr (stringSlice keyToken 1 (stringLength keyToken)) keyToken) keyToken)) (cleanVal (stripQuotes valToken)) (arg (ToolArg :key cleanKey :val cleanVal))] (cons arg (parseArgPairs restTokens)))))))))

fn parseInvocation raw: Str -> (Result ToolInvocation Str)
  (let [(tokens (parseTokens raw))] (mt (listHead tokens) ((none) (err "Empty tool invocation")) ((some headToken) (let [(remaining (if (= headToken "call") (optionOr (listTail tokens) (list)) tokens))] (mt (listHead remaining) ((none) (err "Missing tool name in invocation")) ((some firstTok) (let [(parsedPair (if (= firstTok ":tool") (mt (listTail remaining) ((none) (err "Missing tool identifier after :tool")) ((some tTail) (mt (listHead tTail) ((none) (err "Missing tool identifier after :tool")) ((some nameTok) (ok (pair nameTok (optionOr (listTail tTail) (list)))))))) (ok (pair firstTok (optionOr (listTail remaining) (list))))))] (mt parsedPair ((err e) (err e)) ((ok p) (let [(toolName (pairFirst p)) (argTokens (pairSecond p)) (args (parseArgPairs argTokens))] (ok (ToolInvocation :toolName toolName :args args :rawCall raw))))))))))))
