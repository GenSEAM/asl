(module asl-sql/core
  :d "Native AgentScript Cross-Dialect SQL AST Query Builder and Parameterized Renderer."
  :x [SqlDialect BinaryOp OrderDir JoinType SqlExpr SqlJoin SelectQuery RenderedQuery WhenClause
      defaultDialect dialectQuoteChar dialectParamPrefix
      isParameterized isLiteralParam colExpr strExpr intExpr boolExpr rawExpr jsonGetExpr
      arithExpr aggExpr aliasExpr qualColExpr caseWhenExpr makeWhen
      makeJoin makeSelect renderBinaryOp renderPlaceholder renderJsonPath
      renderExprStr countParams renderSelect countPairParams renderLogicalOp
      collectParams collectJoinsParams renderJoinsIndexed renderWhereClauseIndexed
      renderGroupBy renderHavingClauseIndexed extractHavingParams]
  :i [(asl-text/string :a s)])

(dfe SqlDialect
  (:c sqlite     [] "SQLite 3 embedded dialect with '?' positional placeholders")
  (:c postgres   [] "PostgreSQL dialect with '$n' indexed placeholders")
  (:c mysql      [] "MySQL/MariaDB dialect with backtick quotes")
  (:c clickhouse [] "ClickHouse OLAP dialect with backtick quotes"))

(dfe BinaryOp
  (:c eq     [] "Equal (=)")
  (:c neq    [] "Not equal (<>)")
  (:c gt     [] "Greater than (>)")
  (:c gte    [] "Greater than or equal (>=)")
  (:c lt     [] "Less than (<)")
  (:c lte    [] "Less than or equal (<=)")
  (:c like   [] "Pattern match (LIKE)")
  (:c inOp  [] "In set membership (IN)"))

(dfe OrderDir
  (:c asc  [] "Ascending order")
  (:c desc [] "Descending order"))

(dfe JoinType
  (:c innerJoin [] "INNER JOIN")
  (:c leftJoin  [] "LEFT OUTER JOIN")
  (:c rightJoin [] "RIGHT OUTER JOIN")
  (:c fullJoin  [] "FULL OUTER JOIN"))

(dfs WhenClause
  (:f cond SqlExpr "Condition predicate")
  (:f result SqlExpr "Result expression"))

(dfe SqlExpr
  (:c col          [(name String)]                                   "Column identifier")
  (:c litStr      [(val String)]                                    "String literal parameter")
  (:c litInt      [(val Int64)]                                     "Integer literal parameter")
  (:c litBool     [(val Bool)]                                      "Boolean literal parameter")
  (:c litNull     []                                                "NULL SQL literal")
  (:c rawSql      [(snippet String)]                                "Direct unescaped SQL escape hatch")
  (:c jsonExtract [(col String) (path String)]                      "Cross-dialect JSON field extraction polyfill")
  (:c binary       [(op BinaryOp) (left SqlExpr) (right SqlExpr)]    "Binary comparison operation")
  (:c andExpr     [(left SqlExpr) (right SqlExpr)]                  "Logical AND conjunction")
  (:c orExpr      [(left SqlExpr) (right SqlExpr)]                  "Logical OR disjunction")
  (:c notExpr     [(inner SqlExpr)]                                 "Logical NOT inversion")
  (:c arith       [(op String) (left SqlExpr) (right SqlExpr)]      "Arithmetic expression (+ - * /)")
  (:c agg         [(fn String) (arg SqlExpr) (distinct Bool)]       "Aggregate function invocation (sum, count, avg, min, max)")
  (:c alias       [(expr SqlExpr) (asName String)]                  "Aliased expression AS asName")
  (:c qualCol     [(tbl String) (col String)]                       "Qualified column reference tbl.col")
  (:c caseWhen    [(whens (List WhenClause)) (elseExpr SqlExpr)]    "CASE WHEN ... THEN ... ELSE ... END"))

(dfs SqlJoin
  (:f joinType JoinType "Join classification")
  (:f table String "Target joined table")
  (:f onClause SqlExpr "Join predicate condition"))

(dfs SelectQuery
  (:f columns (List String) "Projected column list")
  (:f fromTable String "Primary source table name")
  (:f joins (List SqlJoin) "Joined table clauses")
  (:f whereClause (Option SqlExpr) "Optional filter predicate")
  (:f groupBy (List String) "Optional GROUP BY column list")
  (:f havingClause (Option SqlExpr) "Optional HAVING predicate")
  (:f orderColumn (Option String) "Optional ordering column")
  (:f orderDir OrderDir "Sort direction (asc or desc)")
  (:f limitCount (Option Int64) "Maximum rows to return")
  (:f offsetCount (Option Int64) "Row offset")
  (:f forUpdateSkipLocked Bool "Whether query locks rows with FOR UPDATE SKIP LOCKED")
  (:f returningColumns (List String) "Columns to return in RETURNING clause"))

(dfs RenderedQuery
  (:f sql String "Parameterized SQL query string")
  (:f querySql String "Parameterized SQL query string alias")
  (:f paramCount Int64 "Total bound parameter placeholders")
  (:f params (List SqlExpr) "Literal parameter expressions in traversal order"))

(df defaultDialect [] -> SqlDialect
  :d "Returns the default target SQL dialect (PostgreSQL)."
  (postgres))

(df dialectQuoteChar [(dialect SqlDialect)] -> String
  :d "Returns the identifier quoting character for the given dialect."
  (mt dialect
    ((mysql)      "`")
    ((clickhouse) "`")
    (_            "\"")))

(df dialectParamPrefix [(dialect SqlDialect)] -> String
  :d "Returns parameter placeholder prefix for the dialect ($ for postgres, ? for others)."
  (mt dialect
    ((postgres) "$")
    (_          "?")))

(df colExpr [(name String)] -> SqlExpr
  :d "Constructs a column identifier expression."
  (col name))

(df strExpr [(val String)] -> SqlExpr
  :d "Constructs a string literal parameter expression."
  (litStr val))

(df intExpr [(val Int64)] -> SqlExpr
  :d "Constructs an integer literal parameter expression."
  (litInt val))

(df boolExpr [(val Bool)] -> SqlExpr
  :d "Constructs a boolean literal parameter expression."
  (litBool val))

(df rawExpr [(snippet String)] -> SqlExpr
  :d "Constructs a raw unescaped SQL expression escape hatch."
  (rawSql snippet))

(df jsonGetExpr [(col String) (path String)] -> SqlExpr
  :d "Constructs a cross-dialect JSON extraction expression."
  (jsonExtract col path))

(df makeWhen [(cond SqlExpr) (result SqlExpr)] -> WhenClause
  :d "Constructs a WhenClause record."
  (WhenClause :cond cond :result result))

(df arithExpr [(op String) (left SqlExpr) (right SqlExpr)] -> SqlExpr
  :d "Constructs an arithmetic expression."
  (arith op left right))

(df aggExpr [(fn String) (arg SqlExpr) (distinct Bool)] -> SqlExpr
  :d "Constructs an aggregate function expression."
  (agg fn arg distinct))

(df aliasExpr [(expr SqlExpr) (asName String)] -> SqlExpr
  :d "Constructs an aliased expression."
  (alias expr asName))

(df qualColExpr [(tbl String) (col String)] -> SqlExpr
  :d "Constructs a qualified column expression."
  (qualCol tbl col))

(df caseWhenExpr [(whens (List WhenClause)) (elseExpr SqlExpr)] -> SqlExpr
  :d "Constructs a CASE WHEN expression."
  (caseWhen whens elseExpr))

(df makeJoin [(jt JoinType) (tbl String) (onCond SqlExpr)] -> SqlJoin
  :d "Constructs a SqlJoin record."
  (SqlJoin :joinType jt :table tbl :onClause onCond))

(df makeSelect [(cols (List String)) (tbl String) (whereOpt (Option SqlExpr))] -> SelectQuery
  :d "Constructs a basic SelectQuery with optional where clause."
  (SelectQuery :columns cols
               :fromTable tbl
               :joins (list)
               :whereClause whereOpt
               :groupBy (list)
               :havingClause (none)
               :orderColumn (none)
               :orderDir (asc)
               :limitCount (none)
               :offsetCount (none)
               :forUpdateSkipLocked false
               :returningColumns (list)))

(df renderBinaryOp [(op BinaryOp)] -> String
  :d "Renders binary operator token to standard SQL string."
  (mt op
    ((eq)    "=")
    ((neq)   "<>")
    ((gt)    ">")
    ((gte)   ">=")
    ((lt)    "<")
    ((lte)   "<=")
    ((like)  "LIKE")
    ((inOp) "IN")))

(df renderPlaceholder [(dialect SqlDialect) (idx Int64)] -> String
  :d "Renders a dialect-specific parameter placeholder."
  (mt dialect
    ((postgres) (str "$" (string-from-int64 idx)))
    (_          "?")))

(df countPairParams [(l SqlExpr) (r SqlExpr)] -> Int64
  :d "Helper to sum parameters across expression pair."
  (+ (countParams l) (countParams r)))

(df isLiteralParam [(expr SqlExpr)] -> Bool
  :d "Returns true if expression is a parameterized literal."
  (mt expr
    ((litStr _)  true)
    ((litInt _)  true)
    ((litBool _) true)
    (_            false)))

(df countWhensParams [(whens (List WhenClause))] -> Int64
  :d "Recursively counts parameter placeholders across WHEN clauses."
  (if (list-empty? whens)
    0
    (mt (list-head whens)
      ((some w)
       (let [(wCount (+ (countParams (.-cond w)) (countParams (.-result w))))
             (restW (mt (list-tail whens) ((some r) r) ((none) (list))))]
         (+ wCount (countWhensParams restW))))
      ((none) 0))))

(df countParams [(expr SqlExpr)] -> Int64
  :d "Recursively counts parameter placeholders in an expression."
  (if (isLiteralParam expr)
    1
    (mt expr
      ((binary _ l r)   (countPairParams l r))
      ((andExpr l r)   (countPairParams l r))
      ((orExpr l r)    (countPairParams l r))
      ((notExpr inner) (countParams inner))
      ((arith _ l r)   (countPairParams l r))
      ((agg _ arg _)   (countParams arg))
      ((alias inner _) (countParams inner))
      ((qualCol _ _)   0)
      ((caseWhen whens elseExpr) (+ (countWhensParams whens) (countParams elseExpr)))
      (_                0))))

(df collectWhensParams [(whens (List WhenClause))] -> (List SqlExpr)
  :d "Extracts literal parameters across WHEN clauses in traversal order."
  (if (list-empty? whens)
    (list)
    (mt (list-head whens)
      ((some w)
       (let [(wParams (listConcat (collectParams (.-cond w)) (collectParams (.-result w))))
             (restW (mt (list-tail whens) ((some r) r) ((none) (list))))]
         (listConcat wParams (collectWhensParams restW))))
      ((none) (list)))))

(df collectParams [(expr SqlExpr)] -> (List SqlExpr)
  :d "Walks SqlExpr tree and extracts all literal parameters in traversal order."
  (if (isLiteralParam expr)
    (list expr)
    (mt expr
      ((binary _ l r)   (listConcat (collectParams l) (collectParams r)))
      ((andExpr l r)   (listConcat (collectParams l) (collectParams r)))
      ((orExpr l r)    (listConcat (collectParams l) (collectParams r)))
      ((notExpr inner) (collectParams inner))
      ((arith _ l r)   (listConcat (collectParams l) (collectParams r)))
      ((agg _ arg _)   (collectParams arg))
      ((alias inner _) (collectParams inner))
      ((qualCol _ _)   (list))
      ((caseWhen whens elseExpr) (listConcat (collectWhensParams whens) (collectParams elseExpr)))
      (_                (list)))))

(df collectJoinsParams [(joins (List SqlJoin))] -> (List SqlExpr)
  :d "Walks all joins and extracts literal parameters across ON clauses."
  (if (list-empty? joins)
    (list)
    (mt (list-head joins)
      ((some j)
       (let [(restJoins (mt (list-tail joins) ((some r) r) ((none) (list))))]
         (listConcat (collectParams (.-onClause j)) (collectJoinsParams restJoins))))
      ((none) (list)))))

(df isParameterized [(expr SqlExpr)] -> Bool
  :d "Returns true if expression contains literal parameters that need binding."
  (> (countParams expr) 0))

(df renderPairExprs [(l SqlExpr) (r SqlExpr) (dialect SqlDialect) (paramIdx Int64) (sep String) (wrapParen Bool)] -> String
  :d "Helper to render two subexpressions with sequential parameter offsets."
  (let [(lStr (renderExprStr l dialect paramIdx))
        (rIdx (+ paramIdx (countParams l)))
        (rStr (renderExprStr r dialect rIdx))]
    (if wrapParen
      (str "(" lStr ") " sep " (" rStr ")")
      (str lStr " " sep " " rStr))))

(df renderLogicalOp [(opName String) (l SqlExpr) (r SqlExpr) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders a logical AND/OR conjunction with balanced parentheses."
  (renderPairExprs l r dialect paramIdx opName true))

(df renderJsonFunc [(fnOpen String) (col String) (pathOpen String) (path String) (fnClose String)] -> String
  :d "Helper to format vendor JSON extraction function."
  (str fnOpen col pathOpen path fnClose))

(df renderJsonPath [(col String) (path String) (dialect SqlDialect)] -> String
  :d "Renders dialect-specific JSON extraction expression string."
  (mt dialect
    ((postgres)   (str col "->>'" path "'"))
    ((sqlite)     (renderJsonFunc "json_extract(" col ", '$." path "')"))
    ((mysql)      (renderJsonFunc "JSON_UNQUOTE(JSON_EXTRACT(" col ", '$." path "'))"))
    ((clickhouse) (renderJsonFunc "JSONExtractString(" col ", '" path "')"))))

(df renderWhensIndexed [(whens (List WhenClause)) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders WHEN ... THEN ... branches sequentially with threaded parameter indices."
  (if (list-empty? whens)
    ""
    (mt (list-head whens)
      ((some w)
       (let [(condStr (renderExprStr (.-cond w) dialect paramIdx))
             (condCount (countParams (.-cond w)))
             (resIdx (+ paramIdx condCount))
             (resStr (renderExprStr (.-result w) dialect resIdx))
             (resCount (countParams (.-result w)))
             (nextIdx (+ resIdx resCount))
             (restW (mt (list-tail whens) ((some r) r) ((none) (list))))
             (clauseStr (str " WHEN " condStr " THEN " resStr))
             (restStr (renderWhensIndexed restW dialect nextIdx))]
         (str clauseStr restStr)))
      ((none) ""))))

(df renderExprStr [(expr SqlExpr) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Recursively renders a parameterized SQL expression."
  (if (isLiteralParam expr)
    (renderPlaceholder dialect paramIdx)
    (mt expr
      ((col name)       name)
      ((litNull)       "NULL")
      ((rawSql snip)   snip)
      ((jsonExtract cName pName) (renderJsonPath cName pName dialect))
      ((binary op l r)  (renderPairExprs l r dialect paramIdx (renderBinaryOp op) false))
      ((andExpr l r)   (renderLogicalOp "AND" l r dialect paramIdx))
      ((orExpr l r)    (renderLogicalOp "OR" l r dialect paramIdx))
      ((notExpr inner) (str "NOT (" (renderExprStr inner dialect paramIdx) ")"))
      ((arith op l r)  (renderPairExprs l r dialect paramIdx op true))
      ((agg fn arg distinct) (str (string-upper fn) "(" (if distinct "DISTINCT " "") (renderExprStr arg dialect paramIdx) ")"))
      ((alias inner asName) (str (renderExprStr inner dialect paramIdx) " AS " asName))
      ((qualCol tbl col) (str tbl "." col))
      ((caseWhen whens elseExpr)
       (let [(whensSql (renderWhensIndexed whens dialect paramIdx))
             (whensCount (countWhensParams whens))
             (elseIdx (+ paramIdx whensCount))
             (elseSql (renderExprStr elseExpr dialect elseIdx))]
         (str "CASE" whensSql " ELSE " elseSql " END")))
      (_                ""))))

(df renderJoinType [(jt JoinType)] -> String
  :d "Renders SQL join keyword."
  (mt jt
    ((innerJoin) "INNER JOIN")
    ((leftJoin)  "LEFT JOIN")
    ((rightJoin) "RIGHT JOIN")
    ((fullJoin)  "FULL JOIN")))

(df renderJoinClause [(j SqlJoin) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders a single JOIN clause fragment with starting parameter index."
  (str (renderJoinType (.-joinType j)) " " (.-table j) " ON " (renderExprStr (.-onClause j) dialect paramIdx)))

(df renderJoinsIndexed [(joins (List SqlJoin)) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders all JOIN clauses sequentially with threaded parameter indices."
  (if (list-empty? joins)
    ""
    (mt (list-head joins)
      ((some j)
       (let [(clauseSql (renderJoinClause j dialect paramIdx))
             (jParamsCount (countParams (.-onClause j)))
             (nextIdx (+ paramIdx jParamsCount))
             (restJoins (mt (list-tail joins) ((some r) r) ((none) (list))))
             (restSql (renderJoinsIndexed restJoins dialect nextIdx))]
         (if (> (string-length restSql) 0)
           (str " " clauseSql restSql)
           (str " " clauseSql))))
      ((none) ""))))

(df renderJoins [(joins (List SqlJoin)) (dialect SqlDialect)] -> String
  :d "Renders all JOIN clauses sequentially."
  (renderJoinsIndexed joins dialect 1))

(df renderOrderDir [(dir OrderDir)] -> String
  :d "Renders ORDER BY direction token."
  (mt dir
    ((asc)  "ASC")
    ((desc) "DESC")))

(df renderOrderBy [(colOpt (Option String)) (dir OrderDir)] -> String
  :d "Renders ORDER BY clause if order column is present."
  (mt colOpt
    ((none) "")
    ((some col) (str " ORDER BY " col " " (renderOrderDir dir)))))

(df renderLimit [(limitOpt (Option Int64))] -> String
  :d "Renders LIMIT clause if limit is present."
  (mt limitOpt
    ((none) "")
    ((some lim) (str " LIMIT " (string-from-int64 lim)))))

(df renderOffset [(offsetOpt (Option Int64))] -> String
  :d "Renders OFFSET clause if offset is present."
  (mt offsetOpt
    ((none) "")
    ((some off) (str " OFFSET " (string-from-int64 off)))))

(df renderForUpdate [(lock Bool)] -> String
  :d "Renders FOR UPDATE SKIP LOCKED clause if enabled."
  (if lock
    " FOR UPDATE SKIP LOCKED"
    ""))

(df renderReturning [(cols (List String))] -> String
  :d "Renders RETURNING clause if columns are specified."
  (if (list-empty? cols)
    ""
    (str " RETURNING " (string-join cols ", "))))

(df renderWhereClauseIndexed [(whereOpt (Option SqlExpr)) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders WHERE clause SQL string if present with custom parameter offset."
  (mt whereOpt
    ((none) "")
    ((some wExpr) (str " WHERE " (renderExprStr wExpr dialect paramIdx)))))

(df renderWhereClause [(whereOpt (Option SqlExpr)) (dialect SqlDialect)] -> String
  :d "Renders WHERE clause SQL string if present."
  (renderWhereClauseIndexed whereOpt dialect 1))

(df extractWhereParams [(whereOpt (Option SqlExpr))] -> (List SqlExpr)
  :d "Extracts literal parameter list from optional WHERE clause."
  (mt whereOpt
    ((none) (list))
    ((some wExpr) (collectParams wExpr))))

(df renderGroupBy [(groups (List String))] -> String
  :d "Renders GROUP BY clause if columns are specified."
  (if (or (nil? groups) (list-empty? groups))
    ""
    (str " GROUP BY " (string-join groups ", "))))

(df renderHavingClauseIndexed [(havingOpt (Option SqlExpr)) (dialect SqlDialect) (paramIdx Int64)] -> String
  :d "Renders HAVING clause SQL string if present with custom parameter offset."
  (mt havingOpt
    ((none) "")
    ((some hExpr) (str " HAVING " (renderExprStr hExpr dialect paramIdx)))))

(df extractHavingParams [(havingOpt (Option SqlExpr))] -> (List SqlExpr)
  :d "Extracts literal parameter list from optional HAVING clause."
  (mt havingOpt
    ((none) (list))
    ((some hExpr) (collectParams hExpr))))

(df renderSelect [(q SelectQuery) (dialect SqlDialect)] -> RenderedQuery
  :d "Renders a complete SelectQuery into parameterized SQL string."
  (let [(baseSql (str "SELECT " (string-join (.-columns q) ", ") " FROM " (.-fromTable q)))
        (joinParams (collectJoinsParams (.-joins q)))
        (joinParamsCount (list-length joinParams))
        (joinsSql (renderJoinsIndexed (.-joins q) dialect 1))
        (whereStartIdx (+ 1 joinParamsCount))
        (whereSql (renderWhereClauseIndexed (.-whereClause q) dialect whereStartIdx))
        (whereParams (extractWhereParams (.-whereClause q)))
        (whereParamsCount (list-length whereParams))
        (groupSql (renderGroupBy (.-groupBy q)))
        (havingStartIdx (+ whereStartIdx whereParamsCount))
        (havingSql (renderHavingClauseIndexed (.-havingClause q) dialect havingStartIdx))
        (havingParams (extractHavingParams (.-havingClause q)))
        (orderSql (renderOrderBy (.-orderColumn q) (.-orderDir q)))
        (limitSql (renderLimit (.-limitCount q)))
        (offsetSql (renderOffset (.-offsetCount q)))
        (lockSql (renderForUpdate (.-forUpdateSkipLocked q)))
        (returnSql (renderReturning (.-returningColumns q)))
        (fullSql (str baseSql joinsSql whereSql groupSql havingSql orderSql limitSql offsetSql lockSql returnSql))
        (allParams (listConcat (listConcat joinParams whereParams) havingParams))
        (pCount (list-length allParams))]
    (RenderedQuery :sql fullSql
                   :querySql fullSql
                   :paramCount pCount
                   :params allParams)))
