(module asl-know/examples/aslRegex :x [countNumbers! firstGroup! selfTest] :i [(asl-regex/regex :a rx)])

fn ! countNumbers! s: String -> Int64
  (mt (rx/regex-compile! "[0-9]+")
    ((err _) -1)
    ((ok re) (listLength (rx/regex-find-all! re s))))

fn ! firstGroup! s: String -> String
  (mt (rx/regex-compile! "id=([0-9]+)")
    ((err _) "")
    ((ok re)
      (mt (rx/regex-search! re s)
        ((none) "")
        ((some m) (optionOr (rx/regex-group m 1) "")))))

fn ! selfTest -> Bool
  (and (= (countNumbers! "a1 b22 c333") 3) (= (firstGroup! "x id=42 y") "42") (= (firstGroup! "none") ""))
