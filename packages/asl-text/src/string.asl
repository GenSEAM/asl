(module asl-text/string :x [starts? ends? has? split concat join txtStarts? txtEnds? txtHas? txtSplit txt/starts? txt/ends? txt/has? txt/split] :i [])

fn starts? s: Str prefix: Str -> Bool
  (stringStartsWith? s prefix)

fn ends? s: Str suffix: Str -> Bool
  (let [(slen (stringLength s)) (sublen (stringLength suffix))] (if (< slen sublen) false (let [(start (- slen sublen))] (= (optionOr (stringSlice s start slen) "") suffix))))

fn has? s: Str sub: Str -> Bool
  (stringContains? s sub)

fn split s: Str delim: Str -> (List Str)
  (stringSplit s delim)

fn txtStarts? s: Str prefix: Str -> Bool
  (starts? s prefix)

fn txtEnds? s: Str suffix: Str -> Bool
  (ends? s suffix)

fn txtHas? s: Str sub: Str -> Bool
  (has? s sub)

fn txtSplit s: Str delim: Str -> (List Str)
  (split s delim)

fn concat a: Str b: Str -> Str
  (str a b)

fn join parts: (List Str) sep: Str -> Str
  (stringJoin parts sep)
