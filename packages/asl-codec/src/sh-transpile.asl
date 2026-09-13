(module asl-codec/sh-transpile
  :d "AgentScript Shell Command Codec: Bidirectional conversion between compact ASN S-expressions and safe POSIX/Bash scripts."
  :x [ShTranspileResult
      asn-to-sh
      sh-to-asn
      make-cmd
      make-pipe
      make-script
      measure-sh-savings]
  :i [(asl-text/string :a s)
      (asl-text/escape :a esc)
      (asl-text/text :a txt)])

(dfs ShTranspileResult
  (:f output Str "Transpiled shell command string or diagnostic message")
  (:f original-tokens I64 "Estimated token count in raw shell syntax")
  (:f asn-tokens I64 "Token count in compact ASN S-expression syntax")
  (:f savings-percent F64 "Token compaction percentage")
  (:f success Bool "True if transpilation succeeded"))

(df make-cmd [(bin Str) (args (List Str))] -> Str
  :d "Constructs an ASN command S-expression from binary name and argument list."
  (let [(args-str (fold (fn [(acc Str) (arg Str)] -> Str
                          (let [(quoted (s/concat (s/concat "\"" arg) "\""))]
                            (if (string-empty? acc)
                                quoted
                                (s/concat (s/concat acc " ") quoted))))
                        ""
                        args))]
    (s/concat (s/concat (s/concat "(:cmd \"" bin) "\" :args [") (s/concat args-str "])"))))

(df make-pipe [(stages (List Str))] -> Str
  :d "Constructs an ASN pipeline S-expression from a list of command expressions."
  (let [(stages-str (fold (fn [(acc Str) (stg Str)] -> Str
                            (if (string-empty? acc)
                                stg
                                (s/concat (s/concat acc " ") stg)))
                          ""
                          stages))]
    (s/concat (s/concat "(:pipe " stages-str) ")")))

(df make-script [(cmds (List Str)) (strict Bool)] -> Str
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
  (:f in-quote Bool "True if scanner is inside double-quoted string")
  (:f escaped Bool "True if previous character was backslash")
  (:f cur Str "Accumulated token characters")
  (:f tokens (List Str) "List of scanned tokens in reverse order"))

(df scan-arg-char [(st ScanArgState) (ch Str)] -> ScanArgState
  :d "Processes one character during argument token scanning"
  (if (.-in-quote st)
      (if (.-escaped st)
          (ScanArgState
            :in-quote true
            :escaped false
            :cur (str (.-cur st) ch)
            :tokens (.-tokens st))
          (if (= ch "\\")
              (ScanArgState
                :in-quote true
                :escaped true
                :cur (str (.-cur st) ch)
                :tokens (.-tokens st))
              (if (= ch "\"")
                  (ScanArgState
                    :in-quote false
                    :escaped false
                    :cur ""
                    :tokens (list-cons (.-cur st) (.-tokens st)))
                  (ScanArgState
                    :in-quote true
                    :escaped false
                    :cur (str (.-cur st) ch)
                    :tokens (.-tokens st)))))
      (if (= ch "\"")
          (ScanArgState
            :in-quote true
            :escaped false
            :cur ""
            :tokens (.-tokens st))
          st)))

(df extract-cmd-tokens [(s Str)] -> (List Str)
  :d "Extracts double-quoted string tokens from an ASN command string"
  (let [(final-st (fold scan-arg-char
                        (ScanArgState :in-quote false :escaped false :cur "" :tokens (list))
                        (string-chars s)))]
    (list-reverse (.-tokens final-st))))

(df format-sh-arg [(arg Str)] -> Str
  :d "Formats an argument for shell command line, preserving quotes and escaping spaces if unquoted."
  (cond
    ((string-empty? arg) "''")
    ((or (and (string-starts-with? arg "\"") (string-ends-with? arg "\""))
         (and (string-starts-with? arg "'") (string-ends-with? arg "'")))
     arg)
    (true
     (esc/escape-sh-compact arg))))

(df extract-sh-literal [(s Str)] -> Str
  :d "Extracts raw shell command from (:sh ...) form, preserving inner quotes"
  (let [(first-q (string-index-of s "\""))]
    (mt first-q
      ((none) (string-trim (string-replace (string-replace s "(:sh" "") ")" "")))
      ((some q1)
       (let [(rest-s (option-or (string-slice s (+ q1 1) (string-length s)) ""))
             (rev-s (string-reverse rest-s))
             (rev-q (string-index-of rev-s "\""))]
         (mt rev-q
           ((none) (esc/unescape-asn-str rest-s))
           ((some q2)
            (let [(len (- (string-length rest-s) (+ q2 1)))
                  (body (option-or (string-slice rest-s 0 len) ""))]
              (esc/unescape-asn-str body)))))))))

(df transpile-single-cmd [(cmd-str Str)] -> Str
  :d "Transpiles a single (:cmd ...) or (:sh ...) form to a shell string"
  (let [(trimmed (string-trim cmd-str))]
    (cond
      ((string-starts-with? trimmed "(:sh")
       (extract-sh-literal trimmed))
      ((string-starts-with? trimmed "(:cmd")
       (let [(toks (extract-cmd-tokens trimmed))]
         (if (list-empty? toks)
             ""
             (let [(formatted (list-map (fn [(tok Str)] -> Str
                                          (format-sh-arg (esc/unescape-asn-str tok)))
                                        toks))]
               (string-join formatted " ")))))
      (true
       (let [(toks (extract-cmd-tokens trimmed))]
         (if (list-empty? toks)
             trimmed
             (let [(formatted (list-map (fn [(tok Str)] -> Str
                                          (format-sh-arg (esc/unescape-asn-str tok)))
                                        toks))]
               (string-join formatted " "))))))))

(df asn-to-sh [(asn-text Str)] -> ShTranspileResult
  :d "Transpiles ASN shell S-expressions to safe POSIX / Bash command strings."
  (let [(trimmed (string-trim asn-text))]
    (cond
      ((string-empty? trimmed)
       (ShTranspileResult
         :output ""
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((not (or (string-starts-with? trimmed "(:") (string-starts-with? trimmed "(")))
       (ShTranspileResult
         :output "Syntax error: invalid ASN shell root (expected (:cmd, (:pipe, (:seq, (:script, or (:sh))"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      ((string-starts-with? trimmed "(:sh")
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (cleaned (extract-sh-literal trimmed))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output cleaned
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true)))
      ((string-starts-with? trimmed "(:pipe")
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (parts (string-split trimmed "(:cmd"))
             (cmd-parts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiled-cmds (list-map (fn [(p Str)] -> Str
                                          (transpile-single-cmd (str "(:cmd" p)))
                                        cmd-parts))
             (cleaned (string-join transpiled-cmds " | "))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output cleaned
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true)))
      ((string-starts-with? trimmed "(:script")
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (is-strict (string-contains? trimmed ":strict true"))
             (parts (string-split trimmed "(:cmd"))
             (cmd-parts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiled-cmds (list-map (fn [(p Str)] -> Str
                                          (transpile-single-cmd (str "(:cmd" p)))
                                        cmd-parts))
             (body (string-join transpiled-cmds "\n"))
             (cleaned (if is-strict (str "set -euo pipefail\n" body) body))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output cleaned
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true)))
      ((string-starts-with? trimmed "(:seq")
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (parts (string-split trimmed "(:cmd"))
             (cmd-parts (filter (fn [(p Str)] -> Bool (string-contains? p "\"")) parts))
             (transpiled-cmds (list-map (fn [(p Str)] -> Str
                                          (transpile-single-cmd (str "(:cmd" p)))
                                        cmd-parts))
             (cleaned (string-join transpiled-cmds " && "))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output cleaned
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true)))
      (true
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (cleaned (transpile-single-cmd trimmed))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output cleaned
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true))))))

(df sh-to-asn [(sh-text Str)] -> ShTranspileResult
  :d "Converts a simple shell command into a structured ASN (:cmd ...) expression."
  (let [(trimmed (string-trim sh-text))]
    (cond
      ((string-empty? trimmed)
       (ShTranspileResult
         :output ""
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (true
       (let [(raw-tok (txt/estimate-tokens trimmed))
             (asn-out (s/concat (s/concat "(:cmd \"" trimmed) "\")"))
             (asn-tok (txt/estimate-tokens asn-out))
             (savings (txt/calc-savings raw-tok asn-tok))]
         (ShTranspileResult
           :output asn-out
           :original-tokens raw-tok
           :asn-tokens asn-tok
           :savings-percent savings
           :success true))))))

(df measure-sh-savings [(cmd Str)] -> F64
  :d "Measures token compaction achieved by converting a shell command to ASN."
  (let [(res (sh-to-asn cmd))]
    (.-savings-percent res)))
