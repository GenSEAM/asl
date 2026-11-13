(module asl-text/string :x [starts? ends? has? split concat join txtStarts? txtEnds? txtHas? txtSplit stringClipUtf8] :i [])

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

fn clipContinuation? b: Int64 -> Bool
  (and (>= b 128) (<= b 191))

fn clipCharStart bs: Bytes j: Int64 -> Int64
  (if (and (> j 0) (clipContinuation? (bytesGet bs j))) (clipCharStart bs (- j 1)) j)

; (:m :ref UTF8-CLIP-SWEEP :do "s cut to at most n bytes without splitting a UTF-8 character: a cut inside a character moves back to that character's first byte; n <= 0 is empty, n >= the byte length returns s")
fn stringClipUtf8 s: Str n: Int64 -> Str
  (let [(bs (stringToBytes s))
        (len (bytesLength bs))]
    (cond ((<= n 0) "")
          ((>= n len) s)
          (else (optionOr (stringSlice s 0 (clipCharStart bs n)) ""))))
