(module asl-vdom/test
  :d "Unit tests for S-expression Virtual DOM and Dual Perception in ASL"
  :x [run-tests
      test-vnode-creation
      test-axnode-construction
      test-downsampling-prunes-scripts-and-styles
      test-downsampling-filter-attributes
      test-downsampling-collapses-wrappers
      test-dom-diff-added-removed-mutated]
  :i [(vdom :a v)])

"run: (run-tests)"

(df test-vnode-creation [] -> Bool
  :d "Verifies VNode creation, validation, and content accessors"
  (let [(t (v/text "Hello World"))
        (empty-t (v/text ""))
        (attrs (map-set (map-empty) "id" "submit-btn"))
        (btn (v/elem "button" attrs (list t)))]
    (and (v/is-valid-node t)
         (and (not (v/is-valid-node empty-t))
              (and (v/is-valid-node btn)
                   (and (= (v/vnode-tag btn) "button")
                        (and (= (v/vnode-text t) "Hello World")
                             (= (list-length (v/vnode-children btn)) 1))))))))

(df test-axnode-construction [] -> Bool
  :d "Verifies AXNode accessibility tree node construction and state tracking"
  (let [(leaf (v/ax-leaf "button" "Deploy" "@e1"))
        (parent (v/make-ax-node "dialog" "Confirmation" "@e0" "Modal dialog" false true (list leaf)))]
    (and (= (.-role leaf) "button")
         (and (= (.-name leaf) "Deploy")
              (and (= (.-ref leaf) "@e1")
                   (and (not (.-disabled leaf))
                        (and (not (.-focused leaf))
                             (and (= (.-role parent) "dialog")
                                  (and (.-focused parent)
                                       (= (list-length (.-children parent)) 1))))))))))

(df test-downsampling-prunes-scripts-and-styles [] -> Bool
  :d "Verifies downsampler eliminates scripts, styles, and non-semantic tags"
  (let [(script-node (v/elem-plain "script" (list (v/text "console.log(1)"))))
        (style-node (v/elem-plain "style" (list (v/text "body { margin: 0; }"))))
        (meta-node (v/elem-plain "meta" (list)))
        (content-node (v/elem-plain "h1" (list (v/text "Title"))))
        (container (v/elem-plain "main" (list script-node style-node meta-node content-node)))
        (downsampled-opt (v/downsample-node container))]
    (mt downsampled-opt
      ((some clean-node)
       (let [(children (v/vnode-children clean-node))]
         (and (= (v/vnode-tag clean-node) "main")
              (and (= (list-length children) 1)
                   (= (v/vnode-tag (mt (list-head children) ((some h) h) ((none) (v/text "")))) "h1")))))
      ((none) false))))

(df test-downsampling-filter-attributes [] -> Bool
  :d "Verifies downsampler strips CSS styling noise while retaining semantic attributes"
  (let [(noisy-attrs (fold (fn [(acc (Map String String)) (p (Pair String String))] -> (Map String String)
                             (map-set acc (.-first p) (.-second p)))
                           (map-empty)
                           (list (pair "class" "flex items-center justify-between p-4 bg-white")
                                 (pair "style" "color: red; padding: 10px;")
                                 (pair "data-reactroot" "true")
                                 (pair "id" "main-cta")
                                 (pair "aria-label" "Sign Up Now")
                                 (pair "role" "button"))))
        (filtered (v/filter-attributes noisy-attrs))]
    (and (= (map-size filtered) 3)
         (and (map-has? filtered "id")
              (and (map-has? filtered "aria-label")
                   (and (map-has? filtered "role")
                        (and (not (map-has? filtered "class"))
                             (and (not (map-has? filtered "style"))
                                  (not (map-has? filtered "data-reactroot"))))))))))

(df test-downsampling-collapses-wrappers [] -> Bool
  :d "Verifies transparent single-child wrappers are collapsed to the inner semantic element"
  (let [(target-btn (v/elem "button" (map-set (map-empty) "id" "act") (list (v/text "Action"))))
        (wrapper-span (v/elem-plain "span" (list target-btn)))
        (wrapper-div (v/elem-plain "div" (list wrapper-span)))
        (collapsed-opt (v/downsample-node wrapper-div))]
    (mt collapsed-opt
      ((some final-node)
       (and (= (v/vnode-tag final-node) "button")
            (= (v/vnode-text (mt (list-head (v/vnode-children final-node)) ((some h) h) ((none) (v/text "")))) "Action")))
      ((none) false))))

(df test-dom-diff-added-removed-mutated [] -> Bool
  :d "Verifies incremental DOM diffing correctly produces added, removed, and mutated records"
  (let [(attrs-old (map-set (map-empty) "id" "btn"))
        (attrs-new (map-set (map-set (map-empty) "id" "btn") "disabled" "true"))
        (child-old (v/text "Click Me"))
        (child-new (v/text "Saved"))
        (extra-node (v/elem-plain "span" (list (v/text "New Badge"))))
        (old-tree (v/elem "section" attrs-old (list (v/elem "button" attrs-old (list child-old)))))
        (new-tree (v/elem "section" attrs-new (list (v/elem "button" attrs-new (list child-new)) extra-node)))
        (diff (v/dom-diff old-tree new-tree "/settings"))
        (frame (v/format-diff-frame diff))]
    (and (= (.-route diff) "/settings")
         (and (= (list-length (.-added diff)) 1)
              (and (> (list-length (.-mutated diff)) 0)
                   (string-contains? frame "(! dom/diff :route \"/settings\""))))))

(df run-tests [] -> Bool
  :d "Runs all VDOM and dual perception unit tests"
  (and (test-vnode-creation)
       (and (test-axnode-construction)
            (and (test-downsampling-prunes-scripts-and-styles)
                 (and (test-downsampling-filter-attributes)
                      (and (test-downsampling-collapses-wrappers)
                           (test-dom-diff-added-removed-mutated)))))))

