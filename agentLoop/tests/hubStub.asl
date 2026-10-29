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

fn ! main args: (List String) -> (Result Int64 String)
  (let [(sock (optionOr (listGet args 0) ""))
        (out (optionOr (listGet args 1) ""))
        (body "(:reply :content \"hello from hub\")")]
    (match (unixListen sock)
      ((err e) (err e))
      ((ok listener)
        (match (sockAccept listener)
          ((err e) (err e))
          ((ok conn)
            (let [(req (readRequest! conn ""))
                  (wrote (fileWrite out req))]
              (do (fdWrite conn (str "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))
                (fdClose conn) (fdClose listener) (ok 0))))))))
