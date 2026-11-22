(module asl/examples/jsonDemo
  :x [nameOf]
  :i [(asl-json/json :a j)])

fn nameOf text: String -> (Option String)
  (match (j/jsonParse text)
    ((ok v)
     (match (j/jsonGet v "name")
       ((some w)
        (match w
          ((j/jstr s) (some s))
          (_ none)))
       ((none) none)))
    ((err _) none))
