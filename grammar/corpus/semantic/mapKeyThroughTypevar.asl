fn blank seed: K -> (Map K Int64)
  (mapEmpty)

fn probe x: Float64 -> Int64
  (mapSize (blank x))
