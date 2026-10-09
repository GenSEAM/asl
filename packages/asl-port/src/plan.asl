(module asl-port/plan
  :x [buildPortPlan formatPortPlan PortPlan FnPlan ClassPlan ImportPlan]
  :i [(asl-json/json :a json) (asl-port/astUtil :a u)])

(schema ImportPlan
  (:f module String)
  (:f names (List String)))

(schema FnPlan
  (:f name String)
  (:f startLine Int64)
  (:f endLine Int64)
  (:f callers (List String))
  (:f globals (List String)))

(schema ClassPlan
  (:f name String)
  (:f startLine Int64)
  (:f endLine Int64)
  (:f methods (List String)))

(schema PortPlan
  (:f file String)
  (:f imports (List ImportPlan))
  (:f functions (List FnPlan))
  (:f classes (List ClassPlan)))

fn collectImportNames aliases: (List json/Json) -> (List String)
  (map (fn [(a json/Json)] -> String (u/getStringProp a "name")) aliases)

fn parseImportNode item: json/Json -> (Option ImportPlan)
  (cond
    ((u/isType? item "Import")
      (some (ImportPlan :module "" :names (collectImportNames (u/getListProp item "names")))))
    ((u/isType? item "ImportFrom")
      (some (ImportPlan :module (u/getStringProp item "module") :names (collectImportNames (u/getListProp item "names")))))
    (else (none)))

fn collectImports stmts: (List json/Json) acc: (List ImportPlan) -> (List ImportPlan)
  (mt (listHead stmts)
    ((some s)
      (let [(rest (optionOr (listTail stmts) (list)))
            (mPlan (parseImportNode s))]
        (mt mPlan
          ((some ip) (collectImports rest (listAppend acc (list ip))))
          ((none) (collectImports rest acc)))))
    ((none) acc))

fn collectClassMethods body: (List json/Json) acc: (List String) -> (List String)
  (mt (listHead body)
    ((some s)
      (let [(rest (optionOr (listTail body) (list)))]
        (if (u/isType? s "FunctionDef")
          (collectClassMethods rest (listAppend acc (list (u/getStringProp s "name"))))
          (collectClassMethods rest acc))))
    ((none) acc))

fn collectClasses stmts: (List json/Json) acc: (List ClassPlan) -> (List ClassPlan)
  (mt (listHead stmts)
    ((some s)
      (let [(rest (optionOr (listTail stmts) (list)))]
        (if (u/isType? s "ClassDef")
          (let [(cp (ClassPlan :name (u/getStringProp s "name")
                               :startLine (u/getLineno s)
                               :endLine (u/getEndLineno s)
                               :methods (collectClassMethods (u/getListProp s "body") (list))))]
            (collectClasses rest (listAppend acc (list cp))))
          (collectClasses rest acc))))
    ((none) acc))

fn collectFnDefs stmts: (List json/Json) acc: (List json/Json) -> (List json/Json)
  (mt (listHead stmts)
    ((some s)
      (let [(rest (optionOr (listTail stmts) (list)))]
        (if (u/isType? s "FunctionDef")
          (collectFnDefs rest (listAppend acc (list s)))
          (collectFnDefs rest acc))))
    ((none) acc))

fn collectCalls acc: (List String) node: json/Json -> (List String)
  (let [(t (u/getType node))]
    (cond
      ((= t "Call")
        (let [(funcOpt (u/getObjProp node "func"))
              (calledName (mt funcOpt
                            ((some f) (if (u/isType? f "Name") (u/getStringProp f "id") ""))
                            ((none) "")))
              (args (u/getListProp node "args"))
              (acc1 (if (and (not (stringEmpty? calledName)) (not (listContains? acc calledName)))
                      (listAppend acc (list calledName))
                      acc))
              (acc2 (fold collectCalls acc1 args))
              (keywords (u/getListProp node "keywords"))
              (kwValues (map (fn [(kw json/Json)] -> json/Json (optionOr (u/getObjProp kw "value") (json/jnull))) keywords))
              (acc3 (fold collectCalls acc2 kwValues))]
          (mt funcOpt
            ((some f) (collectCalls acc3 f))
            ((none) acc3))))
      (else
        (let [(kvs (mt node ((json/jobj pairs) pairs) (_ (list))))]
          (fold (fn [(a (List String)) (p (Pair String json/Json))] -> (List String)
                  (let [(v (pairSecond p))]
                    (mt v
                      ((json/jarr xs) (fold collectCalls a xs))
                      ((json/jobj _) (collectCalls a v))
                      (_ a))))
                acc kvs)))))

fn collectAssignedNames acc: (List String) node: json/Json -> (List String)
  (let [(t (u/getType node))]
    (cond
      ((= t "Assign")
        (let [(targets (u/getListProp node "targets"))]
          (fold (fn [(a (List String)) (tgt json/Json)] -> (List String)
                  (if (u/isType? tgt "Name")
                    (let [(id (u/getStringProp tgt "id"))]
                      (if (listContains? a id) a (listAppend a (list id))))
                    a))
                acc targets)))
      ((= t "For")
        (let [(tgt (u/getObjProp node "target"))
              (acc1 (mt tgt
                      ((some tn) (if (u/isType? tn "Name")
                                   (let [(id (u/getStringProp tn "id"))]
                                     (if (listContains? acc id) acc (listAppend acc (list id))))
                                   acc))
                      ((none) acc)))
              (body (u/getListProp node "body"))]
          (fold collectAssignedNames acc1 body)))
      ((or (= t "FunctionDef") (= t "ClassDef"))
        acc)
      (else
        (let [(kvs (mt node ((json/jobj pairs) pairs) (_ (list))))]
          (fold (fn [(a (List String)) (p (Pair String json/Json))] -> (List String)
                  (let [(v (pairSecond p))]
                    (mt v
                      ((json/jarr xs) (fold collectAssignedNames a xs))
                      ((json/jobj _) (collectAssignedNames a v))
                      (_ a))))
                acc kvs)))))

fn collectLoadedNames acc: (List String) node: json/Json -> (List String)
  (let [(t (u/getType node))]
    (cond
      ((= t "Name")
        (let [(id (u/getStringProp node "id"))]
          (if (listContains? acc id) acc (listAppend acc (list id)))))
      ((or (= t "FunctionDef") (= t "ClassDef"))
        acc)
      (else
        (let [(kvs (mt node ((json/jobj pairs) pairs) (_ (list))))]
          (fold (fn [(a (List String)) (p (Pair String json/Json))] -> (List String)
                  (let [(v (pairSecond p))]
                    (mt v
                      ((json/jarr xs) (fold collectLoadedNames a xs))
                      ((json/jobj _) (collectLoadedNames a v))
                      (_ a))))
                acc kvs)))))

fn isPyBuiltin? name: String -> Bool
  (listContains? (list "len" "range" "print" "int" "str" "float" "bool" "dict" "list" "set"
                       "min" "max" "sum" "abs" "map" "filter" "zip" "enumerate" "all" "any"
                       "True" "False" "None" "Exception" "ZeroDivisionError" "ValueError")
                 name)

fn getFnParams fnNode: json/Json -> (List String)
  (mt (u/getObjProp fnNode "args")
    ((some a) (map (fn [(arg json/Json)] -> String (u/getStringProp arg "arg")) (u/getListProp a "args")))
    ((none) (list)))

fn collectGlobalsRead fnNode: json/Json modGlobals: (List String) -> (List String)
  (let [(params (getFnParams fnNode))
        (body (u/getListProp fnNode "body"))
        (locals (fold collectAssignedNames (list) body))
        (loaded (fold collectLoadedNames (list) body))
        (nonLocals (filter (fn [(id String)] -> Bool
                             (and (not (listContains? params id))
                                  (and (not (listContains? locals id))
                                       (not (isPyBuiltin? id)))))
                           loaded))]
    (filter (fn [(id String)] -> Bool (listContains? modGlobals id)) nonLocals))

fn findCallersOf targetName: String allFns: (List json/Json) -> (List String)
  (let [(matching (filter (fn [(fnNode json/Json)] -> Bool
                            (let [(calls (collectCalls (list) fnNode))]
                              (listContains? calls targetName)))
                          allFns))]
    (listSort (map (fn [(fnNode json/Json)] -> String (u/getStringProp fnNode "name")) matching)))

fn buildFnPlan fnNode: json/Json allFns: (List json/Json) modGlobals: (List String) -> FnPlan
  (let [(name (u/getStringProp fnNode "name"))
        (startLine (u/getLineno fnNode))
        (endLine (u/getEndLineno fnNode))
        (callers (findCallersOf name allFns))
        (globals (collectGlobalsRead fnNode modGlobals))]
    (FnPlan :name name :startLine startLine :endLine endLine :callers callers :globals globals))

fn buildPortPlan file: String moduleAst: json/Json -> PortPlan
  (let [(body (u/getListProp moduleAst "body"))
        (imports (collectImports body (list)))
        (classes (collectClasses body (list)))
        (fnDefs (collectFnDefs body (list)))
        (topAssigned (fold collectAssignedNames (list) body))
        (topFnNames (map (fn [(f json/Json)] -> String (u/getStringProp f "name")) fnDefs))
        (modGlobals (listAppend topAssigned topFnNames))
        (fnPlans (map (fn [(f json/Json)] -> FnPlan (buildFnPlan f fnDefs modGlobals)) fnDefs))]
    (PortPlan :file file :imports imports :functions fnPlans :classes classes))

fn quoteAsnStr s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn formatImportPlan ip: ImportPlan -> String
  (let [(qNames (map quoteAsnStr ip.names))]
    (if (stringEmpty? ip.module)
      (str "    (:import :names [" (stringJoin qNames " ") "])")
      (str "    (:import :module " (quoteAsnStr ip.module) " :names [" (stringJoin qNames " ") "])")))

fn formatFnPlan fp: FnPlan -> String
  (let [(qCallers (map quoteAsnStr fp.callers))
        (qGlobals (map quoteAsnStr fp.globals))]
    (str "    (:fn :name " (quoteAsnStr fp.name)
         " :startLine " (stringFromInt64 fp.startLine)
         " :endLine " (stringFromInt64 fp.endLine)
         " :callers [" (stringJoin qCallers " ") "]"
         " :globals [" (stringJoin qGlobals " ") "])"))

fn formatClassPlan cp: ClassPlan -> String
  (let [(qMethods (map quoteAsnStr cp.methods))]
    (str "    (:class :name " (quoteAsnStr cp.name)
         " :startLine " (stringFromInt64 cp.startLine)
         " :endLine " (stringFromInt64 cp.endLine)
         " :methods [" (stringJoin qMethods " ") "])"))

fn formatPortPlan plan: PortPlan -> String
  (let [(impStrs (map formatImportPlan plan.imports))
        (fnStrs (map formatFnPlan plan.functions))
        (clsStrs (map formatClassPlan plan.classes))]
    (str "(:portPlan\n"
         "  :file " (quoteAsnStr plan.file) "\n"
         "  :imports [\n" (stringJoin impStrs "\n") (if (listEmpty? impStrs) "  ]\n" "\n  ]\n")
         "  :functions [\n" (stringJoin fnStrs "\n") (if (listEmpty? fnStrs) "  ]\n" "\n  ]\n")
         "  :classes [\n" (stringJoin clsStrs "\n") (if (listEmpty? clsStrs) "  ]\n)" "\n  ]\n)")))
