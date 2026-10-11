(module servedFixture/servedProbe :x [runTests] :i [(tools/fleet/run :a run)])

(schema Row
  (:f pid Int64)
  (:f ppid Int64)
  (:f argv0 String))

fn rowOf line: String -> (Option Row)
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (rest (optionOr (listTail (optionOr (listTail words) (list))) (list)))]
    (mt (stringToInt64 (optionOr (listHead words) ""))
      ((none) (none))
      ((some pid) (mt (stringToInt64 (optionOr (listGet words 1) ""))
                    ((none) (none))
                    ((some ppid) (some (Row :pid pid :ppid ppid :argv0 (optionOr (listHead rest) ""))))))))

fn rowsOf text: String -> (List Row)
  (fold (fn [(acc (List Row)) (line String)] -> (List Row) (mt (rowOf line) ((some r) (cons r acc)) ((none) acc))) (list) (stringLines text))

fn chain rows: (List Row) pid: Int64 stop: Int64 depth: Int64 -> (List String)
  (cond
    ((= pid stop) (list "stop"))
    ((or (<= pid 1) (> depth 64)) (list))
    (else (mt (listHead (filter (fn [(r Row)] -> Bool (= r.pid pid)) rows))
            ((none) (list))
            ((some r) (let [(up (chain rows r.ppid stop (+ depth 1)))]
                        (if (listEmpty? up) (list) (cons r.argv0 up)))))))

fn ! runTests -> Bool
  (let [(stop (optionOr (stringToInt64 (optionOr (envGet "SERVED_STOP_PID") "")) -1))
        (ps (run/runOneLimited (run/job (list "/bin/ps" "-axo" "pid=,ppid=,args=") "." (run/childEnv (list))) (run/limits 20 4)))
        (seen (chain (rowsOf ps.out) (procSelf) stop 0))
        (native? (fn [(c String)] -> Bool (and (stringEndsWith? c "/bin") (stringContains? c "/cli-"))))
        (host? (fn [(c String)] -> Bool (stringEndsWith? c "asl-host")))]
    (do (assert (> stop 1) "the gate names its own pid in SERVED_STOP_PID")
        (assert (= ps.exit 0) "ps listed the processes")
        (assert (listContains? seen "stop") "the ancestor walk reaches the gate")
        (refute (listAny? host? seen) "no asl-host stands between bin/asl and this suite")
        (assert (listAny? native? seen) "a native asl binary from the nativeCli cache served this suite")
        true))
