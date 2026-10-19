(module asl-cli/rcConfig
  :x [rcModeOf rcModeIn! rcModes]
  :i [(asl-parser/reader :a rd)])

; (:m :ref RC-CONFIG :do "the native memory mode is a workspace setting, :native (:rc :notrace) in .asl.config.asn, not an env var; each keyword names the mode string asl1 build --rc takes; absent, the caller's fallback applies (asl build: notrace, RC-DEFAULT; asl test: tracing, so suites keep the per-module cache)")
fn rcModes -> (List (Pair String String))
  (list (pair ":tracing" "0") (pair ":counted" "1") (pair ":asan" "asan") (pair ":notrace" "notrace"))

fn valueAfter items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (mt (listHead items)
    ((none) (none))
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) key))
                (listGet items 1)
                (valueAfter (optionOr (listTail items) (list)) key))))

fn rcModeOf text: String fallback: String -> (Result String String)
  (mt (valueAfter (rd/sexprToList (rd/parseSexpr text)) ":native")
    ((none) (ok fallback))
    ((some native)
      (mt (valueAfter (rd/sexprToList native) ":rc")
        ((none) (ok fallback))
        ((some v) (let [(word (if (rd/isAtom? v) (rd/sexprHead v) (rd/renderSexpr v)))]
                    (mt (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) word)) (rcModes)))
                      ((some p) (ok (pairSecond p)))
                      ((none) (err (str "ERR_CONFIG: :native :rc must be one of " (stringJoin (map (fn [(p (Pair String String))] -> String (pairFirst p)) (rcModes)) " ") ", got " word)))))))))

fn parentOf dir: String -> String
  (let [(parts (stringSplit dir "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! rcModeIn! dir: String fallback: String -> (Result String String)
  (let [(cfg (str dir "/.asl.config.asn"))]
    (cond
      ((fileExists? cfg) (mt (fileReadString cfg) ((err e) (err (str "ERR_CONFIG: cannot read " cfg ": " e))) ((ok text) (rcModeOf text fallback))))
      ((or (stringEmpty? dir) (= dir "/")) (ok fallback))
      (else (rcModeIn! (parentOf dir) fallback))))
