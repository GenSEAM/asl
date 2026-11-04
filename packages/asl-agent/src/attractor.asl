(module aslAgent/attractor
  :x [attractorOn? attractorContract attractorSystem prefixHash attractorCards attractorTail attractorPrefill continueReply proseChars validAttractor?]
  :i [(aslAgent/core :a c) (aslAgent/reply :a r)])

; (:m :ref LEONATTR :do "an opt-in reply attractor: value asn opens the system prompt with one compact ASN contract plus minimal worked op examples and, where the transport passes a trailing assistant message, ends the request with a (:step prefill; off (empty) leaves every byte of the prompt as before")
fn validAttractor? v: String -> Bool
  (listContains? (list "" "off" "asn") v)

fn attractorOn? v: String -> Bool
  (= v "asn")

; (:m :ref LEONATTR :do "the stable prefix: constant text plus the op grammar rows, so it holds no task, session, path, time, turn or model name and its bytes are the same for every session, which lets a provider prompt cache hit")
fn attractorContract shapes: (List String) -> String
  (str "(:reply :format asn :prose none :first \"(:step\" :think brief)\n"
       "(:grammar " (c/joinSep shapes " ") ")\n"
       "(:example (:step :op \"read\" :file \"src/ring.asl\" :symbol \"push\") (:step :op \"gate\"))\n"
       "(:example (:step :op \"write\" :file \"src/ring.asl\" :content :raw)\n```\n(module src/ring)\n```\n(:step :op \"gate\"))\n")

fn attractorSystem v: String shapes: (List String) system: String -> String
  (if (attractorOn? v) (str (attractorContract shapes) system) system)

fn prefixHash v: String shapes: (List String) -> String
  (if (attractorOn? v) (stringFromInt64 (fnv1a64 (attractorContract shapes))) "")

; (:m :ref LEONATTR :do "the dynamic tail is chosen by static rules from the last receipt text, the last parse defect and the write state; each rule is a named card, and the names are journaled")
fn attractorCards v: String lastGot: String lastDefect: Bool writesPersisted: Bool turnsSoFar: Int64 -> (List (Pair String String))
  (if (attractorOn? v)
    (listAppend
      (if (stringContains? lastGot "ERR_USE_RAW")
        (list (pair "rawWrite" "(:attractor :raw :use \"write with :content :raw then a fenced block on the following lines; never quote multi-line code\")"))
        (list))
      (if lastDefect
        (list (pair "stepOnly" "(:attractor :stepOnly :use \"(:step only, no prose\")"))
        (list)))
    (list))

fn attractorTail cards: (List (Pair String String)) -> String
  (if (listEmpty? cards) "" (str (c/joinSep (map pairSecond cards) "\n") "\n\n"))

fn attractorPrefill v: String -> String
  (if (attractorOn? v) "(:step" "")

; (:m :ref LEONATTR :do "a prefilled reply may arrive as only the continuation (it starts mid-form, never with an open paren) or, when the transport ignores the prefill, as the whole reply; only the first needs the prefill put back before parsing")
fn continueReply prefill: String reply: String -> String
  (cond
    ((stringEmpty? prefill) reply)
    ((stringEmpty? (stringTrim reply)) reply)
    ((stringStartsWith? (stringTrim reply) "(") reply)
    (else (str prefill reply)))

fn countNonSpace s: String n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) k)
    ((c/isSpace (c/ch s i)) (countNonSpace s n (+ i 1) k))
    (else (countNonSpace s n (+ i 1) (+ k 1))))

; (:m :ref LEONATTR :do "prose chars: non-space characters outside every balanced top-level form and outside raw fenced blocks bound to a :raw step")
fn proseChars reply: String -> Int64
  (let [bound (r/bindRawBlocks reply)
        plain (r/unfence bound.text)
        rest (c/stripForms plain)]
    (countNonSpace rest (stringLength rest) 0 0))
