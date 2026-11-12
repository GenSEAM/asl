(module aslAgent/tests/groundingTest
  :x [runTests]
  :i [(aslAgent/grounding :a gr) (aslAgent/journal :a jr) (aslAgent/reply :a rp) (aslAgent/exec :a ex)
      (aslAgent/core :a c) (asl-json/json :a j) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl-checker/check :a chk) (asl-checker/types :a ty)])

; (:m :ref LEON-ASL-GROUNDING :do "the ASL card Leon sends a model is cut from tools.asn and the canonical examples, its write steps bind through the same raw-block parser the loop uses, it rides only on ASL tasks, and a rejected write or unknown-key receipt comes back next turn as an (:expect) form with the exact step shape")

fn rawMissingGot -> String
  (str "(:step :op \"write\" :file \"scratch/a.asl\" :content :raw :error \"ERR_RAW_MISSING\")\n"
       "(:receipt :id \"46f39f957d8757af\" :op \"write\" :status :rejected :file \"scratch/a.asl\" :error :ERR_RAW_MISSING :message \"missing raw block for :raw\")\n"
       "(:receipt :id \"46f39f957d8757b0\" :op \"write\" :status :rejected :file \"scratch/a.asl\" :error :ERR_RAW_MISSING :message \"missing raw block for :raw\")\n"
       "(:receipt :id \"71dd738bd583a6a4\" :op \"query\" :status :rejected :hits ((:query :status :rejected :error ERR_UNKNOWN_KEY :keys (:query) :accepted (:text :in :limit) :see \"(:help :op query)\")))\n"
       "(:receipt :id \"912c631e1eed39f0\" :op \"write\" :status :ok :file \"scratch/b.asl\")")

; (:m :do "the Option match example returns the element itself, so its xs is a list of Int64; every other example reads xs as strings")
fn xsType expr: String -> String
  (if (stringStartsWith? expr "(match (listGet xs 0)") "(List Int64)" "(List String)")

fn exampleSource examples: (List (Pair String String)) -> String
  (str "(module q/card\n  :x [" (stringJoin (map (fn [i] (str "e" (stringFromInt64 i))) (range 0 (listLength examples))) " ") "]\n  :i [])\n"
       (stringJoin (map (fn [p] (str "\nfn e" (stringFromInt64 (pairFirst p)) " xs: " (xsType (pairFirst (pairSecond p))) " s: String ns: (List Int64) n: Int64 r: (Result Int64 String) -> " (pairSecond (pairSecond p)) "\n  " (pairFirst (pairSecond p)) "\n"))
                        (enumerate examples)) ""))

fn exampleDiags examples: (List (Pair String String)) -> Int64
  (listLength (chk/checkSource (exampleSource examples) (mapEmpty) "q/card.asl"))

fn countOf hay: String needle: String -> Int64
  (- (listLength (stringSplit hay needle)) 1)

fn journalFixture -> String
  "(:turn 1 :got \"argument to stringSlice: a argument to mapGet: x\") (:turn 2 :got \"argument to stringSlice: b argument to mapGet: y unbound symbol: localHelper\") (:turn 3 :got \"argument to stringSlice: c ERR_ARITY pair takes 2, given 3 unbound symbol: localHelper unbound symbol: localHelper\") (:turn 4 :got \"ERR_ARITY pair takes 2 unbound symbol: localHelper unbound symbol: localHelper unbound symbol: localHelper\")"

fn journalShuffled -> String
  "(:turn 4 :got \"ERR_ARITY pair takes 2 unbound symbol: localHelper unbound symbol: localHelper unbound symbol: localHelper\") (:turn 2 :got \"argument to mapGet: y argument to stringSlice: b unbound symbol: localHelper\") (:turn 1 :got \"argument to mapGet: x argument to stringSlice: a\") (:turn 3 :got \"ERR_ARITY pair takes 2, given 3 argument to stringSlice: c unbound symbol: localHelper unbound symbol: localHelper\")"

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        cardR (gr/aslCard! root)
        card (resultOr cardR "")
        lang (resultOr (gr/languageText! root) "")
        rules (gr/languageRules lang)
        lib (resultOr (fileReadString (str root "/asl/grammar/examples/record.asl")) "")
        libEx (gr/libExample lib (gr/cardItems))
        types (gr/typeRules lang)
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
      (assert (stringStartsWith? libEx "(module asl/grammar/examples/record\n  :x [Point origin moveBy]\n  :i [])") "the lib example header exports only the shown items")
      (assert (stringContains? libEx "\n(schema Point (:f x Int64) (:f y Int64))\n") "the schema line is cut from record.asl by name")
      (assert (stringContains? libEx "fn origin -> Point\n  (Point :x 0 :y 0)") "construction names every field")
      (assert (stringContains? libEx "fn moveBy p: Point dx: Int64 dy: Int64 -> Point\n  (with p :x (+ p.x dx) :y (+ p.y dy))") "the with copy is cut from record.asl by symbol")
      (assert (listAll? (fn [l] (stringContains? lib l)) (filter (fn [l] (not (stringEmpty? l))) (listDrop (stringLines libEx) 3))) "every shown line is a line of record.asl")
      (assert (stringContains? card (str "(:step :op \"write\" :file \"asl/grammar/examples/record.asl\" :content :raw)\n```\n" libEx "\n```")) "the lib is shown as the raw write step Leon parses")
      (assert (= bound.count 1) "the card write step binds their fenced block through reply/bindRawBlocks")
      (assert (listEmpty? bound.missing) "the card write step has its raw block")
      (assert (stringContains? bound.text (str "\"" (c/escapeAsn (str libEx "\n")) "\""))  "the bound content is the lib example itself, newline-terminated")
      (assert (<= (stringLength card) 8000) "the card stays within the 8000-character budget cardTest sets")
      (assert (= (listLength types) (listLength (gr/cardTypeAnchors))) "every type anchor is found in the language topic")
      (assert (listAll? (fn [r] (stringContains? lang r)) types) "each type rule is a verbatim sentence of the language topic")
      (assert (stringStartsWith? card (str "(:aslCard :types (\"" (c/escapeAsn (optionOr (listHead types) "")) "\"")) "the card leads with the no-nil Option rule")
      (assert (stringContains? (optionOr (listHead types) "") "listGet, listSlice, stringSlice and mapGet return (some v) or (none)") "the lead rule names the Option-returning builtins")
      (assert (< (optionOr (stringIndexOf card ":sigs") 0) (optionOr (stringIndexOf card ":rules") 0)) "signatures come before the shape rules")
      (assert (= (gr/sigLine "listGet") "listGet (List T) Int64 -> (Option T)") "a signature line is the checker's own builtinSig")
      (assert (listAll? (fn [n] (stringContains? card (str "\"" (gr/sigLine n) "\""))) (gr/cardSigNames)) "every listed builtin carries its checker signature")
      (assert (listAll? (fn [n] (not (stringEmpty? (gr/sigLine n)))) (gr/cardSigNames)) "every listed builtin is known to the checker")
      (assert (stringContains? card (str ":sigs (\"" (gr/sigLine "println") "\" \"" (gr/sigLine "some?") "\"")) "the builtins the journals show models misnaming lead the sigs, then the repo-frequency list")
      (assert (stringContains? card (str "\"" (gr/sigLine "optionOr") "\" \"" (gr/sigLine "pair") "\"")) "the most-called builtins follow in repo-frequency order")
      (assert (stringContains? card ":wrong (\"println! -> println\" \"isSome -> some?\"") "the card names the invented spellings measured in the journals")
      (assert (stringContains? card "ASL is not on the web, never web-search") "the lookup row says ASL is not on the web")
      (assert (listAll? (fn [op] (listAny? (fn [p] (= (pairFirst p) op)) (ex/opShapes))) (gr/namesAfter (gr/toolLookup) "(:step :op ")) "every op the lookup row advertises is an op exec accepts")
      (assert (not (stringContains? (gr/toolLookup) ":name builtinName")) "the lookup row does not advertise help on a builtin name, which fails today")
      (assert (>= (listLength (gr/namesAfter (gr/toolLookup) "(:step :op ")) 4) "the lookup row names at least four ops")
      (assert (<= (gr/tokensOf (gr/toolCard (gr/toolErrNames))) (gr/toolCapTokens)) "the tool card stays within the 2000-token cap, counted as bytes/3, a conservative bound for code")
      (assert (<= (/ (stringLength (gr/toolCard (gr/toolErrNames))) 3) (gr/toolCapTokens)) "the card's own bytes/3 is within the cap, so the bound is real at about 3 chars per token")
      (assert (listAll? (fn [p] (and (some? (ty/builtinSig (pairSecond p))) (not (some? (ty/builtinSig (pairFirst p)))))) (gr/toolWrongNames)) "every invented spelling has no builtinSig and every target has one")
      (assert (listAll? (fn [n] (some? (ty/builtinSig n))) (gr/toolErrNames)) "every name in toolErrNames has a builtinSig line to show")
      (assert (= (gr/toolCard (gr/toolErrNames)) (gr/toolCard (gr/toolErrNames))) "the tool card is identical on every build")
      (assert (< (gr/tokensOf (gr/toolCardCapped (gr/toolErrNames) 300)) 301) "a 300-token cap is honoured")
      (assert (<= (/ (stringLength (gr/toolCardCapped (gr/toolErrNames) 300)) 3) 300) "a 300-token cap holds by an independent bytes/3 count")
      (assert (< (listLength (stringSplit (gr/toolCardCapped (gr/toolErrNames) 300) " -> ")) (listLength (stringSplit (gr/toolCard (gr/toolErrNames)) " -> "))) "a tight cap drops the tail of the sigs, not the head")
      (assert (stringContains? (gr/toolCardCapped (gr/toolErrNames) 300) (gr/sigLine "println")) "the cap keeps the head of the ranking")
      (assert (= (gr/rankedBuiltins (gr/errorCounts (journalFixture))) (list "stringSlice" "mapGet" "pair")) "journal fixture: builtins by error count, ties by name, helpers that are not builtins dropped")
      (assert (= (gr/rankedBuiltins (gr/errorCounts (journalShuffled))) (list "stringSlice" "mapGet" "pair")) "the ranking does not depend on journal order")
      (assert (stringContains? (gr/toolCard (gr/rankedBuiltins (gr/errorCounts (journalFixture)))) (str ":sigs (\"" (gr/sigLine "stringSlice") "\" \"" (gr/sigLine "mapGet") "\" \"" (gr/sigLine "pair") "\"")) "the fixture journal's top builtins lead the sigs in rank order")
      (assert (= (gr/sigLine "mapEmpty") "mapEmpty () -> (Map K V)") "a builtin with no parameters prints () where the checker has an empty list")
      (assert (listAll? (fn [s] (not (stringEmpty? (gr/sigLine s)))) (list "mapEmpty" "mapSet" "pair" "pairFirst" "pairSecond")) "the map and pair builtins are known to the checker")
      (assert (listAll? (fn [n] (stringContains? card (str "\"" (gr/sigLine n) "\""))) (list "stringSplit" "stringSlice")) "the string signatures are on the card, as the checker's builtinSig prints them")
      (assert (listAll? (fn [s] (not (stringEmpty? (gr/sigLine s)))) (list "stringSplit" "stringSlice" "stringUpper")) "the string builtins are known to the checker")
      (assert (stringContains? card (c/escapeAsn "(match (listGet xs 0) ((some v) v) ((none) 0))")) "the Option match example is on the card")
      (assert (stringContains? card (c/escapeAsn "(match r ((ok v) (ok (+ v 1))) ((err e) (err e)))")) "the Result match example is on the card")
      (assert (= (exampleDiags (list (pair "(match (listGet xs 0) ((some v) v) ((none) 0))" "Int64") (pair "(match r ((ok v) (ok (+ v 1))) ((err e) (err e)))" "(Result Int64 String)"))) 0) "both match examples type-check at their declared types")
      (refute (= (exampleDiags (list (pair "(match (listGet xs 0) ((some v) v) ((none) \"\"))" "Int64"))) 0) "arms of different types are rejected, so the match check is not vacuous")
      (assert (listAll? (fn [p] (stringContains? card (c/escapeAsn (pairFirst p)))) (gr/cardExamples)) "every example is on the card")
      (assert (= (exampleDiags (gr/cardExamples)) 0) "every card example type-checks at its declared type")
      (refute (= (exampleDiags (list (pair "(stringLength (listGet xs 0))" "Int64"))) 0) "the checker rejects an Option used as a String, so the example check is not vacuous")
      (assert (stringContains? aslPrompt "(:aslCard :types (") "an ASL task gets the card in its system prompt")
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
