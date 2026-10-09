(module asl-port/parity
  :x [buildParitySpec formatParitySpec CallSite FnParity ParitySpec]
  :i [(asl-json/json :a json) (asl-port/astUtil :a u)])

(schema CallSite
  (:f caller String)
  (:f line Int64)
  (:f args (List String)))

(schema FnParity
  (:f fnName String)
  (:f callSites (List CallSite)))

(schema ParitySpec
  (:f file String)
  (:f functions (List FnParity)))

fn quoteStr s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\"")

fn formatArgNode node: json/Json -> String
  (let [(t (u/getType node))]
    (cond
      ((= t "Constant")
        (mt (json/jsonGet node "value")
          ((some v)
            (mt v
              ((json/jstr s) (quoteStr s))
              ((json/jint i) (stringFromInt64 i))
              ((json/jbool b) (if b "true" "false"))
              ((json/jnull) "None")
              (_ "")))
          ((none) "")))
      ((= t "Name")
        (u/getStringProp node "id"))
      ((= t "List")
        (let [(elts (map formatArgNode (u/getListProp node "elts")))]
          (str "[" (stringJoin elts ", ") "]")))
      ((= t "UnaryOp")
        (let [(opType (mt (u/getObjProp node "op") ((some o) (u/getType o)) ((none) "")))
              (operandOpt (u/getObjProp node "operand"))]
          (if (= opType "USub")
            (mt operandOpt
              ((some op) (str "-" (formatArgNode op)))
              ((none) ""))
            "")))
      (else "")))

fn collectCallsFromNode node: json/Json targetName: String callerName: String acc: (List CallSite) -> (List CallSite)
  (let [(t (u/getType node))]
    (cond
      ((= t "Call")
        (let [(funcOpt (u/getObjProp node "func"))
              (fnId (mt funcOpt
                      ((some f) (if (u/isType? f "Name") (u/getStringProp f "id") ""))
                      ((none) "")))
              (args (map formatArgNode (u/getListProp node "args")))
              (line (u/getLineno node))
              (acc1 (if (= fnId targetName)
                      (listAppend acc (list (CallSite :caller callerName :line line :args args)))
                      acc))
              (childArgs (u/getListProp node "args"))
              (keywords (u/getListProp node "keywords"))
              (kwValues (map (fn [(kw json/Json)] -> json/Json (optionOr (u/getObjProp kw "value") (json/jnull))) keywords))
              (acc2 (fold (fn [(a (List CallSite)) (c json/Json)] -> (List CallSite)
                            (collectCallsFromNode c targetName callerName a))
                          acc1 childArgs))
              (acc3 (fold (fn [(a (List CallSite)) (c json/Json)] -> (List CallSite)
                            (collectCallsFromNode c targetName callerName a))
                          acc2 kwValues))]
          (mt funcOpt
            ((some f) (collectCallsFromNode f targetName callerName acc3))
            ((none) acc3))))
      (else
        (mt node
          ((json/jobj pairs)
            (fold (fn [(a (List CallSite)) (p (Pair String json/Json))] -> (List CallSite)
                    (collectCallsFromNode (pairSecond p) targetName callerName a))
                  acc pairs))
          ((json/jarr xs)
            (fold (fn [(a (List CallSite)) (x json/Json)] -> (List CallSite)
                    (collectCallsFromNode x targetName callerName a))
                  acc xs))
          (_ acc)))))

fn collectFnCallSites targetName: String allFnNodes: (List json/Json) acc: (List CallSite) -> (List CallSite)
  (mt (listHead allFnNodes)
    ((some f)
      (let [(callerName (u/getStringProp f "name"))
            (body (u/getListProp f "body"))
            (sites (fold (fn [(a (List CallSite)) (stmt json/Json)] -> (List CallSite)
                           (collectCallsFromNode stmt targetName callerName a))
                         acc body))
            (rest (optionOr (listTail allFnNodes) (list)))]
        (collectFnCallSites targetName rest sites)))
    ((none) acc))

fn buildFnParity targetName: String allFnNodes: (List json/Json) -> FnParity
  (let [(sites (collectFnCallSites targetName allFnNodes (list)))]
    (FnParity :fnName targetName :callSites sites))

fn buildParitySpec file: String selectedFns: (List String) moduleAst: json/Json -> ParitySpec
  (let [(body (u/getListProp moduleAst "body"))
        (allFns (filter (fn [(s json/Json)] -> Bool (u/isType? s "FunctionDef")) body))
        (allFnNames (map (fn [(f json/Json)] -> String (u/getStringProp f "name")) allFns))
        (targets (if (listEmpty? selectedFns) allFnNames selectedFns))
        (fnParities (map (fn [(name String)] -> FnParity (buildFnParity name allFns)) targets))]
    (ParitySpec :file file :functions fnParities))

fn formatCallSite cs: CallSite -> String
  (let [(qArgs (map quoteStr cs.args))]
    (str "        (:callSite :caller " (quoteStr cs.caller)
         " :line " (stringFromInt64 cs.line)
         " :args [" (stringJoin qArgs " ") "])"))

fn formatFnParity fp: FnParity -> String
  (let [(siteStrs (map formatCallSite fp.callSites))]
    (if (listEmpty? siteStrs)
      (str "    (:fn :name " (quoteStr fp.fnName) " :callSites [])")
      (str "    (:fn :name " (quoteStr fp.fnName) " :callSites [
"
           (stringJoin siteStrs "
") "
    ])")))

fn formatParitySpec spec: ParitySpec -> String
  (let [(fnStrs (map formatFnParity spec.functions))]
    (str "(:paritySpec
"
         "  :file " (quoteStr spec.file) "
"
         "  :functions [
"
         (stringJoin fnStrs "
") "
"
         "  ]
)"))
