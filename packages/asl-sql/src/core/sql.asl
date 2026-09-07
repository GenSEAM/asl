(module asl-sql/core
  :d "Native AgentScript Cross-Dialect SQL AST Query Builder and Parameterized Renderer."
  :x [SqlDialect BinaryOp OrderDir JoinType SqlExpr SqlJoin SelectQuery RenderedQuery
           default-dialect dialect-quote-char dialect-param-prefix
           is-parameterized is-literal-param col-expr str-expr int-expr bool-expr raw-expr json-get-expr
           make-join make-select render-binary-op render-placeholder render-json-path
           render-expr-str count-params render-select count-pair-params render-logical-op
           collect-params collect-joins-params render-joins-indexed render-where-clause-indexed]
  :i [(core/strings :a s)])

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
  (:c in-op  [] "In set membership (IN)"))

(dfe OrderDir
  (:c asc  [] "Ascending order")
  (:c desc [] "Descending order"))

(dfe JoinType
  (:c inner-join [] "INNER JOIN")
  (:c left-join  [] "LEFT OUTER JOIN")
  (:c right-join [] "RIGHT OUTER JOIN")
  (:c full-join  [] "FULL OUTER JOIN"))

(dfe SqlExpr
  (:c col          [(name String)]                                   "Column identifier")
  (:c lit-str      [(val String)]                                    "String literal parameter")
  (:c lit-int      [(val Int64)]                                     "Integer literal parameter")
  (:c lit-bool     [(val Bool)]                                      "Boolean literal parameter")
  (:c lit-null     []                                                "NULL SQL literal")
  (:c raw-sql      [(snippet String)]                                "Direct unescaped SQL escape hatch")
  (:c json-extract [(col String) (path String)]                      "Cross-dialect JSON field extraction polyfill")
  (:c binary       [(op BinaryOp) (left SqlExpr) (right SqlExpr)]    "Binary comparison operation")
  (:c and-expr     [(left SqlExpr) (right SqlExpr)]                  "Logical AND conjunction")
  (:c or-expr      [(left SqlExpr) (right SqlExpr)]                  "Logical OR disjunction")
  (:c not-expr     [(inner SqlExpr)]                                 "Logical NOT inversion"))

(dfs SqlJoin
  (:f join-type JoinType "Join classification")
  (:f table String "Target joined table")
  (:f on-clause SqlExpr "Join predicate condition"))

(dfs SelectQuery
  (:f columns (List String) "Projected column list")
  (:f from-table String "Primary source table name")
  (:f joins (List SqlJoin) "Joined table clauses")
  (:f where-clause (Option SqlExpr) "Optional filter predicate")
  (:f order-column (Option String) "Optional ordering column")
  (:f order-dir OrderDir "Sort direction (asc or desc)")
  (:f limit-count (Option Int64) "Maximum rows to return")
  (:f offset-count (Option Int64) "Row offset")
  (:f for-update-skip-locked Bool "Whether query locks rows with FOR UPDATE SKIP LOCKED")
  (:f returning-columns (List String) "Columns to return in RETURNING clause"))

(dfs RenderedQuery
  (:f sql String "Parameterized SQL query string")
  (:f query-sql String "Parameterized SQL query string alias")
  (:f param-count Int64 "Total bound parameter placeholders")
  (:f params (List SqlExpr) "Literal parameter expressions in traversal order"))

(df default-dialect [] -> SqlDialect
  :d "Returns the default target SQL dialect (PostgreSQL)."
  (postgres))

(df dialect-quote-char [(dialect SqlDialect)] -> String
  :d "Returns the identifier quoting character for the given dialect."
  (mt dialect
    ((mysql)      "`")
    ((clickhouse) "`")
    (_            "\"")))

(df dialect-param-prefix [(dialect SqlDialect)] -> String
  :d "Returns parameter placeholder prefix for the dialect ($ for postgres, ? for others)."
  (mt dialect
    ((postgres) "$")
    (_          "?")))

(df col-expr [(name String)] -> SqlExpr
  :d "Constructs a column identifier expression."
  (col name))

(df str-expr [(val String)] -> SqlExpr
  :d "Constructs a string literal parameter expression."
  (lit-str val))

(df int-expr [(val Int64)] -> SqlExpr
  :d "Constructs an integer literal parameter expression."
  (lit-int val))

(df bool-expr [(val Bool)] -> SqlExpr
  :d "Constructs a boolean literal parameter expression."
  (lit-bool val))

(df raw-expr [(snippet String)] -> SqlExpr
  :d "Constructs a raw unescaped SQL expression escape hatch."
  (raw-sql snippet))

(df json-get-expr [(col String) (path String)] -> SqlExpr
  :d "Constructs a cross-dialect JSON extraction expression."
  (json-extract col path))

(df make-join [(jt JoinType) (tbl String) (on-cond SqlExpr)] -> SqlJoin
  :d "Constructs a SqlJoin record."
  (SqlJoin :join-type jt :table tbl :on-clause on-cond))

(df make-select [(cols (List String)) (tbl String) (where-opt (Option SqlExpr))] -> SelectQuery
  :d "Constructs a basic SelectQuery with optional where clause."
  (SelectQuery :columns cols
               :from-table tbl
               :joins (list)
               :where-clause where-opt
               :order-column (none)
               :order-dir (asc)
               :limit-count (none)
               :offset-count (none)
               :for-update-skip-locked false
               :returning-columns (list)))

(df render-binary-op [(op BinaryOp)] -> String
  :d "Renders binary operator token to standard SQL string."
  (mt op
    ((eq)    "=")
    ((neq)   "<>")
    ((gt)    ">")
    ((gte)   ">=")
    ((lt)    "<")
    ((lte)   "<=")
    ((like)  "LIKE")
    ((in-op) "IN")))

(df render-placeholder [(dialect SqlDialect) (idx Int64)] -> String
  :d "Renders a dialect-specific parameter placeholder."
  (mt dialect
    ((postgres) (str "$" (string-from-int64 idx)))
    (_          "?")))

(df count-pair-params [(l SqlExpr) (r SqlExpr)] -> Int64
  :d "Helper to sum parameters across expression pair."
  (+ (count-params l) (count-params r)))

(df is-literal-param [(expr SqlExpr)] -> Bool
  :d "Returns true if expression is a parameterized literal."
  (mt expr
    ((lit-str _)  true)
    ((lit-int _)  true)
    ((lit-bool _) true)
    (_            false)))

(df count-params [(expr SqlExpr)] -> Int64
  :d "Recursively counts parameter placeholders in an expression."
  (if (is-literal-param expr)
    1
    (mt expr
      ((binary _ l r)   (count-pair-params l r))
      ((and-expr l r)   (count-pair-params l r))
      ((or-expr l r)    (count-pair-params l r))
      ((not-expr inner) (count-params inner))
      (_                0))))

(df collect-params [(expr SqlExpr)] -> (List SqlExpr)
  :d "Walks SqlExpr tree and extracts all literal parameters in traversal order."
  (if (is-literal-param expr)
    (list expr)
    (mt expr
      ((binary _ l r)   (list-concat (collect-params l) (collect-params r)))
      ((and-expr l r)   (list-concat (collect-params l) (collect-params r)))
      ((or-expr l r)    (list-concat (collect-params l) (collect-params r)))
      ((not-expr inner) (collect-params inner))
      (_                (list)))))

(df collect-joins-params [(joins (List SqlJoin))] -> (List SqlExpr)
  :d "Walks all joins and extracts literal parameters across ON clauses."
  (if (list-empty? joins)
    (list)
    (mt (list-head joins)
      ((some j)
       (let [(rest-joins (mt (list-tail joins) ((some r) r) ((none) (list))))]
         (list-concat (collect-params (.-on-clause j)) (collect-joins-params rest-joins))))
      ((none) (list)))))

(df is-parameterized [(expr SqlExpr)] -> Bool
  :d "Returns true if expression contains literal parameters that need binding."
  (> (count-params expr) 0))

(df render-pair-exprs [(l SqlExpr) (r SqlExpr) (dialect SqlDialect) (param-idx Int64) (sep String) (wrap-paren Bool)] -> String
  :d "Helper to render two subexpressions with sequential parameter offsets."
  (let [(l-str (render-expr-str l dialect param-idx))
        (r-idx (+ param-idx (count-params l)))
        (r-str (render-expr-str r dialect r-idx))]
    (if wrap-paren
      (str "(" l-str ") " sep " (" r-str ")")
      (str l-str " " sep " " r-str))))

(df render-logical-op [(op-name String) (l SqlExpr) (r SqlExpr) (dialect SqlDialect) (param-idx Int64)] -> String
  :d "Renders a logical AND/OR conjunction with balanced parentheses."
  (render-pair-exprs l r dialect param-idx op-name true))

(df render-json-func [(fn-open String) (col String) (path-open String) (path String) (fn-close String)] -> String
  :d "Helper to format vendor JSON extraction function."
  (str fn-open col path-open path fn-close))

(df render-json-path [(col String) (path String) (dialect SqlDialect)] -> String
  :d "Renders dialect-specific JSON extraction expression string."
  (mt dialect
    ((postgres)   (str col "->>'" path "'"))
    ((sqlite)     (render-json-func "json_extract(" col ", '$." path "')"))
    ((mysql)      (render-json-func "JSON_UNQUOTE(JSON_EXTRACT(" col ", '$." path "'))"))
    ((clickhouse) (render-json-func "JSONExtractString(" col ", '" path "')"))))

(df render-expr-str [(expr SqlExpr) (dialect SqlDialect) (param-idx Int64)] -> String
  :d "Recursively renders a parameterized SQL expression."
  (if (is-literal-param expr)
    (render-placeholder dialect param-idx)
    (mt expr
      ((col name)       name)
      ((lit-null)       "NULL")
      ((raw-sql snip)   snip)
      ((json-extract c-name p-name) (render-json-path c-name p-name dialect))
      ((binary op l r)  (render-pair-exprs l r dialect param-idx (render-binary-op op) false))
      ((and-expr l r)   (render-logical-op "AND" l r dialect param-idx))
      ((or-expr l r)    (render-logical-op "OR" l r dialect param-idx))
      ((not-expr inner) (str "NOT (" (render-expr-str inner dialect param-idx) ")"))
      (_                ""))))

(df render-join-type [(jt JoinType)] -> String
  :d "Renders SQL join keyword."
  (mt jt
    ((inner-join) "INNER JOIN")
    ((left-join)  "LEFT JOIN")
    ((right-join) "RIGHT JOIN")
    ((full-join)  "FULL JOIN")))

(df render-join-clause [(j SqlJoin) (dialect SqlDialect) (param-idx Int64)] -> String
  :d "Renders a single JOIN clause fragment with starting parameter index."
  (str (render-join-type (.-join-type j)) " " (.-table j) " ON " (render-expr-str (.-on-clause j) dialect param-idx)))

(df render-joins-indexed [(joins (List SqlJoin)) (dialect SqlDialect) (param-idx Int64)] -> String
  :d "Renders all JOIN clauses sequentially with threaded parameter indices."
  (if (list-empty? joins)
    ""
    (mt (list-head joins)
      ((some j)
       (let [(clause-sql (render-join-clause j dialect param-idx))
             (j-params-count (count-params (.-on-clause j)))
             (next-idx (+ param-idx j-params-count))
             (rest-joins (mt (list-tail joins) ((some r) r) ((none) (list))))
             (rest-sql (render-joins-indexed rest-joins dialect next-idx))]
         (if (> (string-length rest-sql) 0)
           (str " " clause-sql rest-sql)
           (str " " clause-sql))))
      ((none) ""))))

(df render-joins [(joins (List SqlJoin)) (dialect SqlDialect)] -> String
  :d "Renders all JOIN clauses sequentially."
  (render-joins-indexed joins dialect 1))

(df render-order-dir [(dir OrderDir)] -> String
  :d "Renders ORDER BY direction token."
  (mt dir
    ((asc)  "ASC")
    ((desc) "DESC")))

(df render-order-by [(col-opt (Option String)) (dir OrderDir)] -> String
  :d "Renders ORDER BY clause if order column is present."
  (mt col-opt
    ((none) "")
    ((some col) (str " ORDER BY " col " " (render-order-dir dir)))))

(df render-limit [(limit-opt (Option Int64))] -> String
  :d "Renders LIMIT clause if limit is present."
  (mt limit-opt
    ((none) "")
    ((some lim) (str " LIMIT " (string-from-int64 lim)))))

(df render-offset [(offset-opt (Option Int64))] -> String
  :d "Renders OFFSET clause if offset is present."
  (mt offset-opt
    ((none) "")
    ((some off) (str " OFFSET " (string-from-int64 off)))))

(df render-for-update [(lock Bool)] -> String
  :d "Renders FOR UPDATE SKIP LOCKED clause if enabled."
  (if lock
    " FOR UPDATE SKIP LOCKED"
    ""))

(df render-returning [(cols (List String))] -> String
  :d "Renders RETURNING clause if columns are specified."
  (if (list-empty? cols)
    ""
    (str " RETURNING " (string-join cols ", "))))

(df render-where-clause-indexed [(where-opt (Option SqlExpr)) (dialect SqlDialect) (param-idx Int64)] -> String
  :d "Renders WHERE clause SQL string if present with custom parameter offset."
  (mt where-opt
    ((none) "")
    ((some w-expr) (str " WHERE " (render-expr-str w-expr dialect param-idx)))))

(df render-where-clause [(where-opt (Option SqlExpr)) (dialect SqlDialect)] -> String
  :d "Renders WHERE clause SQL string if present."
  (render-where-clause-indexed where-opt dialect 1))

(df extract-where-params [(where-opt (Option SqlExpr))] -> (List SqlExpr)
  :d "Extracts literal parameter list from optional WHERE clause."
  (mt where-opt
    ((none) (list))
    ((some w-expr) (collect-params w-expr))))

(df render-select [(q SelectQuery) (dialect SqlDialect)] -> RenderedQuery
  :d "Renders a complete SelectQuery into parameterized SQL string."
  (let [(base-sql (str "SELECT " (string-join (.-columns q) ", ") " FROM " (.-from-table q)))
        (join-params (collect-joins-params (.-joins q)))
        (join-params-count (list-length join-params))
        (joins-sql (render-joins-indexed (.-joins q) dialect 1))
        (where-start-idx (+ 1 join-params-count))
        (where-sql (render-where-clause-indexed (.-where-clause q) dialect where-start-idx))
        (order-sql (render-order-by (.-order-column q) (.-order-dir q)))
        (limit-sql (render-limit (.-limit-count q)))
        (offset-sql (render-offset (.-offset-count q)))
        (lock-sql (render-for-update (.-for-update-skip-locked q)))
        (return-sql (render-returning (.-returning-columns q)))
        (full-sql (str base-sql joins-sql where-sql order-sql limit-sql offset-sql lock-sql return-sql))
        (where-params (extract-where-params (.-where-clause q)))
        (all-params (list-concat join-params where-params))
        (p-count (list-length all-params))]
    (RenderedQuery :sql full-sql
                   :query-sql full-sql
                   :param-count p-count
                   :params all-params)))
