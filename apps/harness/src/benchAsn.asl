(module aslHarness/benchAsn
  :x [AsnValue parse parseFile!]
  :i [])

enum AsnValue
  (asnList items: (List AsnValue))
  (asnString value: String)
  (asnAtom value: String)

schema Parsed
  (:f value AsnValue)
  (:f next Int64)

fn charAt source: String pos: Int64 -> String
  (optionOr (stringSlice source pos (+ pos 1)) "")

fn whitespace? c: String -> Bool
  (or (= c " ") (or (= c "\n") (or (= c "\r") (= c "\t"))))

fn skipSpace source: String pos: Int64 -> Int64
  (let [(n (stringLength source))
        (c (charAt source pos))]
    (if (>= pos n)
      pos
      (if (whitespace? c)
        (skipSpace source (+ pos 1))
        (if (= c ";")
          (skipSpace source (skipComment source (+ pos 1)))
          pos))))

fn skipComment source: String pos: Int64 -> Int64
  (let [(n (stringLength source))
        (c (charAt source pos))]
    (if (or (>= pos n) (or (= c "\n") (= c "\r")))
      pos
      (skipComment source (+ pos 1))))

fn parseStringAt source: String pos: Int64 -> (Result Parsed String)
  (parseStringLoop source (+ pos 1) "")

fn parseStringLoop source: String pos: Int64 value: String -> (Result Parsed String)
  (let [(n (stringLength source))
        (c (charAt source pos))]
    (if (>= pos n)
      (err "unterminated ASN string")
      (if (= c "\"")
        (ok (Parsed :value (asnString value) :next (+ pos 1)))
        (if (= c "\\")
          (parseEscape source (+ pos 1) value)
          (parseStringLoop source (+ pos 1) (stringConcat value c))))))

fn parseEscape source: String pos: Int64 value: String -> (Result Parsed String)
  (let [(n (stringLength source))
        (c (charAt source pos))]
    (if (>= pos n)
      (err "unterminated ASN escape")
      (cond
        ((= c "\"") (parseStringLoop source (+ pos 1) (stringConcat value "\"")))
        ((= c "\\") (parseStringLoop source (+ pos 1) (stringConcat value "\\")))
        ((= c "n") (parseStringLoop source (+ pos 1) (stringConcat value "\n")))
        ((= c "r") (parseStringLoop source (+ pos 1) (stringConcat value "\r")))
        ((= c "t") (parseStringLoop source (+ pos 1) (stringConcat value "\t")))
        (else (err (stringConcat "unsupported ASN escape: \\" c))))))

fn parseAtomAt source: String pos: Int64 -> (Result Parsed String)
  (parseAtomLoop source pos pos)

fn parseAtomLoop source: String start: Int64 pos: Int64 -> (Result Parsed String)
  (let [(n (stringLength source))
        (c (charAt source pos))]
    (if (or (>= pos n) (or (whitespace? c) (or (= c "(") (or (= c ")") (= c ";")))))
      (if (= start pos)
        (err "expected ASN atom")
        (ok (Parsed :value (asnAtom (optionOr (stringSlice source start pos) "")) :next pos)))
      (parseAtomLoop source start (+ pos 1))))

fn parseList source: String pos: Int64 -> (Result Parsed String)
  (parseListLoop source (+ pos 1) (list))

fn parseListLoop source: String pos: Int64 revItems: (List AsnValue) -> (Result Parsed String)
  (let [(at (skipSpace source pos))
        (n (stringLength source))
        (c (charAt source at))]
    (if (>= at n)
      (err "unterminated ASN list")
      (if (= c ")")
        (ok (Parsed :value (asnList revItems) :next (+ at 1)))
        (mt (parseAt source at)
          ((ok parsed) (parseListLoop source parsed.next (listAppend revItems (list parsed.value))))
          ((err message) (err message))))))

fn parseAt source: String pos: Int64 -> (Result Parsed String)
  (let [(at (skipSpace source pos))
        (n (stringLength source))
        (c (charAt source at))]
    (if (>= at n)
      (err "expected ASN form")
      (cond
        ((= c "(") (parseList source at))
        ((= c "\"") (parseStringAt source at))
        ((= c ")") (err "unexpected closing parenthesis"))
        (else (parseAtomAt source at)))))

fn parse source: String -> (Result AsnValue String)
  (mt (parseAt source 0)
    ((ok parsed)
      (let [(tail (skipSpace source parsed.next))]
        (if (= tail (stringLength source))
          (ok parsed.value)
          (err "trailing data after ASN form"))))
    ((err message) (err message)))

fn parseFile! path: String -> (Result AsnValue String)
  (mt (fileReadString path)
    ((ok contents) (parse contents))
    ((err message) (err message)))
