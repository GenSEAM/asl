(module core/strings :x [concat upper])

"Search-path companion for corpus/valid/06-module.asl, which imports it."

"It is not a gate case: it exists so rule 9 has a real export list to check a"

"qualified name against, which no fixture could do while the module was absent."

"`trim` is left off the export list for semantic/unexportedMember.asl."

fn concat a: String b: String -> String
  (str a b)

fn upper s: String -> String
  (stringUpper s)

fn trim s: String -> String
  (stringTrim s)
