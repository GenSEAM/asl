(module asl-net/tests/reactorParserTest
  :x [runTests]
  :i [(asl-net/reactor :a r)])

fn requestConn input: String -> r/Connection
  (r/Connection :fd 7 :connId 9 :buffer input :lastActivityNs 0 :chunkedMode false)

fn testContentLengthBodyAndPipeline -> Bool
  (let [(input "POST /body HTTP/1.1\r\nContent-Length: 4\r\n\r\nDATAGET /next HTTP/1.1\r\n\r\n")
        (result (r/tryParseRequests (requestConn input) 8192))
        (events (pairSecond result))
        (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) events))]
    (assert (= (listLength requests) 2) "body parser emits POST and following pipelined GET")
    (assert (= (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).body "DATA") "Content-Length bytes become request body")
    (assert (= (optionOr (listGet requests 1) (r/mkRequestEvent 0 "" "" (list) "")).path "/next") "bytes after request body remain next request")
    true)

fn testIncompleteBodyWaits -> Bool
  (let [(conn (requestConn "POST /body HTTP/1.1\r\nContent-Length: 4\r\n\r\nDA"))
        (result (r/tryParseRequests conn 8192))]
    (assert (listEmpty? (pairSecond result)) "incomplete Content-Length body emits no partial request")
    (assert (= (pairFirst result).buffer conn.buffer) "incomplete body remains buffered")
    true)

fn testChunkedBodyAndPipeline -> Bool
  (let [(input "POST /body HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n\r\nGET /next HTTP/1.1\r\n\r\n")
        (result (r/tryParseRequests (requestConn input) 8192))
        (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) (pairSecond result)))]
    (assert (= (listLength requests) 2) "chunked request body ends before the next request")
    (assert (= (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).body "Wiki") "chunked request body is decoded")
    true)

fn testChunkTerminatorInsideData -> Bool
  (let [(input "POST /body HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\n0\r\n\r\n0\r\n\r\nGET /next HTTP/1.1\r\n\r\n")
        (result (r/tryParseRequests (requestConn input) 8192))
        (events (pairSecond result))
        (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) events))]
    (assert (= (listLength requests) 2) "chunk data containing zero-terminator bytes does not end framing")
    (assert (= (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).body "0\r\n") "chunk parser consumes exact chunk payload")
    (assert (= (optionOr (listGet requests 1) (r/mkRequestEvent 0 "" "" (list) "")).path "/next") "chunk terminator preserves following pipelined request")
    true)

fn testChunkSizeHex -> Bool
  (do
    (assert (= (r/int64ToHex 10) "a") "chunk size ten is hexadecimal")
    (assert (= (r/int64ToHex 16) "10") "chunk size sixteen uses two hexadecimal digits")
    true)

fn testPollErrorPropagates! -> Bool
  (let [(server (r/Server :listenerFd -1 :nextConnId 1 :connections (list) :procs (list) :config (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128)))
        (result (r/reactorStep! server 0))]
    (assert (err? result) "reactorStep returns fdPoll errors")
    true)

fn ! runTests -> Bool
  (do
    (assert (testContentLengthBodyAndPipeline) "Content-Length body and pipeline")
    (assert (testIncompleteBodyWaits) "incomplete body buffering")
    (assert (testChunkedBodyAndPipeline) "chunked body and pipeline")
    (assert (testChunkTerminatorInsideData) "chunk marker bytes in data")
    (assert (testChunkSizeHex) "hex chunk sizes")
    (assert (testPollErrorPropagates!) "fdPoll error propagation")
    true)
