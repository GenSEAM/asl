(module aslAgent/tests/readLoopContextTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/context :a ctx) (aslAgent/main :a m) (asl-json/json :a j)])

; (:m :ref LEON-READ-LOOP-CONTEXT-LOSS :do "U11 30 read-only turns, turn 13 repeating turn 1's reads: a re-read still shown whole in the kept window is a (:same :turn N) marker, a stale marker re-renders with the content, a dropped turn's digest names its read ranges, and a read-only streak gets one (:mustEdit :known ...) form at 6 of the default 12")

fn readGot file: String lines: String content: String -> String
  (str "(:step :op \"read\" :file \"" file "\")\n(:receipt :id \"r" file lines "\" :op \"read\" :status :ok :file \"" file "\" :lines (" lines ") :content \"" content "\")")

fn entry turn: Int64 got: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr "Task: read")) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr "read")) (pair "files" (j/jstr "")) (pair "gates" (j/jstr "")) (pair "wrote" (j/jstr "0"))))

; (:m :ref LEON-READ-LOOP-CONTEXT-LOSS :do "an entry already rendered, as freezeTranscriptHistory stores it, so a test can hand it a target clipped after its marker was made, as when the kept cap changes with the served context mid-run")
fn renderedEntry turn: Int64 got: String rendered: String shown: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr "Task: read")) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr "read")) (pair "files" (j/jstr "")) (pair "gates" (j/jstr "")) (pair "wrote" (j/jstr "0"))
    (pair "rendered" (j/jstr rendered)) (pair "shown" (j/jstr shown))))

fn grow history: (List j/Json) h: j/Json keptCap: Int64 -> (List j/Json)
  (ctx/freezeTranscriptHistory (listAppend history (list h)) 8 40 keptCap 4000)

fn renderedOf history: (List j/Json) turn: Int64 -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :"))) (stringSplit (ctx/renderTranscriptKept history 8 40 50 40 4000) "\n"))) "")

fn ! runTests -> Bool
  (let [a (readGot "a.txt" "1 2" "alpha one\\nalpha two\\n")
        b (readGot "b.txt" "1 1" "beta one\\n")
        h1 (grow (list) (entry 1 a) 2000)
        h2 (grow h1 (entry 2 b) 2000)
        h3 (grow h2 (entry 3 a) 2000)
        r3 (renderedOf h3 3)
        r1 (renderedOf h3 1)
        h4 (grow h3 (entry 4 (readGot "a.txt" "1 2" "alpha one\\nalpha CHANGED\\n")) 2000)
        r4 (renderedOf h4 4)
        whole1 (renderedOf h1 1)
        sameWhole (ctx/sameMarkedGot a (list (j/jobj (list (pair "turn" (j/jstr "1")) (pair "rendered" (j/jstr whole1))))))
        sameClipped (ctx/sameMarkedGot a (list (j/jobj (list (pair "turn" (j/jstr "1")) (pair "rendered" (j/jstr (optionOr (stringSlice whole1 0 (- (stringLength whole1) 12)) "")))))))
        w8 (fold (fn [acc i] (grow acc (entry i (if (< i 3) a b)) 60)) (list) (range 1 9))
        w9 (grow w8 (entry 9 b) 60)
        staleH (ctx/freezeTranscriptHistory (list (renderedEntry 1 a "(:turn 1 :sent \"Task: read\" :got \"clipped\")" "")
          (renderedEntry 2 a "(:turn 2 :sent \"Task: read\" :got \"(:same :turn 1)\")" sameWhole) (entry 3 b)) 8 40 2000 4000)
        staleR2 (renderedOf staleH 2)
        digest (ctx/turnReceiptLine (entry 5 (str a "\n" b)))
        must (ctx/mustEditForm (list (entry 1 a) (entry 2 b) (entry 3 a)) (list "src/x.asl") 6)
        root (rk/freshRecorderRoot! "readLoopContext")
        w1 (ok? (fileWrite (str root "/a.txt") "alpha line one\nalpha line two\n"))
        w2 (ok? (fileWrite (str root "/b.txt") "beta line one\n"))
        reads (map (fn [i] (if (= (mod i 2) 0) "a.txt" "b.txt")) (range 0 14))
        run (rk/runRecordedAgentLoop! root "readLoopContext" reads "read" 30 8000)
        sentSame (filter (fn [l] (stringContains? l ":content (:same :turn 1)")) run.sentLines)
        sentMust (filter (fn [l] (stringContains? l "(:mustEdit :readOnly 6 :known (")) run.sentLines)
        cleaned (ok? (pathRemove root))]
    (do
      (assert (stringContains? r3 ":content (:same :turn 1)") "turn 3 re-reads turn 1's range with the same content and gets a (:same :turn 1) marker")
      (assert (not (stringContains? r3 "alpha two")) "the marked turn does not carry the content again")
      (assert (stringContains? r1 "alpha two") "turn 1 still shows the content the marker points to")
      (assert (stringContains? r4 "alpha CHANGED") "a read whose content changed is shown, not marked")
      (assert (not (stringContains? r4 ":same")) "changed content gets no marker")
      (assert (stringContains? sameWhole ":content (:same :turn 1)") "an earlier rendering that shows the read whole yields the marker")
      (assert (not (stringContains? sameClipped ":same")) "no marker points at a rendering that clipped the content")
      (assert (stringContains? (renderedOf w8 2) ":content (:same :turn 1)") "turn 2 is marked while turn 1 shows the read whole")
      (assert (not (stringContains? (renderedOf w9 2) ":same")) "when the window first fills and turn 1 re-renders clipped at the kept cap, turn 2 re-renders without the stale marker")
      (assert (and (stringContains? staleR2 "alpha two") (not (stringContains? staleR2 ":same"))) (str "a stored marker whose target no longer shows the read whole re-renders with the content: " staleR2))
      (assert (stringContains? digest ":read \"a.txt:1-2 b.txt:1-1\"") (str "a dropped turn's digest names the ranges it read: " digest))
      (assert (stringContains? must ":known (\"a.txt:1-2\" \"b.txt:1-1\")") (str "mustEdit lists each read range once: " must))
      (assert (stringContains? must ":owns (\"src/x.asl\")") "mustEdit names the owned files")
      (assert (= (m/readOnlyTurnCapIn "") 12) "readOnlyTurnCap defaults to 12")
      (assert (and w1 w2) "fixture files are written")
      (assert (not (listEmpty? sentSame)) "in a real loop, a re-read of turn 1's file reaches the model as (:same :turn 1)")
      (assert (= (listLength sentMust) (- (listLength run.sentLines) 6)) (str "the mustEdit form is injected once at the 6th read-only turn and stays in the window: " (stringFromInt64 (listLength sentMust)) " of " (stringFromInt64 (listLength run.sentLines))))
      (assert (stringContains? run.journal "(:turn 6 :signal :readNudge :readOnly 6 :cap 12)") "the nudge point is 6 of the default cap 12")
      (assert (stringContains? run.journal ":signal :readStreak :cause :readOnly") "the default cap of 12 stops 14 read-only turns")
      (assert cleaned "the fixture root is removed")
      true))
