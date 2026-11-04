(module aslAgent/tests/contextConfigScopeTest
  :x [runTests]
  :i [(aslAgent/context :a ctx)])

; (:m :ref AGENTLOOP-CONFIG-SCHEMA :do "context.asl read parseDefectEscalate and the three context settings by a scan of the whole config text, so the same key in another group or inside a doc string set them; now only a top-level key of :agentLoop counts")
fn ints text: String -> (List (Option Int64))
  (list (ctx/parseDefectEscalateIn text) (ctx/contextKeepTurnsIn text) (ctx/contextToolCapBytesIn text) (ctx/contextMaxOlderLinesIn text))

fn allNone? xs: (List (Option Int64)) -> Bool
  (listAll? (fn [(x (Option Int64))] -> Bool (none? x)) xs)

fn shown xs: (List (Option Int64)) -> String
  (stringJoin (map (fn [(x (Option Int64))] -> String (match x ((some n) (stringFromInt64 n)) ((none) "none"))) xs) " ")

fn ! runTests -> Bool
  (let [(keys ":parseDefectEscalate 5 :contextKeepTurns 3 :contextToolCapBytes 77 :contextMaxOlderLines 9")
        (own (ints (str "(:aslConfig :agentLoop (" keys "))")))
        (other (ints (str "(:aslConfig :mesh (" keys ") :agentLoop (:baseline true))")))
        (doc (ints (str "(:aslConfig :agentLoop (:doc \"set " keys " to tune\" :baseline true))")))
        (nested (ints (str "(:aslConfig :agentLoop (:sub (" keys ") :baseline true))")))
        (word (ints "(:aslConfig :agentLoop (:parseDefectEscalate 0 :contextKeepTurns many :contextToolCapBytes -4 :contextMaxOlderLines 9x))"))]
    (do
      (assert (= own (list (some 5) (some 3) (some 77) (some 9))) (str "top-level keys of :agentLoop are read: " (shown own)))
      (assert (allNone? other) (str "the same keys in another group are not read: " (shown other)))
      (assert (allNone? doc) (str "the same keys inside a doc string are not read: " (shown doc)))
      (assert (allNone? nested) (str "the same keys in a nested list are not read: " (shown nested)))
      (assert (allNone? word) (str "a value that is not a positive integer reads as absent: " (shown word)))
      true))
