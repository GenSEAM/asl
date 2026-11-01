(module aslGateway/requestLog
  :x [ReqRow ReqInfo defaultRequestDeadlineSec reqPath reqAcceptLine reqDoneLine reqParse readReqs! noteAccept! noteDone! unresolvedRows recoverLost! tornTail! quarantineCorrupt! completeLines statusOfWire outcomeOfWire stuckRows lostSince requestDeadlineFromText]
  :i [(aslGateway/usage :a g)
      (aslGateway/config :a c)
      (aslGateway/wire :a wire)
      (asl-parser/reader :a rd)])

; (:m :ref GW-REQUEST-ACCOUNTING :do "every accepted request has one accepted row and, when it ends, one done row (outcome ok, limit, noRoute, timeout, upstreamError, gatewayError, clientGone or lost) in gatewayRequests.asn under .asl/run/usage; a restart turns every accepted row with no done row into a done row with outcome lost")
(schema ReqRow
  (:f id String)
  (:f phase String)
  (:f atMs Int64)
  (:f outcome String)
  (:f status Int64)
  (:f ms Int64))

; (:m :ref GW-REQUEST-ACCOUNTING :do "an accepted request the server still holds: its connection fd, its id, when it was accepted, and once the reply is rendered the outcome and status the done row will carry")
(schema ReqInfo
  (:f fd Int64)
  (:f id String)
  (:f startMs Int64)
  (:f outcome String)
  (:f status Int64))

fn defaultRequestDeadlineSec -> Int64
  900

fn reqPath home: String -> String
  (g/posixJoin home ".asl/run/usage/gatewayRequests.asn")

fn reqAcceptLine id: String atMs: Int64 -> String
  (str "(:req :id \"" (wire/asnEscape id) "\" :phase \"accepted\" :at " (stringFromInt64 atMs) ")\n")

fn reqDoneLine id: String atMs: Int64 outcome: String status: Int64 ms: Int64 -> String
  (str "(:req :id \"" (wire/asnEscape id) "\" :phase \"done\" :at " (stringFromInt64 atMs) " :outcome \"" (wire/asnEscape outcome) "\" :status " (stringFromInt64 status) " :ms " (stringFromInt64 ms) ")\n")

fn propInt props: (Map String rd/SExpr) key: String -> (Option Int64)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarInt n) (some n)) (_ none))))

fn propStr props: (Map String rd/SExpr) key: String -> (Option String)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarStr s) (some s)) (_ none))))

fn reqParse line: String -> (Result ReqRow String)
  (match (c/asnProps (rd/parseSexpr (stringTrim line)) (some ":req"))
    ((err e) (err (str "corrupt request row: " e)))
    ((ok p)
      (match (propStr p "id")
        ((none) (err (str "corrupt request row: no id in " line)))
        ((some id)
          (match (propStr p "phase")
            ((none) (err (str "corrupt request row: no phase in " line)))
            ((some phase)
              (match (propInt p "at")
                ((none) (err (str "corrupt request row: no at in " line)))
                ((some at)
                  (ok (ReqRow :id id :phase phase :atMs at :outcome (optionOr (propStr p "outcome") "") :status (optionOr (propInt p "status") 0) :ms (optionOr (propInt p "ms") 0)))))))))))

fn reqAll lines: (List String) acc: (List ReqRow) -> (Result (List ReqRow) String)
  (match (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some l)
      (match (reqParse l)
        ((err e) (err e))
        ((ok row) (reqAll (optionOr (listTail lines) (list)) (cons row acc)))))) 

; (:m :ref GW-REQUEST-ACCOUNTING :do "a reader does not take the append lock, so the last row may be half written: only text up to the last newline counts")
fn completeLines text: String -> (List String)
  (let [(parts (stringSplit text "\n"))]
    (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (listTake parts (max 0 (- (listLength parts) 1)))))

; (:m :ref GW-REQUEST-ACCOUNTING :do "true when the request log ends in a half written row (text that does not end in a newline)")
fn ! tornTail! path: String -> Bool
  (if (not (fileExists? path))
    false
    (match (fileReadString path)
      ((err _) false)
      ((ok text) (and (not (stringEmpty? text)) (not (stringEndsWith? text "\n"))))))

fn ! readReqs! path: String -> (Result (List ReqRow) String)
  (if (not (fileExists? path))
    (ok (list))
    (match (fileReadString path)
      ((err e) (err (str "read " path ": " e)))
      ((ok text) (reqAll (completeLines text) (list))))) 

; (:m :ref GW-REQUEST-ACCOUNTING :do "a request log with a corrupt row in the middle is renamed to gatewayRequests.asn.corrupt-<ms> and the log starts fresh, so one bad row cannot stop the recovery on every start; returns the new name, none when the log reads clean")
fn ! quarantineCorrupt! home: String nowMs: Int64 -> (Option String)
  (let [(path (reqPath home))]
    (match (readReqs! path)
      ((ok _) none)
      ((err e)
        (if (stringStartsWith? e "corrupt request row")
          (let [(to (str path ".corrupt-" (stringFromInt64 nowMs)))]
            (match (pathRename path to) ((ok _) (some to)) ((err _) none)))
          none))))

fn ! appendReq! home: String line: String -> (Result Bool String)
  (let [(path (reqPath home))]
    (match (dirCreate (g/posixDirname path))
      ((err e) (err (str "request log dir: " e)))
      ((ok _) (if (tornTail! path)
                (err "request log has a torn tail; recovery pending, row not appended")
                (g/appendFile! path line 200)))))

fn ! noteAccept! home: String id: String atMs: Int64 -> (Result Bool String)
  (appendReq! home (reqAcceptLine id atMs))

fn ! noteDone! home: String id: String atMs: Int64 outcome: String status: Int64 ms: Int64 -> (Result Bool String)
  (appendReq! home (reqDoneLine id atMs outcome status ms))

; (:m :ref GW-REQUEST-ACCOUNTING :do "the accepted rows that have no done row yet")
fn unresolvedRows rows: (List ReqRow) -> (List ReqRow)
  (let [(doneIds (map (fn [(r ReqRow)] -> String r.id) (filter (fn [(r ReqRow)] -> Bool (= r.phase "done")) rows)))]
    (filter (fn [(r ReqRow)] -> Bool (and (= r.phase "accepted") (not (listContains? doneIds r.id)))) rows))

; (:m :ref GW-REQUEST-ACCOUNTING :do "the unresolved rows older than the deadline: the stuck requests")
fn stuckRows rows: (List ReqRow) nowMs: Int64 deadlineSec: Int64 -> (List ReqRow)
  (filter (fn [(r ReqRow)] -> Bool (> (- nowMs r.atMs) (* 1000 deadlineSec))) (unresolvedRows rows))

; (:m :ref GW-REQUEST-ACCOUNTING :do "how many requests ended lost at or after sinceMs")
fn lostSince rows: (List ReqRow) sinceMs: Int64 -> Int64
  (listLength (filter (fn [(r ReqRow)] -> Bool (and (= r.phase "done") (and (= r.outcome "lost") (>= r.atMs sinceMs)))) rows))

fn replaceFile! path: String text: String -> (Result Bool String)
  (match (dirCreate (g/posixDirname path))
    ((err e) (err (str "dir for " path ": " e)))
    ((ok _)
      (let [(tmp (str path ".tmp"))]
        (match (fileWrite tmp text)
          ((err e) (err (str "write " tmp ": " e)))
          ((ok _) (match (pathRename tmp path) ((err e) (err (str "rename " tmp ": " e))) ((ok _) (ok true))))))))

fn lostRow r: ReqRow nowMs: Int64 -> ReqRow
  (ReqRow :id r.id :phase "done" :atMs nowMs :outcome "lost" :status 0 :ms (- nowMs r.atMs))

fn doneText r: ReqRow -> String
  (reqDoneLine r.id r.atMs r.outcome r.status r.ms)

; (:m :ref GW-REQUEST-ACCOUNTING :do "at server start every accepted row with no done row becomes a done row with outcome lost, the accepted rows that are resolved are dropped and done rows older than retentionMs are dropped; returns how many were lost")
fn ! recoverLost! home: String nowMs: Int64 retentionMs: Int64 -> (Result Int64 String)
  (match (readReqs! (reqPath home))
    ((err e) (err e))
    ((ok rows)
      (let [(lost (map (fn [(r ReqRow)] -> ReqRow (lostRow r nowMs)) (unresolvedRows rows)))
            (kept (filter (fn [(r ReqRow)] -> Bool (and (= r.phase "done") (>= r.atMs (- nowMs retentionMs)))) rows))
            (text (stringJoin (map doneText (listAppend kept lost)) ""))]
        (if (and (not (tornTail! (reqPath home))) (listEmpty? lost) (= (listLength kept) (listLength (filter (fn [(r ReqRow)] -> Bool (= r.phase "done")) rows))) (= (listLength rows) (listLength kept)))
          (ok 0)
          (match (replaceFile! (reqPath home) text)
            ((err e) (err e))
            ((ok _) (ok (listLength lost))))))))

fn statusOfWire data: String -> Int64
  (if (stringStartsWith? data "HTTP/1.1 ")
    (optionOr (stringToInt64 (optionOr (stringSlice data 9 12) "")) 0)
    0)

; (:m :ref GW-REQUEST-ACCOUNTING :do "the outcome of a rendered reply: 2xx ok; from the gateway itself 429 limit, 503 noRoute, 504 timeout, any other gatewayError; from an upstream 504 or 408 timeout, any other upstreamError")
fn outcomeOfWire data: String -> String
  (let [(status (statusOfWire data))
        (gw (or (stringContains? data "X-ASL-Origin: gateway") (stringContains? data "(:error :status ")))]
    (cond
      ((and (>= status 200) (< status 300)) "ok")
      ((and gw (= status 429)) "limit")
      ((and gw (= status 503)) "noRoute")
      ((or (= status 504) (= status 408)) "timeout")
      (gw "gatewayError")
      (else "upstreamError")))

; (:m :ref GW-REQUEST-ACCOUNTING :do "(:gateway ... :requestDeadlineSec N): the age after which an unfinished request counts as stuck; default 900, only 1..86400 is taken")
fn requestDeadlineFromText text: String -> Int64
  (match (c/gatewayTopIntOverride text "requestDeadlineSec")
    ((some n) (if (and (>= n 1) (<= n 86400)) n (defaultRequestDeadlineSec)))
    ((none) (defaultRequestDeadlineSec)))
