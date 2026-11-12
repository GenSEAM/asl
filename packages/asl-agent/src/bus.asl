(module aslAgent/bus
  :x [BusEvent busPath eventLine parseEvent emitTerminal! readEvents! findEvent waitFor! pollMs]
  :i [(aslGateway/wire :a wire)
      (aslGateway/config :a c)
      (aslGateway/usage :a g)
      (asl-parser/reader :a rd)])

; (:m :ref SIGNAL-LEON-DONE :do "every terminal Leon run appends one single-line row to the shared inbox events.asn under a lock; a waiter reads the file with bounded sleeps instead of polling a process. Rows are keyed by unit, never rewritten")
(schema BusEvent
  (:f unit String)
  (:f stop String)
  (:f head String)
  (:f gates String)
  (:f exit Int64)
  (:f asserts Int64)
  (:f receiptPath String)
  (:f at Int64))

fn busPath home: String -> String
  (g/posixJoin home ".asl/bus/events.asn")

fn quoted s: String -> String
  (str "\"" (wire/asnEscape s) "\"")

fn eventLine ev: BusEvent -> String
  (str "(:event :unit " (quoted ev.unit) " :stop " (quoted ev.stop) " :head " (quoted ev.head) " :gates " (quoted ev.gates)
       " :exit " (stringFromInt64 ev.exit) " :asserts " (stringFromInt64 ev.asserts) " :receiptPath " (quoted ev.receiptPath)
       " :at " (stringFromInt64 ev.at) ")")

fn strField props: (Map String rd/SExpr) key: String -> (Option String)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarStr s) (some s)) (_ none))))

fn intField props: (Map String rd/SExpr) key: String -> (Option Int64)
  (match (mapGet props key)
    ((none) none)
    ((some e) (match (c/asnScalar e) ((c/scalarInt n) (some n)) (_ none))))

; (:m :do "none for a torn, malformed or incomplete row: every field must be present with its type")
fn parseEvent line: String -> (Option BusEvent)
  (let [(t (stringTrim line))]
    (if (stringEmpty? t)
      none
      (match (c/asnProps (rd/parseSexpr t) (some ":event"))
        ((err _) none)
        ((ok p)
         (match (strField p "unit")
           ((none) none)
           ((some unit)
            (match (strField p "stop")
              ((none) none)
              ((some stop)
               (match (strField p "head")
                 ((none) none)
                 ((some head)
                  (match (strField p "gates")
                    ((none) none)
                    ((some gates)
                     (match (intField p "exit")
                       ((none) none)
                       ((some ex)
                        (match (intField p "asserts")
                          ((none) none)
                          ((some asserts)
                           (match (strField p "receiptPath")
                             ((none) none)
                             ((some rp)
                              (match (intField p "at")
                                ((none) none)
                                ((some at) (some (BusEvent :unit unit :stop stop :head head :gates gates :exit ex :asserts asserts :receiptPath rp :at at))))))))))))))))))))))

fn ! appendLocked! path: String text: String tries: Int64 -> (Result Bool String)
  (match (fileLock (str path ".lock") true)
    ((err e)
     (if (and (= e "busy") (> tries 0))
       (do (sleepMs 5) (appendLocked! path text (- tries 1)))
       (err (str "bus lock " path ": " e))))
    ((ok fd)
     (let [(res (fileAppend path text))
           (closed (fdClose fd))]
       (match res
         ((err e) (err (str "bus append " path ": " e)))
         ((ok _) (ok true))))))

; (:m :ref SIGNAL-LEON-DONE :do "one whole row per call: the unit must be named, the line is built from escaped fields so it never holds a newline, and the append is serialised by a lock beside the file")
fn ! emitTerminal! path: String ev: BusEvent -> (Result Bool String)
  (if (stringEmpty? ev.unit)
    (err "bus event needs a unit")
    (match (dirCreate (g/posixDirname path))
      ((err e) (err (str "bus dir: " e)))
      ((ok _) (appendLocked! path (str (eventLine ev) "\n") 400))))

fn completeLines text: String -> (List String)
  (let [(parts (stringSplit text "\n"))]
    (if (stringEndsWith? text "\n") parts (listTake parts (max 0 (- (listLength parts) 1)))))

; (:m :do "a missing file is no events; a last line without its newline is a row still being written and is left for the next read; unparsable rows are skipped")
fn ! readEvents! path: String -> (Result (List BusEvent) String)
  (if (not (fileExists? path))
    (ok (list))
    (match (fileReadString path)
      ((err e) (err e))
      ((ok text)
       (ok (fold (fn [(acc (List BusEvent)) (line String)] -> (List BusEvent)
                   (match (parseEvent line) ((some ev) (listAppend acc (list ev))) ((none) acc)))
             (list) (completeLines text))))))

fn findEvent events: (List BusEvent) unit: String sinceMs: Int64 -> (Option BusEvent)
  (listFind (fn [(e BusEvent)] -> Bool (and (= e.unit unit) (>= e.at sinceMs))) (reverse events))

fn pollMs -> Int64
  200

; (:m :ref SIGNAL-LEON-DONE :do "blocks until a row for unit with at >= sinceMs appears or nowMs reaches deadlineMs, sleeping at most pollMs between reads and never past the deadline; none on the deadline")
fn ! waitFor! path: String unit: String sinceMs: Int64 deadlineMs: Int64 -> (Option BusEvent)
  (let [(found (match (readEvents! path) ((ok evs) (findEvent evs unit sinceMs)) ((err _) none)))
        (now (/ (nowNs) 1000000))]
    (match found
      ((some ev) (some ev))
      ((none)
       (if (>= now deadlineMs)
         none
         (do (sleepMs (min (pollMs) (- deadlineMs now)))
           (waitFor! path unit sinceMs deadlineMs))))))
