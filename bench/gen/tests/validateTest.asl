(module aslBench/gen/tests/validateTest
  :x [runTests]
  :i [(aslBench/gen/core :a gc)
      (aslBench/gen/validate :a va)])

; (:m :ref GENRUN-CROSSWIRE :do "the validator on a results text built here: a row whose reply defines the entry of another task and a row whose prompt token counts fall are crossWired, an infra row is infra, and the trusted rows end before the first trial of 330 s or more and before the first cross-wired row; the filtered copy holds the header and the trusted rows only")

fn rowText key: String arm: String task: String wallMs: Int64 tokIn: String reply: String -> String
  (str "(:trial :key " (gc/asnQuote key) " :arm " (gc/asnQuote arm) " :task " (gc/asnQuote task) " :stages (\"ok\") :tokIn (" tokIn ") :wallMs " (stringFromInt64 wallMs)
       " :replies (" (gc/asnQuote reply) "))")

fn ! runTests -> Bool
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))
        (root (resultOr (realPath given) given))
        (tasks (resultOr (gc/loadTasks root) (list)))
        (gcdReply "```asl\nfn gcd a: Int64 b: Int64 -> Int64\n  (if (= b 0) a (gcd b (mod a b)))\n```")
        (maxReply "```asl\nfn maxOf xs: (List Int64) -> (Option Int64)\n  (none)\n```")
        (lines (list "(:run :id \"FABLE-LANG-01\" :arms (\"asl\"))"
                     (rowText "asl|gcd|m|1" "asl" "gcd" 4000 "1026" gcdReply)
                     (rowText "asl|gcd|m|2" "asl" "gcd" 340000 "1026" gcdReply)
                     (rowText "asl|gcd|m|3" "asl" "gcd" 5000 "1026" gcdReply)
                     "(:callFailed :key \"asl|gcd|m|4\" :error \"call: http 502\")"
                     (rowText "asl|maxOf|m|1" "asl" "maxOf" 5000 "1026" gcdReply)
                     (rowText "asl|maxOf|m|2" "asl" "maxOf" 5000 "1601 1025" maxReply)
                     "(:infra :at \"asl|maxOf|m|3\" :error \"infra: timeout\" :costPico 5)"
                     (rowText "asl|maxOf|m|4" "asl" "maxOf" 5000 "1026" maxReply)))
        (rows (map (fn [(i Int64)] -> va/Judged (va/judgeLine tasks (+ i 1) (optionOr (listGet lines i) ""))) (range 0 (listLength lines))))
        (classes (map (fn [(r va/Judged)] -> String r.class) rows))
        (report (va/reportOf rows))
        (kept (va/keptText rows))
        (cleanRows (listTake rows 2))
        (clean (va/reportOf cleanRows))]
    (assert (= (listLength tasks) 30) "the task rows load")
    (assert (= classes (list "" "valid" "valid" "valid" "" "crossWired" "crossWired" "infra" "valid")) (str "each row gets its class: " (stringJoin classes ",")))
    (assert (and (= report.trials 6) (and (= report.valid 4) (and (= report.crossWired 2) (and (= report.infra 1) (= report.callFailed 1))))) "the counts per class")
    (assert (and (= report.firstBad 6) (= report.firstBadKey "asl|maxOf|m|1")) (str "the first cross-wired row is named by its line: " (stringFromInt64 report.firstBad)))
    (assert (= report.firstBadWhy "a reply answers task gcd") (str "with the task its reply answers: " report.firstBadWhy))
    (assert (and (= report.slowFrom 3) (= report.trusted 1)) (str "rows from the first trial of 330 s on are not trusted: " (stringFromInt64 report.slowFrom) " " (stringFromInt64 report.trusted)))
    (assert (= kept (str (optionOr (listGet lines 0) "") "\n" (optionOr (listGet lines 1) "") "\n")) "the filtered copy holds the header and the trusted row")
    (assert (and (= clean.firstBad 0) (and (= clean.slowFrom 0) (= clean.trusted 1))) "a file without a bad or slow row trusts every valid row")
    (assert (= (va/reportLine "f.asn" clean) "(:validate :file \"f.asn\" :trials 1 :valid 1 :crossWired 0 :infra 0 :callFailed 0 :firstBad none :firstBadKey \"\" :firstBadWhy \"\" :slowFrom none :trusted 1)") "the printed row")
    true)
