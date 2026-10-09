"A bare identifier in a pattern is a binder; a parenthesised one names a case."

"Both readings of one name appear here: the prelude seeds `notFound` as an"

"IoError case, so the collision is live without anything being declared."

"Patterns nest one level, so the case test sits in an inner match."

fn outcome r: (Result String IoError) -> String
  (match r ((ok notFound) notFound) ((err e) (match e ((notFound) "missing") (_ "other"))))
