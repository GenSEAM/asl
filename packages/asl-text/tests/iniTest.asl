(module asl-text/tests/iniTest :x [runTests] :i [(asl-text/ini :a ini)])

fn rendered t: String -> String
  (ini/renderIni (resultOr (ini/parseIni t) []))

fn testBasic -> Bool
  (do (assert (= (rendered "[s]\nb=2\na=1") "[s]\na=1\nb=2") "keys sorted")
      (assert (= (rendered "; c\n# c\n\n[s]\n; x\na = 1 \n") "[s]\na=1") "comments blanks trimmed")
      (assert (= (rendered "[s]\na=1\na=2") "[s]\na=2") "repeated key last wins")
      true)

fn testQuotes -> Bool
  (do (assert (= (rendered "[s]\na=\" hi \"\nb=\"x=y\"") "[s]\na=\" hi \"\nb=x=y") "quoted values")
      (assert (= (rendered (rendered "[s]\na=\" hi \"")) (rendered "[s]\na=\" hi \"")) "quote round trip")
      true)

fn testOrder -> Bool
  (do (assert (= (rendered "[z]\nk=1\n[a]\nj=2") "[a]\nj=2\n\n[z]\nk=1") "sections sorted")
      (assert (= (rendered "g=0\n[s]\na=1") "g=0\n\n[s]\na=1") "global keys first")
      (assert (= (rendered "") "") "empty input renders empty")
      true)

fn testErrors -> Bool
  (do (assert (err? (ini/parseIni "noequals")) "missing equals is err")
      (assert (err? (ini/parseIni "[bad")) "unclosed header is err")
      (assert (err? (ini/parseIni "[s]\n=v")) "empty key is err")
      (assert (= (ini/parseIni "") (ok [])) "empty input is ok")
      true)

fn testEmptySection -> Bool
  (do (assert (= (listLength (resultOr (ini/parseIni "[empty]") [])) 1) "empty section parsed")
      (assert (= (rendered "[empty]") "[empty]") "empty section rendered")
      (assert (= (rendered "[a]\n[b]\nx=1") "[a]\n\n[b]\nx=1") "empty section kept between")
      true)

fn runTests -> Bool
  (and (testBasic) (and (testQuotes) (and (testOrder) (and (testEmptySection) (testErrors)))))
