(module asl-codec/shTranspile
  :d "AgentScript Shell Command Codec: Bidirectional conversion between compact ASN S-expressions and safe POSIX/Bash scripts."
  :x [ShTranspileResult
      asnToSh
      shToAsn
      makeCmd
      makePipe
      makeScript
      measureShSavings]
  :i [(asl-text/string :a s)
      (asl-text/escape :a esc)
      (asl-text/text :a txt)])

(dfs ShTranspileResult
  (:f output Str "Transpiled shell command string or diagnostic message")
  (:f originalTokens I64 "Estimated token count in raw shell syntax")
  (:f asnTokens I64 "Token count in compact ASN S-expression syntax")
  (:f savingsPercent F64 "Token compaction percentage")
  (:f success Bool "True if transpilation succeeded"))

(df makeCmd [(bin Str) (args (List Str))] -> Str
  :d "Constructs an ASN command S-expression from binary name and argument list."
  (let [(argsStr (fold (fn [(acc Str) (arg Str)] -> Str
                          (let [(quoted (s/concat (s/concat "\"" arg) "\""))]
                            (if (string-empty? acc)
                                quoted
                                (s/concat (s/concat acc " ") quoted))))
                        ""
                        args))]
    (s/concat (s/concat (s/concat "(:cmd \"" bin) "\" :args [") (s/concat argsStr "])"))))

(df makePipe [(stages (List Str))] -> Str
  :d "Constructs an ASN pipeline S-expression from a list of command expressions."
  (let [(stagesStr (fold (fn [(acc Str) (stg Str)] -> Str
                            (if (string-empty? acc)
                                stg
                                (s/concat (s/concat acc " ") stg)))
                          ""
                          stages))]
    (s/concat (s/concat "(:pipe " stagesStr) ")")))

(df makeScript [(cmds (List Str)) (strict Bool)] -> Str
  :d "Constructs an ASN multi-command script S-expression."
  (let [(body (fold (fn [(acc Str) (cmd Str)] -> Str
                      (if (string-empty? acc)
                          cmd
                          (s/concat (s/concat acc "\n  ") cmd)))
                    ""
                    cmds))]
    (if strict
        (s/concat (s/concat "(:script :strict true\n  " body) "\n)")
        (s/concat (s/concat "(:script\n  " body) "\n)"))))

(dfs ScanArgState
  (:f inQuote Bool "True if scanner is inside double-quoted string")
  (:f escaped Bool "True if previous character was backslash")
  (:f cur Str "Accumulated token characters")
  (:f tokens (List Str) "List of scanned tokens in reverse order"))

(df scanArgChar [(st ScanArgState) (ch Str)] -> ScanArgState
  :d "Processes one character during argument token scanning"
  (if (.-inQuote st)
      (if (.-escaped st)
          (ScanArgState
            :inQuote true
            :escaped false
            :cur (str (.-cur st) ch)
            :tokens (.-tokens st))
          (if (= ch "\\")
              (ScanArgState
                :inQuote true
                :escaped true
                :cur (str (.-cur st) ch)
                :tokens (.-tokens st))
              (if (= ch "\"")
                  (ScanArgState
                    :inQuote false
                    :escaped false
                    :cur ""
                    :tokens (list-cons (.-cur st) (.-tokens st)))
                  (ScanArgState
                    :inQuote true
                    :escaped false
                    :cur (str (.-cur st) ch)
                    :tokens (.-tokens st)))))
      (if (= ch "\"")
          (ScanArgState
            :inQuote true
            :escaped false
            :cur ""
            :tokens (.-tokens st))
          st)))

(df extractCmdTokens [(s Str)] -> (List Str)
  :d "Extracts double-quoted string tokens from an ASN command string"
  (let [(finalSt (fold scanArgChar
                        (ScanArgState :inQuote false :escaped false :cur "" :tokens (list))
                        (string-chars s)))]
    (list-reverse (.-tokens finalSt))))

(df formatShArg [(arg Str)] -> Str
  :d "Formats an argument for shell command line, preserving quotes and escaping spaces if unquoted."
  (cond
    ((string-empty? arg) "''")
    ((or (and (string-starts-with? arg "\"") (string-ends-with? arg "\""))
         (and (string-starts-with? arg "'") (string-ends-with? arg "'")))
     arg)
    (true
     (esc/escapeShCompact arg))))

(df extractShLiteral [(s Str)] -> Str
  :d "Extracts raw shell command from (:sh ...) form, preserving inner quotes"
  (let [(firstQ (string-index-of s "\""))]
    (mt firstQ
      ((none) (string-trim (string-replace (string-replace s "(:sh" "") ")" "")))
      ((some q1)
       (let [(restS (option-or (string-slice s (+ q1 1) (string-length s)) ""))
             (revS (string-reverse restS))
             (revQ (string-index-of revS "\""))]
         (mt revQ
           ((none) (esc/unescapeAsnStr restS))
           ((some q2)
            (let [(len (- (string-length restS) (+ q2 1)))
                  (body (option-or (string-slice restS 0 len) ""))]
              (esc/unescapeAsnStr body)))))))))

(df transpileSingleCmd [(cmdStr Str)] -> Str
  :d "Transpiles a single (:cmd ...) or (:sh ...) form to a shell string"
  (let [(trimmed (string-trim cmdStr))]
    (cond
      ((string-starts-with? trimmed "(:sh")
       (extractShLiteral trimmed))
      ((string-starts-with? trimmed "(:cmd")
       (let [(toks (extractCmdTokens trimmed))]
         (if (list-empty? toks)
             ""
             (let [(formatted (list-map (fn [(tok Str)] -> Str
                                          (formatShArg (esc/unescapeAsnStr tok)))
                                        toks))]
               (string-join formatted " ")))))
      (true
       (let [(toks (extractCmdTokens trimmed))]
         (if (list-empty? toks)
             trimmed
             (let [(formatted (list-map (fn [(tok Str)] -> Str
                                          (formatShArg (esc/unescapeAsnStr tok)))
                                        toks))]
               (string-join formatted " "))))))))

(df asnToSh [(asnText Str)] -> ShTranspileResult
  :d "Transpiles ASN shell S-expressions to safe POSIX / Bash command strings."
  (let [(trimmed (string-trim asnText))]
    (cond
      ((string-empty? trimmed)
       (ShTranspileResult
         :output ""
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((not (or (string-starts-with? trimmed "(:") (string-starts-with? trimmed "(")))
       (ShTranspileResult
         :output "Syntax error: invalid ASN shell root (expected (:cmd, (:pipe, (:seq, (:script, or (:sh))"
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      ((string-starts-with? trimmed "(:sh")
       (let [(asnTok (txt/estimateTokens trimmed))
             (cleaned (extractShLiteral trimmed))
             (rawTok (txt/estimateTokens cleaned))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output cleaned
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true)))
      ((string-starts-with? trimmed "(:pipe")
       (let [(asnTok (txt/estimateTokens trimmed))
             (parts (string-split trimmed "(:cmd"))
             (cmdParts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiledCmds (list-map (fn [(p Str)] -> Str
                                          (transpileSingleCmd (str "(:cmd" p)))
                                        cmdParts))
             (cleaned (string-join transpiledCmds " | "))
             (rawTok (txt/estimateTokens cleaned))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output cleaned
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true)))
      ((string-starts-with? trimmed "(:script")
       (let [(asnTok (txt/estimateTokens trimmed))
             (isStrict (string-contains? trimmed ":strict true"))
             (parts (string-split trimmed "(:cmd"))
             (cmdParts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiledCmds (list-map (fn [(p Str)] -> Str
                                          (transpileSingleCmd (str "(:cmd" p)))
                                        cmdParts))
             (body (string-join transpiledCmds "\n"))
             (cleaned (if isStrict (str "set -euo pipefail\n" body) body))
             (rawTok (txt/estimateTokens cleaned))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output cleaned
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true)))
      ((string-starts-with? trimmed "(:seq")
       (let [(asnTok (txt/estimateTokens trimmed))
             (parts (string-split trimmed "(:cmd"))
             (cmdParts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiledCmds (list-map (fn [(p Str)] -> Str
                                          (transpileSingleCmd (str "(:cmd" p)))
                                        cmdParts))
             (cleaned (string-join transpiledCmds " && "))
             (rawTok (txt/estimateTokens cleaned))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output cleaned
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true)))
      (true
       (let [(asnTok (txt/estimateTokens trimmed))
             (cleaned (transpileSingleCmd trimmed))
             (rawTok (txt/estimateTokens cleaned))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output cleaned
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true))))))

(df shToAsn [(shText Str)] -> ShTranspileResult
  :d "Converts a simple shell command into a structured ASN (:cmd ...) expression."
  (let [(trimmed (string-trim shText))]
    (cond
      ((string-empty? trimmed)
       (ShTranspileResult
         :output ""
         :originalTokens 0
         :asnTokens 0
         :savingsPercent 0.0
         :success false))
      (true
       (let [(rawTok (txt/estimateTokens trimmed))
             (asnOut (s/concat (s/concat "(:cmd \"" trimmed) "\")"))
             (asnTok (txt/estimateTokens asnOut))
             (savings (txt/calcSavings rawTok asnTok))]
         (ShTranspileResult
           :output asnOut
           :originalTokens rawTok
           :asnTokens asnTok
           :savingsPercent savings
           :success true))))))

(df measureShSavings [(cmd Str)] -> F64
  :d "Measures token compaction achieved by converting a shell command to ASN."
  (let [(res (shToAsn cmd))]
    (.-savingsPercent res)))
