(module aslAgent/tests/tools400Stub
  :x [main]
  :i [])

; (:m :ref TOOLS-400-FALLBACK :do "stand-in hub: in mode tools a request that offers tools gets HTTP 400 and one without gets a text reply, in mode always every request gets HTTP 400; every request is appended to the log file")
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

fn ! reply! conn: Int64 status: String ctype: String body: String -> Bool
  (do (fdWrite conn (str "HTTP/1.1 " status "\r\nContent-Type: " ctype "\r\nContent-Length: " (stringFromInt64 (bytesLength (stringToBytes body))) "\r\nConnection: close\r\n\r\n" body))
    (fdClose conn) true)

fn ! serve! listener: Int64 out: String mode: String -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(req (readRequest! conn ""))
            (_logged (fileAppend out (str req "\n----\n")))
            (reject (or (= mode "always") (stringContains? req "\"tools\"")))
            (big (= mode "context"))]
        (do (if reject
              (reply! conn "400 Bad Request" "application/json" (if big "{\"error\":{\"message\":\"maximum context length exceeded\"}}" "{\"error\":{\"message\":\"tools are not supported\"}}"))
              (reply! conn "200 OK" "application/asn+sexpr" "(:reply :content \"text ok\")"))
            (serve! listener out mode)))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener) (serve! listener (optionOr (listGet args 1) "") (optionOr (listGet args 2) "tools"))))
