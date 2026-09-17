(module asl-parser/indentPrinter
  :d "Pure ASL v0.4 Canonical Indented Formatter & Round-Trip Pretty Printer."
  :x [formatIndented formatSexpr isDotAccess? formatDotAccess
      isInterpolatedStr? formatInterpolatedStr isListForm? formatListForm printIndented]
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

(df formatMatchArm [(arm rd/SExpr) (indent Int64)] -> String
  :d "Formats match arm ((pattern) body) as Pattern -> Body."
  (mt arm
    ((sexprList items)
     (let [(firstItem (option-or (list-get items 0) (rd/makeAtom "_")))
           (secondItem (option-or (list-get items 1) (rd/makeAtom "()")))]
       (let [(pat (mt firstItem
                    ((sexprList pItems)
                     (string-join (map (fn [(x rd/SExpr)] -> String (formatSexpr x 0)) pItems) " "))
                    (_ (formatSexpr firstItem 0))))
             (bod (formatCallBody secondItem))]
         (str (indentPrefix indent) pat " -> " bod))))
    (_ "")))

(df formatMatchForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats (match target (arms...)) into match target\\n  arm1\\n  arm2."
  (mt s
    ((sexprList items)
     (let [(targetSexpr (option-or (list-get items 1) (rd/makeAtom "_")))
           (armsContainer (option-or (list-get items 2) (rd/makeList (list))))
           (armsList (rd/sexprToList armsContainer))
           (renderedTarget (formatSexpr targetSexpr 0))
           (armLines (map (fn [(a rd/SExpr)] -> String (formatMatchArm a (+ indent 1))) armsList))]
       (str (indentPrefix indent) "match " renderedTarget "\n"
            (string-join armLines "\n"))))
    (_ "")))

(df stripInlineDoc [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Strips inline docstring :d or :doc and its following argument from items list."
  (mt (list-head items)
    ((none) (list))
    ((some h)
     (let [(hVal (rd/sexprHead h))
           (tailItems (option-or (list-tail items) (list)))]
       (if (or (= hVal ":d") (= hVal ":doc"))
         (stripInlineDoc (option-or (list-tail tailItems) (list)))
         (cons h (stripInlineDoc tailItems)))))))

(df formatDefunForm [(s rd/SExpr) (indent Int64)] -> String
  :d "Formats (df name params -> ret body...) into fn signature and indented body."
  (mt s
    ((sexprList items)
     (let [(fnName (rd/sexprHead (option-or (list-get items 1) (rd/makeAtom "anonymous"))))
           (paramsVect (option-or (list-get items 2) (rd/makeVect (list))))
           (arrowSym (rd/sexprHead (option-or (list-get items 3) (rd/makeAtom "->"))))
           (retType (option-or (list-get items 4) (rd/makeAtom "Unit")))
           (rawBodyForms (if (> (list-length items) 5)
                           (option-or (list-slice items 5 (list-length items)) (list))
                           (list)))
           (bodyForms (stripInlineDoc rawBodyForms))
           (sigText (formatParamsVector paramsVect))
           (retText (formatSexpr retType 0))
           (header (if (string-empty? sigText)
                     (str (indentPrefix indent) "fn " fnName " -> " retText)
                     (str (indentPrefix indent) "fn " fnName " " sigText " -> " retText)))]
       (if (list-empty? bodyForms)
         header
         (let [(bodyLines (map (fn [(b rd/SExpr)] -> String
                                 (formatSexpr b (+ indent 1)))
                               bodyForms))]
           (str header "\n" (string-join bodyLines "\n"))))))
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
          (formatSexpr s 0))
         ((or (= headSym "enum") (or (= headSym "dfe") (= headSym "defenum")))
          (formatSexpr s 0))
         (:else
          (formatIndented s)))))
    (_ (formatSexpr s 0))))

(df printIndented [(forms (List rd/SExpr))] -> String
  :d "Formats a list of AST SExpr forms into canonical indented text."
  (if (list-empty? forms)
    ""
    (let [(strs (map (fn [(s rd/SExpr)] -> String (formatTopForm s)) forms))]
      (string-join strs "\n\n"))))
