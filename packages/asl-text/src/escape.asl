(module asl-text/escape
  :d "Canonical Pure AgentScript String Escaping and Wire Serialization Engine."
  :x [escape-asn-str unescape-asn-str escape-json-str unescape-json-str escape-sh-arg is-sh-safe-arg escape-sh-compact])

(df escape-asn-str [(s Str)] -> Str
  :d "Escapes backslashes, double quotes, and control characters for ASN literals."
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))
        (s3 (string-replace s2 "\n" "\\n"))
        (s4 (string-replace s3 "\r" "\\r"))]
    (string-replace s4 "\t" "\\t")))

(df unescape-asn-str [(s Str)] -> Str
  :d "Inverts ASN string escaping."
  (let [(s1 (string-replace s "\\n" "\n"))
        (s2 (string-replace s1 "\\r" "\r"))
        (s3 (string-replace s2 "\\t" "\t"))
        (s4 (string-replace s3 "\\\"" "\""))]
    (string-replace s4 "\\\\" "\\")))

(df escape-json-str [(s Str)] -> Str
  :d "Escapes backslashes, double quotes, and control characters for RFC 8259 JSON literals."
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))
        (s3 (string-replace s2 "\n" "\\n"))
        (s4 (string-replace s3 "\r" "\\r"))]
    (string-replace s4 "\t" "\\t")))

(df unescape-json-str [(s Str)] -> Str
  :d "Inverts JSON string escaping."
  (let [(s1 (string-replace s "\\n" "\n"))
        (s2 (string-replace s1 "\\r" "\r"))
        (s3 (string-replace s2 "\\t" "\t"))
        (s4 (string-replace s3 "\\\"" "\""))]
    (string-replace s4 "\\\\" "\\")))

(df escape-sh-arg [(arg Str)] -> Str
  :d "Wraps an argument in POSIX single quotes escaping interior single quotes."
  (if (string-empty? arg)
    "''"
    (if (not (string-contains? arg "'"))
      (str "'" arg "'")
      (let [(escaped (string-replace arg "'" "'\\''"))]
        (str "'" escaped "'")))))

(df is-sh-safe-arg [(arg Str)] -> Bool
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

(df escape-sh-compact [(arg Str)] -> Str
  :d "Escapes shell argument, omitting quotes when argument contains only safe characters."
  (let [(trimmed (string-trim arg))]
    (if (is-sh-safe-arg trimmed)
      trimmed
      (escape-sh-arg trimmed))))
