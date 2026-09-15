(module asl-text/escape
  :d "Canonical Pure AgentScript String Escaping and Wire Serialization Engine."
  :x [UnescapeState escapeAsnStr unescapeAsnStr escapeJsonStr unescapeJsonStr escapeShArg isShSafeArg escapeShCompact])

(dfs UnescapeState
  (:f out Str "Accumulated unescaped string buffer")
  (:f esc Bool "True if previous character was escape backslash"))

(df unescapeStringScanner [(s Str)] -> Str
  :d "Single-pass character scanner for unambiguous string unescaping."
  (let [(chars (string-chars s))
        (init (UnescapeState :out "" :esc false))
        (st (fold (fn [(acc UnescapeState) (c Str)] -> UnescapeState
                    (if (.-esc acc)
                      (let [(emitted (cond
                                       ((= c "n") "\n")
                                       ((= c "r") "\r")
                                       ((= c "t") "\t")
                                       ((= c "\"") "\"")
                                       ((= c "\\") "\\")
                                       (:else (str "\\" c))))]
                        (UnescapeState :out (str (.-out acc) emitted) :esc false))
                      (if (= c "\\")
                        (UnescapeState :out (.-out acc) :esc true)
                        (UnescapeState :out (str (.-out acc) c) :esc false))))
                  init
                  chars))]
    (if (.-esc st)
      (str (.-out st) "\\")
      (.-out st))))

(df escapeAsnStr [(s Str)] -> Str
  :d "Escapes backslashes, double quotes, and control characters for ASN literals."
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))
        (s3 (string-replace s2 "\n" "\\n"))
        (s4 (string-replace s3 "\r" "\\r"))]
    (string-replace s4 "\t" "\\t")))

(df unescapeAsnStr [(s Str)] -> Str
  :d "Inverts ASN string escaping via single-pass scanner preventing premature control code substitution."
  (unescapeStringScanner s))

(df escapeJsonStr [(s Str)] -> Str
  :d "Escapes backslashes, double quotes, and control characters for RFC 8259 JSON literals."
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))
        (s3 (string-replace s2 "\n" "\\n"))
        (s4 (string-replace s3 "\r" "\\r"))
        (s5 (string-replace s4 "\b" "\\b"))
        (s6 (string-replace s5 "\f" "\\f"))]
    (string-replace s6 "\t" "\\t")))

(df unescapeJsonStr [(s Str)] -> Str
  :d "Inverts JSON string escaping via single-pass scanner preventing premature control code substitution."
  (unescapeStringScanner s))

(df escapeShArg [(arg Str)] -> Str
  :d "Wraps an argument in POSIX single quotes escaping interior single quotes."
  (if (string-empty? arg)
    "''"
    (if (not (string-contains? arg "'"))
      (str "'" arg "'")
      (let [(escaped (string-replace arg "'" "'\\''"))]
        (str "'" escaped "'")))))

(df isShSafeArg [(arg Str)] -> Bool
  :d "Returns true if argument contains only safe shell characters requiring no quotes."
  (let [(trimmed (string-trim arg))]
    (if (string-empty? trimmed)
      false
      (and (not (string-contains? trimmed " "))
           (and (not (string-contains? trimmed "\""))
                (and (not (string-contains? trimmed "'"))
                     (and (not (string-contains? trimmed "$"))
                          (and (not (string-contains? trimmed "`"))
                               (and (not (string-contains? trimmed "\\"))
                                    (and (not (string-contains? trimmed ";"))
                                         (and (not (string-contains? trimmed "&"))
                                              (and (not (string-contains? trimmed "|"))
                                                   (and (not (string-contains? trimmed ">"))
                                                        (and (not (string-contains? trimmed "<"))
                                                             (and (not (string-contains? trimmed "("))
                                                                  (and (not (string-contains? trimmed ")"))
                                                                       (and (not (string-contains? trimmed "*"))
                                                                            (and (not (string-contains? trimmed "?"))
                                                                                 (and (not (string-contains? trimmed "~"))
                                                                                      (not (string-contains? trimmed "!")))))))))))))))))))))

(df escapeShCompact [(arg Str)] -> Str
  :d "Escapes shell argument, omitting quotes when argument contains only safe characters."
  (let [(trimmed (string-trim arg))]
    (if (isShSafeArg trimmed)
      trimmed
      (escapeShArg trimmed))))
