(module asl-vdom/vdom
  :doc "Declarative S-Expression Virtual DOM in ASL Nano"
  :export [VNode is-valid-node text])

(dfe VNode
  (:case text-node [(content Str)] "text node")
  (:case element-node [(tag Str) (children (List VNode))] "element node"))

(df text [(content Str)] -> VNode
  :doc "Creates text node"
  (:text-node content))

(df is-valid-node [(node VNode)] -> Bool
  :doc "Validates VNode"
  (match node
    ((text-node content) (> (string-length content) 0))
    ((element-node tag children) (> (string-length tag) 0))))
