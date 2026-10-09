(module asl-forms/tests/languageTopicTest
  :x [runTests]
  :i [])

fn ! languageTopic -> String
  (mt (fileReadString "asl/grammar/tools.asn")
    ((err _) "")
    ((ok t) (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "(:topic :name :language ")) (stringSplit t "\n"))) "")))

fn ! runTests -> Bool
  (let [(topic (languageTopic))]
    (do
      (assert (stringContains? topic "(module ws/name ") "tools.asn has the :language topic with its module header example")
      (assert (not (stringContains? topic ":d \\\"")) "the :language topic no longer teaches :d docs in source (D158)")
      (assert (stringContains? topic "x.f, chains as a.b.c") "the :language topic teaches field access x.f (D158)")
      (assert (stringContains? topic "(with x :k v)") "the :language topic teaches the with record copy (D158)")
      true))
