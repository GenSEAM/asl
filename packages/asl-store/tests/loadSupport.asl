(module asl-store/tests/loadSupport
  :x [loadScripts!]
  :i [(asl-store/conform :a cf)])

fn ! parseOne! dir: String name: String -> (Result cf/Script String)
  (match (fileReadString (str dir "/" name))
    ((err e) (err (str name ": " e)))
    ((ok text) (match (cf/parseScript text) ((err e) (err (str name ": " e))) ((ok s) (ok s)))))

; (:m :ref VS-CORE :do "test support: every *.asn script of a directory parsed in name order; the first unreadable or malformed script is the error")
fn ! loadScripts! dir: String -> (Result (List cf/Script) String)
  (match (dirList dir)
    ((err e) (err (str dir ": " e)))
    ((ok names)
      (fold (fn [(acc (Result (List cf/Script) String)) (name String)] -> (Result (List cf/Script) String)
              (match acc
                ((err e) (err e))
                ((ok xs) (match (parseOne! dir name) ((err e) (err e)) ((ok s) (ok (listAppend xs (list s))))))))
            (ok (list))
            (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asn")) names)))))
