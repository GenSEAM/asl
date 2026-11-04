(module aslAgent/tests/poolBigRequestTest
  :x [runTests]
  :i [(aslAgent/sessionPool :a sp) (asl-tools/fleet/run :a fr)])

; (:m :ref LEONPOOL-RETRYAFTER-MAC-HANG :do "a request larger than a unix socket buffer (8 KB each way on macOS) goes to a hub that shares the pool's thread and reads only between pool steps: the pool must not block in the write, it hands the rest over on later steps; the session ends with the hub's reply and the hub saw every byte. The failing shape is a hang at 0% CPU, so the gate runs under a wall")
(schema Stub
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64))

(schema Hub
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen Int64)
  (:f bytes Int64))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn complete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn okReply -> String
  (str "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")

fn withStubs h: Hub stubs: (List Stub) -> Hub
  (with h :stubs stubs)

fn ! stepStub! h: Hub s: Stub ready: (List (Pair Int64 Int64)) -> Hub
  (cond
    ((not (ready? ready s.fd)) (withStubs h (listAppend h.stubs (list s))))
    (else
      (match (fdRead s.fd 65536)
        ((err _) (do (fdClose s.fd) h))
        ((ok chunk)
          (if (stringEmpty? chunk) (do (fdClose s.fd) h)
            (let [(input (str s.input chunk))]
              (if (complete? input)
                (do (fdWrite s.fd (okReply)) (fdClose s.fd) (with h :seen (+ h.seen 1) :bytes (stringLength input)))
                (withStubs h (listAppend h.stubs (list (Stub :fd s.fd :input input :replyAt 0)))))))))))

fn ! stepHub! h: Hub ready: (List (Pair Int64 Int64)) -> Hub
  (let [(accepted (if (ready? ready h.listener)
                    (match (sockAccept h.listener)
                      ((ok fd) (withStubs h (listAppend h.stubs (list (Stub :fd fd :input "" :replyAt 0)))))
                      ((err _) h))
                    h))]
    (fold (fn [(acc Hub) (s Stub)] -> Hub (stepStub! acc s ready)) (withStubs accepted (list)) accepted.stubs))

fn hubWatch h: Hub -> (List (Pair Int64 Int64))
  (cons (pair h.listener 1) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) h.stubs))

fn bigBody -> String
  (str "{\"m\":\"" (stringRepeat "x" 600000) "\"}")

fn turnFn state: String reply: String -> sp/Turn
  (if (= state "big")
    (sp/Turn :state "bigDone" :request (some (bigBody)) :exec none :result none)
    (sp/Turn :state "end" :request none :exec none :result (some reply)))

fn ! pump! p: sp/Pool h: Hub deadline: Int64 -> (Pair sp/Pool Hub)
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair p h)
    (match (fdPoll (listAppend (hubWatch h) (sp/poolWatch p)) 10)
      ((err _) (pump! p h deadline))
      ((ok ready) (pump! (sp/poolStep! p ready turnFn (nowMs!)) (stepHub! h ready) deadline))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/poolBigRequestTest.XXXXXX" 5000) "")))
        (sock (str temp "/hub.sock"))
        (spill (str temp "/spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (p0 (sp/poolSubmit! (sp/newPool sock 1 8 60000 spill) "big" "big" (nowMs!)))
        (out (pump! p0 (Hub :listener listener :stubs (list) :seen 0 :bytes 0) (+ (nowMs!) 20000)))
        (rows (sp/poolDone (pairFirst out)))
        (hub (pairSecond out))
        (closed (do (map (fn [(s Stub)] -> Bool (do (fdClose s.fd) true)) hub.stubs) (fdClose listener) (pathRemove sock) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (= (listLength rows) 1) (str "the session with the large request ended: " (stringFromInt64 (listLength rows))))
      (assert (and (= hub.seen 1) (>= hub.bytes 600000)) (str "the hub read the whole request: " (stringFromInt64 hub.bytes) " bytes"))
      (assert (not (listAny? (fn [(d (Pair String String))] -> Bool (stringContains? (pairSecond d) "unreachable")) rows)) "the hub was not given up on")
      (assert removed "temp dir removed")
      true))
