(module asl-sql/semantic/schema
  :d "Semantic Layer Schema Definition and Entity Model Registry."
  :x [FieldDef DerivedField MeasureDef RelationDef EntityModel SemanticSchema
      makeFieldDef makeDerivedField makeMeasureDef makeRelationDef makeEntityModel makeSemanticSchema
      findEntity findField findDerived findMeasure findRelation]
  :i [(asl-sql/core :a sql)])

(dfs FieldDef
  (:f name String "Physical column name")
  (:f dataType String "Data type specification"))

(dfs DerivedField
  (:f name String "Virtual derived field identifier")
  (:f expr sql/SqlExpr "Underlying SQL expression to inline"))

(dfs MeasureDef
  (:f name String "Measure metric identifier")
  (:f aggFn String "Aggregate function name (sum, count, avg, min, max)")
  (:f expr sql/SqlExpr "Aggregated expression target")
  (:f distinct Bool "Whether aggregation enforces DISTINCT"))

(dfs RelationDef
  (:f name String "Relation alias")
  (:f targetEntity String "Target entity model name")
  (:f card String "Cardinality (toOne or toMany)")
  (:f sourceKey String "Foreign key on source table")
  (:f targetKey String "Primary key on target table"))

(dfs EntityModel
  (:f name String "Entity model identifier")
  (:f primaryKey String "Primary key column name")
  (:f table String "Physical backing database table")
  (:f fields (List FieldDef) "Physical column definitions")
  (:f derived (List DerivedField) "Virtual derived field definitions")
  (:f measures (List MeasureDef) "Business metrics and aggregate definitions")
  (:f relations (List RelationDef) "Entity association and join definitions"))

(dfs SemanticSchema
  (:f entities (List EntityModel) "Registered entity models"))

(df makeFieldDef [(name String) (dataType String)] -> FieldDef
  :d "Constructs a FieldDef record."
  (FieldDef :name name :dataType dataType))

(df makeDerivedField [(name String) (expr sql/SqlExpr)] -> DerivedField
  :d "Constructs a DerivedField record."
  (DerivedField :name name :expr expr))

(df makeMeasureDef [(name String) (aggFn String) (expr sql/SqlExpr) (distinct Bool)] -> MeasureDef
  :d "Constructs a MeasureDef record."
  (MeasureDef :name name :aggFn aggFn :expr expr :distinct distinct))

(df makeRelationDef [(name String) (targetEntity String) (card String) (sourceKey String) (targetKey String)] -> RelationDef
  :d "Constructs a RelationDef record."
  (RelationDef :name name :targetEntity targetEntity :card card :sourceKey sourceKey :targetKey targetKey))

(df makeEntityModel [(name String)
                     (primaryKey String)
                     (table String)
                     (fields (List FieldDef))
                     (derived (List DerivedField))
                     (measures (List MeasureDef))
                     (relations (List RelationDef))] -> EntityModel
  :d "Constructs an EntityModel record."
  (EntityModel :name name
               :primaryKey primaryKey
               :table table
               :fields fields
               :derived derived
               :measures measures
               :relations relations))

(df makeSemanticSchema [(entities (List EntityModel))] -> SemanticSchema
  :d "Constructs a SemanticSchema registry."
  (SemanticSchema :entities entities))

(df findEntity [(schema SemanticSchema) (entityName String)] -> (Option EntityModel)
  :d "Finds an entity model in the schema by name."
  (let [(ents (filter (fn [(e EntityModel)] -> Bool (= (.-name e) entityName)) (.-entities schema)))]
    (if (list-empty? ents) (none) (list-head ents))))

(df findField [(model EntityModel) (name String)] -> (Option FieldDef)
  :d "Finds a physical field definition in the entity model."
  (let [(matches (filter (fn [(f FieldDef)] -> Bool (= (.-name f) name)) (.-fields model)))]
    (if (list-empty? matches) (none) (list-head matches))))

(df findDerived [(model EntityModel) (name String)] -> (Option DerivedField)
  :d "Finds a virtual derived field definition in the entity model."
  (let [(matches (filter (fn [(d DerivedField)] -> Bool (= (.-name d) name)) (.-derived model)))]
    (if (list-empty? matches) (none) (list-head matches))))

(df findMeasure [(model EntityModel) (name String)] -> (Option MeasureDef)
  :d "Finds an aggregate measure definition in the entity model."
  (let [(matches (filter (fn [(m MeasureDef)] -> Bool (= (.-name m) name)) (.-measures model)))]
    (if (list-empty? matches) (none) (list-head matches))))

(df findRelation [(model EntityModel) (name String)] -> (Option RelationDef)
  :d "Finds a relation definition in the entity model."
  (let [(matches (filter (fn [(r RelationDef)] -> Bool (= (.-name r) name)) (.-relations model)))]
    (if (list-empty? matches) (none) (list-head matches))))
