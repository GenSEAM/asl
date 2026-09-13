(module asl-codec/asnDriver
  :d "Driver for the ASN reader, writer and checker. Every entry answers with text
      a test can compare against a value written by hand."
  :x [canon shape kinds verdict idem decodedField]
  :i [(asn :a a) (asnCheck :a c)])

(df canon [(src String)] -> String
  :d "The canonical text of a document, or `!code` when it will not read."
  (mt (a/asnRead src)
    ((ok v)   (a/asnWrite v))
    ((err co) (str "!" co))))

(df idem [(src String)] -> Bool
  :d "Reading canonical text and writing it back is a fixed point. This is the
      round-trip property stated without reference to the source formatting: the
      first write normalises whitespace, and every write after it changes nothing."
  (let [(once (canon src))]
    (= (canon once) once)))

(df shapeOf [(v a/AsnValue)] -> String
  :d "A value's kind and arity, as text."
  (mt v
    ((a/asnNil)         "nil")
    ((a/asnBool _)      "bool")
    ((a/asnUnit)        "unit")
    ((a/asnInt _)       "int")
    ((a/asnFloat _)     "float")
    ((a/asnStr _)       "str")
    ((a/asnKw _)        "kw")
    ((a/asnSym _)       "sym")
    ((a/asnPair _ _)    "pair")
    ((a/asnVec items)   (str "vec/" (string-from-int64 (list-length items))))
    ((a/asnMap es)      (str "map/" (string-from-int64 (list-length es))))
    ((a/asnRec fs)      (str "rec/" (string-from-int64 (list-length fs))))
    ((a/asnCtor n fs)   (str "ctor " n "/" (string-from-int64 (list-length fs))))
    ((a/asnRows n rows) (str "rows " n "/" (string-from-int64 (list-length rows))))
    ((a/asnCase n args) (str "case " n "/" (string-from-int64 (list-length args))))
    ((a/asnTable cs rs) (str "table/" (string-from-int64 (list-length cs))
                              "x" (string-from-int64 (list-length rs))))))

(df shape [(src String)] -> String
  :d "The top-level value's kind and arity, or `!code`."
  (mt (a/asnRead src)
    ((ok v)   (shapeOf v))
    ((err co) (str "!" co))))

(df kinds [(src String)] -> String
  :d "The kind of every element of a vector document, joined by `|`. This is what
      distinguishes a scalar the reader classified from one it merely echoed."
  (mt (a/asnRead src)
    ((ok v)   (string-join (map (fn [(x a/AsnValue)] -> String (shapeOf x))
                                (a/vecItems v)) "|"))
    ((err co) (str "!" co))))

(df verdict [(src String)] -> String
  :d "The conformance codes a document raises, in report order, or `!code` when
      it will not read at all."
  (mt (a/asnRead src)
    ((ok v)   (c/diagCodes (c/asnCheck v)))
    ((err co) (str "!" co))))

(df decodedField [(src String) (key String)] -> String
  :d "The decoded characters of a named string field of a record document, which
      is what proves the reader keeps a lexeme AND can still hand back its value."
  (mt (a/asnRead src)
    ((ok v)   (fieldText v key))
    ((err co) (str "!" co))))

(df fieldText [(v a/AsnValue) (key String)] -> String
  :d "The decoded string at a record's named field, or the empty string."
  (mt v
    ((a/asnRec fs)
     (mt (list-head (filter (fn [(f a/AsnField)] -> Bool (= (.-key f) key)) fs))
       ((some f) (mt (a/asnStringValue (.-val f))
                   ((some s) s)
                   ((none)   "")))
       ((none) "")))
    (_ "")))
