(module aslAgent/tests/toolHubStub
  :x [main]
  :i [(asl-json/json :a j)])

; (:m :ref NATIVE-TOOLS-DEFAULT :do "stand-in hub for a tool-only model: a request that offers tools gets a JSON tool_call (first a step that writes subject.txt green, then done), a request without tools gets the prose a tool-tuned model narrates when no tool is offered; every request is appended to the file in argv 2; it serves until killed")
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

fn ! reply! conn: Int64 ctype: String body: String -> Bool
  (do (fdWrite conn (str "HTTP/1.1 200 OK\r\nContent-Type: " ctype "\r\nContent-Length: " (stringFromInt64 (bytesLength (stringToBytes body))) "\r\nConnection: close\r\n\r\n" body))
    (fdClose conn) true)

fn toolReply form: String -> String
  (j/jsonEmit (j/jobj (list (pair "choices" (j/jarr (list (j/jobj (list (pair "index" (j/jint 0)) (pair "finish_reason" (j/jstr "tool_calls"))
    (pair "message" (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jnull))
      (pair "tool_calls" (j/jarr (list (j/jobj (list (pair "id" (j/jstr "c1")) (pair "type" (j/jstr "function"))
        (pair "function" (j/jobj (list (pair "name" (j/jstr "step")) (pair "arguments" (j/jstr (j/jsonEmit (j/jobj (list (pair "form" (j/jstr form))))))))))))))))))))))))))

fn ! serve! listener: Int64 out: String calls: Int64 -> (Result Int64 String)
  (match (sockAccept listener)
    ((err e) (err e))
    ((ok conn)
      (let [(req (readRequest! conn ""))
            (_logged (fileAppend out (str req "\n----\n")))
            (offered (stringContains? req "\"tools\""))]
        (if offered
          (do (reply! conn "application/json" (toolReply (if (= calls 0) "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\")" "(:done)")))
              (serve! listener out (+ calls 1)))
          (do (reply! conn "application/asn+sexpr" "(:reply :content \"Let me start by reading the file.\")")
              (serve! listener out calls))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (unixListen (optionOr (listGet args 0) ""))
    ((err e) (err e))
    ((ok listener) (serve! listener (optionOr (listGet args 1) "") 0)))
