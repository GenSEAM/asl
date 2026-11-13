(module aslBench/gen/tests/infraDigestTest
  :x [runTests]
  :i [(aslBench/gen/core :a gc)
      (aslBench/gen/score :a sc)
      (asl-tools/fleet/run :a fr)])

; (:m :ref GENRUN-CROSSWIRE :do "a tool child that did not judge the program is infrastructure: it is retried, then recorded as an (:infra ...) row that stops the run and is run again on resume, never as a trial row graded check; a trial row carries the digest of its prompt, and the scorer leaves out a row whose digest or replies belong to another task")

fn done exit: Int64 out: String verdict: String -> fr/Done
  (fr/Done :idx 0 :exit exit :out out :ms 0 :verdict verdict)

fn ! testInfraPure -> Bool
  (let [(recovers (gc/settle! 5 1 (fn [(n Int64)] -> gc/Grade (gc/Grade :stage (if (< n 3) "infra" "ok") :output (stringFromInt64 n) :failing (list))) 1))
        (givesUp (gc/settle! 2 1 (fn [(n Int64)] -> gc/Grade (gc/Grade :stage "infra" :output (stringFromInt64 n) :failing (list))) 1))
        (final (gc/settle! 5 1 (fn [(n Int64)] -> gc/Grade (gc/Grade :stage "check" :output (stringFromInt64 n) :failing (list))) 1))]
    (assert (= (gc/infraOf (done 124 "\n(:fleetRun :verdict :timeout :pid 1 :desc 2 :timeoutMs 30000 :maxDesc 16 :left 0)\n" "timeout") "check") "timeout") "a check ended at its time limit is infrastructure")
    (assert (= (gc/infraOf (done 2 "(:asl :status :failed :error ERR_NATIVE_STALE :message \"the native CLI predates its sources\")" "exit") "check") "nativeCli") "a launcher that reports a stale native CLI is infrastructure")
    (assert (= (gc/infraOf (done 2 "(:err :code rebuildRefused :tree \"/x\" :home \"/y\")" "exit") "test") "nativeCli") "a refused rebuild is infrastructure at the test step too")
    (assert (= (gc/infraOf (done 1 "" "exit") "check") "noDiagnostic") "a check that fails without one diagnostic is infrastructure")
    (assert (= (gc/infraOf (done 1 "cand.asl:4:4: ERR_UNKNOWN_SYMBOL unbound symbol: nosuch\n(:audit :sub check :status :failed)" "exit") "check") "") "a check that names an error judged the program")
    (assert (= (gc/infraOf (done 1 "" "exit") "test") "") "a test that fails silently is the program's own failure")
    (assert (= (gc/infraOf (done 0 "" "") "check") "") "a skipped check is not infrastructure")
    (assert (and (= recovers.stage "ok") (= recovers.output "3")) (str "an infra grade is retried until the tool answers, here on attempt 3: " recovers.stage " " recovers.output))
    (assert (and (= givesUp.stage "infra") (= givesUp.output "2")) (str "after the last attempt the grade stays infra: " givesUp.stage " " givesUp.output))
    (assert (and (= final.stage "check") (= final.output "1")) (str "a grade that judged the program is not retried: " final.stage " " final.output))
    true)

fn ! testVerdictPure root: String -> Bool
  (let [(tasks (resultOr (gc/loadTasks root) (list)))
        (gcdReply "```asl\nfn gcd a: Int64 b: Int64 -> Int64\n  (if (= b 0) a (gcd b (mod a b)))\n```")
        (camelReply "```ts\nfunction sumDigits(n: number): number {\n  return 0;\n}\n```")]
    (assert (= (listLength tasks) 30) "the task rows load")
    (assert (and (gc/hasWord? "(gcd a b)" "gcd") (not (gc/hasWord? "(xgcd a b) gcdOf" "gcd"))) "a name matches only as a whole word")
    (assert (= (gc/rowVerdict tasks "asl" "gcd" (list gcdReply) (list 1026)) "") "a reply that names the entry of its task is kept")
    (assert (= (gc/rowVerdict tasks "asl" "maxOf" (list gcdReply) (list 1026)) "a reply answers task gcd") (str "a reply that defines the entry of another task is cross-wired: " (gc/rowVerdict tasks "asl" "maxOf" (list gcdReply) (list 1026))))
    (assert (= (gc/rowVerdict tasks "py" "sumDigits" (list camelReply) (list 300)) "a reply answers task sumDigits in another arm") "a reply in the spelling of another arm is cross-wired")
    (assert (= (gc/rowVerdict tasks "asl" "maxOf" (list "no code at all" "") (list 1026 1)) "") "a reply that names no task is a model failure, not a cross-wired row")
    (assert (= (gc/rowVerdict tasks "asl" "gcd" (list gcdReply gcdReply) (list 1601 1025)) "prompt token counts do not grow turn over turn") "a later turn with fewer prompt tokens answers another request")
    (assert (= (gc/rowVerdict tasks "asl" "gcd" (list "" gcdReply gcdReply) (list 1 1043 1300)) "") "growing prompt token counts are kept and a cut reply counted as 1 is skipped")
    true)

fn trialForms text: String -> (List (List gc/Sx))
  (match (gc/readForms text)
    ((err _) (list))
    ((ok forms) (map gc/sxItems (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":trial")) forms))))

fn ! testInfraRun root: String -> Bool
  (let [(work (resultOr (realPath (let [(d (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGenInfra-" (stringFromInt64 (nowNs))))
                                        (made (dirCreate d))]
                                    d))
                        ""))
        (tasks (filter (fn [(t gc/Task)] -> Bool (listContains? (list "gcd" "maxOf") t.id)) (resultOr (gc/loadTasks root) (list))))
        (gcdOnly (filter (fn [(t gc/Task)] -> Bool (= t.id "gcd")) tasks))
        (cards (resultOr (gc/loadCardsFor root (list "asl")) (list)))
        (card (gc/cardOf cards "asl"))
        (models (list "fake"))
        (arms (list "asl"))
        (good (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out (str work "/trials.asn") :repairs 1 :maxTokens 1200
                         :priceIn 150000 :priceOut 600000 :capPico 1000000000000 :checkFirst true :infraTries 2 :infraWaitMs 10))
        (rebuilding (with good :aslBin "/usr/bin/false"))
        (trials (gc/planTrials models arms gcdOnly 1 7))
        (header (gc/headerRow "test" models arms tasks 1 7 good cards (list) "2026-11-13" "infraDigestTest"))
        (wroteHeader (fileWrite good.out (str header "\n")))
        (first (pairSecond (gc/runAll! rebuilding cards trials "" 0 (gc/fakeCaller root (list)) 0)))
        (afterInfra (resultOr (fileReadString good.out) ""))
        (resumed (pairSecond (gc/runAll! good cards trials afterInfra 0 (gc/fakeCaller root (list)) 0)))
        (text (resultOr (fileReadString good.out) ""))
        (rows (trialForms text))
        (row (optionOr (listHead rows) (list)))
        (gcdTask (optionOr (listHead gcdOnly) (gc/Task :id "" :family "" :difficulty "" :statement "" :entry "" :entryPy "" :sigAsl "" :sigPy "" :sigTs "" :examples (list) :cases (list))))
        (scored (sc/scoreTextWith text tasks))
        (moved (stringReplace (stringReplace text "\"asl|gcd|fake|1\"" "\"asl|maxOf|fake|1\"") ":task \"gcd\"" ":task \"maxOf\""))
        (movedReply (stringReplace moved (str ":promptSha " (gc/asnQuote (gc/kwText row ":promptSha"))) (str ":promptSha " (gc/asnQuote (gc/expectedPromptSha card.sha "asl" (optionOr (listFind (fn [(t gc/Task)] -> Bool (= t.id "maxOf")) tasks) gcdTask))))))
        (refusedDigest (sc/scoreTextWith moved tasks))
        (refusedReply (sc/scoreTextWith movedReply tasks))
        (cleaned (gc/removeDir! work))]
    (assert (and (= (listLength gcdOnly) 1) (not (stringEmpty? card.sha))) "the task and the card load")
    (assert (not (stringContains? afterInfra "(:trial")) (str "a correct program is never written as a trial row while the CLI does not answer: " (gc/clip afterInfra 2000)))
    (assert (stringContains? afterInfra "(:infra :at \"asl|gcd|fake|1\" :error \"infra: noDiagnostic") (str "the infrastructure failure is recorded as an infra row: " (gc/clip afterInfra 2000)))
    (assert (and (= first.stopped "infra") (= first.done 0)) (str "the run stops on infrastructure and counts no trial: " first.stopped))
    (assert (and (= resumed.done 1) (and (= resumed.skipped 0) (stringEmpty? resumed.stopped))) "the resumed run does the trial again once the CLI answers")
    (assert (and (= (listLength rows) 1) (and (gc/kwBool row ":rawPass") (= (gc/kwText row ":firstFail") "ok"))) "the retried trial is a raw pass")
    (assert (= (gc/kwText row ":promptSha") (gc/expectedPromptSha card.sha "asl" gcdTask)) (str "the row stores the digest of the prompt of its task: " (gc/kwText row ":promptSha")))
    (assert (and (listEmpty? scored.rejected) (= (listLength scored.stats) 1)) (str "the scorer accepts the row: " (stringJoin scored.rejected " ")))
    (assert (and (= (listLength refusedDigest.rejected) 1) (stringContains? (optionOr (listHead refusedDigest.rejected) "") "prompt digest")) (str "a row moved to another task is refused by its prompt digest: " (stringJoin refusedDigest.rejected " ")))
    (assert (and (= (listLength refusedReply.rejected) 1) (stringContains? (optionOr (listHead refusedReply.rejected) "") "a reply answers task gcd")) (str "a row with the digest of its task and the reply of another is refused by its reply: " (stringJoin refusedReply.rejected " ")))
    (assert (= (map (fn [(s sc/ArmStat)] -> (List Int64) (list s.trials s.missing s.rawPass s.solved s.tokens)) scored.stats)
               (list (list 1 1 1 1 (+ (gc/kwInt row ":tokInSum") (gc/kwInt row ":tokOutSum")))))
            "the accepted row is counted: one trial, one raw pass, its tokens, and the other task missing")
    (assert (= (map (fn [(s sc/ArmStat)] -> (List Int64) (list s.trials s.missing s.rawPass s.solved s.tokens)) refusedDigest.stats) (list (list 0 2 0 0 0)))
            "a row refused by its digest leaves every total: no trial, no pass, no tokens, both tasks missing")
    (assert (= (map (fn [(s sc/ArmStat)] -> (List Int64) (list s.trials s.missing s.rawPass s.solved s.tokens)) refusedReply.stats) (list (list 0 2 0 0 0)))
            "a row refused by its reply leaves every total too")
    (assert (and (not refusedDigest.complete) (listAny? (fn [(l String)] -> Bool (stringStartsWith? l "(:score :status :refused :reason \"rows that do not belong")) refusedDigest.lines)) "a refused row is printed and leaves its arm incomplete")
    (assert cleaned "the work directory is removed")
    true)

fn ! runTests -> Bool
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))
        (root (resultOr (realPath given) given))]
    (and (testInfraPure) (and (testVerdictPure root) (testInfraRun root))))
