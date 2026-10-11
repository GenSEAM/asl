(module asl/agentLoop/tests/mainParityTest
  :x [runTests]
  :i [(asl/agentLoop/core :a c)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! host -> String
  (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host")

fn ! runAsl env: String form: String -> ProcessOutput
  (processRun (str env " nice -n 15 " (host) " run asl/agentLoop/tests/mainDriver.asl " (shellQuote form)))

fn ! kvText value: c/KvVal -> String
  (mt value ((c/kvStr text) text) ((c/kvInt _) ""))

fn ! fixtureField line: String key: String -> String
  (let [pairs (c/parseKv line)
        found (filter (fn [p] (= (pairFirst p) key)) pairs)]
    (mt (listHead found)
      ((some p) (kvText (pairSecond p)))
      ((none) "")))

fn ! fixtureInt line: String key: String -> Int64
  (let [pairs (c/parseKv line)
        found (filter (fn [p] (= (pairFirst p) key)) pairs)]
    (mt (listHead found)
      ((some p) (mt (pairSecond p) ((c/kvInt digits) (optionOr (stringToInt64 digits) -999)) ((c/kvStr _) -999)))
      ((none) -999)))

fn hexNibble d: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" d (+ d 1)) "")

fn hex4 v: Int64 -> String
  (str (hexNibble (mod (/ v 4096) 16)) (hexNibble (mod (/ v 256) 16)) (hexNibble (mod (/ v 16) 16)) (hexNibble (mod v 16)))

fn leadLength b: Int64 -> Int64
  (cond ((< b 224) 2) ((< b 240) 3) (else 4))

fn codepointAt bs: Bytes i: Int64 -> Int64
  (let [b0 (bytesGet bs i)
        lead (leadLength b0)]
    (cond
      ((= lead 2) (+ (* (- b0 192) 64) (- (bytesGet bs (+ i 1)) 128)))
      ((= lead 3) (+ (* (- b0 224) 4096) (* (- (bytesGet bs (+ i 1)) 128) 64) (- (bytesGet bs (+ i 2)) 128)))
      (else (+ (* (- b0 240) 262144) (* (- (bytesGet bs (+ i 1)) 128) 4096)
               (* (- (bytesGet bs (+ i 2)) 128) 64) (- (bytesGet bs (+ i 3)) 128)))))

fn escapeFormLoop form: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (c/joinAll (listReverse acc))
    (let [b (bytesGet bs i)]
      (cond
        ((= b 34) (escapeFormLoop form bs n (+ i 1) (cons "\\\"" acc)))
        ((= b 92) (escapeFormLoop form bs n (+ i 1) (cons "\\\\" acc)))
        ((= b 10) (escapeFormLoop form bs n (+ i 1) (cons "\\n" acc)))
        ((= b 9) (escapeFormLoop form bs n (+ i 1) (cons "\\t" acc)))
        ((or (< b 32) (= b 127)) (escapeFormLoop form bs n (+ i 1) (cons (str "\\u" (hex4 b)) acc)))
        ((< b 128) (escapeFormLoop form bs n (+ i 1) (cons (optionOr (stringSlice form i (+ i 1)) "") acc)))
        (else (escapeFormLoop form bs n (+ i (leadLength b)) (cons (str "\\u" (hex4 (codepointAt bs i))) acc))))))

fn escapeForm form: String -> String
  (let [bs (stringToBytes form)]
    (escapeFormLoop form bs (bytesLength bs) 0 (list)))

fn ! fixtureFormMatches repo: String line: String form: String -> Bool
  (= (stringReplace (fixtureField line "form") "{ROOT}" repo) (c/asnUnescape (escapeForm form)))

fn ! fixtureRow lines: (List String) id: String -> String
  (optionOr (listHead (filter (fn [line] (stringContains? line (str ":id \"" id "\""))) lines)) "")

fn ! fixtureRowForForm repo: String lines: (List String) scope: String form: String -> String
  (optionOr (listHead (filter (fn [line]
                               (and (stringStartsWith? line "(:case ")
                                    (and (or (= (fixtureField line "scope") scope)
                                             (and (= scope "default") (= (fixtureField line "scope") "")))
                                         (fixtureFormMatches repo line form)))) lines)) "")

fn ! matchesFixtureRow repo: String scope: String env: String form: String row: String -> Bool
  (let [rowScope (fixtureField row "scope")
        expected (stringReplace (fixtureField row "receipt") "{ROOT}" repo)
        actual (runAsl env form)]
    (and (!= row "")
         (or (= rowScope scope) (and (= scope "default") (= rowScope "")))
         (fixtureFormMatches repo row form)
         (= actual.stdout expected)
         (= actual.exitCode (fixtureInt row "exit"))))

fn ! fixtureMismatchesAt repo: String scope: String env: String prefix: String index: Int64 forms: (List String) acc: (List String) -> (List String)
  (mt (listHead forms)
    ((none) (listReverse acc))
    ((some form)
      (let [digit (stringFromInt64 index)
            id (str prefix (if (< index 10) (str "0" digit) digit))
            lines (stringSplit (readOr "asl/agentLoop/tests/mainParityFixtures.asn") "\n")
            row (if (= prefix "") (fixtureRowForForm repo lines scope form) (fixtureRow lines id))
            matched (matchesFixtureRow repo scope env form row)]
        (fixtureMismatchesAt repo scope env prefix (+ index 1) (optionOr (listTail forms) (list))
                             (if matched acc (cons form acc))))))

fn ! fixtureMismatches repo: String scope: String env: String prefix: String forms: (List String) -> (List String)
  (fixtureMismatchesAt repo scope env prefix 0 forms (list))

fn ! matchesNoArgFixture repo: String -> Bool
  (let [row (fixtureRow (stringSplit (readOr "asl/agentLoop/tests/mainParityFixtures.asn") "\n") "no_arg")
        expected (stringReplace (fixtureField row "receipt") "{ROOT}" repo)
        actual (processRun (str "nice -n 15 " (host) " run asl/agentLoop/tests/mainDriver.asl"))]
    (and (!= row "")
         (= (fixtureField row "scope") "default")
         (= actual.stdout expected)
         (= actual.exitCode (fixtureInt row "exit"))))

fn ! write path: String text: String -> Bool
  (mt (fileWrite path text) ((ok _) true) ((err _) false))

fn rejectionForms -> (List String)
  (list "(:agent :task \"x\" :role :scout)"
        "(:agent :task \"unclosed)"
        "("
        "foo"
        ""
        "(:agent :task \"Inspect\" :badKey 123 :dryRun true)"
        "(:agent :task \"t\" :aa 1)"
        "(:agent :task \"t\" :z 1)"
        "(:agent :task \"t\" :x :y :dryRun true)"
        "(:agent :dryRun true)"
        "(:agent :task \"t\" :contextFile \"/etc/passwd\" :dryRun true)"
        "(:agent :task \"t\" :contextFile \"../nonexistent_q.txt\" :dryRun true)"
        "(:agent :task \"t\" :contextFile \"tests/fixtures/nonexistent_xyz_99.txt\" :dryRun true)"
        "(:agent :task \"t\" :contextTokens 3999 :dryRun true)"
        "(:agent :task \"t\" :contextTokens 2000001 :dryRun true)"
        "(:agent :task \"t\" :gateTimeout 0 :dryRun true)"
        "(:agent :task \"t\" :gateTimeout 86401 :dryRun true)"
        "(:agent :task \"t\" :gateTimeout \"30\" :dryRun true)"
        "(:agent :task \"t\" :root \"nonexistentdir_q\" :dryRun true)"
        "(:agent :task \"t\" :contextTokens 100 :root \"nonexistentdir_q\")"
        "(:agent :task \"t\" :wallBudget 999999 :dryRun true)"
        "(:agent :task \"t\" :wallBudget 0 :dryRun true)"
        "(:agent :task \"t\" :timeout 90000 :queueTimeout 1200 :wallBudget 86401 :dryRun true)"
        "(:agent :task \"t\" :timeout -5 :queueTimeout 5 :dryRun true)"
        "(:agent :task \"t\" :plan 5 :dryRun true)"
        "(:agent :task \"t\" :plan 5 :role x)"
        "(:agent :task \"t\" :backend \"script/missing_fixture_xyz\")"
        "(:agent :task \"t\" :dryRun 1 :backend \"script/missing_fixture_xyz\")"
        "(:agent :task \"t\" :backend \"nope\")"
        "(:agent :task \"t\" :dryRun true :backend \"nope\")"
        "(:agent :resume \"abc\" :dryRun true)")

fn dryRunForms absContext: String -> (List String)
  (list "(:agent :task \"Dry \\\"quoted\\\" task\" :backend \"agy\" :owns (\"src\") :gates (\"echo gate\") :contextTokens 128000 :plan true :dryRun true)"
        "(:agent :task \"t\" :owns \"src\" :gates \"echo hi\" :dryRun true :backend \"codex\")"
        "(:agent :task \"t\" :gates (\"exit 0 (\") :dryRun true)"
        "(:agent :task \"t\" :base \"b\\\"x\" :gates (\"a\" \"exit (\") :dryRun true :backend \"claude\")"
        "(:agent :task \"Dot\" :contextFile \"tests/fixtures/agentLoop/mvp/../../agentLoop/mvp/honest.asn\" :dryRun true :backend \"claude\")"
        (str "(:agent :task \"Absolute\" :contextFile \"" absContext "\" :dryRun true :backend \"claude\")")
        "(:agent :task \"t\\n\" :contextFile \"tests/fixtures/agentLoop/mvp/honest.asn\" :dryRun true :backend \"claude\")"
        "(:agent :contextFile \"tests/fixtures/agentLoop/mvp/honest.asn\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :contextFile \"\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :owns ((\"a\" \"b\") 3 true) :dryRun true :backend \"claude\")"
        "(:agent :task (\"x\" 1) :dryRun true :backend \"claude\")"
        "(:agent :task :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :plan :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :mode ::scout :intent :plan :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :contextTokens 4000 :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :contextTokens \"5000\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :budget \"12\" :timeout \"90\" :dryRun true :backend \"claude\" :wallBudget 1200)"
        "(:agent :task \"t\" :wallBudget 3600 :dryRun true :backend \"agy\")"
        "(:agent :task \"t\" :timeout 100 :wallBudget 3600 :dryRun true)"
        "(:agent :task \"t\" :timeout 1_0 :queueTimeout 5 :wallBudget 16 :dryRun true)"
        "(:agent :task \"t\" ; comment \"\n :dryRun true :backend \"claude\")"
        "(:agent\t:task \"tab\" :dryRun true :backend \"claude\")"
        "(:agent\u001c:task \"c0-1c\" :dryRun true :backend \"claude\")"
        "(:agent\u001d:task \"c0-1d\" :dryRun true :backend \"claude\")"
        "(:agent\u001e:task \"c0-1e\" :dryRun true :backend \"claude\")"
        "(:agent\u001f:task \"c0-1f\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :root \"~\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :root \"/tmp\" :contextFile \"tests/fixtures/agentLoop/mvp/honest.asn\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :model \"claude-x\" :dryRun true :backend \"claude\")"
        "(:agent :task \"t\" :model \"\" :dryRun true :backend \"codex\")"
        "(agent :task \"t\" :dryRun \"true\" :backend \"claude\")"
        "(:agent :task \"esc\\\\q\\t\" :dryRun true :backend \"claude\")")

fn resumeForms -> (List String)
  (list "(:agent :resume \"legacy\")"
        "(:agent :resume \"auto\")"
        "(:agent :resume \"hint\")"
        "(:agent :resume \"a..b\")"
        "(:agent :resume \"staged\")"
        "(:agent :resume \"missing\")"
        "(:agent :resume \"hint\n\")"
        "(:agent :resume \"answered\")"
        "(:agent :resume \"answered\" :answer \"yes\" :dryRun true :backend \"claude\")"
        "(:agent :resume \"answered\" :answer \"yes\" :dryRun true :backend \"claude\" :contextTokens 9000)"
        "(:agent :resume \"noHeader\" :answer \"a\" :dryRun true)"
        "(:agent :resume \"noTurn\" :answer \"a\" :dryRun true)"
        "(:agent :resume \"endedOk\" :answer \"a\" :dryRun true)"
        "(:agent :resume \"missing\" :answer \"a\" :dryRun true)"
        "(:agent :resume \"a..b\" :answer \"a\" :dryRun true)")

fn ! writeJournals root: String -> Bool
  (let [dir (str root "/.asl/run/agentLoop/")]
    (and (ok? (dirCreate dir))
         (ok? (dirCreate (str root "/.asl/vfs/staged/sub")))
         (ok? (dirCreate (str root "/.asl/vfs/staged/a")))
         (write (str dir "legacy.journal")
                (str "(:session :id \"legacy\" :task \"has :mode :x inside\" :mode :review)\n(:turn 3)\n(:turn 1 :note \"first\")\n"
                     "(:gate :cmd \"g1\" :exit 0)\n(:gate :cmd \"g2\" :exit 1)\n(:turn 2 :reply \"(:gate :cmd \\\"fake\\\" :exit 9) :note \\\"no\\\"\")\n"
                     "(:gate :cmd \"g3\" :exit -007)\n(:result :status :failed)\n"))
         (write (str dir "auto.journal") "(:session :task \"auto task\" :mode :auto)\n(:turn 1 :reply \"x\")\n")
         (write (str dir "hint.journal")
                "(:session :task \"t\" :modeHint \"scout\\\"q\")\n(:turn 2 :note \"n1\")\n(:turn 4 :reply \"r :note \\\"fake\\\"\")\n(:result :status :ok)\n")
         (write (str dir "a..b.journal") "(:result :status :ok)\n")
         (write (str dir "staged.journal") "(:session :task \"staged\")\n")
         (write (str root "/.asl/vfs/staged/z.txt") "")
         (write (str root "/.asl/vfs/staged/m.txt") "")
         (write (str root "/.asl/vfs/staged/sub/b.txt") "")
         (write (str root "/.asl/vfs/staged/a/c.txt") "")
         (ok? (pathSymlink "../" (str root "/.asl/vfs/staged/link")))
         (write (str dir "answered.journal")
                (str "(:session :id \"s\" :task \"resumed \\\"t\\\"\" :intent \"plan\" :owns (\"a.txt\" \"b c\") :gates (\"echo g\") :base \"main\" :contextTokens 64000)\n"
                     "(:turn 1 :reply \"(:step :op \\\"read\\\")\")\n(:turn 1 :observation \"obs1\")\n(:turn 2 :reply \"second\")\n(:turn 2 :note \"why\")\n"))
         (write (str dir "noHeader.journal") "(:turn 1 :reply \"x\")\n")
         (write (str dir "noTurn.journal") "(:session :task \"t\")\n(:turn 1 :observation \"o\")\n")
         (write (str dir "endedOk.journal") "(:session :task \"t\")\n(:turn 1 :reply \"x\")\n(:result :status :ok)\n")))

fn ! tempDir tag: String -> String
  (stringTrim (processRun (str "mktemp -d /tmp/asl-main-" tag ".XXXXXX")).stdout)

fn fieldAfter text: String key: String -> String
  (mt (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [start (+ at (stringLength key))
            rest (c/sliceOf text start (stringLength text))]
        (mt (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) "")))))

fn isHex16 s: String -> Bool
  (and (= (stringLength s) 16)
       (listAll? (fn [ch] (stringContains? "0123456789abcdef" ch)) (stringChars s)))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        at (str "ASL_ROOT_DIR=" (shellQuote repo))
        absContext (resultOr (realPath "tests/fixtures/agentLoop/mvp/honest.asn") "")
        noArgAsl (processRun (str "nice -n 15 " (host) " run asl/agentLoop/tests/mainDriver.asl"))
        noArgFixture (matchesNoArgFixture repo)
        rejected (fixtureMismatches repo "default" at "" (rejectionForms))
        dry (fixtureMismatches repo "default" at "dry_" (dryRunForms absContext))
        planOn (matchesFixtureRow repo "ASL_LEON_PLAN=1" (str at " ASL_LEON_PLAN=1") "(:agent :task \"env plan\" :dryRun true :backend \"claude\")" (fixtureRow (stringSplit (readOr "asl/agentLoop/tests/mainParityFixtures.asn") "\n") "plan_1"))
        planBad (matchesFixtureRow repo "ASL_LEON_PLAN=2" (str at " ASL_LEON_PLAN=2") "(:agent :task \"env plan\" :dryRun true)" (fixtureRow (stringSplit (readOr "asl/agentLoop/tests/mainParityFixtures.asn") "\n") "plan_2"))
        planOff (matchesFixtureRow repo "ASL_LEON_PLAN=0" (str at " ASL_LEON_PLAN=0") "(:agent :task \"param plan\" :plan true :dryRun true :backend \"claude\")" (fixtureRow (stringSplit (readOr "asl/agentLoop/tests/mainParityFixtures.asn") "\n") "plan_0"))
        journalRoot (tempDir "journals")
        journalsWritten (writeJournals journalRoot)
        resumed (fixtureMismatches journalRoot "resume" (str "ASL_ROOT_DIR=" (shellQuote journalRoot)) "resume_" (resumeForms))
        liveRoot (tempDir "live")
        fixtureCopied (and (ok? (dirCreate (str liveRoot "/tests/fixtures/agentLoop/mvp")))
                           (write (str liveRoot "/tests/fixtures/agentLoop/mvp/honest.asn") (readOr "tests/fixtures/agentLoop/mvp/honest.asn")))
        liveForm (str "(:agent :task \"Review the fixture\" :mode :scout :backend \"script/honest\" :root \"" liveRoot "\")")
        live (runAsl at liveForm)
        liveAgain (runAsl at liveForm)
        session (fieldAfter live.stdout ":session \"")
        journal (readOr (str liveRoot "/.asl/run/agentLoop/" session ".journal"))
        resumeWritten (write (str liveRoot "/.asl/run/agentLoop/answered.journal")
                             "(:session :task \"answered live\" :mode :review)\n(:turn 1 :reply \"(:note \\\"x\\\")\")\n")
        liveResume (runAsl at (str "(:agent :resume \"answered\" :answer \"go\" :backend \"script/honest\" :root \"" liveRoot "\")"))
        resumeJournal (readOr (str liveRoot "/.asl/run/agentLoop/answered.journal"))
        cleaned (and (ok? (pathRemove journalRoot)) (ok? (pathRemove liveRoot)))]
    (do
      (assert noArgFixture "no argv is rejected with its recorded exit code")
      (assert (= noArgAsl.exitCode 2) "no argv exits 2")
      (assert (listEmpty? rejected) "every rejected form returns a rejection receipt and its recorded exit code")
      (assert (listEmpty? dry) "every dry-run form returns its recorded receipt class and exit code")
      (assert planOn "ASL_LEON_PLAN=1 runs the plan-on dry-run path")
      (assert planBad "ASL_LEON_PLAN=2 is rejected")
      (assert planOff ":plan true wins over ASL_LEON_PLAN=0")
      (assert journalsWritten "resume fixture journals written")
      (assert (listEmpty? resumed) "resume reports and resumed dry runs return their recorded receipt class and exit code")
      (assert fixtureCopied "live root holds the honest script fixture")
      (assert (= live.exitCode 0) "a live run whose script yields one findings reply exits 0")
      (assert (stringStartsWith? live.stdout "(:agentReceipt :status :ok :modeHint \"scout\" :phases (scout) :session \"") "live receipt: ok, scout phase, mode hint and session first")
      (assert (stringContains? live.stdout (str ":journal \".asl/run/agentLoop/" session ".journal\" :unbacked 0 :contextTokens 8000 :turns 1 :findings ((:findings (:f :claim \"read file contents without assertion\" :at \"file.txt\"))) :batching (")) "live receipt names its journal and the one turn the real loop ran and its findings")
      (assert (isHex16 session) "a new session id is 16 hex digits")
      (assert (!= session (fieldAfter liveAgain.stdout ":session \"")) "each live run draws a new session id")
      (assert (and (stringContains? journal "(:turn 1 :reply \"(:findings (:f :claim") (not (stringContains? journal "(:turn 2 "))) "the live journal records the scripted findings reply at turn one and no second turn")
      (assert (stringContains? journal (str "(:result :status :ok :session \"" session "\" :unbacked 0")) "the live journal records the ok result")
      (assert resumeWritten "live resume journal written")
      (assert (= liveResume.exitCode 0) "a resumed live run whose script yields findings exits 0")
      (assert (stringContains? liveResume.stdout ":modeHint \"review\" :phases (scout) :session \"answered\" :journal \".asl/run/agentLoop/answered.journal\"") "a resumed live run keeps the journalled session, mode hint and journal")
      (assert (stringContains? resumeJournal "(:result :status :ok :session \"answered\" :unbacked 0") "the resumed journal gets the ok result appended")
      (assert (stringStartsWith? resumeJournal "(:session :task \"answered live\"") "the resumed journal keeps its history")
      (assert cleaned "temporary roots removed")
      true))
