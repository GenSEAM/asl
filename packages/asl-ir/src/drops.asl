(module asl-ir/drops :x [insertDrops requiresDrop?] :i [(asl-ir/types :a ty)])

fn requiresDrop? t: ty/IrType -> Bool
  (let [(k t.kind)] (or (= k "str") (= k "adt") (= k "closure") (= k "buf") (and (= k "option") (= t.repr "tagged"))))

fn insertDrops stmts: (List ty/IrStmt) -> (List ty/IrStmt)
  stmts
