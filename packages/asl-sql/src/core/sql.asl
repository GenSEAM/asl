(module asl-sql/core
  :doc "Native AgentScript Cross-Dialect SQL AST Query Builder and Parameterized Renderer."
  :export [SqlDialect BinaryOp OrderDir JoinType SqlExpr SqlJoin SelectQuery RenderedQuery
           default-dialect dialect-quote-char dialect-param-prefix
           is-parameterized col-expr str-expr int-expr bool-expr
           make-join make-select render-binary-op render-placeholder
           render-expr-str count-params render-select count-pair-params render-logical-op])

(defenum SqlDialect
  (:case sqlite     [] "SQLite 3 embedded dialect with '?' positional placeholders")
  (:case postgres   [] "PostgreSQL dialect with '$n' indexed placeholders")
  (:case mysql      [] "MySQL/MariaDB dialect with backtick quotes")
  (:case clickhouse [] "ClickHouse OLAP dialect with backtick quotes"))

(defenum BinaryOp
  (:case eq     [] "Equal (=)")
  (:case neq    [] "Not equal (<>)")
  (:case gt     [] "Greater than (>)")
  (:case gte    [] "Greater than or equal (>=)")
  (:case lt     [] "Less than (<)")
  (:case lte    [] "Less than or equal (<=)")
  (:case like   [] "Pattern match (LIKE)")
  (:case in-op  [] "In set membership (IN)"))

(defenum OrderDir
  (:case asc  [] "Ascending order")
  (:case desc [] "Descending order"))

(defenum JoinType
  (:case inner-join [] "INNER JOIN")
  (:case left-join  [] "LEFT OUTER JOIN")
  (:case right-join [] "RIGHT OUTER JOIN")
  (:case full-join  [] "FULL OUTER JOIN"))

(defenum SqlExpr
  (:case col      [(name String)]                                   "Column identifier")
  (:case lit-str  [(val String)]                                    "String literal parameter")
  (:case lit-int  [(val Int64)]                                     "Integer literal parameter")
  (:case lit-bool [(val Bool)]                                      "Boolean literal parameter")
  (:case lit-null []                                                "NULL SQL literal")
  (:case binary   [(op BinaryOp) (left SqlExpr) (right SqlExpr)]    "Binary comparison operation")
  (:case and-expr [(left SqlExpr) (right SqlExpr)]                  "Logical AND conjunction")
  (:case or-expr  [(left SqlExpr) (right SqlExpr)]                  "Logical OR disjunction")
  (:case not-expr [(inner SqlExpr)]                                 "Logical NOT inversion"))

(defschema SqlJoin
  (:field join-type JoinType "Join classification")
  (:field table String "Target joined table")
  (:field on-clause SqlExpr "Join predicate condition"))

(defschema SelectQuery
  (:field columns (List String) "Projected column list")
  (:field from-table String "Primary source table name")
  (:field joins (List SqlJoin) "Joined table clauses")
  (:field where-clause (Option SqlExpr) "Optional filter predicate")
  (:field order-column (Option String) "Optional ordering column")
  (:field order-dir OrderDir "Sort direction (asc or desc)")
  (:field limit-count (Option Int64) "Maximum rows to return")
  (:field offset-count (Option Int64) "Row offset"))

(defschema RenderedQuery
  (:field query-sql String "Parameterized SQL query string")
  (:field param-count Int64 "Total bound parameter placeholders"))

(defun default-dialect [] -> SqlDialect
  :doc "Returns the default target SQL dialect (PostgreSQL)."
  (postgres))

(defun dialect-quote-char [(dialect SqlDialect)] -> String
  :doc "Returns the identifier quoting character for the given dialect."
  (match dialect
    ((mysql)      "`")
    ((clickhouse) "`")
    (_            "\"")))

(defun dialect-param-prefix [(dialect SqlDialect)] -> String
  :doc "Returns parameter placeholder prefix for the dialect ($ for postgres, ? for others)."
  (match dialect
    ((postgres) "$")
    (_          "?")))

(defun col-expr [(name String)] -> SqlExpr
  :doc "Constructs a column identifier expression."
  (col name))

(defun str-expr [(val String)] -> SqlExpr
  :doc "Constructs a string literal parameter expression."
  (lit-str val))

(defun int-expr [(val Int64)] -> SqlExpr
  :doc "Constructs an integer literal parameter expression."
  (lit-int val))

(defun bool-expr [(val Bool)] -> SqlExpr
  :doc "Constructs a boolean literal parameter expression."
  (lit-bool val))

(defun make-join [(jt JoinType) (tbl String) (on-cond SqlExpr)] -> SqlJoin
  :doc "Constructs a SqlJoin record."
  (SqlJoin :join-type jt :table tbl :on-clause on-cond))

(defun make-select [(cols (List String)) (tbl String) (where-opt (Option SqlExpr))] -> SelectQuery
  :doc "Constructs a basic SelectQuery with optional where clause."
  (SelectQuery :columns cols
               :from-table tbl
               :joins (list)
               :where-clause where-opt
               :order-column (none)
               :order-dir (asc)
               :limit-count (none)
               :offset-count (none)))

(defun render-binary-op [(op BinaryOp)] -> String
  :doc "Renders binary operator token to standard SQL string."
  (match op
    ((eq)    "=")
    ((neq)   "<>")
    ((gt)    ">")
    ((gte)   ">=")
    ((lt)    "<")
    ((lte)   "<=")
    ((like)  "LIKE")
    ((in-op) "IN")))

(defun render-placeholder [(dialect SqlDialect) (idx Int64)] -> String
  :doc "Renders a dialect-specific parameter placeholder."
  (match dialect
    ((postgres) (str "$" (string-from-int64 idx)))
    (_          "?")))

(defun count-pair-params [(l SqlExpr) (r SqlExpr)] -> Int64
  :doc "Helper to sum parameters across expression pair."
  (+ (count-params l) (count-params r)))

(defun count-params [(expr SqlExpr)] -> Int64
  :doc "Recursively counts parameter placeholders in an expression."
  (match expr
    ((lit-str _)      1)
    ((lit-int _)      1)
    ((lit-bool _)     1)
    ((binary _ l r)   (count-pair-params l r))
    ((and-expr l r)   (count-pair-params l r))
    ((or-expr l r)    (count-pair-params l r))
    ((not-expr inner) (count-params inner))
    (_                0)))

(defun is-parameterized [(expr SqlExpr)] -> Bool
  :doc "Returns true if expression contains literal parameters that need binding."
  (> (count-params expr) 0))

(defun render-logical-op [(op-name String) (l SqlExpr) (r SqlExpr) (dialect SqlDialect) (param-idx Int64)] -> String
  :doc "Renders a logical AND/OR conjunction with balanced parentheses."
  (let [(l-str (render-expr-str l dialect param-idx))
        (r-idx (+ param-idx (count-params l)))
        (r-str (render-expr-str r dialect r-idx))]
    (str "(" l-str ") " op-name " (" r-str ")")))

(defun render-expr-str [(expr SqlExpr) (dialect SqlDialect) (param-idx Int64)] -> String
  :doc "Recursively renders a parameterized SQL expression."
  (match expr
    ((col name)       name)
    ((lit-null)       "NULL")
    ((lit-str _)      (render-placeholder dialect param-idx))
    ((lit-int _)      (render-placeholder dialect param-idx))
    ((lit-bool _)     (render-placeholder dialect param-idx))
    ((binary op l r)
     (let [(l-str (render-expr-str l dialect param-idx))
           (r-idx (+ param-idx (count-params l)))
           (r-str (render-expr-str r dialect r-idx))
           (op-str (render-binary-op op))]
       (str l-str " " op-str " " r-str)))
    ((and-expr l r)   (render-logical-op "AND" l r dialect param-idx))
    ((or-expr l r)    (render-logical-op "OR" l r dialect param-idx))
    ((not-expr inner) (str "NOT (" (render-expr-str inner dialect param-idx) ")"))))

(defun render-select [(q SelectQuery) (dialect SqlDialect)] -> RenderedQuery
  :doc "Renders a complete SelectQuery into parameterized SQL string."
  (let [(base (str "SELECT " (string-join (.-columns q) ", ") " FROM " (.-from-table q)))]
    (match (.-where-clause q)
      ((none)
       (RenderedQuery :query-sql base :param-count 0))
      ((some w-expr)
       (let [(where-sql (render-expr-str w-expr dialect 1))
             (p-count (count-params w-expr))
             (full-sql (str base " WHERE " where-sql))]
         (RenderedQuery :query-sql full-sql :param-count p-count))))))
