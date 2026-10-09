"A note is a string literal bound to nothing. The body position already admitted
one; the top level did not, so a file banner or a note between declarations had
nowhere to live. A note is an ADDITION beside the `;` comment, not a replacement
for it: the host still reads `;` as a comment to the end of the line."

(module text/notes :x [initials shout])

"Notes sit between declarations as well as inside them; the host evaluates a
top-level one at load and discards it. A note may span lines."

fn initials name: String -> String
  (do "Splitting on a single space rather than on whitespace is deliberate: the
   vocabulary has no whitespace-class split, and the caller trims." (stringJoin (map (fn [w] (stringUpper (optionOr (stringSlice w 0 1) ""))) (stringSplit (stringTrim name) " ")) ""))

fn shout s: String -> String
  (str (stringUpper s) "!")
