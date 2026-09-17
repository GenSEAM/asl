(module asl-hypergraph/index
  :d "Pure ASL Codebase Hypergraph index extraction, AST analysis, and lazy index serialization under ADR D94."
  :x [extractSymbolsFromSexpr
      extractNodesAndEdgesFromModule
      buildHypergraphFromModules
      serializeHyperIndex
      deserializeHyperIndex
      loadOrBuildHyperIndex]
  :i [(asl-hypergraph/model :a model)
      (asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)])

(dfs ReaderFrame
  :d "Frame tracking open delimiter and accumulated child S-expressions"
  (:field items (List rd/SExpr) "Completed children, kept reversed")
  (:field paren Bool "True for a paren list, false for bracket vector"))

(dfs ReaderState
  :d "Reader scan state tracking open frame stack and output expressions"
  (:field stack (List ReaderFrame) "Open frames, innermost first")
  (:field out (List rd/SExpr) "Completed top-level forms, kept reversed")
  (:field fail (Option Str) "The first error message, once set stops reading"))

(df pushReaderFrame [(st ReaderState) (paren Bool)] -> ReaderState
  :d "Pushes a new frame onto reader stack."
  (ReaderState :stack (list-cons (ReaderFrame :items (list) :paren paren) (.-stack st))
               :out (.-out st)
               :fail (.-fail st)))

(df emitReaderNode [(st ReaderState) (node rd/SExpr)] -> ReaderState
  :d "Emits completed node to innermost frame or top-level forms list."
  (mt (list-head (.-stack st))
    ((some f)
     (ReaderState :stack (list-cons (ReaderFrame :items (list-cons node (.-items f)) :paren (.-paren f))
                                    (option-or (list-tail (.-stack st)) (list)))
                  :out (.-out st)
                  :fail (none)))
    ((none)
     (ReaderState :stack (list)
                  :out (list-cons node (.-out st))
                  :fail (none)))))

(df finishReaderFrame [(st ReaderState) (f ReaderFrame)] -> ReaderState
  :d "Finishes current frame and emits compound node."
  (let [(items (list-reverse (.-items f)))
        (node (if (.-paren f)
                (rd/makeList items)
                (rd/makeVect items)))
        (popped (ReaderState :stack (option-or (list-tail (.-stack st)) (list))
                             :out (.-out st)
                             :fail (none)))]
    (emitReaderNode popped node)))

(df closeReaderFrame [(st ReaderState) (paren Bool)] -> ReaderState
  :d "Closes innermost matching frame."
  (mt (list-head (.-stack st))
    ((some f)
     (if (= (.-paren f) paren)
       (finishReaderFrame st f)
       (ReaderState :stack (.-stack st) :out (.-out st) :fail (some "mismatched delimiter"))))
    ((none)
     (ReaderState :stack (list) :out (.-out st) :fail (some "unexpected closing delimiter")))))

(df finishReader [(st ReaderState)] -> ReaderState
  :d "Verifies clean frame closure at EOF."
  (mt (list-head (.-stack st))
    ((some _)
     (ReaderState :stack (.-stack st) :out (.-out st) :fail (some "unclosed delimiter")))
    ((none) st)))

(df readTokenStep [(st ReaderState) (t lx/Token)] -> ReaderState
  :d "Processes single token."
  (mt (.-kind t)
    ((lx/tokLparen)   (pushReaderFrame st true))
    ((lx/tokLbracket) (pushReaderFrame st false))
    ((lx/tokRparen)   (closeReaderFrame st true))
    ((lx/tokRbracket) (closeReaderFrame st false))
    ((lx/tokEof)      (finishReader st))
    ((lx/tokError m)  (ReaderState :stack (.-stack st) :out (.-out st) :fail (some m)))
    (_ (emitReaderNode st (rd/makeAtom (.-rawText t))))))

(df parseSexprForms [(src Str)] -> (Result (List rd/SExpr) Str)
  :d "Parses ASL source into list of top-level S-expressions."
  (let [(toks (lx/tokenize src))
        (st (fold (fn [(s ReaderState) (t lx/Token)] -> ReaderState
                    (mt (.-fail s)
                      ((some _) s)
                      ((none) (readTokenStep s t))))
                  (ReaderState :stack (list) :out (list) :fail (none))
                  toks))]
    (mt (.-fail st)
      ((some e) (err e))
      ((none) (ok (list-reverse (.-out st)))))))

(df isSpecialForm? [(sym Str)] -> Bool
  :d "Determines if an atom is a language special form rather than a user function call."
  (let [(forms (list "let" "if" "mt" "do" "cond" "fn" "module" "df" "dfs" "dfe" "assert" "refute" "str" "list" "pair" "and" "or" "not" "=" "!=" "+" "-" "*" "/" ".-"))]
    (or (string-starts-with? sym ":")
        (fold (fn [(acc Bool) (f Str)] -> Bool (or acc (= sym f))) false forms))))

(df extractSymbolsFromSexpr [(form rd/SExpr)] -> (List Str)
  :d "Extracts all potential callee function symbols invoked in an S-expression tree."
  (mt form
    ((rd/sexprList items)
     (mt (list-head items)
       ((some headNode)
        (let [(restNodes (option-or (list-tail items) (list)))
              (subSymbols (fold (fn [(acc (List Str)) (child rd/SExpr)] -> (List Str)
                                  (list-append acc (extractSymbolsFromSexpr child)))
                                (list)
                                restNodes))]
          (if (rd/isAtom? headNode)
              (let [(headSym (rd/sexprHead headNode))]
                (if (or (isSpecialForm? headSym) (string-empty? headSym))
                    subSymbols
                    (list-cons headSym subSymbols)))
              (list-append (extractSymbolsFromSexpr headNode) subSymbols))))
       ((none) (list))))
    (_ (list))))

(df unquoteText [(s Str)] -> Str
  :d "Strips enclosing quotes from a string literal."
  (let [(len (string-length s))]
    (if (and (>= len 2)
             (string-starts-with? s "\"")
             (string-ends-with? s "\""))
        (option-or (string-slice s 1 (- len 1)) "")
        s)))

(df findDocstring [(items (List rd/SExpr))] -> Str
  :d "Finds :d docstring value in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) ":d"))
           (mt (list-head rest)
             ((some valNode) (unquoteText (rd/sexprHead valNode)))
             ((none) ""))
           (findDocstring rest))))
    ((none) "")))

(df extractNodesAndEdgesFromModule [(modName Str) (sourceText Str)] -> (Pair (List model/HyperNode) (List model/HyperEdge))
  :d "Extracts declaration nodes and relationship edges from a single ASL module source."
  (mt (parseSexprForms sourceText)
    ((err _) (pair (list) (list)))
    ((ok forms)
     (fold (fn [(acc (Pair (List model/HyperNode) (List model/HyperEdge))) (form rd/SExpr)] -> (Pair (List model/HyperNode) (List model/HyperEdge))
             (let [(nodes (pair-first acc))
                   (edges (pair-second acc))]
               (mt form
                 ((rd/sexprList items)
                  (let [(head (mt (list-head items) ((some h) (rd/sexprHead h)) ((none) "")))]
                    (cond
                      ((or (= head "df") (= head "df!"))
                       (let [(tailItems (option-or (list-tail items) (list)))
                             (isBang (= head "df!"))
                             (effectiveTail (if (and (not isBang)
                                                     (mt (list-head tailItems) ((some h) (= (rd/sexprHead h) "!")) ((none) false)))
                                                (option-or (list-tail tailItems) (list))
                                                tailItems))
                             (fnName (mt (list-head effectiveTail) ((some n) (rd/sexprHead n)) ((none) "anonymous")))
                             (fnDoc (findDocstring items))
                             (fullId (str modName ":" fnName))
                             (kind (if (or (string-starts-with? fnName "test")
                                           (string-contains? modName "/tests/")
                                           (string-contains? modName "tests/"))
                                       "test"
                                       "function"))
                             (fnNode (model/makeHyperNode fullId kind modName fnName fnDoc))
                             (callees (extractSymbolsFromSexpr form))
                             (callEdges (fold (fn [(eAcc (List model/HyperEdge)) (callee Str)] -> (List model/HyperEdge)
                                                (let [(isTestKind (= kind "test"))
                                                      (rel (if isTestKind "tests" "calls"))
                                                      (edge (model/makeHyperEdge fullId rel callee "body"))]
                                                  (list-append eAcc (list edge))))
                                              (list)
                                              callees))]
                         (pair (list-append nodes (list fnNode))
                               (list-append edges callEdges))))
                      ((or (= head "dfs") (= head "defschema"))
                       (let [(tailItems (option-or (list-tail items) (list)))
                             (structName (mt (list-head tailItems) ((some n) (rd/sexprHead n)) ((none) "anonymous")))
                             (structDoc (findDocstring items))
                             (fullId (str modName ":" structName))
                             (structNode (model/makeHyperNode fullId "struct" modName structName structDoc))]
                         (pair (list-append nodes (list structNode)) edges)))
                      ((or (= head "dfe") (= head "defenum"))
                       (let [(tailItems (option-or (list-tail items) (list)))
                             (enumName (mt (list-head tailItems) ((some n) (rd/sexprHead n)) ((none) "anonymous")))
                             (enumDoc (findDocstring items))
                             (fullId (str modName ":" enumName))
                             (enumNode (model/makeHyperNode fullId "type" modName enumName enumDoc))]
                         (pair (list-append nodes (list enumNode)) edges)))
                      (:else acc))))
                 (_ acc))))
           (pair (list) (list))
           forms))))

(df buildHypergraphFromModules [(modules (List (Pair Str Str)))] -> model/HyperIndex
  :d "Constructs unified HyperIndex from list of module name and source pairs."
  (let [(combined (fold (fn [(acc (Pair (List model/HyperNode) (List model/HyperEdge))) (modEntry (Pair Str Str))] -> (Pair (List model/HyperNode) (List model/HyperEdge))
                          (let [(modName (pair-first modEntry))
                                (srcText (pair-second modEntry))
                                (modRes (extractNodesAndEdgesFromModule modName srcText))]
                            (pair (list-append (pair-first acc) (pair-first modRes))
                                  (list-append (pair-second acc) (pair-second modRes)))))
                        (pair (list) (list))
                        modules))]
    (model/makeHyperIndex 1 (pair-first combined) (pair-second combined) 1789720000000)))

(df renderHyperNode [(n model/HyperNode)] -> Str
  :d "Renders a single HyperNode to ASN format."
  (str "    (:node :id \"" (.-id n) "\" :kind \"" (.-kind n) "\" :module \"" (.-module n) "\" :symbol \"" (.-symbol n) "\" :doc \"" (.-doc n) "\")"))

(df renderHyperEdge [(e model/HyperEdge)] -> Str
  :d "Renders a single HyperEdge to ASN format."
  (str "    (:edge :source \"" (.-source e) "\" :relation \"" (.-relation e) "\" :target \"" (.-target e) "\" :anchor \"" (.-anchor e) "\")"))

(df serializeHyperIndex [(idx model/HyperIndex)] -> Str
  :d "Serializes HyperIndex to canonical .asl/mem/hyper.idx ASN text."
  (let [(nodeLines (map (fn [(n model/HyperNode)] -> Str (renderHyperNode n)) (.-nodes idx)))
        (edgeLines (map (fn [(e model/HyperEdge)] -> Str (renderHyperEdge e)) (.-edges idx)))]
    (str "(:hyperIndex\n"
         "  :version " (string-from-int64 (.-version idx)) "\n"
         "  :timestamp " (string-from-int64 (.-timestamp idx)) "\n"
         "  :nodes [\n"
         (string-join nodeLines "\n")
         "\n  ]\n"
         "  :edges [\n"
         (string-join edgeLines "\n")
         "\n  ])\n")))

(df findKvAtom [(items (List rd/SExpr)) (key Str)] -> Str
  :d "Finds atom value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (mt (list-head rest)
             ((some valNode) (unquoteText (rd/sexprHead valNode)))
             ((none) ""))
           (findKvAtom rest key))))
    ((none) "")))

(df findKvNode [(items (List rd/SExpr)) (key Str)] -> (Option rd/SExpr)
  :d "Finds node value following keyword key in SExpr list."
  (mt (list-head items)
    ((some it)
     (let [(rest (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? it) (= (rd/sexprHead it) key))
           (list-head rest)
           (findKvNode rest key))))
    ((none) (none))))

(df parseHyperNode [(form rd/SExpr)] -> (Option model/HyperNode)
  :d "Parses single HyperNode from SExpr form."
  (mt form
    ((rd/sexprList items)
     (let [(head (mt (list-head items) ((some h) (rd/sexprHead h)) ((none) "")))]
       (if (and (!= head ":node") (!= head "node"))
           (none)
           (let [(id (findKvAtom items ":id"))
                 (kind (findKvAtom items ":kind"))
                 (module (findKvAtom items ":module"))
                 (symbol (findKvAtom items ":symbol"))
                 (doc (findKvAtom items ":doc"))]
             (if (string-empty? id)
                 (none)
                 (some (model/makeHyperNode id kind module symbol doc)))))))
    (_ (none))))

(df parseHyperEdge [(form rd/SExpr)] -> (Option model/HyperEdge)
  :d "Parses single HyperEdge from SExpr form."
  (mt form
    ((rd/sexprList items)
     (let [(head (mt (list-head items) ((some h) (rd/sexprHead h)) ((none) "")))]
       (if (and (!= head ":edge") (!= head "edge"))
           (none)
           (let [(source (findKvAtom items ":source"))
                 (relation (findKvAtom items ":relation"))
                 (target (findKvAtom items ":target"))
                 (anchor (findKvAtom items ":anchor"))]
             (if (or (string-empty? source) (string-empty? target))
                 (none)
                 (some (model/makeHyperEdge source relation target anchor)))))))
    (_ (none))))

(df deserializeHyperIndex [(text Str)] -> (Result model/HyperIndex Str)
  :d "Parses HyperIndex from serialized ASN text."
  (if (string-empty? (string-trim text))
      (ok (model/makeHyperIndex 1 (list) (list) 0))
      (mt (parseSexprForms text)
        ((err msg) (err (str "Failed to parse hyper index ASN: " msg)))
        ((ok forms)
         (mt (list-head forms)
           ((none) (err "Empty hyper index input"))
           ((some rootForm)
            (mt rootForm
              ((rd/sexprList items)
               (let [(nodesOpt (findKvNode items ":nodes"))
                     (edgesOpt (findKvNode items ":edges"))
                     (nodeForms (mt nodesOpt
                                  ((some (rd/sexprVect v)) v)
                                  ((some (rd/sexprList l)) l)
                                  (_ (list))))
                     (edgeForms (mt edgesOpt
                                  ((some (rd/sexprVect v)) v)
                                  ((some (rd/sexprList l)) l)
                                  (_ (list))))
                     (nodesRes (fold (fn [(acc (Result (List model/HyperNode) Str)) (nf rd/SExpr)] -> (Result (List model/HyperNode) Str)
                                       (mt acc
                                         ((err e) (err e))
                                         ((ok ns)
                                          (mt (parseHyperNode nf)
                                            ((some n) (ok (list-append ns (list n))))
                                            ((none) (err "Corrupted node definition in hyper index"))))))
                                     (ok (list))
                                     nodeForms))
                     (edgesRes (fold (fn [(acc (Result (List model/HyperEdge) Str)) (ef rd/SExpr)] -> (Result (List model/HyperEdge) Str)
                                       (mt acc
                                         ((err e) (err e))
                                         ((ok es)
                                          (mt (parseHyperEdge ef)
                                            ((some e) (ok (list-append es (list e))))
                                            ((none) (err "Corrupted edge definition in hyper index"))))))
                                     (ok (list))
                                     edgeForms))]
                 (mt nodesRes
                   ((err e) (err e))
                   ((ok ns)
                    (mt edgesRes
                      ((err e) (err e))
                      ((ok es)
                       (ok (model/makeHyperIndex 1 ns es 1789720000000))))))))
              (_ (err "Hyper index root must be an S-expression list")))))))))

(df loadOrBuildHyperIndex [(indexPath Str) (fallbackModules (List (Pair Str Str)))] -> model/HyperIndex
  :d "Loads hypergraph index from disk or builds from fallback modules."
  (let [(readRes (file-read indexPath))]
    (mt readRes
      ((ok content)
       (let [(parsedRes (deserializeHyperIndex content))]
         (mt parsedRes
           ((ok idx) idx)
           ((err _) (buildHypergraphFromModules fallbackModules)))))
      ((err _)
       (let [(idx (buildHypergraphFromModules fallbackModules))
             (rendered (serializeHyperIndex idx))
             (_ (file-write indexPath rendered))]
         idx)))))
