(module asl/agentLoop/grounding
  :x [cardSources cardRuleAnchors languageText! languageRules libExample testExample aslCard! wantsAslCard
      rejectedReceipts rejectHints lastGot hintCodes]
  :i [(asl/agentLoop/core :a c) (asl-json/json :a j)])

; (:m :ref LEON-ASL-GROUNDING :do "a model with no ASL priors gets the language from the workspace's own sources: rule sentences cut by anchor from the tools.asn language topic and code cut by symbol from the canonical examples, shown as the write steps Leon parses; nothing here restates the language in its own words")

fn cardSources -> (List String)
  (list "asl/grammar/tools.asn" "asl/grammar/examples/greeting.asl" "asl/grammar/examples/tests/examplesTest.asl")

fn cardRuleAnchors -> (List String)
  (list "An ASL file is a module header" "Imports name the module" "A function is a bare line" "(let [(a 1)"
        "(fn [x] body) is a value" "Conditions, and, or, not" "Int and Float never mix" "There is no nil"
        "Builtins are camelCase" "A test exports runTests")

fn at s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn from s: String i: Int64 -> String
  (optionOr (stringSlice s i (stringLength s)) "")

fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn quoteEnd s: String n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (at s i) "\\") (quoteEnd s n (+ i 2)))
    ((= (at s i) "\"") i)
    (else (quoteEnd s n (+ i 1))))

fn ! languageText! repoRoot: String -> (Result String String)
  (match (fileReadString (str repoRoot "/" (optionOr (listHead (cardSources)) "")))
    ((err e) (err e))
    ((ok text)
      (let [marker ":name :language :text \""]
        (match (stringIndexOf text marker)
          ((none) (err "tools.asn has no :language topic text"))
          ((some p)
            (let [a (+ p (stringLength marker))]
              (ok (c/asnUnescape (cut text a (quoteEnd text (stringLength text) a))))))))))

fn sentenceOpener? s: String -> Bool
  (and (not (stringEmpty? s)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ(" s))

fn sentenceEnd s: String n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((and (or (= (at s i) ".") (= (at s i) ";"))
          (or (>= (+ i 1) n) (and (= (at s (+ i 1)) " ") (sentenceOpener? (at s (+ i 2))))))
      (+ i 1))
    (else (sentenceEnd s n (+ i 1))))

fn ruleAt text: String anchor: String -> (Option String)
  (match (stringIndexOf text anchor)
    ((none) none)
    ((some p) (some (cut text p (sentenceEnd text (stringLength text) p)))))

fn languageRules text: String -> (List String)
  (filter (fn [r] (not (stringEmpty? r))) (map (fn [a] (optionOr (ruleAt text a) "")) (cardRuleAnchors)))

fn moduleName text: String -> String
  (let [first (optionOr (listHead (stringLines text)) "")
        rest (from first (stringLength "(module "))]
    (optionOr (listHead (stringSplit rest " ")) rest))

fn indented? line: String -> Bool
  (stringStartsWith? line "  ")

fn takeWhileIndented lines: (List String) -> (List String)
  (match (listHead lines)
    ((none) (list))
    ((some l) (if (indented? l) (cons l (takeWhileIndented (listDrop lines 1))) (list))))

fn blockLines lines: (List String) head: String -> (List String)
  (match (listHead lines)
    ((none) (list))
    ((some l)
      (if (or (stringStartsWith? l (str "fn " head " ")) (stringStartsWith? l (str "fn ! " head " ")))
        (cons l (takeWhileIndented (listDrop lines 1)))
        (blockLines (listDrop lines 1) head))))

fn libExample text: String fnName: String -> String
  (str "(module " (moduleName text) "\n  :x [" fnName "]\n  :i [])\n\n" (stringJoin (blockLines (stringLines text) fnName) "\n"))

fn aliasOf testText: String libModule: String -> String
  (let [marker (str "(" libModule " :a ")]
    (match (stringIndexOf testText marker)
      ((none) "")
      ((some p)
        (let [rest (from testText (+ p (stringLength marker)))]
          (cut rest 0 (optionOr (stringIndexOf rest ")") 0))))))

fn testExample testText: String libModule: String fnName: String -> String
  (let [alias (aliasOf testText libModule)
        block (blockLines (stringLines testText) "runTests")
        calls (filter (fn [l] (stringContains? l (str "(" alias "/" fnName " "))) block)
        frame (listTake block 2)
        last (listDrop block (- (listLength block) 1))]
    (str "(module " (moduleName testText) "\n  :x [runTests]\n  :i [(" libModule " :a " alias ")])\n\n"
         (stringJoin (listAppend frame (listAppend calls last)) "\n")))

fn rawStep path: String code: String -> String
  (str "(:step :op \"write\" :file \"" path "\" :content :raw)\n```\n" code "\n```")

fn quotedList xs: (List String) -> String
  (c/joinSep (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) xs) " ")

fn ! aslCard! repoRoot: String -> (Result String String)
  (let [paths (cardSources)
        libPath (optionOr (listGet paths 1) "")
        testPath (optionOr (listGet paths 2) "")]
    (match (languageText! repoRoot)
      ((err e) (err e))
      ((ok lang)
        (match (fileReadString (str repoRoot "/" libPath))
          ((err e) (err e))
          ((ok lib)
            (match (fileReadString (str repoRoot "/" testPath))
              ((err e) (err e))
              ((ok tst)
                (ok (str "(:aslCard :src (" (quotedList paths) ") :rules (" (quotedList (languageRules lang)) ")"
                         " :reply \"a write step ends its line and the file follows unescaped in a ``` fence on the next lines, as in this example module and its test\")\n"
                         (rawStep libPath (libExample lib "greet")) "\n"
                         (rawStep testPath (testExample tst (moduleName lib) "greet")))))))))))

fn wantsAslCard task: String gates: (List String) -> Bool
  (or (stringContains? task ".asl") (listAny? (fn [g] (stringContains? g ".asl")) gates))

fn hintCodes -> (List String)
  (list "ERR_RAW_MISSING" "ERR_USE_RAW" "ERR_UNKNOWN_KEY" "ERR_MISSING_ARG")

fn quotedAfter line: String key: String -> String
  (match (stringIndexOf line (str key " \""))
    ((none) "")
    ((some p)
      (let [rest (from line (+ p (stringLength key) 2))]
        (cut rest 0 (optionOr (stringIndexOf rest "\"") 0)))))

fn codeChar? s: String -> Bool
  (and (not (stringEmpty? s)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ_" s))

fn codeEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (codeChar? (at s i))) (codeEnd s n (+ i 1)) i)

fn errorCode line: String -> String
  (match (stringIndexOf line ":error ")
    ((none) "")
    ((some p)
      (let [rest (from line p)]
        (match (stringIndexOf rest "ERR_")
          ((none) "")
          ((some q) (cut rest q (codeEnd rest (stringLength rest) q)))))))

fn acceptedKeys line: String -> String
  (match (stringIndexOf line ":accepted (")
    ((none) "")
    ((some p)
      (let [rest (from line (+ p (stringLength ":accepted (")))]
        (cut rest 0 (optionOr (stringIndexOf rest ")") 0)))))

fn rejectedReceipts got: String -> (List (List String))
  (map (fn [l] (list (quotedAfter l ":op") (errorCode l) (quotedAfter l ":file") (acceptedKeys l)))
       (filter (fn [l] (and (stringStartsWith? l "(:receipt ") (stringContains? l ":status :rejected"))) (stringLines got)))

fn hintFor r: (List String) shapes: (List (Pair String String)) -> String
  (let [op (optionOr (listGet r 0) "")
        code (optionOr (listGet r 1) "")
        file (optionOr (listGet r 2) "")
        accepted (optionOr (listGet r 3) "")
        shape (optionOr (listHead (map pairSecond (filter (fn [p] (= (pairFirst p) op)) shapes))) "")
        raw (or (= code "ERR_RAW_MISSING") (= code "ERR_USE_RAW"))]
    (str "(:expect :op \"" (c/escapeAsn op) "\" :error " code
         (if (stringEmpty? shape) "" (str " :form \"" (c/escapeAsn shape) "\""))
         (if (stringEmpty? accepted) "" (str " :accepted (" accepted ")"))
         (if raw (str " :example \"" (c/escapeAsn (rawStep (if (stringEmpty? file) "f" file) "<code>")) "\"") "")
         ")"))

fn rejectHints got: String shapes: (List (Pair String String)) -> String
  (let [hits (filter (fn [r] (listContains? (hintCodes) (optionOr (listGet r 1) ""))) (rejectedReceipts got))
        keys (fold (fn [acc r] (let [k (str (optionOr (listGet r 0) "") " " (optionOr (listGet r 1) ""))]
                                 (if (listAny? (fn [p] (= (pairFirst p) k)) acc) acc (listAppend acc (list (pair k r))))))
                   (list) hits)]
    (stringJoin (map (fn [p] (hintFor (pairSecond p) shapes)) keys) "\n"))

fn lastGot history: (List j/Json) -> String
  (match (listHead (listReverse history))
    ((none) "")
    ((some h)
      (match h
        ((j/jobj kvs)
          (match (listHead (filter (fn [p] (= (pairFirst p) "got")) kvs))
            ((some p) (match (pairSecond p) ((j/jstr s) s) (_ "")))
            ((none) "")))
        (_ ""))))
