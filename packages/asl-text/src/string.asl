(module asl-text/string :doc "Pure AgentScript high-performance modular string primitives and 1-to-2 token aliases per d46 and d47." :export [starts? ends? has? split concat join txt-starts? txtEnds? txtHas? txtSplit txt/starts? txt/ends? txt/has? txt/split])

fn starts? s: Str prefix: Str -> Bool
  string-starts-with? s prefix

fn ends? s: Str suffix: Str -> Bool
  let slen = (string-length s)
  let sublen = (string-length suffix)
  if (< slen sublen) false (let start = (- slen sublen) in (= (option-or (string-slice s start slen) "") suffix))

fn has? s: Str sub: Str -> Bool
  string-contains? s sub

fn split s: Str delim: Str -> (List Str)
  s |> (string-split delim)

fn txt-starts? s: Str prefix: Str -> Bool
  starts? s prefix

fn txtEnds? s: Str suffix: Str -> Bool
  ends? s suffix

fn txtHas? s: Str sub: Str -> Bool
  has? s sub

fn txtSplit s: Str delim: Str -> (List Str)
  split s delim

fn concat a: Str b: Str -> Str
  str a b

fn join parts: (List Str) sep: Str -> Str
  parts |> (string-join sep)
