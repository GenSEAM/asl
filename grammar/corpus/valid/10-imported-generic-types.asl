"A parameterised imported type instantiated at Int64, destructured recursively,"
"and an imported record constructed and read through .-field."

(module text/sizes
  :doc "Measurements over trees declared in another module."
  :export [depthOf unwrap]
  :import [(core/trees :as t)])

(df depthOf [(tr (t/Tree Int64))] -> Int64
  :doc "Depth of an imported tree."
  (match tr
    ((t/leaf)       0)
    ((t/node v l r) (+ 1 (max (depthOf l) (depthOf r))))))

(df unwrap [] -> Int64
  :doc "Read the field of an imported record."
  (.-value (t/Cell :value 1)))
