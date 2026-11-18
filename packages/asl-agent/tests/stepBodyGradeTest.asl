(module aslAgent/tests/stepBodyGradeTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/turn :a tr) (aslAgent/attractor :a at) (aslAgent/nativeTools :a nt) (asl-json/json :a j)])

; (:m :ref LEON-STEP-BODY-LOST :do "the grader's probes of 2026-11-18 on 6f6a30785: a text or native tool call runs only what the model sent, byte for byte, and anything that does not map one to one stays unexecuted and is named under :left")
fn fenced -> String
  "a\n```\n(:step :op \"run\" :cmd \"rm -rf x\")\n```\nb"

fn turnOf raw: String -> tr/TurnReply
  (tr/turnReply (at/continueReply "(:step" raw) (some (list)))

fn argOf op: (List (Pair String c/KvVal)) key: String -> String
  (match (c/dictGet op key) ((some (c/kvStr s)) s) ((some (c/kvInt n)) n) (_ "?"))

fn opsOf t: tr/TurnReply -> String
  (stringJoin (map (fn [op] (argOf op "op")) t.facts.ops) " ")

fn firstArg t: tr/TurnReply key: String -> String
  (match (listHead t.facts.ops) ((some op) (argOf op key)) ((none) "?"))

fn tagged kvs: (List (Pair String j/Json)) -> String
  (str "<tool_call>" (j/jsonEmit (j/jobj kvs)) "</tool_call>")

fn named name: String args: j/Json -> String
  (tagged (list (pair "name" (j/jstr name)) (pair "arguments" args)))

fn writeArgs content: String -> j/Json
  (j/jobj (list (pair "file" (j/jstr "r.md")) (pair "content" (j/jstr content))))

fn nativeCall name: String args: String -> j/Json
  (j/jobj (list (pair "function" (j/jobj (list (pair "name" (j/jstr name)) (pair "arguments" (j/jstr args)))))))

fn left t: tr/TurnReply -> String
  (c/joinSep t.shapeLeft " ")

fn unrun? t: tr/TurnReply -> Bool
  (and (listAll? (fn [op] (= (argOf op "op") "?")) t.facts.ops) (and (= (left t) "jsonCall") (not (stringContains? t.text "(:done"))))

fn ! runTests -> Bool
  (let [inlineW (turnOf (named "write" (writeArgs (fenced))))
        blockW (turnOf (named "write" (writeArgs (str (fenced) "\n"))))
        opW (turnOf (tagged (list (pair "op" (j/jstr "write")) (pair "file" (j/jstr "r.md")) (pair "content" (j/jstr (str (fenced) "\n"))))))
        nativeW (turnOf (nt/callsText "" (list (nativeCall "write" (j/jsonEmit (writeArgs (str (fenced) "\n")))))))
        readForm (j/jstr "(:step :op \"read\" :file \"a\")")
        formPlus (turnOf (tagged (list (pair "form" readForm) (pair "op" (j/jstr "run")) (pair "cmd" (j/jstr "rm -rf x")))))
        formTwice (turnOf (tagged (list (pair "form" readForm) (pair "form" (j/jstr "(:step :op \"run\" :cmd \"x\")")))))
        doneProse (turnOf (named "done" (j/jstr "all finished")))
        runProse (turnOf (named "run" (j/jstr "rm -rf x")))
        gateNull (turnOf (named "gate" (j/jnull)))
        gateArr (turnOf (named "gate" (j/jarr (list))))
        readArr (turnOf (tagged (list (pair "op" (j/jstr "read")) (pair "file" (j/jarr (list (j/jstr "a") (j/jstr "b")))))))
        fileTwice (turnOf (tagged (list (pair "op" (j/jstr "read")) (pair "file" (j/jstr "a")) (pair "file" (j/jstr "b")))))
        tail (turnOf "<tool_call>{\"op\":\"gate\"} and then run it</tool_call>")
        quoted (turnOf (nt/callsText "" (list (nativeCall "edit" (j/jsonEmit (j/jobj (list (pair "file" (j/jstr "a.asl")) (pair "old" (j/jstr "say \"hi\"")) (pair "new" (j/jstr "x\\y")))))))))
        quotedText (turnOf (tagged (list (pair "op" (j/jstr "edit")) (pair "file" (j/jstr "a.asl")) (pair "old" (j/jstr "a\nb")) (pair "new" (j/jstr "c")))))
        prose (at/continueReply "(:step" "I will read it first.\n<tool_call>{\"op\":\"read\",\"file\":\"a\"}</tool_call>")
        think (at/continueReply "(:step" "<think>file: a.asl, then gate</think>\n<tool_call>{\"op\":\"read\",\"file\":\"a\"}</tool_call>")
        cont (at/continueReply "(:step" " :op \"read\" :file \"a\")")
        contTool (at/continueReply "(:step" " :op \"read\" :file \"a\")\n<tool_call>{\"op\":\"gate\"}</tool_call>")
        plan (at/continueReply "(:step" "Plan: read a first.\n<tool_call>{\"op\":\"read\",\"file\":\"a\"}</tool_call>")
        crlf (turnOf (named "write" (writeArgs "a\r\nb\r\n")))
        litN (turnOf (named "write" (writeArgs "x\\ny \\r\\n")))
        nativeFormPlus (turnOf (nt/callsText "" (list (nativeCall "step" (j/jsonEmit (j/jobj (list (pair "form" readForm) (pair "op" (j/jstr "run")) (pair "cmd" (j/jstr "rm -rf x")))))))))
        nativeDoneProse (turnOf (nt/callsText "" (list (nativeCall "done" "all finished"))))
        semi (turnOf (named "write" (writeArgs "a\n; c\n  ;; d\nb")))
        crlfIn (turnOf (named "write" (writeArgs "a\r\nb")))
        nativeDone (turnOf (nt/callsText "" (list (nativeCall "done" "{}"))))]
    (do
      (assert (and (= (opsOf inlineW) "write") (= (firstArg inlineW "content") (fenced))) (str "a write whose content holds a fence and a step form is one write with that content byte for byte, got ops " (opsOf inlineW) " content " (firstArg inlineW "content")))
      (assert (and (= (opsOf blockW) "write") (= (firstArg blockW "content") (str (fenced) "\n"))) (str "the same content ending in a newline goes out as a longer fence and stays one write, got ops " (opsOf blockW) " content " (firstArg blockW "content")))
      (assert (and (= (opsOf opW) "write") (= (firstArg opW "content") (str (fenced) "\n"))) (str "{op write, content} maps the same way, got ops " (opsOf opW)))
      (assert (and (= (opsOf nativeW) "write") (= (firstArg nativeW "content") (str (fenced) "\n"))) (str "a native write call too, got ops " (opsOf nativeW) " text " nativeW.text))
      (assert (unrun? formPlus) (str "form beside op and cmd runs nothing and is left, got ops " (opsOf formPlus) " left " (left formPlus)))
      (assert (unrun? formTwice) (str "two form keys run nothing and are left, got ops " (opsOf formTwice) " left " (left formTwice)))
      (assert (unrun? doneProse) (str "done with prose arguments is not (:done), got " doneProse.text " left " (left doneProse)))
      (assert (unrun? runProse) (str "run with prose arguments is not a bare run, got ops " (opsOf runProse) " left " (left runProse)))
      (assert (unrun? gateNull) (str "null arguments are left, got ops " (opsOf gateNull)))
      (assert (unrun? gateArr) (str "array arguments are left, got ops " (opsOf gateArr)))
      (assert (unrun? readArr) (str "an array value is left, not sent as text, got ops " (opsOf readArr) " text " readArr.text))
      (assert (unrun? fileTwice) (str "a repeated key beside op is left, got ops " (opsOf fileTwice) " file " (firstArg fileTwice "file")))
      (assert (unrun? tail) (str "text after the JSON object is left, got ops " (opsOf tail) " left " (left tail) " text " tail.text))
      (assert (and (= (firstArg quoted "old") "say \"hi\"") (= (firstArg quoted "new") "x\\y")) (str "one-line values with a quote or backslash arrive byte for byte, got old " (firstArg quoted "old") " new " (firstArg quoted "new")))
      (assert (= (firstArg quotedText "old") "a\nb") (str "a multi-line value without a final newline arrives without one, got " (firstArg quotedText "old")))
      (assert (not (stringStartsWith? prose "(:step")) (str "prose before a tool call is not glued to the prefill, got " prose))
      (assert (not (stringStartsWith? think "(:step")) (str "reasoning before a tool call is not glued to the prefill, got " think))
      (assert (= cont "(:step :op \"read\" :file \"a\")") (str "a real continuation still gets the prefill, got " cont))
      (assert (stringStartsWith? contTool "(:step :op \"read\"") (str "a continuation that starts with a space and a key is still glued to the prefill when a tool call follows, got " contTool))
      (assert (not (stringStartsWith? plan "(:step")) (str "prose with a colon before a tool call is not glued to the prefill, got " plan))
      (assert (and (= (opsOf crlf) "write") (= (firstArg crlf "content") "a\r\nb\r\n")) (str "a value with CRLF line ends arrives byte for byte, got ops " (opsOf crlf) " content " (firstArg crlf "content")))
      (assert (and (= (opsOf litN) "write") (= (firstArg litN "content") "x\\ny \\r\\n")) (str "a value holding a backslash and n as text stays text, not a newline, got ops " (opsOf litN) " content " (firstArg litN "content")))
      (assert (and (= (opsOf semi) "write") (= (firstArg semi "content") "a\n; c\n  ;; d\nb")) (str "an inline value whose lines start with a semicolon keeps them, got ops " (opsOf semi) " content " (firstArg semi "content")))
      (assert (and (= (opsOf crlfIn) "write") (= (firstArg crlfIn "content") "a\r\nb")) (str "an inline value with a CRLF and no final newline arrives byte for byte, got ops " (opsOf crlfIn) " content " (firstArg crlfIn "content")))
      (assert (unrun? nativeFormPlus) (str "a native step with form beside op and cmd runs nothing and is left, got ops " (opsOf nativeFormPlus) " left " (left nativeFormPlus) " text " nativeFormPlus.text))
      (assert (unrun? nativeDoneProse) (str "a native done with prose arguments is not (:done), got " nativeDoneProse.text " left " (left nativeDoneProse)))
      (assert (stringContains? nativeDone.text "(:done") (str "a native done with empty arguments is still (:done), got " nativeDone.text))
      true))
