(module asl/tools/fleet/bounded
  :x [main parseArgs Parsed receiptLine]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref WATCHDOG-GROUP-KILL :do "the one-line bounded runner for briefs and reruns: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] [--receipt FILE] -- CMD ARGV...; the command runs as one fleet/run.asl child, and at SECS its whole process tree and groups are killed (a timeout verdict note is printed, exit 124); otherwise its output is printed whole and its exit code is returned; a perl alarm or a bare timeout kills only the direct child and leaves bin/asl descendants running")

(schema Parsed
  (:f secs Int64)
  (:f maxDesc Int64)
  (:f receipt String)
  (:f argv (List String))
  (:f error String))

fn usage -> String
  "usage: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] [--receipt FILE] -- CMD ARGV..."

; (:m :do "SECS first (a positive integer), then the options --max-desc N (default 64) and --receipt FILE in any order, then -- and the command; a missing separator, a non-positive SECS, an option without its value or an empty command is an error text, never a run")
fn optionsOf rest: (List String) maxDesc: Int64 receipt: String bad: String -> Parsed
  (let [(flag (optionOr (listHead rest) ""))
        (value (optionOr (listGet rest 1) ""))
        (hasValue (and (>= (listLength rest) 2) (not (= value "--"))))]
    (cond
      ((and (= flag "--max-desc") hasValue) (optionsOf (listDrop rest 2) (optionOr (stringToInt64 value) 0) receipt bad))
      ((and (= flag "--receipt") hasValue) (optionsOf (listDrop rest 2) maxDesc value bad))
      ((or (= flag "--max-desc") (= flag "--receipt")) (Parsed :secs 0 :maxDesc maxDesc :receipt receipt :argv (list) :error (str flag " needs a value")))
      (else (let [(sepOk (= flag "--"))]
              (Parsed :secs 0 :maxDesc maxDesc :receipt receipt :argv (if sepOk (optionOr (listTail rest) (list)) (list))
                      :error (if sepOk bad "the command must follow --"))))))

fn parseArgs args: (List String) -> Parsed
  (let [(secs (optionOr (stringToInt64 (optionOr (listHead args) "")) 0))
        (o (optionsOf (optionOr (listTail args) (list)) 64 "" ""))]
    (Parsed :secs secs :maxDesc o.maxDesc :receipt o.receipt :argv o.argv
            :error (cond ((<= secs 0) "SECS must be a positive integer")
                         ((not (stringEmpty? o.error)) o.error)
                         ((<= o.maxDesc 0) "--max-desc must be a positive integer")
                         ((listEmpty? o.argv) "the command is empty")
                         (else ""))))

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :ref LEON-TIMEOUT-NO-RECEIPT :do "the one ASN line --receipt FILE gains on every stop of the command, an exit, a timeout or a runaway kill: the verdict, exit code, SECS, run time and the command's first word, never its arguments or environment, so a run the bound killed before it wrote its own receipt still leaves one")
fn receiptLine verdict: String exit: Int64 secs: Int64 ms: Int64 argv: (List String) -> String
  (str "(:bounded :verdict :" verdict " :exit " (stringFromInt64 exit) " :secs " (stringFromInt64 secs) " :ms " (stringFromInt64 ms)
       " :cmd " (quoted (optionOr (listHead argv) "")) ")\n")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (parseArgs args))]
    (if (not (stringEmpty? p.error))
      (do (eprintln (str "bounded: " p.error)) (eprintln (usage)) (ok 2))
      (let [(root (resultOr (realPath ".") "."))
            (d (fr/runOneLimited (fr/job p.argv root (fr/childEnv (list))) (fr/limits p.secs p.maxDesc)))
            (wrote (or (stringEmpty? p.receipt) (ok? (fileAppend p.receipt (receiptLine d.verdict d.exit p.secs d.ms p.argv)))))]
        (do (print d.out)
            (if wrote () (eprintln (str "bounded: the receipt could not be written to " p.receipt)))
            (ok d.exit)))))
