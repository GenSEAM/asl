(module asl/agentLoop/tests/attractorTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/main :a m) (asl/agentLoop/core :a c)
      (asl/agentLoop/attractor :a at) (asl/agentLoop/providers :a pv) (asl-json/json :a j)
      (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEONATTR :do "the opt-in reply attractor: off is byte-identical, on opens with a stable prefix, ends with a prefill that is put back before parsing, picks tail cards by static rules, and journals proseChars and the prefix hash")

fn shapes -> (List String)
  (list "(:step :op \"read\" :file f)" "(:done)")

fn testOffIdentical -> Bool
  (do (assert (= (at/attractorSystem "" (shapes) "SYS") "SYS") "knob off leaves the system prompt as is")
      (assert (= (at/attractorSystem "off" (shapes) "SYS") "SYS") "off spelled out is the same")
      (assert (= (at/attractorPrefill "") "") "no prefill when off")
      (assert (= (at/attractorTail (at/attractorCards "" "ERR_USE_RAW" true false 9)) "") "no tail when off, whatever the state")
      (assert (= (at/continueReply "" "reply") "reply") "no prefill, the reply is untouched")
      (assert (= (listLength (pv/profileMessages "S" "U" "")) 2) "request messages are system then user")
      (assert (not (stringContains? (j/jsonEmit (j/jarr (pv/profileMessages "S" "U" ""))) "assistant")) "nothing trailing")
      true))

fn testOnShape -> Bool
  (let [sys (at/attractorSystem "asn" (shapes) "SYS")
        msgs (pv/profileMessages "S" "U" (at/attractorPrefill "asn"))
        full "(:step :op \"read\" :file \"a.txt\")"
        cont " :op \"read\" :file \"a.txt\")"]
    (do (assert (stringStartsWith? sys "(:reply :format asn :prose none :first \"(:step\"") "contract opens the system")
        (assert (stringContains? sys ":content :raw") "the raw write example is present")
        (assert (stringEndsWith? sys "SYS") "the existing system follows the prefix")
        (assert (= (listLength msgs) 3) "three messages with a prefill")
        (assert (stringContains? (j/jsonEmit (j/jarr msgs)) "\"role\":\"assistant\",\"content\":\"(:step\"") "the trailing assistant message carries the prefill")
        (assert (= (c/serOps (c/parseReply (at/continueReply "(:step" cont))) (c/serOps (c/parseReply full))) "a prefilled continuation parses into the ops of the full reply")
        (assert (= (at/continueReply "(:step" full) full) "a full reply from a transport that ignores the prefill is not doubled")
        true)))

fn testPrefixStable -> Bool
  (let [a (at/attractorSystem "asn" (shapes) "SYS one")
        b (at/attractorSystem "asn" (shapes) "SYS two, other root and task")
        pre (at/attractorContract (shapes))]
    (do (assert (stringStartsWith? a pre) "session one starts with the prefix")
        (assert (stringStartsWith? b pre) "session two starts with the same prefix bytes")
        (assert (= (at/prefixHash "asn" (shapes)) (at/prefixHash "asn" (shapes))) "the hash is deterministic")
        (assert (!= (at/prefixHash "asn" (shapes)) "") "the hash is journalled when on")
        (assert (= (at/prefixHash "" (shapes)) "") "no hash when off")
        (assert (not (stringContains? pre "/Users")) "no path in the prefix")
        true)))

fn names cards: (List (Pair String String)) -> String
  (stringJoin (map pairFirst cards) ",")

fn testCards -> Bool
  (do (assert (= (names (at/attractorCards "asn" "x ERR_USE_RAW y" false true 1)) "rawWrite,stepOnly") "raw rejection and a parse defect")
      (assert (= (names (at/attractorCards "asn" "" false false 3)) "gateFirst") "no edit after three turns")
      (assert (= (names (at/attractorCards "asn" "" false true 9)) "") "writes done, no card")
      (assert (stringContains? (at/attractorTail (at/attractorCards "asn" "ERR_USE_RAW" false true 0)) "fenced") "the raw card teaches the fence")
      true))

fn testProse -> Bool
  (do (assert (= (at/proseChars "(:step :op \"gate\")") 0) "a pure step has no prose")
      (assert (> (at/proseChars "Let me start by exploring.\n(:step :op \"gate\")") 20) "leading prose is counted")
      (assert (= (at/proseChars "(:step :op \"write\" :file \"a.txt\" :content :raw)\n```\nhello\n```\n(:done)") 0) "a raw block bound to a step is not prose")
      true))

fn initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
    (gk/initGitRepo! root "attractorTest" "attractor@example.invalid"))

fn drive! root: String name: String attractor: String reply: String -> String
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        _fixture (fileWrite (str fixtureDir "/" name ".asn") (rk/scriptFixtureTextFromReplies! name (list reply)))
        form (str "(:agent :task \"Note and finish.\" :backend \"script/" name "\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :budget 3 :contextTokens 8000"
                  (if (stringEmpty? attractor) "" (str " :attractor " attractor)) ")")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)]
    (journalText root)))

fn journalText root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        files (match (dirList dir) ((ok fs) fs) ((err _) (list)))
        all (filter (fn [f] (stringEndsWith? f ".journal")) (map (fn [f] (str dir "/" f)) files))]
    (stringJoin (map (fn [f] (match (fileReadString f) ((ok t) t) ((err _) ""))) all) "\n")))

fn testJournal -> Bool
  (let [root (rk/freshRecorderRoot! "attractorJournal")
        root2 (rk/freshRecorderRoot! "attractorJournalOff")
        ready (and (initRepo! root) (initRepo! root2))
        on (drive! root "attrOn" "asn" " :op \"note\" :text \"x\")\n(:done)")
        off (drive! root2 "attrOff" "" "I will note first.\n(:step :op \"note\" :text \"x\")\n(:done)")
        cleaned (and (ok? (pathRemove root)) (ok? (pathRemove root2)))]
    (do (assert ready "the repo is tracked")
        (assert (stringContains? on ":proseChars 0") "proseChars is journaled, zero for a pure reply")
        (assert (stringContains? on ":prefixHash \"") "the prefix hash is journaled when on")
        (assert (not (stringContains? on "parse-defect")) "the prefilled continuation parsed")
        (assert (stringContains? off ":proseChars ") "proseChars is journaled with the knob off")
        (assert (not (stringContains? off ":prefixHash")) "no hash line when off")
        (assert (not (stringContains? off ":proseChars 0)")) "the prose of the off arm is counted")
        (assert cleaned "the fixture root is removed")
        true)))

fn runTests -> Bool
  (and (testOffIdentical) (and (testOnShape) (and (testPrefixStable) (and (testCards) (and (testProse) (testJournal)))))))
