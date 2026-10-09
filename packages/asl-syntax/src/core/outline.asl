(module asl-syntax/core/outline
  :x [OutlineItem
      makeOutlineItem
      escapeAsnValue
      formatOutlineItem
      formatOutlineItems
      formatOutlineReceipt
      formatOutlineReceiptFromText]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/symbols :a sym)])

(schema OutlineItem
  (:f name String)
  (:f kind String)
  (:f startLine Int64)
  (:f endLine Int64))

fn makeOutlineItem name: String kind: String startLine: Int64 endLine: Int64 -> OutlineItem
  (OutlineItem :name name :kind kind :startLine startLine :endLine endLine)

fn escapeAsnValue s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))]
    (stringReplace s2 "\n" "\\n"))

fn formatOutlineItem name: String kind: String startLine: Int64 endLine: Int64 -> String
  (str "(:item :name \"" (escapeAsnValue name)
       "\" :kind \"" (escapeAsnValue kind)
       "\" :start " (stringFromInt64 startLine)
       " :end " (stringFromInt64 endLine) ")")

fn symbolToOutlineItem s: src/Source d: sym/SymbolDef -> OutlineItem
  (let [(st (sym/symbolStart d))
        (en (sym/symbolEnd d))
        (stLine (optionOr (src/sourceLineAt s st) 1))
        (lastCharOff (if (> en st) (- en 1) st))
        (enLine (optionOr (src/sourceLineAt s lastCharOff) stLine))]
    (OutlineItem :name (sym/symbolName d) :kind (sym/symbolKind d) :startLine stLine :endLine enLine))

fn formatOutlineItems items: (List OutlineItem) -> String
  (if (listEmpty? items)
    ""
    (let [(strs (map (fn [(it OutlineItem)] -> String
                       (formatOutlineItem it.name it.kind it.startLine it.endLine))
                     items))]
      (stringJoin strs " ")))

fn formatOutlineReceipt file: String language: String syms: (List sym/SymbolDef) s: src/Source -> String
  (let [(items (map (fn [(d sym/SymbolDef)] -> OutlineItem (symbolToOutlineItem s d)) syms))
        (itemsCount (listLength items))
        (itemsText (formatOutlineItems items))]
    (if (= itemsCount 0)
      (str "(:outline :status :ok :file \"" (escapeAsnValue file)
           "\" :language \"" (escapeAsnValue language)
           "\" :itemsCount 0 :items [])")
      (str "(:outline :status :ok :file \"" (escapeAsnValue file)
           "\" :language \"" (escapeAsnValue language)
           "\" :itemsCount " (stringFromInt64 itemsCount)
           " :items [" itemsText "])")))

fn formatOutlineReceiptFromText file: String language: String syms: (List sym/SymbolDef) text: String -> String
  (let [(s (src/sourceFromString file text))]
    (formatOutlineReceipt file language syms s))
