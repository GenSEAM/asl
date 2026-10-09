(module a :x [fromA] :i [(b :a b)])

"expect: rule-11"

"Half of a two-file cycle. A cycle cannot be expressed in one file, which is"

"why this fixture is a directory: a flat glob would never see it."

fn fromA -> Int64
  1
