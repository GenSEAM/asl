(module aslExamples/stringExample
  :x [words csv hasTarget prefix shout])

fn words s: String -> (List String)
  (stringSplit s " ")

fn csv parts: (List String) -> String
  (stringJoin parts ",")

fn hasTarget s: String needle: String -> Bool
  (stringContains? s needle)

fn prefix s: String n: Int64 -> String
  (optionOr (stringSlice s 0 n) s)

fn shout s: String -> String
  (str (stringUpper s) "!")
