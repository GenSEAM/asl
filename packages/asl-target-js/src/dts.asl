(module asl-target-js/dts
  :x [tsType emitDts]
  :i [(asl-parser/ast :a a) (asl-parser/reader :a rd)])

fn reservedWords -> (List String)
  ["break" "case" "catch" "class" "const" "continue" "debugger" "default" "delete" "do" "else" "enum" "export" "extends" "false" "finally" "for" "function" "if" "import" "in" "instanceof" "new" "null" "return" "super" "switch" "this" "throw" "true" "try" "typeof" "var" "void" "while" "with" "yield" "let" "static" "implements" "interface" "package" "private" "protected" "public" "await"]

fn identChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (or (and (>= c "0") (<= c "9")) (or (= c "_") (= c "$")))))

fn plainIdent? name: String -> Bool
  (and (not (stringEmpty? name))
    (and (listAll? identChar? (stringChars name))
      (and (not (and (>= (optionOr (stringSlice name 0 1) "") "0") (<= (optionOr (stringSlice name 0 1) "") "9")))
        (not (listContains? (reservedWords) name)))))

fn tsString s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn typeVar? name: String locals: (List String) -> Bool
  (or (listContains? locals name)
    (and (= (stringLength name) 1) (and (>= name "A") (<= name "Z"))))

fn atomType name: String locals: (List String) known: (List String) -> String
  (cond
    ((listContains? ["Int64" "Int" "I64"] name) "bigint")
    ((listContains? ["Float64" "Float" "F64"] name) "number")
    ((listContains? ["String" "Str"] name) "string")
    ((= name "Bool") "boolean")
    ((= name "Unit") "AslUnit")
    ((= name "Bytes") "Uint8Array")
    ((= name "Keyword") "AslKeyword")
    ((= name "Any") "unknown")
    ((typeVar? name locals) name)
    ((listContains? known name) name)
    (else (str "AslOpaque<" (tsString name) ">")))

fn atomText e: rd/SExpr -> String
  (mt e ((rd/sexprAtom v) v) (_ ""))

fn generic name: String args: (List String) -> String
  (str name "<" (stringJoin args ", ") ">")

fn fnType items: (List rd/SExpr) locals: (List String) known: (List String) -> String
  (let [(params (mt (listGet items 1) ((some x) (mt x ((rd/sexprVect ps) ps) (_ []))) ((none) [])))
        (ret (optionOr (listLast items) (rd/makeAtom "Unit")))]
    (str "((" (stringJoin (map (fn [(p (Pair Int64 rd/SExpr))] -> String (str "a" (stringFromInt64 (pairFirst p)) ": " (tsType (pairSecond p) locals known))) (enumerate params)) ", ") ") => " (tsType ret locals known) ")"))

fn tsType e: rd/SExpr locals: (List String) known: (List String) -> String
  (mt e
    ((rd/sexprAtom v) (atomType v locals known))
    ((rd/sexprVect items) "unknown")
    ((rd/sexprList items)
      (let [(head (atomText (optionOr (listHead items) (rd/makeAtom ""))))
            (args (map (fn [(x rd/SExpr)] -> String (tsType x locals known)) (listDrop items 1)))]
        (cond
          ((= head "List") (generic "AslList" args))
          ((= head "Option") (generic "AslOption" args))
          ((= head "Result") (generic "AslResult" args))
          ((= head "Pair") (generic "AslPair" args))
          ((= head "Map") (generic "AslMap" args))
          ((= head "fn") (fnType items locals known))
          ((listContains? known head) (generic head args))
          (else (str "AslOpaque<" (tsString head) ">"))))))

fn parseType text: String -> rd/SExpr
  (rd/parseSexpr text)

fn typeOf text: String locals: (List String) known: (List String) -> String
  (tsType (parseType text) locals known)

fn typeParams vars: (List String) -> String
  (if (listEmpty? vars) "" (str "<" (stringJoin vars ", ") ">"))

fn usedVars texts: (List String) -> (List String)
  (fold (fn [(acc (List String)) (t String)] -> (List String)
          (fold (fn [(acc2 (List String)) (tok String)] -> (List String) (if (and (typeVar? tok []) (not (listContains? acc2 tok))) (listAppend acc2 [tok]) acc2))
                acc (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace t "(" " ") ")" " ") "[" " ") "]" " ") " ")))
        [] texts)

fn schemaDecl s: a/SchemaNode known: (List String) -> String
  (str "export interface " s.name (typeParams s.typeVars) " {\n"
       (stringJoin (map (fn [(f a/AstField)] -> String (str "  readonly " (if (plainIdent? f.name) f.name (tsString f.name)) ": " (typeOf f.type s.typeVars known) ";\n")) s.fields) "")
       "}\n")

fn caseType c: a/EnumCase vars: (List String) known: (List String) -> String
  (str "{ readonly name: " (tsString c.name) "; readonly fields: readonly [" (stringJoin (map (fn [(p a/Param)] -> String (typeOf p.type vars known)) c.fields) ", ") "] }")

fn enumDecl e: a/EnumNode known: (List String) -> String
  (str "export type " e.name (typeParams e.typeVars) " =\n  | " (stringJoin (map (fn [(c a/EnumCase)] -> String (caseType c e.typeVars known)) e.cases) "\n  | ") ";\n")

fn localName name: String -> String
  (str "asl$" (stringJoin (map (fn [(c String)] -> String (if (identChar? c) c (str "$" (stringFromInt64 (charCode c))))) (stringChars name)) ""))

fn defunDecl d: a/DefunNode known: (List String) -> String
  (let [(vars (let [(found (usedVars (cons d.retType (map (fn [(p a/Param)] -> String p.type) d.params))))] (listAppend d.typeVars (filter (fn [(v String)] -> Bool (not (listContains? d.typeVars v))) found))))
        (sig (str (typeParams vars) "(" (stringJoin (map (fn [(p a/Param)] -> String (str (if (plainIdent? p.name) p.name (localName p.name)) ": " (typeOf p.type vars known))) d.params) ", ") "): " (if (stringEmpty? d.retType) "AslUnit" (typeOf d.retType vars known)) ";\n"))]
    (if (plainIdent? d.name)
      (str "export declare function " d.name sig)
      (str "declare function " (localName d.name) sig "export { " (localName d.name) " as " (tsString d.name) " };\n")))

fn prologue moduleName: String -> String
  (stringJoin
    [(str "// Generated by asl-target-js: TypeScript declarations for " moduleName ".")
     "// Int is bigint, Float is number; List, Option, Result and Pair are the runtime's own shapes."
     "export type AslList<T> = null | { readonly h: T; readonly t: AslList<T> };"
     "export type AslOption<T> = { readonly name: \"some\"; readonly fields: readonly [T] } | { readonly name: \"none\"; readonly fields: readonly [] };"
     "export type AslResult<T, E> = { readonly name: \"ok\"; readonly fields: readonly [T] } | { readonly name: \"err\"; readonly fields: readonly [E] };"
     "export type AslPair<A, B> = { readonly name: \"pair\"; readonly fields: readonly [A, B] };"
     "export type AslMap<K, V> = { readonly __aslMap: [K, V] };"
     "export type AslUnit = { readonly __aslUnit: true };"
     "export type AslKeyword = { readonly name: string };"
     "export type AslOpaque<N extends string> = { readonly __asl: N };"
     "export declare class AslTrap extends Error { readonly code: string; }"
     "export declare function setOutput(write: (text: string) => void): void;"
     "export declare const counts: { asserts: number; refutes: number };"
     "export declare const asl: {"
     "  list<T>(...items: T[]): AslList<T>;"
     "  toArray<T>(list: AslList<T>): T[];"
     "  some<T>(value: T): AslOption<T>;"
     "  none: AslOption<never>;"
     "  ok<T>(value: T): AslResult<T, never>;"
     "  err<E>(error: E): AslResult<never, E>;"
     "  pair<A, B>(a: A, b: B): AslPair<A, B>;"
     "  variant<V extends { name: string; fields: readonly unknown[] }>(name: V[\"name\"], ...fields: V[\"fields\"]): V;"
     "  record<R extends object>(schema: string, fields: R): R;"
     "  unit: AslUnit;"
     "  show(value: unknown): string;"
     "};"
     ""]
    "\n")

fn emitDts source: String -> (Result String String)
  (mt (a/parse source)
    ((err pe) (err (str "parse: " pe.msg)))
    ((ok forms)
      (let [(moduleName (fold (fn [(acc String) (f a/TopForm)] -> String (mt f ((a/topModule m) m.path) (_ acc))) "" forms))
            (schemas (fold (fn [(acc (List a/SchemaNode)) (f a/TopForm)] -> (List a/SchemaNode) (mt f ((a/topSchema s) (listAppend acc [s])) (_ acc))) [] forms))
            (enums (fold (fn [(acc (List a/EnumNode)) (f a/TopForm)] -> (List a/EnumNode) (mt f ((a/topEnum e) (listAppend acc [e])) (_ acc))) [] forms))
            (defuns (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] -> (List a/DefunNode) (mt f ((a/topDefun d) (listAppend acc [d])) (_ acc))) [] forms))
            (known (listAppend (map (fn [(s a/SchemaNode)] -> String s.name) schemas) (map (fn [(e a/EnumNode)] -> String e.name) enums)))]
        (ok (str (prologue moduleName)
                 (stringJoin (map (fn [(s a/SchemaNode)] -> String (schemaDecl s known)) schemas) "")
                 (stringJoin (map (fn [(e a/EnumNode)] -> String (enumDecl e known)) enums) "")
                 (stringJoin (map (fn [(d a/DefunNode)] -> String (defunDecl d known)) defuns) ""))))))
