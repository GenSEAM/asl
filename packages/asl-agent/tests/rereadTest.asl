(module aslAgent/tests/rereadTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/context :a ctx) (aslAgent/main :a m) (asl-json/json :a j)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEONFIX-READSTREAK :do "a read of lines an earlier kept turn still shows is answered by a notice, the second one asks for the edit and names the owned files, an edit to the file ends the cache for it; grade H1/M3: a repeat-only turn counts toward the read-only cap and the readStreak like any read, so a loop of repeats stops no later than one of new reads; L1: a notice whose turn left the kept window says so and the next read of those lines is content")

fn readReply file: String first: Int64 last: Int64 -> String
  (str "(:step :op \"read\" :file \"" file "\" :start " (stringFromInt64 first) " :end " (stringFromInt64 last) ")")

fn ! recorded! tag: String cap: Int64 replies: (List String) -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "alpha one\nbeta two\ngamma three\ndelta four\nepsilon five\nzeta six\n")
        wroteO (fileWrite (str root "/other.txt") "o1\no2\no3\no4\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :readOnlyTurnCap " (stringFromInt64 cap) "))"))
        repo (gk/initGitRepoWith! root "reread" "reread@example.invalid" (list "subject.txt" "other.txt"))
        run (rk/runRecordedAgentLoopWithReplies! root (str "reread" tag) replies (list "subject.txt") "fix subject" 20 8000)
        cleaned (pathRemove root)]
    run)

; (:m :ref LEONFIX-READSTREAK :do "a run under a declared gate that always fails, with the baseline off and the caps from cfg; returns the journal and the printed receipt")
fn ! gatedRun! tag: String cfg: String replies: (List String) -> String
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "alpha one\nbeta two\ngamma three\ndelta four\nepsilon five\nzeta six\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") cfg)
        repo (gk/initGitRepoWith! root "reread" "reread@example.invalid" (list "subject.txt"))
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/rg" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "rg" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/rg" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"false\") :budget 40 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")
        rootDir (match (envGet "ASL_ROOT_DIR") ((some r) (if (stringEmpty? r) repoRoot r)) ((none) repoRoot))
        res (m/mainWithRoots (list form) repoRoot rootDir)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        cleaned (pathRemove root)]
    (str journal "\n" res.stdout))

fn gateCfg cap: Int64 escalate: Int64 -> String
  (str "(:aslConfig :agentLoop (:specCheck false :baseline false :readOnlyTurnCap " (stringFromInt64 cap) " :readStreakEscalate " (stringFromInt64 escalate) " :readStreakNudge 2))")

fn cycles k: Int64 -> (List String)
  (fold (fn [acc _] (listAppend acc (list (readReply "subject.txt" 2 4) (readReply "subject.txt" 2 4) "(:step :op \"gate\")"))) (list) (range 0 k))

fn receiptOf file: String lines: String content: String -> String
  (str "(:receipt :id \"r" file "\" :op \"read\" :status :ok :file \"" file "\" :lines (" lines ") :content \"" content "\")")

fn readGot file: String lines: String content: String -> String
  (str "(:step :op \"read\" :file \"" file "\")\n" (receiptOf file lines content))

fn noticeGot file: String lines: String turn: String -> String
  (str "(:step :op \"read\" :file \"" file "\")\n(:receipt :id \"r" file "\" :op \"read\" :status :ok :file \"" file "\" :lines (" lines ") :content (:same :turn " turn ") :note \"unchanged, already in context at turn " turn "\")")

fn entry turn: Int64 got: String ops: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr "Task: read")) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr ops)) (pair "files" (j/jstr "")) (pair "gates" (j/jstr "")) (pair "wrote" (j/jstr "0"))))

; (:m :do "history grown one turn at a time as the loop freezes it, keeping 4 whole turns: the cut moves from 0 to 4 at the eighth turn")
fn grow history: (List j/Json) h: j/Json -> (List j/Json)
  (ctx/freezeTranscriptHistory (listAppend history (list h)) 4 1500 4000 4000)

fn renderedOf history: (List j/Json) turn: Int64 -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :sent "))) (stringSplit (ctx/renderTranscriptKept history 4 1500 50 4000 4000) "\n"))) "")

fn keptAfter history: (List j/Json) next: Int64 -> (List j/Json)
  (ctx/keptBefore (listAppend history (list (entry next "" "read"))))

fn clip s: String n: Int64 -> String
  (c/sliceOf s 0 (min n (stringLength s)))

fn sentOf run: rk/RecordedRun turn: Int64 -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :sent "))) run.sentLines)) "")

fn occurrences text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn ! runTests -> Bool
  (let [tricky "a \\n b \"q\" \\\\ end\nnext\tline\\"
        cache (recorded! "Cache" 12 (list
                (readReply "subject.txt" 1 6) (readReply "subject.txt" 2 4) (readReply "subject.txt" 1 3)
                "(:step :op \"edit\" :file \"subject.txt\" :old \"epsilon five\" :new \"EPSILON five\")"
                (readReply "subject.txt" 2 4) (readReply "subject.txt" 2 4) "(:done)"))
        mixed (recorded! "Mixed" 4 (list
                (readReply "subject.txt" 1 6) (readReply "subject.txt" 2 4) (readReply "subject.txt" 1 3) (readReply "subject.txt" 5 6)
                (readReply "other.txt" 1 1) (readReply "other.txt" 2 2) (readReply "other.txt" 3 3)))
        looped (recorded! "Looped" 4 (cons (readReply "subject.txt" 1 6) (map (fn [_] (readReply "subject.txt" 2 4)) (range 0 8))))
        graderLoop (gatedRun! "Grader" (gateCfg 3 3) (cons (readReply "subject.txt" 1 6) (cycles 4)))
        streakLoop (gatedRun! "Streak" (gateCfg 100 4) (cons "(:step :op \"write\" :file \"subject.txt\" :content \"alpha one\\nbeta two\\ngamma three\\ndelta four\\nepsilon five\\nzeta six\\nseven\\n\")" (cons (readReply "subject.txt" 1 6) (map (fn [_] (readReply "subject.txt" 2 4)) (range 0 10)))))
        h3 (fold (fn [acc t] (grow acc (entry t (readGot (str "f" (stringFromInt64 t) ".txt") "1 1" "x\\n") "read"))) (list) (range 1 4))
        h5 (grow (grow h3 (entry 4 (readGot "a.txt" "1 2" "alpha one\\nalpha two\\n") "read")) (entry 5 (noticeGot "a.txt" "1 2" "4") "reread"))
        h7 (grow (grow h5 (entry 6 (readGot "f6.txt" "1 1" "y\\n") "read")) (entry 7 (noticeGot "a.txt" "1 2" "4") "reread"))
        h8 (grow h7 (entry 8 (readGot "f8.txt" "1 1" "z\\n") "read"))
        same (receiptOf "a.txt" "1 2" "alpha one\\nalpha two\\n")
        held (ctx/rereadMarked same (keptAfter h5 6))
        changed (ctx/rereadMarked (receiptOf "a.txt" "1 2" "alpha one\\nalpha CHANGED\\n") (keptAfter h5 6))
        fresh (ctx/rereadMarked same (keptAfter h8 9))
        notice "(:same :turn 1) :note \\\\\\\"unchanged, already in context at turn 1"
        ask "(:reread :n 2 :owns (\\\\\\\"subject.txt\\\\\\\")"]
    (do
      (assert (= (ctx/asnUnescape (c/escapeAsn tricky)) tricky) "asnUnescape inverts escapeAsn, also for a backslash before n")
      (assert (stringContains? cache.journal "(:turn 2 :signal :reread :n 1 :seen 1)") "a read inside lines turn 1 still shows is a repeat")
      (assert (= (occurrences (sentOf cache 3) notice) 1) (str "the repeat is answered by the notice, in the next prompt " (sentOf cache 3)))
      (assert (= (occurrences (sentOf cache 3) "gamma three") (occurrences (sentOf cache 2) "gamma three")) "the repeated lines are not sent again: the prompt after the repeat holds them as often as the one before it")
      (assert (not (stringContains? (sentOf cache 3) "(:reread :n")) "one repeat does not yet ask for the edit")
      (assert (stringContains? cache.journal "(:turn 3 :signal :reread :n 1 :seen 2)") "the second repeat is counted")
      (assert (stringContains? (sentOf cache 4) ask) (str "the second repeat asks for the edit and names the owned file, prompt " (sentOf cache 4)))
      (assert (not (stringContains? cache.journal "(:turn 5 :signal :reread")) "after an edit to the file a read of unchanged lines of it is not a repeat")
      (assert (= (occurrences (sentOf cache 6) "gamma three") (+ 1 (occurrences (sentOf cache 5) "gamma three"))) "after the edit the lines are sent again")
      (assert (stringContains? cache.journal "(:turn 6 :signal :reread :n 1 :seen 1)") "the read after the edit is the new cache entry")
      (assert (stringContains? mixed.journal "(:turn 4 :signal :readStreak :cause :readOnly :reason \"4 turns in a row") "a new read and three repeat turns reach the cap of 4: a repeat saves the content, not a turn (H1)")
      (assert (not (stringContains? mixed.journal "(:turn 5 :reply")) "no turn runs past the cap")
      (assert (stringContains? looped.journal "(:turn 4 :signal :readStreak :cause :readOnly :reason \"4 turns in a row") "repeat-only turns stop at the cap as readStreak readOnly on the turn new reads would")
      (assert (stringContains? graderLoop ":signal :readStreak") "the grader's read, [repeat, repeat, gate] loop under a red gate stops as readStreak (M3)")
      (assert (not (stringContains? graderLoop "(:turn 4 :reply")) "it stops at the cap of 3: a gate turn between repeats buys no turns")
      (assert (stringContains? streakLoop "(:turn 3 :signal :reread") (str "under the red gate the repeat of turn 3 is a reread: " (clip streakLoop 6000)))
      (assert (stringContains? streakLoop ":signal :readStreak") "repeats under a red gate stop as readStreak with the read-only cap out of reach")
      (assert (not (stringContains? streakLoop "(:turn 7 :reply")) "repeat-only turns count toward the readStreak: after the write of turn 1, escalate 4 stops the run by turn 6")
      (assert (stringContains? streakLoop ":stop readStreak :lastStep (:turn 5 :op \"read\") :streak 4 ") (str "the receipt counts every turn, the repeats too, in :streak: " (clip streakLoop 6000)))
      (assert (= (pairSecond held) 1) "a read of lines turn 4 still shows whole is a repeat while turn 4 is kept")
      (assert (= (pairSecond changed) 0) "a changed line under the same span is sent as content")
      (assert (stringContains? (pairFirst changed) "alpha CHANGED") "the changed read keeps its content")
      (assert (stringContains? (renderedOf h7 4) "alpha two") "turn 4 is kept whole at seven turns")
      (assert (stringContains? (renderedOf h7 5) "already in context at turn 4") "while turn 4 is kept the notice of turn 5 names it")
      (assert (stringEmpty? (renderedOf h8 4)) "compaction at turn 8 drops turn 4 from the kept window")
      (assert (not (stringEmpty? (renderedOf h8 5))) "turn 5 is still kept")
      (assert (not (stringContains? (renderedOf h8 5) "already in context at turn 4")) (str "once turn 4 left the kept window no notice names it: " (renderedOf h8 5)))
      (assert (not (stringContains? (renderedOf h8 7) "already in context at turn 4")) "the notice of turn 7 is rewritten too")
      (assert (stringContains? (renderedOf h8 7) "no longer in context, re-read to see") "the stale notice says a re-read shows the lines")
      (assert (= (pairSecond fresh) 0) "after turn 4 left, the next read of its lines is content, not a notice")
      (assert (stringContains? (pairFirst fresh) "alpha two") "the read after the drop carries the lines")
      (assert (and (ctx/rereadAskDue 2 1) (and (ctx/rereadAskDue 3 2) (ctx/rereadAskDue 6 1))) "the ask is due when the repeats reach 2 and again at 6")
      (assert (not (or (ctx/rereadAskDue 1 1) (or (ctx/rereadAskDue 3 1) (or (ctx/rereadAskDue 5 1) (ctx/rereadAskDue 2 0))))) "no ask before the second repeat, none on the turns between, none on a turn without a repeat")
      true))
