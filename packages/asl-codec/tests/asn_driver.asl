(module asl-codec/asn-driver
  :d "Driver for the ASN reader, writer and checker. Every entry answers with text
      a test can compare against a value written by hand."
  :x [canon shape kinds verdict idem decoded-field]
  :i [(asn :a a) (asn-check :a c)])

(df canon [(src String)] -> String
  :d "The canonical text of a document, or `!code` when it will not read."
  (mt (a/asn-read src)
    ((ok v)   (a/asn-write v))
    ((err co) (str "!" co))))

(df idem [(src String)] -> Bool
  :d "Reading canonical text and writing it back is a fixed point. This is the
      round-trip property stated without reference to the source formatting: the
      first write normalises whitespace, and every write after it changes nothing."
  (let [(once (canon src))]
    (= (canon once) once)))

(df shape-of [(v a/AsnValue)] -> String
  :d "A value's kind and arity, as text."
  (mt v
    ((a/asn-nil)         "nil")
    ((a/asn-bool _)      "bool")
    ((a/asn-unit)        "unit")
    ((a/asn-int _)       "int")
    ((a/asn-float _)     "float")
    ((a/asn-str _)       "str")
    ((a/asn-kw _)        "kw")
    ((a/asn-sym _)       "sym")
    ((a/asn-pair _ _)    "pair")
    ((a/asn-vec items)   (str "vec/" (string-from-int64 (list-length items))))
    ((a/asn-map es)      (str "map/" (string-from-int64 (list-length es))))
    ((a/asn-rec fs)      (str "rec/" (string-from-int64 (list-length fs))))
    ((a/asn-ctor n fs)   (str "ctor " n "/" (string-from-int64 (list-length fs))))
    ((a/asn-rows n rows) (str "rows " n "/" (string-from-int64 (list-length rows))))
    ((a/asn-case n args) (str "case " n "/" (string-from-int64 (list-length args))))
    ((a/asn-table cs rs) (str "table/" (string-from-int64 (list-length cs))
                              "x" (string-from-int64 (list-length rs))))))

(df shape [(src String)] -> String
  :d "The top-level value's kind and arity, or `!code`."
  (mt (a/asn-read src)
    ((ok v)   (shape-of v))
    ((err co) (str "!" co))))

(df kinds [(src String)] -> String
  :d "The kind of every element of a vector document, joined by `|`. This is what
      distinguishes a scalar the reader classified from one it merely echoed."
  (mt (a/asn-read src)
    ((ok v)   (string-join (map (fn [(x a/AsnValue)] -> String (shape-of x))
                                (a/vec-items v)) "|"))
    ((err co) (str "!" co))))

(df verdict [(src String)] -> String
  :d "The conformance codes a document raises, in report order, or `!code` when
      it will not read at all."
  (mt (a/asn-read src)
    ((ok v)   (c/diag-codes (c/asn-check v)))
    ((err co) (str "!" co))))

(df decoded-field [(src String) (key String)] -> String
  :d "The decoded characters of a named string field of a record document, which
      is what proves the reader keeps a lexeme AND can still hand back its value."
  (mt (a/asn-read src)
    ((ok v)   (field-text v key))
    ((err co) (str "!" co))))

(df field-text [(v a/AsnValue) (key String)] -> String
  :d "The decoded string at a record's named field, or the empty string."
  (mt v
    ((a/asn-rec fs)
     (mt (list-head (filter (fn [(f a/AsnField)] -> Bool (= (.-key f) key)) fs))
       ((some f) (mt (a/asn-string-value (.-val f))
                   ((some s) s)
                   ((none)   "")))
       ((none) "")))
    (_ "")))
