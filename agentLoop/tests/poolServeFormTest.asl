(module asl/agentLoop/tests/poolServeFormTest
  :x [runTests]
  :i [(asl/agentLoop/poolServe :a ps) (asl/agentLoop/sessionPool :a sp) (tools/fleet/leonClient :a lc) (tools/fleet/freePool :a fp) (tools/fleet/model :a fm)])

; (:m :ref POOL-FORM-MISSING-TASK :do "the server side of the control line, no daemon: the conductor's real form (a task of several lines with quotes, a literal backslash n, a carriage return and a tab) built by freePool leonFormExtra and put on the wire by leonClient runLine reaches the open hook of poolServe handleLine! byte for byte, its parsed :task equals the task plus the commit instruction, and a receipt row whose :result has the same hard characters is one line that leonClient receiptResult reads back whole, 100 KB long included")
fn taskText -> String
  "write it\nsecond \"quoted\" line with a literal \\n and a back\\\\slash\r\n\tlast line\r"

fn ! formOf -> String
  (fp/leonFormExtra (taskText) (list "subject.txt") (list "grep -qx green subject.txt") 900 ":backend \"script/edit\" :mode \"implement\"")

fn openHook -> (fn [String String String String String] -> (Pair String (Option (Pair Int64 String))))
  (fn [(d String) (id String) (form String) (repo String) (root String)] -> (Pair String (Option (Pair Int64 String)))
    (pair form (some (pair 125 "(:declined)"))))

fn ! taskOf form: String -> String
  (match (fm/parseForms form)
    ((err e) (str "parse error " e))
    ((ok forms) (match (listHead forms)
                  ((none) "no form")
                  ((some f) (match (fm/kvGet (fm/itemsOf f) ":task") ((some t) (fm/textOf t)) ((none) "no :task"))))))

fn ! runTests -> Bool
  (let [(temp (str (resultOr (realPath ".") ".") "/.asl/cache/poolServeFormTest-" (stringFromInt64 (procSelf))))
        (made (ok? (dirCreate (str temp "/receipts"))))
        (form (formOf))
        (line (lc/runLine "u9" form "/tmp/root"))
        (s (ps/newServe -1 (sp/newPool (str temp "/hub.sock") 2 64 300000 (str temp "/spill")) (str temp "/receipts")))
        (handled (ps/handleLine! s line "" (openHook)))
        (received (pairSecond (pairFirst handled)))
        (expectedTask (str (taskText) (fp/commitInstruction (list "subject.txt"))))
        (big (stringJoin (map (fn [(i Int64)] -> String (str "line " (stringFromInt64 i) " \"q\" \\ \t\r end")) (range 0 5000)) "\n"))
        (row (ps/receiptRow "u9" 2 big))
        (cleaned (ok? (pathRemove temp)))]
    (do
      (assert made "the scratch receipts dir is created")
      (assert (= (listLength (stringLines line)) 1) "the control line is one line")
      (assert (stringStartsWith? (pairSecond handled) "(:queued ") (str "the run is accepted: " (pairSecond handled)))
      (assert (= received form) "the form handed to open equals the conductor's form byte for byte")
      (assert (= (taskOf received) expectedTask) (str "the parsed :task equals the task plus the commit instruction, newlines, CR and tab included: " (taskOf received)))
      (assert (= (listLength (stringLines (stringTrim row))) 1) "a receipt row with a multi-line result is one line")
      (assert (= (lc/receiptResult row) big) "the client reads the 100 KB multi-line result back whole")
      (assert cleaned "scratch removed")
      true))
