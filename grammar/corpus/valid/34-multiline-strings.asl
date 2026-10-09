"The STRING terminal admits a raw newline between the quotes, and now that a"

"comment is spelled as a free-standing string, a note running to a second line"

"is ordinary source. Every backend passed the token through"

"verbatim, so the raw newline landed between the target's quotes. Rust takes a"

"multi-line literal and Python, TypeScript and Go reject one, so three of four"

"emitted source their own compiler refused, while the grammar, the checker and"

"every gate stayed green over it: no fixture had ever written one."

"A raw tab rides along because it is the other character the grammar lets"

"through as itself, and `lines` splits on the escape form of the same newline"

"the banner spells raw, so the two spellings have to arrive as one character."

"Help text is where a multi-line literal stops being exotic and becomes the
 ordinary case, which is why this module is written as help text."

(module text/usage :x [banner usage cells lines render])

fn banner -> String
  "AgentScript
==========="

fn usage -> String
  "usage: fmt [--width N] FILE

  --width N  wrap at N columns
  --help     show this text"

fn cells -> String
  "a	b	c"

fn lines -> Int64
  (do "A note inside a body, itself running to a second line: its value is
   discarded like any other non-final expression, and no backend may let its
   newline reach the target." (listLength (stringSplit (banner) "\n")))

fn render name: String -> String
  (stringReplace (str (banner) "\n" (usage)) "fmt" name)
