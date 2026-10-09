(module asl-net/tests/reactorFramingTest
  :x [runTests]
  :i [(asl-net/reactor :a r) (asl-http/http11 :a http)])

fn headerCount headers: (List (Pair String String)) name: String -> Int64
  (listLength (filter (fn [(h (Pair String String))] -> Bool (= (stringLower (pairFirst h)) name)) headers))

fn ! slowReaderWrite! payload: String deadlineMs: Int64 -> (Pair (Result Unit String) Int64)
  (mt (procSpawnv (list "/bin/sh" "-c" "sleep 0.3; cat > /dev/null") (none) (none))
    ((err e) (pair (err (str "spawn: " e)) 0))
    ((ok sp)
      (let [(_ (fdClose sp.stdout))
            (_ (fdClose sp.stderr))
            (nb (fdNonBlocking sp.stdin true))
            (started (monotonicNs))
            (written (if (ok? nb) (r/writeAll! sp.stdin payload 0 (+ started (* deadlineMs 1000000))) (err "fdNonBlocking failed")))
            (elapsedMs (/ (- (monotonicNs) started) 1000000))
            (_ (fdClose sp.stdin))
            (_ (if (ok? written) (procWaitPid sp.pid false) (do (procKill (- 0 sp.pid) "SIGKILL") (procWaitPid sp.pid false))))]
        (pair written elapsedMs))))

fn ! runTests -> Bool
  (let [(chunked (r/responseHeaders (list (pair "Transfer-Encoding" "chunked") (pair "Content-Length" "3")) "abc"))
        (explicit (r/responseHeaders (list (pair "Content-Length" "3")) "abc"))
        (implicit (r/responseHeaders (list) "hello"))
        (badPollServer (r/Server :listenerFd -1 :nextConnId 1 :connections (list) :procs (list) :config (r/makeServerConfig)))
        (pollResult (r/reactorStep! badPollServer 0))
        (payload (fold (fn [(s String) (_ Int64)] -> String (str s s)) "x" (range 0 20)))
        (slow (slowReaderWrite! payload 5000))
        (stuck (slowReaderWrite! payload 200))]
    (do
      (assert (= (headerCount chunked "content-length") 0) "chunked response omits Content-Length")
      (assert (= (headerCount explicit "content-length") 1) "a caller's Content-Length is not duplicated")
      (assert (= (optionOr (listHead (map (fn [(h (Pair String String))] -> String (pairSecond h)) implicit)) "") "5") "Content-Length is added from the body when absent")
      (mt (http/parseHttpRequest "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
        ((err e) (assert false (str "Content-Length body parses: " e)))
        ((ok parsed) (assert (= parsed.body "hello") "parsed request body equals Content-Length bytes")))
      (assert (err? pollResult) "fdPoll failure is returned, not reported as an empty successful step")
      (assert (ok? (pairFirst slow)) (str "1 MiB to a non-blocking pipe completes once the reader starts: " (mt (pairFirst slow) ((ok _) "ok") ((err e) e))))
      (assert (>= (pairSecond slow) 250) (str "the write waited for the reader (" (stringFromInt64 (pairSecond slow)) " ms)"))
      (assert (= (mt (pairFirst stuck) ((ok _) "ok") ((err e) e)) "ERR_WRITE_TIMEOUT") (str "a reader that never drains in time ends in ERR_WRITE_TIMEOUT: " (mt (pairFirst stuck) ((ok _) "ok") ((err e) e))))
      true))
