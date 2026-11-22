(module asl-csv/csvWriteTest
  :x [runTests]
  :i [(asl-csv/csvWrite :a csvWrite) (asl-csv/csv :a csv)])

fn runTests -> Bool
  (let [(p1 (= (csvWrite/csvField "plain") "plain"))
        (p2 (= (csvWrite/csvField "a,b") "\"a,b\""))
        (p3 (= (csvWrite/csvField "say \"hi\"") "\"say \"\"hi\"\"\""))
        (p4 (= (csvWrite/csvField "a\nb") "\"a\nb\""))
        (p5 (= (csvWrite/csvField "a\r\nb") "\"a\r\nb\""))
        (p6 (= (csvWrite/csvField " x ") "\" x \""))
        (p7 (= (csvWrite/csvField "") ""))
        (p8 (= (csvWrite/csvRow (list "a" "b,c" "")) "a,\"b,c\","))
        (p9 (= (csvWrite/csvFormat (list (list "a" "b") (list "c" "d"))) "a,b\nc,d\n"))
        (basic (and p1 p2 p3 p4 p5 p6 p7 p8 p9))
        (rows (list (list "name" "note")
                    (list "a,b" "say \"hi\"")
                    (list "line1\nline2" "")
                    (list "" " x ")))
        (parsed (match (csv/csvParseRows (csvWrite/csvFormat rows))
                  ((err e) (list))
                  ((ok parsed) parsed)))
        (rt (= parsed rows))]
    (assert (and basic rt) "csvWrite tests passed")
    true)
