(module asl-ir/drops
  :d "Linear and affine ownership drop insertion pass for AgentScript Core IR"
  :x [insertDrops
      requiresDrop?]
  :i [(asl-ir/types :a ty)])

(df requiresDrop? [(t ty/IrType)] -> Bool
  :d "Returns true if the type holds heap resources requiring deterministic release."
  (let [(k (.-kind t))]
    (or (= k "str")
        (= k "adt")
        (= k "closure")
        (= k "buf")
        (and (= k "option") (= (.-repr t) "tagged")))))

(df insertDrops [(stmts (List ty/IrStmt))] -> (List ty/IrStmt)
  :d "Inserts ir/drop statements for heap allocations before returns."
  stmts)
