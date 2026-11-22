(module asl-tools/fleet/tests/ticketPumpDropTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js)])

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/ticketPumpDropTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! testDropBeforeOnDone -> Bool
  (let [(dir (scratch "a"))
        (_ (rmDir dir))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/config.asn") "(:jobserver :tokens 1)\n"))
        (lim (fr/heavy (fr/limits 60 16) "writer" dir))
        (jobs (list (fr/job (list "sleep" "1") "." (fr/childEnv (list))) (fr/job (list "true") "." (fr/childEnv (list)))))
        (seen (fn [(acc (List Int64)) (d fr/Done)] -> (List Int64)
                (cons (listLength (resultOr (dirList (str dir "/wait")) (list))) acc)))
        (r (fr/runPoolEach jobs 2 lim (fn [(i Int64)] -> Bool true) seen (list)))
        (counts (pairSecond r))
        (_ (rmDir dir))]
    (do (assert (= (listLength counts) 2) (str "both items finished: " counts))
        (assert (= (optionOr (listLast counts) -1) 0) (str "no ticket of the waiting item is filed while the first onDone runs: " counts))
        true))

fn ! runTests -> Bool
  (do (assert (testDropBeforeOnDone) "poolPump drops the next ticket before onDone") true)

fn ! rmDir dir: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 16)))] (= d.exit 0))
