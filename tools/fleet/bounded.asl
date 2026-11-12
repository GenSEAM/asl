(module asl/tools/fleet/bounded
  :x [main parseArgs Parsed]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref WATCHDOG-GROUP-KILL :do "the one-line bounded runner for briefs and reruns: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] -- CMD ARGV...; the command runs as one fleet/run.asl child, and at SECS its whole process tree and groups are killed (a timeout verdict note is printed, exit 124); otherwise its output is printed whole and its exit code is returned; a perl alarm or a bare timeout kills only the direct child and leaves bin/asl descendants running")

(schema Parsed
  (:f secs Int64)
  (:f maxDesc Int64)
  (:f argv (List String))
  (:f error String))

fn usage -> String
  "usage: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] -- CMD ARGV..."

; (:m :do "SECS first (a positive integer), then an optional --max-desc N (default 64), then -- and the command; a missing separator, a non-positive SECS or an empty command is an error text, never a run")
fn parseArgs args: (List String) -> Parsed
  (let [(secs (optionOr (stringToInt64 (optionOr (listHead args) "")) 0))
        (rest (optionOr (listTail args) (list)))
        (hasMax (and (>= (listLength rest) 2) (= (optionOr (listHead rest) "") "--max-desc")))
        (maxDesc (if hasMax (optionOr (stringToInt64 (optionOr (listGet rest 1) "")) 0) 64))
        (after (if hasMax (listDrop rest 2) rest))
        (sepOk (and (not (listEmpty? after)) (= (optionOr (listHead after) "") "--")))
        (argv (if sepOk (optionOr (listTail after) (list)) (list)))]
    (Parsed :secs secs :maxDesc maxDesc :argv argv
            :error (cond ((<= secs 0) "SECS must be a positive integer")
                         ((<= maxDesc 0) "--max-desc must be a positive integer")
                         ((not sepOk) "the command must follow --")
                         ((listEmpty? argv) "the command is empty")
                         (else ""))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (parseArgs args))]
    (if (not (stringEmpty? p.error))
      (do (eprintln (str "bounded: " p.error)) (eprintln (usage)) (ok 2))
      (let [(root (resultOr (realPath ".") "."))
            (d (fr/runOneLimited (fr/job p.argv root (fr/childEnv (list))) (fr/limits p.secs p.maxDesc)))]
        (do (print d.out) (ok d.exit)))))
