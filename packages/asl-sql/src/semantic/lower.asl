(module asl-sql/semantic/lower
  :d "Semantic Lowering Compiler: Transforms ExpandedQuery AST into Concrete sql/SelectQuery."
  :x [lowerQuery lowerJoins formatProjectedExpr]
  :i [(asl-sql/core :a sql)
      (asl-sql/semantic/schema :a sem)
      (asl-sql/semantic/expand :a exp)
      (asl-text/string :a s)])

(df formatProjectedExpr [(expr sql/SqlExpr)] -> String
  :d "Formats a projected SqlExpr into a SQL SELECT column fragment."
  (sql/renderExprStr expr (sql/postgres) 1))

(df lowerJoins [(rootTable String) (rels (List sem/RelationDef))] -> (List sql/SqlJoin)
  :d "Lowers required relations into aliased LEFT JOIN clauses."
  (if (list-empty? rels)
    (list)
    (mt (list-head rels)
      ((none) (list))
      ((some r)
       (let [(restJoins (lowerJoins rootTable (unwrap (list-tail rels))))
             (onCond (sql/binary (sql/eq)
                                 (sql/qualCol rootTable (.-sourceKey r))
                                 (sql/qualCol (.-targetEntity r) (.-targetKey r))))
             (j (sql/makeJoin (sql/leftJoin) (.-targetEntity r) onCond))]
         (cons j restJoins))))))

(df lowerQuery [(schema sem/SemanticSchema) (eq exp/ExpandedQuery)] -> (Result sql/SelectQuery String)
  :d "Lowers an ExpandedQuery into a standard sql/SelectQuery with joins, projections, and grouping."
  (let [(root (.-rootEntity eq))
        (rootTable (.-table root))
        (allExprs (listConcat (.-projectedFields eq) (.-projectedMeasures eq)))
        (cols (map formatProjectedExpr allExprs))
        (joins (lowerJoins rootTable (.-requiredRelations eq)))
        (groups (.-groupBy eq))]
    (ok (sql/SelectQuery :columns cols
                         :fromTable rootTable
                         :joins joins
                         :whereClause (.-whereClause eq)
                         :groupBy groups
                         :havingClause (none)
                         :orderColumn (.-orderBy eq)
                         :orderDir (.-orderDir eq)
                         :limitCount (.-limitCount eq)
                         :offsetCount (.-offsetCount eq)
                         :forUpdateSkipLocked false
                         :returningColumns (list)))))
