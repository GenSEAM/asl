(module asl-foreign/block :x [js py sh sql html css llvm c jsStr jsNum shArg pyStr sqlStr htmlText htmlAttr cssStr])

fn js body: String -> String
  body

fn py body: String -> String
  body

fn sh body: String -> String
  body

fn sql body: String -> String
  body

fn html body: String -> String
  body

fn css body: String -> String
  body

fn llvm body: String -> String
  body

fn c body: String -> String
  body

fn jsStr body: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace body "\\" "\\\\") "\"" "\\\"") "'" "\\'") "\n" "\\n") "\r" "\\r") "</" "<\\/")

fn jsNum value: Int64 -> String
  (stringFromInt64 value)

fn shArg body: String -> String
  (str "'" (stringReplace body "'" "'\\''") "'")

fn pyStr body: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace body "\\" "\\\\") "\"" "\\\"") "'" "\\'") "\n" "\\n") "\r" "\\r")

fn sqlStr body: String -> String
  (stringReplace body "'" "''")

fn htmlText body: String -> String
  (stringReplace (stringReplace (stringReplace body "&" "&amp;") "<" "&lt;") ">" "&gt;")

fn htmlAttr body: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace body "&" "&amp;") "<" "&lt;") ">" "&gt;") "\"" "&quot;") "'" "&#39;")

fn cssStr body: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace body "\\" "\\\\") "\"" "\\\"") "'" "\\'") "\n" "\\a ") "\r" "\\d ")
