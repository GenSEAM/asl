(module asl-sql/core
  :doc "Native AgentScript Cross-Dialect SQL AST Query Builder and Representation."
  :export [SqlDialect BinaryOp OrderDir JoinType SqlExpr SqlJoin SelectQuery
           default-dialect dialect-quote-char dialect-param-prefix
           is-parameterized col-expr str-expr int-expr bool-expr
           make-join make-select])

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

(defun default-dialect [] -> SqlDialect
  :doc "Returns the default target SQL dialect (PostgreSQL)."
  (postgres))

(defun dialect-quote-char [(dialect SqlDialect)] -> String
  :doc "Returns the identifier quoting character for the given dialect."
  (match dialect
    ((sqlite)     "\"")
    ((postgres)   "\"")
    ((mysql)      "`")
    ((clickhouse) "`")))

(defun dialect-param-prefix [(dialect SqlDialect)] -> String
  :doc "Returns parameter placeholder prefix for the dialect ($ for postgres, ? for others)."
  (match dialect
    ((postgres)   "$")
    ((sqlite)     "?")
    ((mysql)      "?")
    ((clickhouse) "?")))

(defun is-parameterized [(expr SqlExpr)] -> Bool
  :doc "Returns true if expression contains literal parameters that need binding."
  (match expr
    ((lit-str _)      true)
    ((lit-int _)      true)
    ((lit-bool _)     true)
    ((binary _ l r)   (or (is-parameterized l) (is-parameterized r)))
    ((and-expr l r)   (if (is-parameterized l) true (is-parameterized r)))
    ((or-expr l r)    (if (is-parameterized r) true (is-parameterized l)))
    ((not-expr inner) (is-parameterized inner))
    (_                false)))

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
