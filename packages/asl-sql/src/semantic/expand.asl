(module asl-sql/semantic/expand
  :d "Semantic Query Expander, Virtual Field Inliner, and Cycle Detection Engine."
  :x [SemanticQuery ExpandedQuery makeSemanticQuery expandQuery expandExpr]
  :i [(asl-sql/core :a sql)
      (asl-sql/semantic/schema :a sem)
      (asl-text/string :a s)])

(dfs SemanticQuery
  (:f fromEntity String "Root entity model name")
  (:f selectFields (List String) "List of field or virtual derived field names to select")
  (:f selectMeasures (List String) "List of measure names to aggregate")
  (:f whereExpr (Option sql/SqlExpr) "Optional filter condition")
  (:f orderBy (Option String) "Sort column or measure")
  (:f orderDir sql/OrderDir "Sort direction")
  (:f limitCount (Option Int64) "Max rows")
  (:f offsetCount (Option Int64) "Row offset"))

(dfs ExpandedQuery
  (:f rootEntity sem/EntityModel "Target entity model")
  (:f projectedFields (List sql/SqlExpr) "Expanded physical and aliased field expressions")
  (:f projectedMeasures (List sql/SqlExpr) "Expanded measure expressions")
  (:f whereClause (Option sql/SqlExpr) "Fully inlined where expression")
  (:f requiredRelations (List sem/RelationDef) "List of relation joins needed by the query")
  (:f groupBy (List String) "Group by column names for measure aggregation")
  (:f orderBy (Option String) "Sort column")
  (:f orderDir sql/OrderDir "Sort direction")
  (:f limitCount (Option Int64) "Max rows")
  (:f offsetCount (Option Int64) "Row offset"))

(df makeSemanticQuery [(fromEntity String)
                       (selectFields (List String))
                       (selectMeasures (List String))
                       (whereExpr (Option sql/SqlExpr))
                       (orderBy (Option String))
                       (orderDir sql/OrderDir)
                       (limitCount (Option Int64))
                       (offsetCount (Option Int64))] -> SemanticQuery
  :d "Constructs a SemanticQuery record."
  (SemanticQuery :fromEntity fromEntity
                 :selectFields selectFields
                 :selectMeasures selectMeasures
                 :whereExpr whereExpr
                 :orderBy orderBy
                 :orderDir orderDir
                 :limitCount limitCount
                 :offsetCount offsetCount))

(df listContainsStr [(lst (List String)) (item String)] -> Bool
  :d "Checks if a string item is present in a list of strings."
  (if (list-empty? lst)
    false
    (mt (list-head lst)
      ((some x) (if (= x item) true (listContainsStr (unwrap (list-tail lst)) item)))
      ((none) false))))

(df expandExpr [(expr sql/SqlExpr)
                (model sem/EntityModel)
                (schema sem/SemanticSchema)
                (visited (List String))] -> (Result sql/SqlExpr String)
  :d "Recursively expands virtual derived fields into concrete expressions with cycle detection."
  (mt expr
    ((col name)
     (if (listContainsStr visited name)
       (err (str "Cycle detected in derived field: " name))
       (mt (sem/findDerived model name)
         ((some d)
          (expandExpr (.-expr d) model schema (cons name visited)))
         ((none)
          (if (string-contains? name ".")
            (let [(parts (string-split name "."))
                  (relName (unwrap (list-head parts)))
                  (colName (unwrap (list-head (unwrap (list-tail parts)))))]
              (mt (sem/findRelation model relName)
                ((some r)
                 (ok (sql/qualCol (.-targetEntity r) colName)))
                ((none)
                 (ok (sql/col name)))))
            (ok (sql/col name)))))))
    ((binary op l r)
     (mt (expandExpr l model schema visited)
       ((err e) (err e))
       ((ok el)
        (mt (expandExpr r model schema visited)
          ((err e) (err e))
          ((ok er) (ok (sql/binary op el er)))))))
    ((andExpr l r)
     (mt (expandExpr l model schema visited)
       ((err e) (err e))
       ((ok el)
        (mt (expandExpr r model schema visited)
          ((err e) (err e))
          ((ok er) (ok (sql/andExpr el er)))))))
    ((orExpr l r)
     (mt (expandExpr l model schema visited)
       ((err e) (err e))
       ((ok el)
        (mt (expandExpr r model schema visited)
          ((err e) (err e))
          ((ok er) (ok (sql/orExpr el er)))))))
    ((notExpr inner)
     (mt (expandExpr inner model schema visited)
       ((err e) (err e))
       ((ok ei) (ok (sql/notExpr ei)))))
    ((arith op l r)
     (mt (expandExpr l model schema visited)
       ((err e) (err e))
       ((ok el)
        (mt (expandExpr r model schema visited)
          ((err e) (err e))
          ((ok er) (ok (sql/arith op el er)))))))
    ((agg fn arg distinct)
     (mt (expandExpr arg model schema visited)
       ((err e) (err e))
       ((ok ea) (ok (sql/agg fn ea distinct)))))
    ((alias inner asName)
     (mt (expandExpr inner model schema visited)
       ((err e) (err e))
       ((ok ei) (ok (sql/alias ei asName)))))
    (_ (ok expr))))

(df collectReferencedRelations [(expr sql/SqlExpr) (model sem/EntityModel)] -> (List sem/RelationDef)
  :d "Extracts all relations referenced via qualified column expressions."
  (mt expr
    ((col name)
     (if (string-contains? name ".")
       (let [(parts (string-split name "."))
             (relName (unwrap (list-head parts)))]
         (mt (sem/findRelation model relName)
           ((some r) (list r))
           ((none) (list))))
       (list)))
    ((qualCol tbl col)
     (let [(rels (.-relations model))]
       (filter (fn [(r sem/RelationDef)] -> Bool (= (.-targetEntity r) tbl)) rels)))
    ((binary _ l r) (listConcat (collectReferencedRelations l model) (collectReferencedRelations r model)))
    ((andExpr l r) (listConcat (collectReferencedRelations l model) (collectReferencedRelations r model)))
    ((orExpr l r) (listConcat (collectReferencedRelations l model) (collectReferencedRelations r model)))
    ((notExpr inner) (collectReferencedRelations inner model))
    ((arith _ l r) (listConcat (collectReferencedRelations l model) (collectReferencedRelations r model)))
    ((agg _ arg _) (collectReferencedRelations arg model))
    ((alias inner _) (collectReferencedRelations inner model))
    (_ (list))))

(df expandFieldsList [(fields (List String))
                      (model sem/EntityModel)
                      (schema sem/SemanticSchema)] -> (Result (List sql/SqlExpr) String)
  :d "Expands a list of field names into concrete or aliased SQL expressions."
  (if (list-empty? fields)
    (ok (list))
    (mt (list-head fields)
      ((none) (ok (list)))
      ((some fName)
       (let [(restFields (unwrap (list-tail fields)))]
         (if (string-contains? fName ".")
           (let [(parts (string-split fName "."))
                 (relName (unwrap (list-head parts)))
                 (colName (unwrap (list-head (unwrap (list-tail parts)))))]
             (mt (sem/findRelation model relName)
               ((some r)
                (let [(expr (sql/alias (sql/qualCol (.-targetEntity r) colName) (str relName "_" colName)))]
                  (mt (expandFieldsList restFields model schema)
                    ((err e) (err e))
                    ((ok restExprs) (ok (cons expr restExprs))))))
               ((none) (err (str "Unknown relation in field: " fName)))))
           (mt (sem/findField model fName)
             ((some f)
              (let [(expr (sql/col (.-name f)))]
                (mt (expandFieldsList restFields model schema)
                  ((err e) (err e))
                  ((ok restExprs) (ok (cons expr restExprs))))))
             ((none)
              (mt (sem/findDerived model fName)
                ((some d)
                 (mt (expandExpr (.-expr d) model schema (list fName))
                   ((err e) (err e))
                   ((ok ex)
                    (let [(expr (sql/alias ex fName))]
                      (mt (expandFieldsList restFields model schema)
                        ((err e) (err e))
                        ((ok restExprs) (ok (cons expr restExprs))))))))
                ((none)
                 (err (str "Unknown field: " fName " on entity: " (.-name model)))))))))))))

(df expandMeasuresList [(measures (List String))
                        (model sem/EntityModel)
                        (schema sem/SemanticSchema)] -> (Result (List sql/SqlExpr) String)
  :d "Expands a list of measure names into aggregate expressions."
  (if (list-empty? measures)
    (ok (list))
    (mt (list-head measures)
      ((none) (ok (list)))
      ((some mName)
       (let [(restMeasures (unwrap (list-tail measures)))]
         (mt (sem/findMeasure model mName)
           ((some m)
            (mt (expandExpr (.-expr m) model schema (list))
              ((err e) (err e))
              ((ok ex)
               (let [(aggEx (sql/alias (sql/agg (.-aggFn m) ex (.-distinct m)) mName))]
                 (mt (expandMeasuresList restMeasures model schema)
                   ((err e) (err e))
                   ((ok restM) (ok (cons aggEx restM))))))))
           ((none)
            (err (str "Unknown measure: " mName " on entity: " (.-name model))))))))))

(df deduplicateRelations [(rels (List sem/RelationDef))] -> (List sem/RelationDef)
  :d "Deduplicates relation definitions by target entity."
  (if (list-empty? rels)
    (list)
    (mt (list-head rels)
      ((none) (list))
      ((some r)
       (let [(tailR (unwrap (list-tail rels)))
             (restDedup (deduplicateRelations tailR))
             (matches (filter (fn [(x sem/RelationDef)] -> Bool (= (.-targetEntity x) (.-targetEntity r))) restDedup))]
         (if (> (list-length matches) 0)
           restDedup
           (cons r restDedup)))))))

(df expandQuery [(schema sem/SemanticSchema) (q SemanticQuery)] -> (Result ExpandedQuery String)
  :d "Expands a SemanticQuery against a SemanticSchema with full cycle detection."
  (mt (sem/findEntity schema (.-fromEntity q))
    ((none) (err (str "Entity not found: " (.-fromEntity q))))
    ((some model)
     (mt (expandFieldsList (.-selectFields q) model schema)
       ((err e) (err e))
       ((ok projFields)
        (mt (expandMeasuresList (.-selectMeasures q) model schema)
          ((err e) (err e))
          ((ok projMeasures)
           (let [(whereRes (mt (.-whereExpr q)
                             ((none) (ok (none)))
                             ((some w)
                              (mt (expandExpr w model schema (list))
                                ((err e) (err e))
                                ((ok ew) (ok (some ew)))))))]
             (mt whereRes
               ((err e) (err e))
               ((ok expWhere)
                (let [(whereRels (mt expWhere ((none) (list)) ((some ew) (collectReferencedRelations ew model))))
                      (fieldRels (fold (fn [(acc (List sem/RelationDef)) (f sql/SqlExpr)] -> (List sem/RelationDef)
                                         (listConcat acc (collectReferencedRelations f model)))
                                       (list)
                                       projFields))
                      (allRels (deduplicateRelations (listConcat whereRels fieldRels)))
                      (groups (if (> (list-length projMeasures) 0)
                                (fold (fn [(acc (List String)) (f sql/SqlExpr)] -> (List String)
                                        (mt f
                                          ((col n) (cons n acc))
                                          ((qualCol _ c) (cons c acc))
                                          ((alias _ n) (cons n acc))
                                          (_ acc)))
                                      (list)
                                      projFields)
                                (list)))]
                  (ok (ExpandedQuery :rootEntity model
                                     :projectedFields projFields
                                     :projectedMeasures projMeasures
                                     :whereClause expWhere
                                     :requiredRelations allRels
                                     :groupBy (reverse groups)
                                     :orderBy (.-orderBy q)
                                     :orderDir (.-orderDir q)
                                     :limitCount (.-limitCount q)
                                     :offsetCount (.-offsetCount q))))))))))))))
