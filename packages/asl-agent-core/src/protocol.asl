(module asl-agent-core/protocol
  :d "Compact S-expression tool calling protocol and parser for AgentScript."
  :x [ToolParam ToolDef ToolArg ToolInvocation ToolResult
      format-tool-param format-tool-def format-invocation format-result
      get-arg-value strip-quotes parse-tokens parse-invocation]
  :i [])

(dfs ToolParam
  (:f name Str "Parameter identifier without leading colon")
  (:f param-type Str "Type name e.g. Str, I64, F64, Bool")
  (:f required Bool "True if this parameter must be present")
  (:f doc Str "Documentation string for parameter"))

(dfs ToolDef
  (:f name Str "Tool identifier")
  (:f doc Str "Tool documentation description")
  (:f params (List ToolParam) "List of accepted parameters"))

(dfs ToolArg
  (:f key Str "Argument key without leading colon")
  (:f val Str "Argument string value"))

(dfs ToolInvocation
  (:f tool-name Str "Target tool identifier")
  (:f args (List ToolArg) "List of passed argument key-value pairs")
  (:f raw-call Str "Original raw S-expression call string"))

(dfs ToolResult
  (:f tool-name Str "Identifier of invoked tool")
  (:f success Bool "True if tool completed without error")
  (:f output Str "Output payload on success")
  (:f error-msg Str "Error message on failure"))

(dfs TokenizerState
  (:f tokens (List Str) "Accumulated reversed token list")
  (:f current-buf Str "Buffer for current token")
  (:f in-quote Bool "True if inside quotation marks"))

(df format-tool-param [(p ToolParam)] -> Str
  :d "Formats a single tool parameter definition into compact ASL notation."
  (let [(req-marker (if (.-required p) "!" ""))]
    (str ":" (.-name p) req-marker " " (.-param-type p))))

(df format-tool-def [(d ToolDef)] -> Str
  :d "Formats a ToolDef into a compact S-expression specification."
  (let [(params-str (string-join (map (fn [(p ToolParam)] -> Str (format-tool-param p)) (.-params d)) " "))]
    (str "(tool :" (.-name d) " :d "" (.-doc d) "" [" params-str "])")))

(df format-invocation [(inv ToolInvocation)] -> Str
  :d "Formats a ToolInvocation into a canonical S-expression string."
  (let [(args-str (string-join (map (fn [(a ToolArg)] -> Str
                                      (str ":" (.-key a) " "" (.-val a) """))
                                    (.-args inv)) " "))]
    (if (string-empty? args-str)
        (str "(call :tool " (.-tool-name inv) ")")
        (str "(call :tool " (.-tool-name inv) " " args-str ")"))))

(df format-result [(res ToolResult)] -> Str
  :d "Formats ToolResult into compact ASL S-expression."
  (if (.-success res)
      (str "(result :tool " (.-tool-name res) " :ok true :out "" (.-output res) "")")
      (str "(result :tool " (.-tool-name res) " :ok false :err "" (.-error-msg res) "")")))

(df get-arg-value [(args (List ToolArg)) (key Str)] -> (Option Str)
  :d "Finds argument value by key in argument list."
  (let [(matches (filter (fn [(a ToolArg)] -> Bool (= (.-key a) key)) args))]
    (mt (list-head matches)
      ((none) (none))
      ((some matched) (some (.-val matched))))))

(df strip-quotes [(s Str)] -> Str
  :d "Strips enclosing double quotes from a token if present."
  (if (and (string-starts-with? s "\"") (string-ends-with? s "\""))
      (if (> (string-length s) 1)
          (option-or (string-slice s 1 (- (string-length s) 1)) "")
          s)
      s))

(df tokenize-chars [(chars (List Str)) (state TokenizerState)] -> (List Str)
  :d "Walks characters folding into token list respecting quotes."
  (let [(final-state
         (fold (fn [(st TokenizerState) (c Str)] -> TokenizerState
                 (cond
                   ((= c "\"")
                    (TokenizerState
                      :tokens (.-tokens st)
                      :current-buf (str (.-current-buf st) c)
                      :in-quote (not (.-in-quote st))))
                   ((and (not (.-in-quote st)) (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r")))))
                    (if (string-empty? (.-current-buf st))
                        st
                        (TokenizerState
                          :tokens (list-cons (.-current-buf st) (.-tokens st))
                          :current-buf ""
                          :in-quote false)))
                   (:else
                    (TokenizerState
                      :tokens (.-tokens st)
                      :current-buf (str (.-current-buf st) c)
                      :in-quote (.-in-quote st)))))
               state
               chars))]
    (let [(all-rev (if (string-empty? (.-current-buf final-state))
                       (.-tokens final-state)
                       (list-cons (.-current-buf final-state) (.-tokens final-state))))]
      (list-reverse all-rev))))

(df parse-tokens [(s Str)] -> (List Str)
  :d "Tokenizes an S-expression string into tokens preserving quoted strings."
  (let [(trimmed (string-trim s))
        (no-open (if (string-starts-with? trimmed "(")
                     (option-or (string-slice trimmed 1 (string-length trimmed)) trimmed)
                     trimmed))
        (no-close (if (string-ends-with? no-open ")")
                      (option-or (string-slice no-open 0 (- (string-length no-open) 1)) no-open)
                      no-open))
        (init-state (TokenizerState :tokens (list) :current-buf "" :in-quote false))]
    (tokenize-chars (string-chars no-close) init-state)))

(df parse-arg-pairs [(tokens (List Str))] -> (List ToolArg)
  :d "Recursively parses remaining tokens into ToolArg records."
  (mt (list-head tokens)
    ((none) (list))
    ((some key-token)
     (mt (list-tail tokens)
       ((none) (list))
       ((some tail1)
        (mt (list-head tail1)
          ((none) (list))
          ((some val-token)
           (let [(rest-tokens (option-or (list-tail tail1) (list)))
                 (clean-key (if (string-starts-with? key-token ":")
                                (option-or (string-slice key-token 1 (string-length key-token)) key-token)
                                key-token))
                 (clean-val (strip-quotes val-token))
                 (arg (ToolArg :key clean-key :val clean-val))]
             (list-cons arg (parse-arg-pairs rest-tokens))))))))))

(df parse-invocation [(raw Str)] -> (Result ToolInvocation Str)
  :d "Parses a raw S-expression string like (call :tool search :q \"query\") into ToolInvocation."
  (let [(tokens (parse-tokens raw))]
    (mt (list-head tokens)
      ((none) (err "Empty tool invocation"))
      ((some head-token)
       (let [(remaining (if (= head-token "call")
                            (option-or (list-tail tokens) (list))
                            tokens))]
         (mt (list-head remaining)
           ((none) (err "Missing tool name in invocation"))
           ((some first-tok)
            (let [(parsed-pair
                   (if (= first-tok ":tool")
                       (mt (list-tail remaining)
                         ((none) (err "Missing tool identifier after :tool"))
                         ((some t-tail)
                          (mt (list-head t-tail)
                            ((none) (err "Missing tool identifier after :tool"))
                            ((some name-tok)
                             (ok (pair name-tok (option-or (list-tail t-tail) (list))))))))
                       (ok (pair first-tok (option-or (list-tail remaining) (list))))))]
              (mt parsed-pair
                ((err e) (err e))
                ((ok p)
                 (let [(tool-name (.-first p))
                       (arg-tokens (.-second p))
                       (args (parse-arg-pairs arg-tokens))]
                   (ok (ToolInvocation
                         :tool-name tool-name
                         :args args
                         :raw-call raw)))))))))))))
