(module asl-parser/indentPrinter
  :d "Pure ASL v0.4 Canonical Indented Formatter & Round-Trip Pretty Printer."
  :x [formatIndented formatSexpr isDotAccess? formatDotAccess
      isInterpolatedStr? formatInterpolatedStr isListForm? formatListForm printIndented
      formatSchemaForm formatEnumForm isMatchForm? extractDocstring]
  :i [(reader :a rd)])

(df indentPrefix [(level Int64)] -> String
  :d "Generates 2-space indentation string for given level."
  (string-repeat "  " level))

(df isDotAccess? [(s rd/SExpr)] -> Bool
  :d "Checks if SExpr is a (.-property target) field accessor."
  (mt s
    ((sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexprAtom v) (string-starts-with? v ".-"))
          (_ false)))
       ((none) false)))
    (_ false)))

(df formatDotAccess [(s rd/SExpr)] -> String
  :d "Formats (.-c (.-b (.-a x))) into canonical dot chain x.a.b.c."
  (mt s
    ((sexprList items)
     (let [(headSym (rd/sexprHead s))
           (propName (if (string-starts-with? headSym ".-")
                       (string-slice headSym 2 (string-length headSym))
                       (some headSym)))
           (prop (option-or propName headSym))
           (tailItems (option-or (list-tail items) (list)))]
       (mt (list-head tailItems)
         ((some target)
          (if (isDotAccess? target)
            (str (formatDotAccess target) "." prop)
            (str (formatSexpr target 0) "." prop)))
         ((none) prop))))
    ((sexprAtom v) v)
    (_ "")))

(df isInterpolatedStr? [(s rd/SExpr)] -> Bool
  :d "Checks if SExpr is a (str ...) concatenation form representing interpolation."
  (mt s
    ((sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexprAtom v) (= v "str"))
          (_ false)))
       ((none) false)))
    (_ false)))

(df formatInterpolatedStr [(s rd/SExpr)] -> String
  :d "Formats (str \"part\" expr \"part\") into \"part{expr}part\"."
  (mt s
    ((sexprList items)
     (let [(args (option-or (list-tail items) (list)))
           (bodyText (fold (fn [(acc String) (arg rd/SExpr)] -> String
                             (mt arg
                               ((sexprAtom v)
                                (if (and (string-starts-with? v "\"") (string-ends-with? v "\""))
                                  (str acc (option-or (string-slice v 1 (- (string-length v) 1)) ""))
                                  (str acc "{" v "}")))
                               (_
                                (str acc "{" (formatCallBody arg) "}"))))
                           ""
                           args))]
       (str "\"" bodyText "\"")))
    (_ "")))

(df isListForm? [(s rd/SExpr)] -> Bool
  :d "Checks if SExpr is a (list ...) collection constructor."
  (mt s
    ((sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexprAtom v) (= v "list"))
          (_ false)))
       ((none) false)))
    (_ false)))

(df formatListForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats (list a b c) as [a b c] if <= 5 items, else bullet lines."
  (mt s
    ((sexprList items)
     (let [(args (option-or (list-tail items) (list)))]
       (if (<= (list-length args) 5)
         (str "[" (string-join (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) args) " ") "]")
         (let [(lines (map (fn [(x rd/SExpr)] -> String
                             (str (indentPrefix (+ indent 1)) "- " (formatCallBody x)))
                           args))]
           (str "\n" (string-join lines "\n"))))))
    (_ "[]")))

(df formatParamsVector [(v rd/SExpr)] -> String
  :d "Formats [(p1 T1) (p2 T2)] into p1: T1 p2: T2."
  (mt v
    ((sexprVect items)
     (let [(paramStrs (map (fn [(p rd/SExpr)] -> String
                             (mt p
                               ((sexprList pItems)
                                (let [(pName (rd/sexprHead p))
                                      (restItems (option-or (list-tail pItems) (list)))
                                      (pTypeSexpr (option-or (list-head restItems) (rd/makeAtom "Any")))
                                      (pType (formatSexpr pTypeSexpr 0))]
                                  (str pName ": " pType)))
                               (_ "")))
                           items))]
       (string-join paramStrs " ")))
    (_ "")))

(df formatCallBody [(s rd/SExpr)] -> String
  :d "Formats a function call without outer enclosing parentheses."
  (mt s
    ((sexprAtom v) v)
    ((sexprVect items)
     (str "[" (string-join (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items) " ") "]"))
    ((sexprList items)
     (cond
       ((isDotAccess? s)       (formatDotAccess s))
       ((isInterpolatedStr? s) (formatInterpolatedStr s))
       ((isListForm? s)        (formatListForm s 0))
       (:else
        (let [(renderedArgs (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items))]
          (string-join renderedArgs " ")))))))

(df isMatchForm? [(s rd/SExpr)] -> Bool
  :d "Checks if SExpr is a match form."
  (mt s
    ((sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((sexprAtom v) (= v "match"))
          (_ false)))
       ((none) false)))
    (_ false)))

(df formatMatchArm [(arm rd/SExpr) (indent Int64)] -> String
  :d "Formats match arm ((pattern) body) as Pattern -> Body or Pattern -> indented body."
  (mt arm
    ((sexprList items)
     (let [(firstItem (option-or (list-get items 0) (rd/makeAtom "_")))
           (secondItem (option-or (list-get items 1) (rd/makeAtom "()")))]
       (let [(pat (mt firstItem
                    ((sexprList pItems)
                     (string-join (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) pItems) " "))
                    (_ (formatSexpr firstItem 0))))]
         (if (isMatchForm? secondItem)
           (str (indentPrefix indent) pat " ->\n" (formatMatchForm secondItem (+ indent 1)))
           (let [(bod (formatCallBody secondItem))]
             (str (indentPrefix indent) pat " -> " bod))))))
    (_ "")))

(df formatMatchForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats (match target (arms...)) into match target\n  arm1\n  arm2."
  (mt s
    ((sexprList items)
     (let [(targetSexpr (option-or (list-get items 1) (rd/makeAtom "_")))
           (renderedTarget (formatSexpr targetSexpr 0))
           (armsList (if (> (list-length items) 3)
                       (option-or (list-slice items 2 (list-length items)) (list))
                       (let [(c (option-or (list-get items 2) (rd/makeList (list))))]
                         (mt c
                           ((sexprList cItems)
                            (mt (list-head cItems)
                              ((some firstEl)
                               (if (rd/isList? firstEl)
                                 cItems
                                 (list c)))
                              ((none) (list))))
                           (_ (list c))))))
           (armLines (map (fn [(a rd/SExpr)] -> String (formatMatchArm a (+ indent 1))) armsList))]
       (str (indentPrefix indent) "match " renderedTarget "\n"
            (string-join armLines "\n"))))
    (_ "")))

(df extractDocstring [(items (List rd/SExpr))] -> (Pair (Option String) (List rd/SExpr))
  :d "Extracts inline docstring if present at head of body forms."
  (mt (list-head items)
    ((some h)
     (let [(hVal (rd/sexprHead h))
           (tailItems (option-or (list-tail items) (list)))]
       (if (or (= hVal ":d") (= hVal ":doc"))
         (mt (list-head tailItems)
           ((some docAtom)
            (pair (some (rd/sexprHead docAtom)) (option-or (list-tail tailItems) (list))))
           ((none)
            (pair (none) tailItems)))
         (pair (none) items))))
    ((none) (pair (none) (list)))))

(df stripInlineDoc [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Strips inline docstring :d or :doc and its following argument from items list."
  (.-second (extractDocstring items)))

(df formatDefunForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats (df name [!] params -> ret body...) into fn signature and indented body."
  (mt s
    ((sexprList items)
     (let [(fnName (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom "anonymous"))))
           (item2 (option-or (list-get items 2) (rd/makeVect (list))))
           (hasEffect (and (rd/isAtom? item2) (= (rd/sexprHead item2) "!")))
           (paramsVect (if hasEffect
                         (option-or (list-get items 3) (rd/makeVect (list)))
                         item2))
           (arrowSym (if hasEffect
                       (rd/sexprHead (option-or (list-get items 4) (rd/makeAtom "->")))
                       (rd/sexprHead (option-or (list-get items 3) (rd/makeAtom "->")))))
           (retType (if hasEffect
                      (option-or (list-get items 5) (rd/makeAtom "Unit"))
                      (option-or (list-get items 4) (rd/makeAtom "Unit"))))
           (rawBodyForms (if hasEffect
                           (if (> (list-length items) 6)
                             (option-or (list-slice items 6 (list-length items)) (list))
                             (list))
                           (if (> (list-length items) 5)
                             (option-or (list-slice items 5 (list-length items)) (list))
                             (list))))
           (docRes (extractDocstring rawBodyForms))
           (docOpt (.-first docRes))
           (bodyForms (.-second docRes))
           (sigText (formatParamsVector paramsVect))
           (retText (formatSexpr retType 0))
           (effStr (if hasEffect "! " ""))
           (header (if (string-empty? sigText)
                     (str (indentPrefix indent) "fn " fnName (if hasEffect " ! -> " " -> ") retText)
                     (str (indentPrefix indent) "fn " fnName " " effStr sigText " -> " retText)))
           (docLine (mt docOpt
                      ((some d) (list (str (indentPrefix (+ indent 1)) ":d " d)))
                      ((none) (list))))
           (bodyLines (map (fn [(b rd/SExpr)] -> String
                             (formatSexpr b (+ indent 1)))
                           bodyForms))
           (allLines (list-append docLine bodyLines))]
       (if (list-empty? allLines)
         header
         (str header "\n" (string-join allLines "\n")))))
    (_ "")))

(df formatSchemaField [(f rd/SExpr) (indent Int64)] -> String
  :d "Formats a single schema field (:field name type [doc]) into 'name: type [doc]'."
  (mt f
    ((sexprList items)
     (let [(fName (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom ""))))
           (fType (formatSexpr (option-or (list-get items 2) (rd/makeAtom "Any")) 0))
           (docOpt (list-get items 3))]
       (mt docOpt
         ((some docAtom)
          (let [(docStr (rd/sexprHead docAtom))]
            (if (or (= docStr "") (= docStr "\"\""))
              (str (indentPrefix indent) fName ": " fType)
              (str (indentPrefix indent) fName ": " fType " " docStr))))
         ((none)
          (str (indentPrefix indent) fName ": " fType)))))
    (_ "")))

(df formatSchemaForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats defschema SExpr into clean v0.4 indented schema declaration."
  (mt s
    ((sexprList items)
     (let [(name (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom "Anonymous"))))
           (fieldForms (if (> (list-length items) 2)
                         (option-or (list-slice items 2 (list-length items)) (list))
                         (list)))
           (header (str (indentPrefix indent) "schema " name))]
       (if (list-empty? fieldForms)
         header
         (let [(fieldLines (map (fn [(f rd/SExpr)] -> String
                                  (formatSchemaField f (+ indent 1)))
                                fieldForms))]
           (str header "\n" (string-join fieldLines "\n"))))))
    (_ "")))

(df formatEnumCase [(c rd/SExpr) (indent Int64)] -> String
  :d "Formats a single enum variant (:case Name [params] [doc]) into 'Name'."
  (mt c
    ((sexprList items)
     (let [(caseName (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom ""))))]
       (str (indentPrefix indent) caseName)))
    ((sexprAtom v)
     (str (indentPrefix indent) v))
    (_ "")))

(df formatEnumForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats defenum SExpr into clean v0.4 indented enum declaration."
  (mt s
    ((sexprList items)
     (let [(name (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom "Anonymous"))))
           (caseForms (if (> (list-length items) 2)
                        (option-or (list-slice items 2 (list-length items)) (list))
                        (list)))
           (header (str (indentPrefix indent) "enum " name))]
       (if (list-empty? caseForms)
         header
         (let [(caseLines (map (fn [(c rd/SExpr)] -> String
                                 (formatEnumCase c (+ indent 1)))
                               caseForms))]
           (str header "\n" (string-join caseLines "\n"))))))
    (_ "")))

(df formatSexpr [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats single SExpr into canonical v0.4 indented text."
  (mt s
    ((sexprAtom v) v)
    ((sexprVect items)
     (str "[" (string-join (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items) " ") "]"))
    ((sexprList items)
     (let [(headSym (rd/sexprHead s))]
       (cond
         ((or (= headSym "df") (= headSym "defun"))
          (formatDefunForm s indent))
         ((= headSym "match")
          (formatMatchForm s indent))
         ((or (= headSym "schema") (or (= headSym "dfs") (= headSym "defschema")))
          (formatSchemaForm s indent))
         ((or (= headSym "enum") (or (= headSym "dfe") (= headSym "defenum")))
          (formatEnumForm s indent))
         ((isDotAccess? s)
          (formatDotAccess s))
         ((isInterpolatedStr? s)
          (formatInterpolatedStr s))
         ((isListForm? s)
          (formatListForm s indent))
         (:else
          (let [(renderedArgs (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) items))]
            (if (> indent 0)
              (str (indentPrefix indent) (string-join renderedArgs " "))
              (str "(" (string-join renderedArgs " ") ")")))))))))

(df formatIndented [(s rd/SExpr)] -> String
  :d "Canonical top-level formatter entrypoint."
  (mt s
    ((sexprList items)
     (let [(headSym (rd/sexprHead s))]
       (cond
         ((or (= headSym "df") (= headSym "defun"))
          (formatDefunForm s 0))
         ((= headSym "match")
          (formatMatchForm s 0))
         ((= headSym "module")
          (formatSexpr s 0))
         ((or (= headSym "schema") (or (= headSym "dfs") (= headSym "defschema")))
          (formatSchemaForm s 0))
         ((or (= headSym "enum") (or (= headSym "dfe") (= headSym "defenum")))
          (formatEnumForm s 0))
         ((isDotAccess? s)
          (formatDotAccess s))
         ((isInterpolatedStr? s)
          (formatInterpolatedStr s))
         ((isListForm? s)
          (formatListForm s 0))
         (:else
          (formatCallBody s)))))
    (_ (formatSexpr s 0))))

(df formatTopForm [(s rd/SExpr)] -> String
  :d "Formats a single top-level form into clean v0.4 surface syntax."
  (mt s
    ((sexprList items)
     (let [(headSym (rd/sexprHead s))]
       (cond
         ((or (= headSym "df") (= headSym "defun"))
          (formatDefunForm s 0))
         ((= headSym "match")
          (formatMatchForm s 0))
         ((= headSym "module")
          (formatSexpr s 0))
         ((or (= headSym "schema") (or (= headSym "dfs") (= headSym "defschema")))
          (formatSchemaForm s 0))
         ((or (= headSym "enum") (or (= headSym "dfe") (= headSym "defenum")))
          (formatEnumForm s 0))
         (:else
          (formatIndented s)))))
    (_ (formatSexpr s 0))))

(df printIndented [(forms (List rd/SExpr))] -> String
  :d "Formats a list of AST SExpr forms into canonical indented text."
  (if (list-empty? forms)
    ""
    (let [(strs (map (fn [(s rd/SExpr)] -> String (formatTopForm s)) forms))]
      (string-join strs "\n\n"))))
