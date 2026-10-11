fn outcome r: (Result String IoError) -> String
  (match r ((ok notFound) notFound) ((err e) (match e ((notFound) "missing") (_ "other"))))
