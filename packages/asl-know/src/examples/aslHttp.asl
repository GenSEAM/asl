(module asl-know/examples/aslHttp :x [pathOf selfTest] :i [(asl-http/http11 :a http)])

fn pathOf raw: String -> String
  (match (http/parseHttpRequest raw)
    ((err e) (str "error: " e))
    ((ok req) (str req.method " " req.path)))

fn selfTest -> Bool
  (= (pathOf "GET /items?id=3 HTTP/1.1\r\nHost: x\r\n\r\n") "GET /items")
