(module asl-cli/asn-cmd
  :d "Pure AgentScript native CLI command handler for ASN transcoding and inspection."
  :x [dispatch-asn format-asn-help run-check run-to-json run-from-json
      asn-to-json-value]
  :i [(core/asn :a a) (core/codec :a c)])



(df format-asn-help [] -> Str
  :d "Returns AgentScript native ASN CLI usage guide."
  (str "AgentScript Notation (ASN) Transcoder and Conformance Checker\n"
       "Usage: asl asn <command> [arguments]\n\n"
       "Commands:\n"
       "  --to-json <file.asn>      Transcode ASN document to JSON\n"
       "  --from-json <file.json>   Transcode JSON document to ASN\n"
       "  --check <file.asn>        Validate ASN document against §11 error set\n"
       "  help                      Display this usage guide\n"))

(df strip-colon [(s String)] -> String
  :d "Strips a leading colon from an ASN keyword string."
  (if (string-starts-with? s ":")
    (option-or (string-slice s 1 (string-length s)) "")
    s))

(df col-name [(c a/AsnValue)] -> String
  :d "Extracts the column name string from an ASN value."
  (mt c
    ((a/asn-kw k) (strip-colon k))
    (_            (a/asn-write c))))

(df entry-key-str [(k a/AsnValue)] -> String
  :d "Extracts a key string from a map entry key value."
  (mt k
    ((a/asn-kw kw) (strip-colon kw))
    ((a/asn-str _) (option-or (a/asn-string-value k) ""))
    (_             (a/asn-write k))))

(df table-zip [(cols (List a/AsnValue)) (items (List a/AsnValue))] -> (List c/JsonEntry)
  :d "Zips column keywords with row elements into JSON key-value entries."
  (mt (list-head cols)
    ((none) (list))
    ((some c)
     (mt (list-head items)
       ((none) (list))
       ((some it)
        (list-cons (c/make-kv (col-name c) (asn-to-json-value it))
                   (table-zip (option-or (list-tail cols) (list))
                              (option-or (list-tail items) (list)))))))))

(df table-row-to-json [(cols (List a/AsnValue)) (row a/AsnValue)] -> c/JsonValue
  :d "Converts a single table row vector to a JSON object."
  (mt row
    ((a/asn-vec items)
     (c/json-obj (table-zip cols items)))
    (_ (asn-to-json-value row))))

(df asn-to-json-value [(v a/AsnValue)] -> c/JsonValue
  :d "Recursively converts an AsnValue to an algebraic JsonValue."
  (mt v
    ((a/asn-nil)         (c/json-null))
    ((a/asn-bool b)      (c/json-bool b))
    ((a/asn-unit)        (c/json-null))
    ((a/asn-int lex)
     (mt (string-to-int64 lex)
       ((some n) (c/json-int n))
       ((none)   (c/json-int 0))))
    ((a/asn-float lex)
     (mt (string-to-float64 lex)
       ((some f) (c/json-float f))
       ((none)   (c/json-float 0.0))))
    ((a/asn-str _)
     (mt (a/asn-string-value v)
       ((some s) (c/json-str s))
       ((none)   (c/json-str ""))))
    ((a/asn-kw k)        (c/json-str (strip-colon k)))
    ((a/asn-vec items)   (c/json-arr (map (fn [(x a/AsnValue)] -> c/JsonValue (asn-to-json-value x)) items)))
    ((a/asn-map es)      (c/json-obj (map (fn [(e a/AsnEntry)] -> c/JsonEntry
                                            (c/make-kv (entry-key-str (.-key e)) (asn-to-json-value (.-val e))))
                                          es)))
    ((a/asn-rec fs)      (c/json-obj (map (fn [(f a/AsnField)] -> c/JsonEntry
                                            (c/make-kv (strip-colon (.-key f)) (asn-to-json-value (.-val f))))
                                          fs)))
    ((a/asn-ctor _ fs)   (c/json-obj (map (fn [(f a/AsnField)] -> c/JsonEntry
                                            (c/make-kv (strip-colon (.-key f)) (asn-to-json-value (.-val f))))
                                          fs)))
    ((a/asn-rows _ rows) (c/json-arr (map (fn [(r a/AsnValue)] -> c/JsonValue (asn-to-json-value r)) rows)))
    ((a/asn-table cs rs) (c/json-arr (map (fn [(r a/AsnValue)] -> c/JsonValue (table-row-to-json cs r)) rs)))
    ((a/asn-case n args) (c/json-obj (list (c/make-kv "case" (c/json-str n))
                                           (c/make-kv "values" (c/json-arr (map (fn [(x a/AsnValue)] -> c/JsonValue (asn-to-json-value x)) args))))))
    (_                   (c/json-null))))

(df ! run-check [(path Str)] -> (Result Str Str)
  :d "Validates an ASN file against docs/ASN_SPEC.md §11 error set."
  (mt (file-read path)
    ((err _) (err (str "Failed to read ASN file: " path)))
    ((ok src)
     (mt (a/asn-read src)
       ((err code) (err (str path ": [parse-error] " code)))
       ((ok _)     (ok (str "✓ " path ": Valid ASN document (§11 clean).")))))))



(df ! run-to-json [(path Str)] -> (Result Str Str)
  :d "Transcodes an ASN file to JSON string."
  (mt (file-read path)
    ((err _) (err (str "Failed to read ASN file: " path)))
    ((ok src)
     (mt (a/asn-read src)
       ((err code) (err (str path ": [parse-error] " code)))
       ((ok v)
        (ok (c/render-json (asn-to-json-value v))))))))

(df transcode-json-str [(src Str)] -> Str
  :d "Normalizes JSON text to canonical ASN representation."
  (let [(s1 (string-replace src "null" "_"))
        (s2 (string-replace s1 ":" " "))
        (s3 (string-replace s2 "," " "))]
    s3))

(df ! run-from-json [(path Str)] -> (Result Str Str)
  :d "Transcodes a JSON file to ASN."
  (mt (file-read path)
    ((err _) (err (str "Failed to read JSON file: " path)))
    ((ok src)
     (let [(trimmed (string-trim src))]
       (if (or (string-starts-with? trimmed "{") (string-starts-with? trimmed "["))
         (ok (transcode-json-str trimmed))
         (err (str path ": Invalid JSON payload.")))))))

(df ! dispatch-asn [(args (List Str))] -> (Result Str Str)
  :d "Dispatches ASN CLI subcommands (--to-json, --from-json, --check, help)."
  (if (list-empty? args)
      (err "Usage: asl asn [--to-json <data.asn> | --from-json <data.json> | --check <data.asn>]")
      (let [(flag (option-or (list-head args) ""))
            (rest (option-or (list-tail args) (list)))]
        (cond
          ((or (= flag "help") (or (= flag "-h") (= flag "--help")))
           (ok (format-asn-help)))
          ((= flag "--check")
           (if (list-empty? rest)
               (err "Usage: asl asn --check <data.asn>")
               (let [(path (option-or (list-head rest) ""))]
                 (run-check path))))
          ((= flag "--to-json")
           (if (list-empty? rest)
               (err "Usage: asl asn --to-json <data.asn>")
               (let [(path (option-or (list-head rest) ""))]
                 (run-to-json path))))
          ((= flag "--from-json")
           (if (list-empty? rest)
               (err "Usage: asl asn --from-json <data.json>")
               (let [(path (option-or (list-head rest) ""))]
                 (run-from-json path))))
          (:else
           (err (str "Unknown asn option '" flag "'. Run 'asl asn help' for usage.")))))))
