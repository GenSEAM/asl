(module asl-csv/csvWrite
  :x [csvField csvRow csvFormat]
  :i [])

fn csvWriteNeedsQuote s: String -> Bool
  (if (stringEmpty? s) false
    (or (stringContains? s ",")
        (or (stringContains? s "\"")
            (or (stringContains? s "\r")
                (or (stringContains? s "\n")
                    (or (= (optionOr (stringSlice s 0 1) "") " ")
                        (= (optionOr (stringSlice s (- (stringLength s) 1) (stringLength s)) "") " ")))))))

fn csvField s: String -> String
  (if (csvWriteNeedsQuote s)
    (str "\"" (stringJoin (stringSplit s "\"") "\"\"") "\"")
    s)

fn csvRow fields: (List String) -> String
  (stringJoin (map csvField fields) ",")

fn csvFormat rows: (List (List String)) -> String
  (if (listEmpty? rows) ""
    (str (stringJoin (map csvRow rows) "\n") "\n"))
