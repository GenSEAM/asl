(module core/private :x [sizeOf])

(enum Hidden (:c secret [(payload String)] "A value nobody outside may name"))

(schema Vault (:f x Int64 "A counter nobody outside may construct"))

fn sizeOf s: String -> Int64
  (stringLength s)
