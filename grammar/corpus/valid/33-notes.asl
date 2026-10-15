(module text/notes :x [initials shout])

"A note is a string literal bound to nothing. The body position already admitted
one; the top level did not, so a file banner or a note between declarations had
nowhere to live."

fn initials name: String -> String
  "Notes sit between declarations as well as inside them; the host evaluates a
top-level one at load and discards it."
  (stringJoin (map (fn [(w String)] -> String (optionOr (stringSlice w 0 1) "")) (stringSplit name " ")) "")

"A note may span lines."

fn shout s: String -> String
  (str (stringUpper s) "!")
