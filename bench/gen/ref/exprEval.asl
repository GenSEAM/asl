enum Expr (num n: Int64) (add l: Expr r: Expr) (mul l: Expr r: Expr) (neg e: Expr)

fn exprEval e: Expr -> Int64
  (match e
    ((num n) n)
    ((add l r) (+ (exprEval l) (exprEval r)))
    ((mul l r) (* (exprEval l) (exprEval r)))
    ((neg inner) (- 0 (exprEval inner))))
