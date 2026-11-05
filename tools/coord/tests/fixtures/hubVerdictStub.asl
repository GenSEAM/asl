(module asl-tools/coord/tests/fixtures/hubVerdictStub
  :x [main]
  :i [])

; (:m :ref PIPE-GATES :do "stand-in hub: every request is appended to the log and answered 200 with the current text of the reply file as the reply content (read per request, so a test switches the verdict between calls)")
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

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" " ")

fn ! serve! listener: Int64 out: String replyFile: String -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(req (readRequest! conn ""))
            (_ (fileAppend out (str req "\n----\n")))
            (body (str "(:reply :content \"" (esc (stringTrim (resultOr (fileReadString replyFile) ""))) "\")"))
            (_ (fdWrite conn (str "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (bytesLength (stringToBytes body))) "\r\nConnection: close\r\n\r\n" body)))
            (_ (fdClose conn))]
        (serve! listener out replyFile))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener) (serve! listener (optionOr (listGet args 1) "") (optionOr (listGet args 2) ""))))
