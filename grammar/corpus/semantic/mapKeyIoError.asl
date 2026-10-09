"expect-only: map-key-order"

"IoError is an opaque host value with no order either; the rule is that a key"

"has one, not that it avoids Float64."

fn lookup m: (Map IoError Int64) k: IoError -> (Option Int64)
  (mapGet m k)
