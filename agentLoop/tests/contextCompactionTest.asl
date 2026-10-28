(module asl/agentLoop/tests/contextCompactionTest
  :x [runTests]
  :i [(asl/agentLoop/context :a ctx) (asl-json/json :a j)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-CONTEXT-RESEND-20261017 :do "renderTranscript's budget was the model's entire context window, so a run of a few dozen turns never reached it and resent the whole growing history verbatim every call; this suite proves the three things the fix promises: a per-call ceiling that holds for a run far longer than the old mechanism would tolerate, the final receipt is unaffected by whether compaction actually triggered, and the rendered prefix is never rewritten call over call (only ever appended to) as long as the run stays under the hard-drop cap")

fn histEntry turn: Int64 sent: String got: String ops: String files: String gates: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr sent)) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr ops)) (pair "files" (j/jstr files)) (pair "gates" (j/jstr gates))))

fn plainHistory n: Int64 -> (List j/Json)
  (map (fn [i] (histEntry (+ i 1) (str "sent" (stringFromInt64 (+ i 1))) (str "got" (stringFromInt64 (+ i 1)))
         "read" "subject.txt" "1/1 green"))
    (range 0 n))

fn oldSummaryPrefix n: Int64 keepTurns: Int64 maxOlderLines: Int64 -> String
  (let [older (optionOr (listSlice (plainHistory n) 0 (ctx/compactionCut n keepTurns (ctx/contextCompactStep))) (list))
        olderCount (listLength older)
        survivors (optionOr (listSlice older (max 0 (- olderCount maxOlderLines)) olderCount) (list))]
    (stringJoin (map ctx/turnReceiptLine survivors) "\n"))

fn writeConfig! root: String keepTurns: Int64 toolCapBytes: Int64 maxOlderLines: Int64 -> Bool
  (ok? (fileWrite (str root "/.asl.config.asn")
    (str "(:agentLoop (:specCheck false) :contextKeepTurns " (stringFromInt64 keepTurns)
      " :contextToolCapBytes " (stringFromInt64 toolCapBytes)
      " :contextMaxOlderLines " (stringFromInt64 maxOlderLines) ")\n")))

fn initRepo! root: String initial: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") initial))
    (gk/initGitRepo! root "compactionTest" "compaction-test@example.invalid"))

fn readRepoFile root: String -> String
  (resultOr (fileReadString (str root "/subject.txt")) "")

fn fortyReplies -> (List String)
  (listAppend (map (fn [_] "(:step :op \"read\" :file \"subject.txt\")") (range 0 39))
    (list "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)"))

fn runCompactionScenario! tag: String keepTurns: Int64 toolCapBytes: Int64 maxOlderLines: Int64 -> (Pair String rk/RecordedRun)
  (let [root (rk/freshRecorderRoot! tag)
        ready (initRepo! root "before\n")
        configured (writeConfig! root keepTurns toolCapBytes maxOlderLines)
        run (rk/runRecordedAgentLoopWithReplies! root (str "compaction" tag) (fortyReplies) (list "subject.txt")
              "read subject.txt 39 times then write green and finish" 45 8000)]
    (pair root run))

fn maxSentLen lines: (List String) -> Int64
  (fold (fn [acc l] (max acc (stringLength l))) 0 lines)

fn runTests -> Bool
  (let [h11 (plainHistory 12)
        h12 (plainHistory 13)
        result11 (ctx/renderTranscriptBounded h11 5 300 50)
        result12 (ctx/renderTranscriptBounded h12 5 300 50)
        prefix11 (oldSummaryPrefix 12 5 50)
        prefix12 (oldSummaryPrefix 13 5 50)

        h60 (plainHistory 60)
        resultDropped (ctx/renderTranscriptBounded h60 5 300 10)

        bigGot (stringJoin (map (fn [_] "x") (range 0 1000)) "")
        hBig (list (histEntry 1 "sentx" bigGot "read" "subject.txt" ""))
        resultClipped (ctx/renderTranscriptBounded hBig 5 50 50)

        cfgText "(:agentLoop :contextKeepTurns 3 :contextToolCapBytes 77 :contextMaxOlderLines 9)"

        tightPair (runCompactionScenario! "tight" 5 300 50)
        loosePair (runCompactionScenario! "loose" 1000 100000 1000)
        tightRoot (pairFirst tightPair)
        tight (pairSecond tightPair)
        looseRoot (pairFirst loosePair)
        loose (pairSecond loosePair)
        tightMax (maxSentLen tight.sentLines)
        looseMax (maxSentLen loose.sentLines)
        tightFile (readRepoFile tightRoot)
        looseFile (readRepoFile looseRoot)
        tightCleaned (ok? (pathRemove tightRoot))
        looseCleaned (ok? (pathRemove looseRoot))
        ceiling 6000]
    (do
      (assert (stringStartsWith? result12 prefix11)
        "renderTranscriptBounded never rewrites an earlier call's older-summary section -- call 12's output starts with exactly call 11's older-summary text")
      (assert (stringStartsWith? result11 prefix11)
        "call 11's own older-summary section matches the same text independently computed from its own survivors")
      (assert (> (stringLength prefix12) (stringLength prefix11))
        "the older-summary section grows by exactly one appended line as a turn ages out of the kept window")

      (assert (not (stringContains? resultDropped "(:turnSummary :turn 1 "))
        "once older turns exceed maxOlderLines, the oldest excess are dropped with no line at all")
      (assert (not (stringContains? resultDropped "(:turnSummary :turn 42 "))
        "turn 42 is still past the 10-line survivor window at 60 turns / keepTurns 5 and is dropped too")
      (assert (stringContains? resultDropped "(:turnSummary :turn 43 ")
        "turn 43 is the oldest surviving summary line (60 turns, keepTurns 5, maxOlderLines 10 -> survivors are turns 43..52, the cut moves in steps of 4 so 52 turns are summarised)")
      (assert (stringContains? resultDropped "(:turnSummary :turn 52 ")
        "turn 52 is the newest line still in the summary section (turn 53..60 are in the kept-whole tail)")

      (assert (stringContains? resultClipped "more bytes clipped, see turn 1 in the journal")
        "a kept turn's tool output past toolCapBytes is clipped with a pointer back to the journal")
      (assert (not (stringContains? resultClipped bigGot))
        "the clipped kept turn never contains the full, unclipped tool output")

      (assert (= (ctx/contextKeepTurnsIn cfgText) (some 3)) "contextKeepTurnsIn reads the configured turn count")
      (assert (= (ctx/contextToolCapBytesIn cfgText) (some 77)) "contextToolCapBytesIn reads the configured byte cap")
      (assert (= (ctx/contextMaxOlderLinesIn cfgText) (some 9)) "contextMaxOlderLinesIn reads the configured drop cap")
      (assert (= (ctx/contextKeepTurnsIn "(:agentLoop :budget 30)") (none))
        "contextKeepTurnsIn returns none when the key is absent, so the caller falls back to the default")

      (assert (= tight.exitCode loose.exitCode) "compacting the transcript never changes the run's final exit code")
      (assert (= tight.exitCode 0) "the 40-turn scripted run reaches a successful exit code at all")
      (assert (= tightFile looseFile) "compaction never changes what actually lands on disk -- same final written file either way")
      (assert (= tightFile "green\n") "the written file reflects the scripted write on turn 40, not some clipped or summarized stand-in")
      (assert (stringContains? tight.journal "(:result :status :ok") "the tightly-compacted run still reaches a successful terminal receipt")
      (assert (stringContains? loose.journal "(:result :status :ok") "the loosely-compacted (effectively uncompacted) run reaches the same terminal receipt")
      (assert (= (listLength tight.sentLines) (listLength loose.sentLines))
        "compaction changes what each turn is sent, never how many turns the run takes")
      (assert tightCleaned "the tight-config scenario's temporary root is removed")
      (assert looseCleaned "the loose-config scenario's temporary root is removed")

      (assert (< tightMax ceiling)
        (str "max per-call input under the tight config was " (stringFromInt64 tightMax) ", wanted under " (stringFromInt64 ceiling)))
      (assert (> looseMax tightMax)
        (str "the effectively-uncompacted run's largest per-call input (" (stringFromInt64 looseMax)
          ") is larger than the compacted run's (" (stringFromInt64 tightMax)
          ") -- compaction is doing real work, not a no-op"))
      true))
