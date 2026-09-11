(module asl-text/string
  :d "Pure AgentScript high-performance modular string primitives and 1-to-2 token aliases per d46 and d47."
  :x [starts?
      ends?
      has?
      split
      concat
      join
      txt-starts?
      txt-ends?
      txt-has?
      txt-split
      txt/starts?
      txt/ends?
      txt/has?
      txt/split]
  :i [])

(df starts? [(s Str) (prefix Str)] -> Bool
  :d "Tests whether string starts with given prefix."
  (string-starts-with? s prefix))

(df ends? [(s Str) (suffix Str)] -> Bool
  :d "Tests whether string ends with given suffix."
  (let [(slen (string-length s))
        (sublen (string-length suffix))]
    (if (< slen sublen)
      false
      (let [(start (- slen sublen))]
        (= (option-or (string-slice s start slen) "") suffix)))))

(df has? [(s Str) (sub Str)] -> Bool
  :d "Tests whether string contains given substring."
  (string-contains? s sub))

(df split [(s Str) (delim Str)] -> (List Str)
  :d "Splits string by delimiter into list of substrings."
  (string-split s delim))

(df txt-starts? [(s Str) (prefix Str)] -> Bool
  :d "Hyphen compatibility alias for starts?."
  (starts? s prefix))

(df txt-ends? [(s Str) (suffix Str)] -> Bool
  :d "Hyphen compatibility alias for ends?."
  (ends? s suffix))

(df txt-has? [(s Str) (sub Str)] -> Bool
  :d "Hyphen compatibility alias for has?."
  (has? s sub))

(df txt-split [(s Str) (delim Str)] -> (List Str)
  :d "Hyphen compatibility alias for split."
  (split s delim))


(df concat [(a Str) (b Str)] -> Str
  :d "Concatenates two strings."
  (str a b))

(df join [(parts (List Str)) (sep Str)] -> Str
  :d "Joins list of strings with separator."
  (string-join parts sep))
