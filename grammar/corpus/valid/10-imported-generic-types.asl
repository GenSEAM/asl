"A parameterised imported type instantiated at Int64, destructured recursively,"

"and an imported record constructed and read through .-field."

(module text/sizes :x [depthOf unwrap] :i [(core/trees :a t)])

fn depthOf tr: (t/Tree Int64) -> Int64
  (match tr ((t/leaf) 0) ((t/node v l r) (+ 1 (max (depthOf l) (depthOf r)))))

fn unwrap -> Int64
  (t/Cell :value 1).value
