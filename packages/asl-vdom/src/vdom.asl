(module asl-vdom/vdom
  :doc "Declarative S-Expression Virtual DOM in ASL"
  :export [VNode is-valid-node text])

(defenum VNode
  (:case text-node [(content String)] "text node")
  (:case element-node [(tag String) (children (List VNode))] "element node"))

(defun text [(content String)] -> VNode
  :doc "Creates text node"
  (text-node content))

(defun is-valid-node [(node VNode)] -> Bool
  :doc "Validates VNode"
  (match node
    ((text-node content) (> (string-length content) 0))
    ((element-node tag _) (> (string-length tag) 0))))
