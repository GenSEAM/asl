(module aslSite/ui/bridge
  :x [Op attrOp textOp swapOp copyOp storeOp afterOp quote encodeOp encodeOps]
  :i [(asl-html/html :a h)])

(enum Op (:c attrOp [(sel String) (name String) (value String)] "set an attribute") (:c textOp [(sel String) (s String)] "set text content") (:c swapOp [(sel String) (node h/Node)] "replace the children of an element") (:c copyOp [(s String)] "write text to the clipboard") (:c storeOp [(key String) (value String)] "persist a preference on this device") (:c afterOp [(ms Int64) (msg Int64)] "deliver msg back to update after ms"))

fn quote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn encodeOp op: Op -> String
  (mt op
    ((attrOp sel name value) (str "(:attr " (quote sel) " " (quote name) " " (quote value) ")"))
    ((textOp sel s) (str "(:text " (quote sel) " " (quote s) ")"))
    ((swapOp sel node) (str "(:swap " (quote sel) " " (quote (h/render node)) ")"))
    ((copyOp s) (str "(:copy " (quote s) ")"))
    ((storeOp key value) (str "(:store " (quote key) " " (quote value) ")"))
    ((afterOp ms msg) (str "(:after " (stringFromInt64 ms) " " (stringFromInt64 msg) ")")))

fn encodeOps ops: (List Op) -> String
  (stringJoin (map (fn [(op Op)] -> String (str (encodeOp op) "\n")) ops) "")
