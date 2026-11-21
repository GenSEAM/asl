(module asl-forms/tests/observeTreeDriver
  :x [main]
  :i [(asl-forms/search :a s)])

fn pairsOf xs: (List String) acc: (Map String String) -> (Map String String)
  (match (listHead xs)
    ((none) acc)
    ((some k) (let [(rest (optionOr (listTail xs) (list)))]
      (pairsOf (optionOr (listTail rest) (list)) (mapSet acc k (optionOr (listHead rest) ""))))))

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "observeTreeTest's child: runs the (:observe :dim DIM KEY VALUE ...) step of asl-forms (DIM its first argument, tokenCost by default; then key/value pairs) with its cwd as both workspace and tool root and prints the receipt lines, so the test sees which tree's observe code answered")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(tree (resultOr (realPath ".") "."))
        (kw (pairsOf (optionOr (listTail args) (list)) (mapEmpty)))
        (out (s/observeStep! (s/KnowCtx :ws tree :toolRoot tree :binDir "" :vfsDir "" :toolsFile "" :home "") 1 kw (list (optionOr (listHead args) "tokenCost")) (mapKeys kw)))]
    (do (println (stringJoin out.lines "\n"))
        (ok out.errCount)))
