(module aslAgent/tests/hubRetryStub
  :x [main]
  :i [])

; (:m :ref HUB-QUEUE-PACED :do "stand-in hub: mode down answers the first request 503 with Retry-After 2 and later ones a text reply, mode retry answers the first request 429 with Retry-After 2 and every later one a text reply, mode long answers every request 429 with Retry-After 9999; every request is appended to the log")
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

fn ! reply! conn: Int64 status: String extra: String ctype: String body: String -> Bool
  (do (fdWrite conn (str "HTTP/1.1 " status "\r\nContent-Type: " ctype "\r\n" extra "Content-Length: " (stringFromInt64 (bytesLength (stringToBytes body))) "\r\nConnection: close\r\n\r\n" body))
    (fdClose conn) true)

fn ! serve! listener: Int64 out: String mode: String n: Int64 -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(req (readRequest! conn ""))
            (_logged (fileAppend out (str "at " (stringFromInt64 (/ (nowNs) 1000000)) "\n" req "\n----\n")))
            (limited (or (= mode "long") (= n 0)))]
        (do (if limited
              (reply! conn (if (= mode "down") "503 Service Unavailable" "429 Too Many Requests") (str "Retry-After: " (if (= mode "long") "9999" "2") "\r\n") "application/json" "{\"error\":\"ERR_RATE_LIMITED: no rate-limit token within the queue budget; retry in 2s\"}")
              (reply! conn "200 OK" "" "application/asn+sexpr" "(:reply :content \"text ok\")"))
            (serve! listener out mode (+ n 1))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener) (serve! listener (optionOr (listGet args 1) "") (optionOr (listGet args 2) "retry") 0)))
