(module aslExamples/fileExample
  :x [roundTrip readOr lineCount])

fn roundTrip path: String text: String -> (Result String String)
  (match (fileWrite path text)
    ((ok _) (fileReadString path))
    ((err e) (err e)))

fn readOr path: String fallback: String -> String
  (resultOr (fileReadString path) fallback)

fn lineCount path: String -> (Result Int64 String)
  (match (fileReadString path)
    ((ok s) (ok (listLength (stringSplit s "\n"))))
    ((err e) (err e)))
