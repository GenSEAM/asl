(module asl-sql/semantic/lower :x [lowerQuery lowerJoins formatProjectedExpr] :i [(asl-sql/core :a sql) (asl-sql/semantic/schema :a sem) (asl-sql/semantic/expand :a exp) (asl-text/string :a s)])

fn formatProjectedExpr expr: sql/SqlExpr -> String
  (sql/renderExprStr expr (sql/postgres) 1)

fn lowerJoins rootTable: String rels: (List sem/RelationDef) -> (List sql/SqlJoin)
  (if (listEmpty? rels) (list) (mt (listHead rels) ((none) (list)) ((some r) (let [(restJoins (lowerJoins rootTable (optionOr (listTail rels) (list)))) (onCond (sql/binary (sql/eq) (sql/qualCol rootTable r.sourceKey) (sql/qualCol r.targetEntity r.targetKey))) (j (sql/makeJoin (sql/leftJoin) r.targetEntity onCond))] (cons j restJoins)))))

fn lowerQuery schema: sem/SemanticSchema eq: exp/ExpandedQuery -> (Result sql/SelectQuery String)
  (let [(root eq.rootEntity) (rootTable root.table) (allExprs (listAppend eq.projectedFields eq.projectedMeasures)) (cols (map formatProjectedExpr allExprs)) (joins (lowerJoins rootTable eq.requiredRelations)) (groups eq.groupBy)] (ok (sql/SelectQuery :columns cols :fromTable rootTable :joins joins :whereClause eq.whereClause :groupBy groups :havingClause (none) :orderColumn eq.orderBy :orderDir eq.orderDir :limitCount eq.limitCount :offsetCount eq.offsetCount :forUpdateSkipLocked false :returningColumns (list))))
