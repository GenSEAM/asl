(module aslAgent/tests/escalateUnreadTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-ESCALATE-UNREAD :do "GWADMIT escalated at turn 7 naming owned files it had not read with most of its budget left; the first escalation that names an unread owned file is answered with a read hint and the run goes on, a second one after the read stops it")

fn escalateReply what: String -> String
  (str "(:escalate :reason \"blocked: " what " needs a change I cannot see\" :seen \"the task\" :tried \"nothing\")")

fn ! recorded! tag: String replies: (List String) -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root tag "escalate-unread@example.invalid")
        run (rk/runRecordedAgentLoopWithReplies! root tag replies (list "subject.txt") "fix subject" 20 8000)
        cleaned (pathRemove root)]
    run)

fn ! runTests -> Bool
  (let [held (recorded! "escHeld" (list (escalateReply "subject.txt") "(:step :op \"read\" :file \"subject.txt\")" (escalateReply "subject.txt")))
        plain (recorded! "escPlain" (list (escalateReply "the provider")))
        twice (recorded! "escTwice" (list (escalateReply "subject.txt") (escalateReply "subject.txt")))]
    (do
      (assert (= (m/escalateUnread (list "a/server.asl" "b/*.asl" "src") "blocked on server.asl and src" (list)) (list "a/server.asl")) "an unread owned file named in the escalation is listed; globs and extensionless dirs are not")
      (assert (listEmpty? (m/escalateUnread (list "a/server.asl") "blocked on server.asl" (list "a/server.asl"))) "a file the run already read is not listed")
      (assert (listEmpty? (m/escalateUnread (list "a/server.asl") "blocked on the gateway" (list))) "an owned file the escalation does not name is not listed")
      (assert (stringContains? (m/escalateRefusal (list "a/server.asl")) ":unread (\"a/server.asl\")") "the refusal names the unread files")
      (assert (stringContains? held.journal "(:turn 1 :signal :escalateRefused :unread 1)") "the first escalation naming unread subject.txt is refused at turn 1")
      (assert (not (stringContains? held.journal "(:turn 1 :signal :modelEscalated")) "the refused escalation does not stop the run")
      (assert (stringContains? held.journal "(:turn 3 :signal :modelEscalated") "after the read, the second escalation stops the run")
      (assert (stringContains? plain.journal "(:turn 1 :signal :modelEscalated") "an escalation that names no owned file stops at once")
      (assert (not (stringContains? plain.journal ":escalateRefused")) "and is not refused")
      (assert (stringContains? twice.journal "(:turn 2 :signal :modelEscalated") "a second escalation is never refused again, read from the journal's refusal row")
      (assert (not (stringContains? twice.journal "(:turn 2 :signal :escalateRefused")) "the second escalation is not refused")
      true))
