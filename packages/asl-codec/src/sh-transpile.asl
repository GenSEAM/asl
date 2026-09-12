(module asl-codec/sh-transpile
  :d "AgentScript Shell Command Codec: Bidirectional conversion between compact ASN S-expressions and safe POSIX/Bash scripts."
  :x [ShTranspileResult
      escape-sh-arg
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

(df calc-savings [(orig I64) (asn I64)] -> F64
  :d "Calculates token savings percentage."
  (if (<= orig 0)
      0.0
      (let [(diff (- orig asn))]
        (if (<= diff 0)
            0.0
            (/ (* (float-from-int64 diff) 100.0) (float-from-int64 orig))))))

(df escape-sh-arg [(arg Str)] -> Str
  :d "Safely escapes an argument string for POSIX shell using canonical asl-text/escape."
  (esc/escape-sh-compact arg))

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
      ((not (string-starts-with? trimmed "(:"))
       (ShTranspileResult
         :output "Syntax error: invalid ASN shell root (expected (:cmd, (:pipe, (:seq, or (:script))"
         :original-tokens 0
         :asn-tokens 0
         :savings-percent 0.0
         :success false))
      (true
       (let [(asn-tok (txt/estimate-tokens trimmed))
             (s1 (string-replace trimmed "(:pipe" ""))
             (s2 (string-replace s1 "(:seq" ""))
             (s3 (string-replace s2 "(:cmd" ""))
             (s4 (string-replace s3 ":args [" ""))
             (s5 (string-replace s4 ":args" ""))
             (s6 (string-replace s5 "]" ""))
             (s7 (string-replace s6 "\"" ""))
             (s8 (string-replace s7 ")" ""))
             (s9 (if (string-contains? trimmed ":strict true")
                     (s/concat "set -euo pipefail\n" (string-trim (string-replace s8 ":script :strict true" "")))
                     s8))
             (cleaned (string-trim s9))
             (raw-tok (txt/estimate-tokens cleaned))
             (savings (calc-savings raw-tok asn-tok))]
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
             (savings (calc-savings raw-tok asn-tok))]
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
