(module asl-vdom/vdom
  :d "Declarative S-Expression Virtual DOM in ASL"
  :x [VNode is-valid-node text])

(dfe VNode
  (:c text-node [(content String)] "text node")
  (:c element-node [(tag String) (children (List VNode))] "element node"))

(df text [(content String)] -> VNode
  :d "Creates text node"
  (text-node content))

(df is-valid-node [(node VNode)] -> Bool
  :d "Validates VNode"
  (mt node
    ((text-node content) (> (string-length content) 0))
    ((element-node tag _) (> (string-length tag) 0))))
