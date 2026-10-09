(module asl-sql/core :x [SqlDialect BinaryOp OrderDir JoinType SqlExpr SqlJoin SelectQuery RenderedQuery WhenClause defaultDialect dialectQuoteChar dialectParamPrefix isParameterized isLiteralParam colExpr strExpr intExpr boolExpr rawExpr jsonGetExpr arithExpr aggExpr aliasExpr qualColExpr caseWhenExpr makeWhen makeJoin makeSelect renderBinaryOp renderPlaceholder renderJsonPath renderExprStr countParams renderSelect countPairParams renderLogicalOp collectParams collectJoinsParams renderJoinsIndexed renderWhereClauseIndexed renderGroupBy renderHavingClauseIndexed extractHavingParams] :i [(asl-text/string :a s)])

(enum SqlDialect (:c sqlite [] "SQLite 3 embedded dialect with '?' positional placeholders") (:c postgres [] "PostgreSQL dialect with '$n' indexed placeholders") (:c mysql [] "MySQL/MariaDB dialect with backtick quotes") (:c clickhouse [] "ClickHouse OLAP dialect with backtick quotes"))

(enum BinaryOp (:c eq [] "Equal (=)") (:c neq [] "Not equal (<>)") (:c gt [] "Greater than (>)") (:c gte [] "Greater than or equal (>=)") (:c lt [] "Less than (<)") (:c lte [] "Less than or equal (<=)") (:c like [] "Pattern match (LIKE)") (:c inOp [] "In set membership (IN)"))

(enum OrderDir (:c asc [] "Ascending order") (:c desc [] "Descending order"))

(enum JoinType (:c innerJoin [] "INNER JOIN") (:c leftJoin [] "LEFT OUTER JOIN") (:c rightJoin [] "RIGHT OUTER JOIN") (:c fullJoin [] "FULL OUTER JOIN"))

(schema WhenClause (:f cond SqlExpr) (:f result SqlExpr))

(enum SqlExpr (:c col [(name String)] "Column identifier") (:c litStr [(val String)] "String literal parameter") (:c litInt [(val Int64)] "Integer literal parameter") (:c litBool [(val Bool)] "Boolean literal parameter") (:c litNull [] "NULL SQL literal") (:c rawSql [(snippet String)] "Direct unescaped SQL escape hatch") (:c jsonExtract [(col String) (path String)] "Cross-dialect JSON field extraction polyfill") (:c binary [(op BinaryOp) (left SqlExpr) (right SqlExpr)] "Binary comparison operation") (:c andExpr [(left SqlExpr) (right SqlExpr)] "Logical AND conjunction") (:c orExpr [(left SqlExpr) (right SqlExpr)] "Logical OR disjunction") (:c notExpr [(inner SqlExpr)] "Logical NOT inversion") (:c arith [(op String) (left SqlExpr) (right SqlExpr)] "Arithmetic expression (+ - * /)") (:c agg [(fn String) (arg SqlExpr) (distinct Bool)] "Aggregate function invocation (sum, count, avg, min, max)") (:c alias [(expr SqlExpr) (asName String)] "Aliased expression AS asName") (:c qualCol [(tbl String) (col String)] "Qualified column reference tbl.col") (:c caseWhen [(whens (List WhenClause)) (elseExpr SqlExpr)] "CASE WHEN ... THEN ... ELSE ... END"))

(schema SqlJoin (:f joinType JoinType) (:f table String) (:f onClause SqlExpr))

(schema SelectQuery (:f columns (List String)) (:f fromTable String) (:f joins (List SqlJoin)) (:f whereClause (Option SqlExpr)) (:f groupBy (List String)) (:f havingClause (Option SqlExpr)) (:f orderColumn (Option String)) (:f orderDir OrderDir) (:f limitCount (Option Int64)) (:f offsetCount (Option Int64)) (:f forUpdateSkipLocked Bool) (:f returningColumns (List String)))

(schema RenderedQuery (:f sql String) (:f querySql String) (:f paramCount Int64) (:f params (List SqlExpr)))

fn defaultDialect -> SqlDialect
  (postgres)

fn dialectQuoteChar dialect: SqlDialect -> String
  (mt dialect ((mysql) "`") ((clickhouse) "`") (_ "\""))

fn dialectParamPrefix dialect: SqlDialect -> String
  (mt dialect ((postgres) "$") (_ "?"))

fn colExpr name: String -> SqlExpr
  (col name)

fn strExpr val: String -> SqlExpr
  (litStr val)

fn intExpr val: Int64 -> SqlExpr
  (litInt val)

fn boolExpr val: Bool -> SqlExpr
  (litBool val)

fn rawExpr snippet: String -> SqlExpr
  (rawSql snippet)

fn jsonGetExpr col: String path: String -> SqlExpr
  (jsonExtract col path)

fn makeWhen cond: SqlExpr result: SqlExpr -> WhenClause
  (WhenClause :cond cond :result result)

fn arithExpr op: String left: SqlExpr right: SqlExpr -> SqlExpr
  (arith op left right)

fn aggExpr fn: String arg: SqlExpr distinct: Bool -> SqlExpr
  (agg fn arg distinct)

fn aliasExpr expr: SqlExpr asName: String -> SqlExpr
  (alias expr asName)

fn qualColExpr tbl: String col: String -> SqlExpr
  (qualCol tbl col)

fn caseWhenExpr whens: (List WhenClause) elseExpr: SqlExpr -> SqlExpr
  (caseWhen whens elseExpr)

fn makeJoin jt: JoinType tbl: String onCond: SqlExpr -> SqlJoin
  (SqlJoin :joinType jt :table tbl :onClause onCond)

fn makeSelect cols: (List String) tbl: String whereOpt: (Option SqlExpr) -> SelectQuery
  (SelectQuery :columns cols :fromTable tbl :joins (list) :whereClause whereOpt :groupBy (list) :havingClause (none) :orderColumn (none) :orderDir (asc) :limitCount (none) :offsetCount (none) :forUpdateSkipLocked false :returningColumns (list))

fn renderBinaryOp op: BinaryOp -> String
  (mt op ((eq) "=") ((neq) "<>") ((gt) ">") ((gte) ">=") ((lt) "<") ((lte) "<=") ((like) "LIKE") ((inOp) "IN"))

fn renderPlaceholder dialect: SqlDialect idx: Int64 -> String
  (mt dialect ((postgres) (str "$" (stringFromInt64 idx))) (_ "?"))

fn countPairParams l: SqlExpr r: SqlExpr -> Int64
  (+ (countParams l) (countParams r))

fn isLiteralParam expr: SqlExpr -> Bool
  (mt expr ((litStr _) true) ((litInt _) true) ((litBool _) true) (_ false))

fn countWhensParams whens: (List WhenClause) -> Int64
  (if (listEmpty? whens) 0 (mt (listHead whens) ((some w) (let [(wCount (+ (countParams w.cond) (countParams w.result))) (restW (mt (listTail whens) ((some r) r) ((none) (list))))] (+ wCount (countWhensParams restW)))) ((none) 0)))

fn countParams expr: SqlExpr -> Int64
  (if (isLiteralParam expr) 1 (mt expr ((binary _ l r) (countPairParams l r)) ((andExpr l r) (countPairParams l r)) ((orExpr l r) (countPairParams l r)) ((notExpr inner) (countParams inner)) ((arith _ l r) (countPairParams l r)) ((agg _ arg _) (countParams arg)) ((alias inner _) (countParams inner)) ((qualCol _ _) 0) ((caseWhen whens elseExpr) (+ (countWhensParams whens) (countParams elseExpr))) (_ 0)))

fn collectWhensParams whens: (List WhenClause) -> (List SqlExpr)
  (if (listEmpty? whens) (list) (mt (listHead whens) ((some w) (let [(wParams (listAppend (collectParams w.cond) (collectParams w.result))) (restW (mt (listTail whens) ((some r) r) ((none) (list))))] (listAppend wParams (collectWhensParams restW)))) ((none) (list))))

fn collectParams expr: SqlExpr -> (List SqlExpr)
  (if (isLiteralParam expr) (list expr) (mt expr ((binary _ l r) (listAppend (collectParams l) (collectParams r))) ((andExpr l r) (listAppend (collectParams l) (collectParams r))) ((orExpr l r) (listAppend (collectParams l) (collectParams r))) ((notExpr inner) (collectParams inner)) ((arith _ l r) (listAppend (collectParams l) (collectParams r))) ((agg _ arg _) (collectParams arg)) ((alias inner _) (collectParams inner)) ((qualCol _ _) (list)) ((caseWhen whens elseExpr) (listAppend (collectWhensParams whens) (collectParams elseExpr))) (_ (list))))

fn collectJoinsParams joins: (List SqlJoin) -> (List SqlExpr)
  (if (listEmpty? joins) (list) (mt (listHead joins) ((some j) (let [(restJoins (mt (listTail joins) ((some r) r) ((none) (list))))] (listAppend (collectParams j.onClause) (collectJoinsParams restJoins)))) ((none) (list))))

fn isParameterized expr: SqlExpr -> Bool
  (> (countParams expr) 0)

fn renderPairExprs l: SqlExpr r: SqlExpr dialect: SqlDialect paramIdx: Int64 sep: String wrapParen: Bool -> String
  (let [(lStr (renderExprStr l dialect paramIdx)) (rIdx (+ paramIdx (countParams l))) (rStr (renderExprStr r dialect rIdx))] (if wrapParen (str "(" lStr ") " sep " (" rStr ")") (str lStr " " sep " " rStr)))

fn renderLogicalOp opName: String l: SqlExpr r: SqlExpr dialect: SqlDialect paramIdx: Int64 -> String
  (renderPairExprs l r dialect paramIdx opName true)

fn renderJsonFunc fnOpen: String col: String pathOpen: String path: String fnClose: String -> String
  (str fnOpen col pathOpen path fnClose)

fn renderJsonPath col: String path: String dialect: SqlDialect -> String
  (mt dialect ((postgres) (str col "->>'" path "'")) ((sqlite) (renderJsonFunc "json_extract(" col ", '$." path "')")) ((mysql) (renderJsonFunc "JSON_UNQUOTE(JSON_EXTRACT(" col ", '$." path "'))")) ((clickhouse) (renderJsonFunc "JSONExtractString(" col ", '" path "')")))

fn renderWhensIndexed whens: (List WhenClause) dialect: SqlDialect paramIdx: Int64 -> String
  (if (listEmpty? whens) "" (mt (listHead whens) ((some w) (let [(condStr (renderExprStr w.cond dialect paramIdx)) (condCount (countParams w.cond)) (resIdx (+ paramIdx condCount)) (resStr (renderExprStr w.result dialect resIdx)) (resCount (countParams w.result)) (nextIdx (+ resIdx resCount)) (restW (mt (listTail whens) ((some r) r) ((none) (list)))) (clauseStr (str " WHEN " condStr " THEN " resStr)) (restStr (renderWhensIndexed restW dialect nextIdx))] (str clauseStr restStr))) ((none) "")))

fn renderExprStr expr: SqlExpr dialect: SqlDialect paramIdx: Int64 -> String
  (if (isLiteralParam expr) (renderPlaceholder dialect paramIdx) (mt expr ((col name) name) ((litNull) "NULL") ((rawSql snip) snip) ((jsonExtract cName pName) (renderJsonPath cName pName dialect)) ((binary op l r) (renderPairExprs l r dialect paramIdx (renderBinaryOp op) false)) ((andExpr l r) (renderLogicalOp "AND" l r dialect paramIdx)) ((orExpr l r) (renderLogicalOp "OR" l r dialect paramIdx)) ((notExpr inner) (str "NOT (" (renderExprStr inner dialect paramIdx) ")")) ((arith op l r) (renderPairExprs l r dialect paramIdx op true)) ((agg fn arg distinct) (str (stringUpper fn) "(" (if distinct "DISTINCT " "") (renderExprStr arg dialect paramIdx) ")")) ((alias inner asName) (str (renderExprStr inner dialect paramIdx) " AS " asName)) ((qualCol tbl col) (str tbl "." col)) ((caseWhen whens elseExpr) (let [(whensSql (renderWhensIndexed whens dialect paramIdx)) (whensCount (countWhensParams whens)) (elseIdx (+ paramIdx whensCount)) (elseSql (renderExprStr elseExpr dialect elseIdx))] (str "CASE" whensSql " ELSE " elseSql " END"))) (_ "")))

fn renderJoinType jt: JoinType -> String
  (mt jt ((innerJoin) "INNER JOIN") ((leftJoin) "LEFT JOIN") ((rightJoin) "RIGHT JOIN") ((fullJoin) "FULL JOIN"))

fn renderJoinClause j: SqlJoin dialect: SqlDialect paramIdx: Int64 -> String
  (str (renderJoinType j.joinType) " " j.table " ON " (renderExprStr j.onClause dialect paramIdx))

fn renderJoinsIndexed joins: (List SqlJoin) dialect: SqlDialect paramIdx: Int64 -> String
  (if (listEmpty? joins) "" (mt (listHead joins) ((some j) (let [(clauseSql (renderJoinClause j dialect paramIdx)) (jParamsCount (countParams j.onClause)) (nextIdx (+ paramIdx jParamsCount)) (restJoins (mt (listTail joins) ((some r) r) ((none) (list)))) (restSql (renderJoinsIndexed restJoins dialect nextIdx))] (if (> (stringLength restSql) 0) (str " " clauseSql restSql) (str " " clauseSql)))) ((none) "")))

fn renderJoins joins: (List SqlJoin) dialect: SqlDialect -> String
  (renderJoinsIndexed joins dialect 1)

fn renderOrderDir dir: OrderDir -> String
  (mt dir ((asc) "ASC") ((desc) "DESC"))

fn renderOrderBy colOpt: (Option String) dir: OrderDir -> String
  (mt colOpt ((none) "") ((some col) (str " ORDER BY " col " " (renderOrderDir dir))))

fn renderLimit limitOpt: (Option Int64) -> String
  (mt limitOpt ((none) "") ((some lim) (str " LIMIT " (stringFromInt64 lim))))

fn renderOffset offsetOpt: (Option Int64) -> String
  (mt offsetOpt ((none) "") ((some off) (str " OFFSET " (stringFromInt64 off))))

fn renderForUpdate lock: Bool -> String
  (if lock " FOR UPDATE SKIP LOCKED" "")

fn renderReturning cols: (List String) -> String
  (if (listEmpty? cols) "" (str " RETURNING " (stringJoin cols ", ")))

fn renderWhereClauseIndexed whereOpt: (Option SqlExpr) dialect: SqlDialect paramIdx: Int64 -> String
  (if (or (none? whereOpt) (none? whereOpt)) "" (mt whereOpt ((some wExpr) (str " WHERE " (renderExprStr wExpr dialect paramIdx))) (_ "")))

fn renderWhereClause whereOpt: (Option SqlExpr) dialect: SqlDialect -> String
  (renderWhereClauseIndexed whereOpt dialect 1)

fn extractWhereParams whereOpt: (Option SqlExpr) -> (List SqlExpr)
  (if (or (none? whereOpt) (none? whereOpt)) (list) (mt whereOpt ((some wExpr) (collectParams wExpr)) (_ (list))))

fn renderGroupBy groups: (List String) -> String
  (if (listEmpty? groups) "" (str " GROUP BY " (stringJoin groups ", ")))

fn renderHavingClauseIndexed havingOpt: (Option SqlExpr) dialect: SqlDialect paramIdx: Int64 -> String
  (if (or (none? havingOpt) (none? havingOpt)) "" (mt havingOpt ((some hExpr) (str " HAVING " (renderExprStr hExpr dialect paramIdx))) (_ "")))

fn extractHavingParams havingOpt: (Option SqlExpr) -> (List SqlExpr)
  (if (or (none? havingOpt) (none? havingOpt)) (list) (mt havingOpt ((some hExpr) (collectParams hExpr)) (_ (list))))

fn renderSelect q: SelectQuery dialect: SqlDialect -> RenderedQuery
  (let [(baseSql (str "SELECT " (stringJoin q.columns ", ") " FROM " q.fromTable)) (joinParams (collectJoinsParams q.joins)) (joinParamsCount (listLength joinParams)) (joinsSql (renderJoinsIndexed q.joins dialect 1)) (whereStartIdx (+ 1 joinParamsCount)) (whereSql (renderWhereClauseIndexed q.whereClause dialect whereStartIdx)) (whereParams (extractWhereParams q.whereClause)) (whereParamsCount (listLength whereParams)) (groupSql (renderGroupBy q.groupBy)) (havingStartIdx (+ whereStartIdx whereParamsCount)) (havingSql (renderHavingClauseIndexed q.havingClause dialect havingStartIdx)) (havingParams (extractHavingParams q.havingClause)) (orderSql (renderOrderBy q.orderColumn q.orderDir)) (limitSql (renderLimit q.limitCount)) (offsetSql (renderOffset q.offsetCount)) (lockSql (renderForUpdate q.forUpdateSkipLocked)) (returnSql (renderReturning q.returningColumns)) (fullSql (str baseSql joinsSql whereSql groupSql havingSql orderSql limitSql offsetSql lockSql returnSql)) (allParams (listAppend (listAppend joinParams whereParams) havingParams)) (pCount (listLength allParams))] (RenderedQuery :sql fullSql :querySql fullSql :paramCount pCount :params allParams))
