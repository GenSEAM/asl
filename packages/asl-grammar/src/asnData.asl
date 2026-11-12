(module asl-grammar/asnData
  :x [AsnValue asnParse asnParseAll asnField asnItems asnString asnInt asnFloat asnBool asnKeyword asnRender]
  :i [(asl-grammar/asn :a an)])

; (:m :ref DS-ASNREADER :do "ASN data text as typed values (inbox workspace-20261030-asnDataReader, row asnDataReader): the reading is asl-grammar/asn's asnReadAll (comments, string escapes, keywords, integers, byte-offset errors), this module only types its atoms (true and false as Bool, a decimal with a point or exponent as Float64) and adds keyword field lookup and a canonical printer; every read error is an err whose text starts with ERR_ASN_")

(enum AsnValue
  (:c asnKw [(name String)] "A keyword, without its colon.")
  (:c asnSym [(name String)] "A symbol.")
  (:c asnStr [(text String)] "A string with its escapes resolved.")
  (:c asnI64 [(value Int64)] "A decimal integer.")
  (:c asnF64 [(value Float64)] "A decimal with a point or an exponent.")
  (:c asnB [(value Bool)] "true or false.")
  (:c asnList [(items (List AsnValue))] "A parenthesised form; a record is a form of :key value pairs, after an optional head.")
  (:c asnVec [(items (List AsnValue))] "A bracketed vector."))

fn floatText? s: String -> Bool
  (and (or (stringContains? s ".") (or (stringContains? s "e") (stringContains? s "E")))
       (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789.eE+-" c)) (stringChars s)))

fn symbolValue s: String -> AsnValue
  (cond
    ((= s "true") (asnB true))
    ((= s "false") (asnB false))
    ((floatText? s) (match (stringToFloat64 s) ((some f) (asnF64 f)) ((none) (asnSym s))))
    (else (asnSym s)))

fn typed x: an/Sx -> AsnValue
  (match x
    ((an/sxList items) (asnList (map typed items)))
    ((an/sxVec items) (asnVec (map typed items)))
    ((an/sxKw name) (asnKw name))
    ((an/sxSym name) (symbolValue name))
    ((an/sxStr text) (asnStr text))
    ((an/sxInt v) (asnI64 v)))

; (:m :ref DS-ASNREADER :do "every top-level value of the text; a read error is ERR_ASN_READ: with the reader's message and byte offset")
fn asnParseAll text: String -> (Result (List AsnValue) String)
  (match (an/asnReadAll text)
    ((err e) (err (str "ERR_ASN_READ: " e)))
    ((ok xs) (ok (map typed xs))))

; (:m :ref DS-ASNREADER :do "exactly one value: none is ERR_ASN_EMPTY, more than one is ERR_ASN_TRAILING")
fn asnParse text: String -> (Result AsnValue String)
  (match (asnParseAll text)
    ((err e) (err e))
    ((ok xs)
      (cond
        ((listEmpty? xs) (err "ERR_ASN_EMPTY: no value in the text"))
        ((> (listLength xs) 1) (err (str "ERR_ASN_TRAILING: " (stringFromInt64 (listLength xs)) " top-level values, want one")))
        (else (ok (optionOr (listHead xs) (asnSym "")))))))

fn asnItems v: AsnValue -> (List AsnValue)
  (match v
    ((asnList items) items)
    ((asnVec items) items)
    (_ (list)))

fn fieldIn items: (List AsnValue) key: String -> (Option AsnValue)
  (match (listHead items)
    ((none) (none))
    ((some x)
      (let [(rest (optionOr (listTail items) (list)))]
        (match x
          ((asnKw k) (if (= k key) (listHead rest) (fieldIn (listDrop rest 1) key)))
          (_ (fieldIn (listDrop rest 1) key))))))

; (:m :ref DS-ASNREADER :do "the value after :key at the top level of a form: keys and values are taken in pairs, after a head when the form has an odd number of items ((:cfg :k v) or (tag :k v)), so a keyword used as a value is not read as a key; nested forms and strings are values, never searched")
fn asnField v: AsnValue key: String -> (Option AsnValue)
  (let [(items (asnItems v))]
    (fieldIn (if (= (mod (listLength items) 2) 1) (listDrop items 1) items) key))

fn asnString v: AsnValue -> (Option String)
  (match v ((asnStr t) (some t)) ((asnSym s) (some s)) (_ (none)))

fn asnInt v: AsnValue -> (Option Int64)
  (match v ((asnI64 n) (some n)) (_ (none)))

fn asnFloat v: AsnValue -> (Option Float64)
  (match v ((asnF64 f) (some f)) ((asnI64 n) (some (int64ToFloat64 n))) (_ (none)))

fn asnBool v: AsnValue -> (Option Bool)
  (match v ((asnB b) (some b)) (_ (none)))

fn asnKeyword v: AsnValue -> (Option String)
  (match v ((asnKw k) (some k)) (_ (none)))

fn quoteText s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\r" "\\r") "\"")

; (:m :ref DS-ASNREADER :do "canonical ASN text of a value: single spaces, strings quoted with escapes, so asnParse of the printed text gives the same value")
fn asnRender v: AsnValue -> String
  (match v
    ((asnKw k) (str ":" k))
    ((asnSym s) s)
    ((asnStr t) (quoteText t))
    ((asnI64 n) (stringFromInt64 n))
    ((asnF64 f) (stringFromFloat64 f))
    ((asnB b) (if b "true" "false"))
    ((asnList items) (str "(" (stringJoin (map asnRender items) " ") ")"))
    ((asnVec items) (str "[" (stringJoin (map asnRender items) " ") "]")))
