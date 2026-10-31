(module asl/agentLoop/agentConfig
  :x [agentLoopBlock agentLoopValue positiveInt configProblems configText!]
  :i [])

; (:m :ref LEON-CAPS :do "scoped reader for the :agentLoop group of .asl.config.asn: a key counts only as a top-level token of that group, quoted strings and nested groups are single tokens, so a key named in a doc string or in another group never matches")
fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn charAt s: String i: Int64 -> String
  (cut s i (+ i 1))

fn isSpace ch: String -> Bool
  (or (= ch " ") (or (= ch "\n") (or (= ch "\t") (= ch "\r"))))

fn skipSpace s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isSpace (charAt s i))) (skipSpace s n (+ i 1)) i)

fn lineEnd s: String n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (= (charAt s i) "\n")) i (lineEnd s n (+ i 1)))

fn strEnd s: String n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (charAt s i) "\\") (strEnd s n (+ i 2)))
    ((= (charAt s i) "\"") i)
    (else (strEnd s n (+ i 1))))

fn atomEnd s: String n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (or (isSpace (charAt s i)) (or (= (charAt s i) "(") (or (= (charAt s i) ")") (= (charAt s i) "\"")))))
    i
    (atomEnd s n (+ i 1)))

fn closeAt s: String n: Int64 i: Int64 depth: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (charAt s i) ";") (closeAt s n (lineEnd s n i) depth))
    ((= (charAt s i) "\"") (closeAt s n (+ (strEnd s n (+ i 1)) 1) depth))
    ((= (charAt s i) "(") (closeAt s n (+ i 1) (+ depth 1)))
    ((= (charAt s i) ")") (if (= depth 1) i (closeAt s n (+ i 1) (- depth 1))))
    (else (closeAt s n (+ i 1) depth)))

fn tokensFrom s: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [j (skipSpace s n i)]
    (if (>= j n)
      (listReverse acc)
      (let [ch (charAt s j)]
        (cond
          ((= ch ";") (tokensFrom s n (lineEnd s n j) acc))
          ((= ch "\"")
            (let [e (min n (+ (strEnd s n (+ j 1)) 1))]
              (tokensFrom s n e (cons (cut s j e) acc))))
          ((= ch "(")
            (let [e (closeAt s n (+ j 1) 1)]
              (if (< e 0) (listReverse acc) (tokensFrom s n (+ e 1) (cons (cut s j (+ e 1)) acc)))))
          ((= ch ")") (tokensFrom s n (+ j 1) acc))
          (else
            (let [e (atomEnd s n j)]
              (tokensFrom s n e (cons (cut s j e) acc))))))))

fn quoteCount s: String -> Int64
  (- (- (listLength (stringSplit s "\"")) 1) (- (listLength (stringSplit s "\\\"")) 1))

; (:m :ref LEON-CAPS :do "a :agentLoop that sits inside a string literal (odd quote count before it) is skipped, so a doc string naming the group never opens it")
fn blockFrom text: String from: Int64 -> (Option String)
  (match (stringIndexOf (cut text from (stringLength text)) ":agentLoop")
    ((none) none)
    ((some rel)
      (let [after (+ (+ from rel) (stringLength ":agentLoop"))
            inString (= (mod (quoteCount (cut text 0 (+ from rel))) 2) 1)
            rest (cut text after (min (stringLength text) (+ after 16000)))
            n (stringLength rest)
            lead (skipSpace rest n 0)]
        (if (and (not inString) (and (< lead n) (= (charAt rest lead) "(")))
          (let [close (closeAt rest n (+ lead 1) 1)]
            (if (< close 0) none (some (cut rest (+ lead 1) close))))
          (blockFrom text after)))))

fn agentLoopBlock text: String -> (Option String)
  (blockFrom text 0)

fn unquote t: String -> String
  (if (and (>= (stringLength t) 2) (and (stringStartsWith? t "\"") (stringEndsWith? t "\"")))
    (cut t 1 (- (stringLength t) 1))
    t)

fn valueOf toks: (List String) key: String -> (Option String)
  (cond
    ((< (listLength toks) 2) none)
    ((= (optionOr (listGet toks 0) "") key) (some (unquote (optionOr (listGet toks 1) ""))))
    (else (valueOf (listDrop toks 1) key)))

; (:m :ref LEON-CAPS :do "the value token of a top-level key of the :agentLoop group, quotes removed; none when the group or the key is absent")
fn agentLoopValue text: String key: String -> (Option String)
  (match (agentLoopBlock text)
    ((none) none)
    ((some block) (valueOf (tokensFrom block (stringLength block) 0 (list)) key)))

fn allDigits? s: String i: Int64 -> Bool
  (or (>= i (stringLength s))
    (and (>= (charAt s i) "0") (and (<= (charAt s i) "9") (allDigits? s (+ i 1)))))

fn positiveInt v: String -> (Option Int64)
  (if (and (not (stringEmpty? v)) (allDigits? v 0))
    (match (stringToInt64 v) ((some n) (if (> n 0) (some n) none)) ((none) none))
    none)

fn danglingProblem text: String -> (List String)
  (match (agentLoopBlock text)
    ((none) (list))
    ((some block)
      (let [last (optionOr (listLast (tokensFrom block (stringLength block) 0 (list))) "")]
        (if (stringStartsWith? last ":") (list (str ":agentLoop key " last " has no value")) (list)))))

fn intProblem text: String key: String -> (List String)
  (match (agentLoopValue text key)
    ((none) (list))
    ((some v) (if (some? (positiveInt v)) (list) (list (str ":agentLoop " key " must be a positive integer, got \"" v "\"")))))

fn boolProblem text: String key: String -> (List String)
  (match (agentLoopValue text key)
    ((none) (list))
    ((some v) (if (or (= v "true") (= v "false")) (list) (list (str ":agentLoop " key " must be true or false, got \"" v "\"")))))

fn nameProblem text: String key: String -> (List String)
  (match (agentLoopValue text key)
    ((none) (list))
    ((some v) (if (stringEmpty? v) (list (str ":agentLoop " key " must not be empty")) (list))))

; (:m :ref LEON-CAPS :do "every invalid :agentLoop value of the config text, one message each; the run refuses to start while any is left")
fn configProblems text: String -> (List String)
  (listAppend (danglingProblem text)
   (listAppend (intProblem text ":readOutlineBytes")
   (listAppend (intProblem text ":wallReserveSec")
   (listAppend (intProblem text ":wallGateMinSec")
   (listAppend (intProblem text ":gateVacuousRounds")
    (listAppend (boolProblem text ":baseline")
      (listAppend (boolProblem text ":specCheck")
        (listAppend (nameProblem text ":graderIntent") (nameProblem text ":graderProfile")))))))))

fn ! configText! root: String -> String
  (resultOr (fileReadString (str root "/.asl.config.asn")) "")
