(module text/bareCase
  :x [circle])

(enum Shape
  (:c circle    [(radius Float64)]                 "A circle")
  (:c rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))
