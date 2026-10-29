(module asl/agentLoop/tests/hubStub
  :x [main]
  :i [])

; (:m :ref ORCH-LEON-CLIENT :do "one-shot stand-in for the hub: listens on the unix socket in argv 1, writes the first request it reads to the file in argv 2 and answers one ASN reply; providersHubTest runs it as a bounded child because the provider call blocks the caller")
fn bodyComplete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end)
      (let [(head (stringLower (optionOr (stringSlice raw 0 end) "")))
            (want (match (stringIndexOf head "content-length:")
                    ((none) 0)
                    ((some at) (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit (optionOr (stringSlice head (+ at 15) (stringLength head)) "") "\r\n")) ""))) 0))))]
        (>= (- (stringLength raw) (+ end 4)) want))))

fn ! readRequest! fd: Int64 acc: String -> String
  (if (bodyComplete? acc) acc
    (match (fdRead fd 65536)
      ((err _) acc)
      ((ok chunk) (if (stringEmpty? chunk) acc (readRequest! fd (str acc chunk))))))

fn ! reply! conn: Int64 status: String body: String -> Bool
  (do (fdWrite conn (str "HTTP/1.1 " status "\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))
    (fdClose conn) true)

fn ! serve! listener: Int64 out: String busy: Bool -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(req (readRequest! conn ""))]
        (if busy
          (do (reply! conn "503 Service Unavailable" "(:error :status 503 :reason \"hub busy\")") (serve! listener out false))
          (do (fileWrite out req) (reply! conn "200 OK" "(:reply :content \"hello from hub\")") (fdClose listener) (ok 0))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener) (serve! listener (optionOr (listGet args 1) "") (= (optionOr (listGet args 2) "") "busy"))))
