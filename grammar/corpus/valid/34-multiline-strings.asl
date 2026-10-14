(module text/usage :x [banner usage cells lines render])

fn banner -> String
  "AgentSlang
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
