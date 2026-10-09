"expect-only: rule-2"

"`Missing` is on the export list and is declared nowhere in this module. Same"

"code as an exported-but-undefined function: the entry names nothing."

(module text/missing :x [Missing shout])

fn shout x: String -> String
  (str (stringUpper x) "!")
