(module asl/agentLoop/tests/groundingTest
  :x [runTests]
  :i [(asl/agentLoop/grounding :a gr) (asl/agentLoop/journal :a jr) (asl/agentLoop/reply :a rp) (asl/agentLoop/exec :a ex)
      (asl/agentLoop/core :a c) (asl-json/json :a j) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-ASL-GROUNDING :do "the ASL card Leon sends a model is cut from tools.asn and the canonical examples, its write steps bind through the same raw-block parser the loop uses, it rides only on ASL tasks, and a rejected write or unknown-key receipt comes back next turn as an (:expect) form with the exact step shape")

fn rawMissingGot -> String
  (str "(:step :op \"write\" :file \"scratch/a.asl\" :content :raw :error \"ERR_RAW_MISSING\")\n"
       "(:receipt :id \"46f39f957d8757af\" :op \"write\" :status :rejected :file \"scratch/a.asl\" :error :ERR_RAW_MISSING :message \"missing raw block for :raw\")\n"
       "(:receipt :id \"46f39f957d8757b0\" :op \"write\" :status :rejected :file \"scratch/a.asl\" :error :ERR_RAW_MISSING :message \"missing raw block for :raw\")\n"
       "(:receipt :id \"71dd738bd583a6a4\" :op \"query\" :status :rejected :hits ((:query :status :rejected :error ERR_UNKNOWN_KEY :keys (:query) :accepted (:text :in :limit) :see \"(:help :op query)\")))\n"
       "(:receipt :id \"912c631e1eed39f0\" :op \"write\" :status :ok :file \"scratch/b.asl\")")

fn countOf hay: String needle: String -> Int64
  (- (listLength (stringSplit hay needle)) 1)

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        cardR (gr/aslCard! root)
        card (resultOr cardR "")
        lang (resultOr (gr/languageText! root) "")
        rules (gr/languageRules lang)
        lib (resultOr (fileReadString (str root "/asl/grammar/examples/greeting.asl")) "")
        tst (resultOr (fileReadString (str root "/asl/grammar/examples/tests/examplesTest.asl")) "")
        libEx (gr/libExample lib "greet")
        testEx (gr/testExample tst "asl/grammar/examples/greeting" "greet")
        bound (rp/bindRawBlocks card)
        aslPrompt (resultOr (jr/buildSystemPrompt root "Create scratch/x.asl with fn double" root "" (list "./bin/asl test scratch/xTest.asl") none false) "ERR")
        otherPrompt (resultOr (jr/buildSystemPrompt root "port the loop" root "" (list "./bin/asl test x") none false) "ERR")
        hints (gr/rejectHints (rawMissingGot) (ex/opShapes))
        history (list (j/jobj (list (pair "turn" (j/jint 1)) (pair "sent" (j/jstr "s")) (pair "got" (j/jstr (rawMissingGot))))))
        recRoot (rk/freshRecorderRoot! "grounding")
        replies (list "(:step :op \"write\" :file \"g.asl\" :content :raw)" "(:done)")
        run (rk/runRecordedAgentLoopWithReplies! recRoot "grounding" replies (list "g.asl") "write g.asl" 3 8000)
        sentAt (fn [n] (filter (fn [l] (= (rk/sentLineTurn l) n)) run.sentLines))
        cleaned (ok? (pathRemove recRoot))]
    (do
      (assert (ok? cardR) "the card builds from the workspace sources")
      (assert (= (listLength rules) (listLength (gr/cardRuleAnchors))) "every rule anchor is found in the tools.asn language topic")
      (assert (listAll? (fn [r] (stringContains? lang r)) rules) "each card rule is a verbatim sentence of the language topic")
      (assert (listAny? (fn [r] (stringStartsWith? r "A function is a bare line, fn name a: Int64 b: String -> Bool")) rules) "the fn line rule with typed params is carried")
      (assert (listAny? (fn [r] (stringStartsWith? r "A test exports runTests")) rules) "the test rule is carried")
      (assert (listAll? (fn [r] (or (stringEndsWith? r ".") (stringEndsWith? r ";"))) rules) "a rule is cut at its sentence end")
      (assert (stringStartsWith? libEx "(module asl/grammar/examples/greeting\n  :x [greet]\n  :i [])") "the lib example header exports only the shown fn")
      (assert (stringContains? lib "fn greet name: String -> String\n  (str \"Hello, \" name \"!\")") "the source carries the fn block the card shows")
      (assert (stringContains? libEx "fn greet name: String -> String\n  (str \"Hello, \" name \"!\")") "the fn block is cut from greeting.asl by symbol")
      (assert (stringContains? testEx ":i [(asl/grammar/examples/greeting :a g)]") "the test example imports the lib by module name with an alias")
      (assert (stringContains? testEx "(assert (= (g/greet \"world\") \"Hello, world!\") \"greet formats a name\")") "the test example asserts with a message through the alias")
      (assert (not (stringContains? testEx "r/describePoint")) "asserts on other modules are left out")
      (assert (stringEndsWith? testEx "true)") "the test example ends true")
      (assert (stringContains? card (str "(:step :op \"write\" :file \"asl/grammar/examples/greeting.asl\" :content :raw)\n```\n" libEx "\n```")) "the lib is shown as the raw write step Leon parses")
      (assert (= bound.count 2) "both card write steps bind their fenced block through reply/bindRawBlocks")
      (assert (listEmpty? bound.missing) "no card write step is left without its raw block")
      (assert (stringContains? bound.text (str "\"" (c/escapeAsn (str libEx "\n")) "\""))  "the bound content is the lib example itself, newline-terminated")
      (assert (< (stringLength card) 2600) "the card stays within its budget of about 600 tokens")
      (assert (stringContains? aslPrompt "(:aslCard :src (") "an ASL task gets the card in its system prompt")
      (assert (stringContains? otherPrompt "(:pool :ask (:ask :to i :body (...))") "every prompt names the pool ask and answer forms")
      (assert (not (stringContains? otherPrompt "(:aslCard")) "a task with no .asl in task or gates gets no card")
      (assert (gr/wantsAslCard "port it" (list "./bin/asl test a/bTest.asl")) "an .asl gate alone asks for the card")
      (assert (stringContains? hints "(:expect :op \"write\" :error ERR_RAW_MISSING :form \"(:step :op \\\"write\\\" :file f :content :raw|s)\"") "a raw-missing write gets the write shape back")
      (assert (stringContains? hints (str ":example \"" (c/escapeAsn "(:step :op \"write\" :file \"scratch/a.asl\" :content :raw)\n```\n<code>\n```") "\"")) "the raw hint shows the fenced example for the rejected file")
      (assert (= (countOf hints "ERR_RAW_MISSING") 1) "two identical rejections give one expect form")
      (assert (stringContains? hints "(:expect :op \"query\" :error ERR_UNKNOWN_KEY") "an unknown-key rejection gets an expect form")
      (assert (stringContains? hints ":accepted (:text :in :limit)") "the unknown-key expect names the accepted keys from the receipt")
      (assert (not (stringContains? hints "scratch/b.asl")) "an ok receipt gives no hint")
      (assert (= (gr/rejectHints "(:receipt :id \"x\" :op \"write\" :status :ok :file \"a\")" (ex/opShapes)) "") "no rejection, no hint")
      (assert (= (gr/lastGot history) (rawMissingGot)) "the last turn's got is read from the loop history")
      (assert (= (listLength (sentAt 2)) 1) "the scripted run journals its turn 2 prompt")
      (assert (listAny? (fn [l] (stringContains? l "ERR_RAW_MISSING :form")) (sentAt 2)) "a raw write with no fence in turn 1 puts the expect form in turn 2's prompt")
      (assert (not (listAny? (fn [l] (stringContains? l "(:expect :op")) (sentAt 1))) "turn 1 carries no expect form")
      (assert cleaned "the recorder root is removed")
      true))
