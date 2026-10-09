(module core/private :x [sizeOf])

"Search-path companion: everything it declares stays private, so a fixture can"

"reach for a type, a case and a record that exist and are not published."

(enum Hidden (:c secret [(payload String)] "A value nobody outside may name"))

(schema Vault (:f x Int64 "A counter nobody outside may construct"))

fn sizeOf s: String -> Int64
  (stringLength s)
