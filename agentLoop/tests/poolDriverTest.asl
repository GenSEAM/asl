(module asl/agentLoop/tests/poolDriverTest
  :x [runTests]
  :i [(asl/agentLoop/sessionPool :a sp) (asl-tools/fleet/run :a fr)])

; (:m :ref SE3-POOL-DRIVER :do "poolStepG! threads a caller value through every turn call: three calls of one session leave three log entries (the first turn, the 503 reply, the 200 reply). The turn's headers reach the wire (X-Asl-Class, and the session's own X-Asl-Unit once, not the id), a 503 re-parks the same request for 1 s without spending a connection try, and the raw response, status line included, reaches the turn function")
fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn complete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn reply status: String body: String -> String
  (str "HTTP/1.1 " status "\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

; (:m :ref SE3-POOL-DRIVER :do "the stub hub answers the first request 503 and every later one 200, keeping each request text")
fn ! serveOne! listener: Int64 seen: (List String) -> (List String)
  (match (sockAccept listener)
    ((err _) seen)
    ((ok fd)
      (let [(raw (readAll! fd ""))
            (answer (if (listEmpty? seen) (reply "503 Service Unavailable" "busy") (reply "200 OK" "ok")))
            (sent (fdWrite fd answer))]
        (do (fdClose fd) (listAppend seen (list raw))))))

fn ! readAll! fd: Int64 acc: String -> String
  (if (complete? acc) acc
    (match (fdPoll (list (pair fd 1)) 2000)
      ((err _) acc)
      ((ok r)
        (match (fdRead fd 65536)
          ((err _) acc)
          ((ok chunk) (if (stringEmpty? chunk) acc (readAll! fd (str acc chunk))))))))

fn hubRequest -> String
  "{\"m\":1}"

fn turnFn log: String state: String raw: String -> (Pair String sp/Turn)
  (cond
    ((= state "a")
      (pair (str log "first;") (sp/Turn :state "b" :request (some (hubRequest)) :exec none :result none :headers (list (pair "X-Asl-Class" "hub") (pair "X-Asl-Unit" "custom") (pair "Content-Length" "999")))))
    ((stringStartsWith? raw "HTTP/1.1 503")
      (pair (str log "busy;") (sp/Turn :state "b" :request none :exec none :result none :busy true)))
    (else
      (pair (str log "done;") (sp/Turn :state "end" :request none :exec none :result (some (optionOr (stringSlice raw 0 12) ""))))))

fn ! pump! p: sp/Pool listener: Int64 seen: (List String) log: String deadline: Int64 -> (Pair sp/Pool (Pair (List String) String))
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair p (pair seen log))
    (match (fdPoll (cons (pair listener 1) (sp/poolWatch p)) 20)
      ((err _) (pump! p listener seen log deadline))
      ((ok ready)
        (let [(hubSeen (if (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) listener)) ready) (serveOne! listener seen) seen))
              (stepped (sp/poolStepG! p ready turnFn log (nowMs!)))]
          (pump! (pairFirst stepped) listener hubSeen (pairSecond stepped) deadline)))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/poolDriverTest.XXXXXX" 5000) "")))
        (sock (str temp "/hub.sock"))
        (spill (str temp "/spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (t0 (nowMs!))
        (p0 (sp/poolSubmit! (sp/newPool sock 2 8 60000 spill) "u1" "a" t0))
        (out (pump! p0 listener (list) "" (+ t0 20000)))
        (wall (- (nowMs!) t0))
        (p (pairFirst out))
        (seen (pairFirst (pairSecond out)))
        (log (pairSecond (pairSecond out)))
        (result (optionMap (fn [(d (Pair String String))] -> String (pairSecond d)) (listFind (fn [(d (Pair String String))] -> Bool (= (pairFirst d) "u1")) (sp/poolDone p))))
        (closed (do (fdClose listener) (pathRemove sock) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (match result ((some r) (= r "HTTP/1.1 200")) ((none) false)) (str "the raw response with its status line reached the turn function: " (match result ((some r) r) ((none) "no result"))))
      (assert (= log "first;busy;done;") (str "the caller value went through all three turn calls in order: " log))
      (assert (= (listLength seen) 2) (str "the 503 sent the same request again: " (stringFromInt64 (listLength seen)) " requests"))
      (assert (listAll? (fn [(r String)] -> Bool (and (stringContains? r "X-Asl-Class: hub") (stringContains? r "X-Asl-Unit: custom"))) seen) "the turn's headers are on the wire")
      (assert (listAll? (fn [(r String)] -> Bool (and (not (stringContains? r "X-Asl-Unit: u1")) (not (stringContains? r "Content-Length: 999")))) seen) "the session id is not added over a named unit, and a framing header from the turn is dropped")
      (assert (and (>= wall 1000) (< wall 6000)) (str "a 503 waits one second, not more: " (stringFromInt64 wall) " ms"))
      (assert removed "temp dir removed")
      true))
