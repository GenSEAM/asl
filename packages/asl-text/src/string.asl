(module asl-text/string
  :d "Pure AgentScript high-performance modular string primitives and 1-to-2 token aliases per d46 and d47."
  :x [txt/starts?
      txt/ends?
      txt/has?
      txt/split
      txt-starts?
      txt-ends?
      txt-has?
      txt-split]
  :i [])

(df txt/starts? [(s Str) (prefix Str)] -> Bool
  :d "Tests whether string starts with given prefix."
  (string-starts-with? s prefix))

(df txt/ends? [(s Str) (suffix Str)] -> Bool
  :d "Tests whether string ends with given suffix."
  (let [(slen (string-length s))
        (sublen (string-length suffix))]
    (if (< slen sublen)
      false
      (let [(start (- slen sublen))]
        (= (option-or (string-slice s start slen) "") suffix)))))

(df txt/has? [(s Str) (sub Str)] -> Bool
  :d "Tests whether string contains given substring."
  (string-contains? s sub))

(df txt/split [(s Str) (delim Str)] -> (List Str)
  :d "Splits string by delimiter into list of substrings."
  (string-split s delim))

(df txt-starts? [(s Str) (prefix Str)] -> Bool
  :d "Hyphen compatibility alias for txt/starts?."
  (txt/starts? s prefix))

(df txt-ends? [(s Str) (suffix Str)] -> Bool
  :d "Hyphen compatibility alias for txt/ends?."
  (txt/ends? s suffix))

(df txt-has? [(s Str) (sub Str)] -> Bool
  :d "Hyphen compatibility alias for txt/has?."
  (txt/has? s sub))

(df txt-split [(s Str) (delim Str)] -> (List Str)
  :d "Hyphen compatibility alias for txt/split."
  (txt/split s delim))
