(module asl-sql/semantic/schema :x [FieldDef DerivedField MeasureDef RelationDef EntityModel SemanticSchema makeFieldDef makeDerivedField makeMeasureDef makeRelationDef makeEntityModel makeSemanticSchema findEntity findField findDerived findMeasure findRelation] :i [(asl-sql/core :a sql)])

(schema FieldDef (:f name String) (:f dataType String))

(schema DerivedField (:f name String) (:f expr sql/SqlExpr))

(schema MeasureDef (:f name String) (:f aggFn String) (:f expr sql/SqlExpr) (:f distinct Bool))

(schema RelationDef (:f name String) (:f targetEntity String) (:f card String) (:f sourceKey String) (:f targetKey String))

(schema EntityModel (:f name String) (:f primaryKey String) (:f table String) (:f fields (List FieldDef)) (:f derived (List DerivedField)) (:f measures (List MeasureDef)) (:f relations (List RelationDef)))

(schema SemanticSchema (:f entities (List EntityModel)))

fn makeFieldDef name: String dataType: String -> FieldDef
  (FieldDef :name name :dataType dataType)

fn makeDerivedField name: String expr: sql/SqlExpr -> DerivedField
  (DerivedField :name name :expr expr)

fn makeMeasureDef name: String aggFn: String expr: sql/SqlExpr distinct: Bool -> MeasureDef
  (MeasureDef :name name :aggFn aggFn :expr expr :distinct distinct)

fn makeRelationDef name: String targetEntity: String card: String sourceKey: String targetKey: String -> RelationDef
  (RelationDef :name name :targetEntity targetEntity :card card :sourceKey sourceKey :targetKey targetKey)

fn makeEntityModel name: String primaryKey: String table: String fields: (List FieldDef) derived: (List DerivedField) measures: (List MeasureDef) relations: (List RelationDef) -> EntityModel
  (EntityModel :name name :primaryKey primaryKey :table table :fields fields :derived derived :measures measures :relations relations)

fn makeSemanticSchema entities: (List EntityModel) -> SemanticSchema
  (SemanticSchema :entities entities)

fn findEntity schema: SemanticSchema entityName: String -> (Option EntityModel)
  (let [(ents (filter (fn [(e EntityModel)] -> Bool (= e.name entityName)) schema.entities))] (if (listEmpty? ents) (none) (listHead ents)))

fn findField model: EntityModel name: String -> (Option FieldDef)
  (let [(matches (filter (fn [(f FieldDef)] -> Bool (= f.name name)) model.fields))] (if (listEmpty? matches) (none) (listHead matches)))

fn findDerived model: EntityModel name: String -> (Option DerivedField)
  (let [(matches (filter (fn [(d DerivedField)] -> Bool (= d.name name)) model.derived))] (if (listEmpty? matches) (none) (listHead matches)))

fn findMeasure model: EntityModel name: String -> (Option MeasureDef)
  (let [(matches (filter (fn [(m MeasureDef)] -> Bool (= m.name name)) model.measures))] (if (listEmpty? matches) (none) (listHead matches)))

fn findRelation model: EntityModel name: String -> (Option RelationDef)
  (let [(matches (filter (fn [(r RelationDef)] -> Bool (= r.name name)) model.relations))] (if (listEmpty? matches) (none) (listHead matches)))
