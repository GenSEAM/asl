(module asl-target-sh/tests/escapeCmdStringTest :x [runTests] :i [(asl-target-sh/emitCmd :a ec)])

; (:m :ref COVBATCH3 :do "escapeCmdString prefixes each cmd.exe metacharacter with a caret, caret first")
fn runTests -> Bool
  (do
    (assert (= (ec/escapeCmdString "plain text") "plain text") "plain text is unchanged")
    (assert (= (ec/escapeCmdString "") "") "empty")
    (assert (= (ec/escapeCmdString "a^b") "a^^b") "caret doubles")
    (assert (= (ec/escapeCmdString "a&b") "a^&b") "ampersand")
    (assert (= (ec/escapeCmdString "a|b") "a^|b") "pipe")
    (assert (= (ec/escapeCmdString "a<b") "a^<b") "less-than")
    (assert (= (ec/escapeCmdString "a>b") "a^>b") "greater-than")
    (assert (= (ec/escapeCmdString "^&") "^^^&") "carets are escaped before the others, so an escape is not escaped twice")
    (assert (= (ec/escapeCmdString "&&||<<>>") "^&^&^|^|^<^<^>^>") "every occurrence is escaped")
    (assert (= (ec/formatCmdEcho "a&b") "echo a^&b\n") "echo uses the escaped text")
    true)
