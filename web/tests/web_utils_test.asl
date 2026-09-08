(module asl-web/web-utils-test
  :d "Verification suite for pure ASL DOM and web utilities"
  :x [test-dom-element
      test-dom-query
      test-format-vdom-node
      test-web-lib-queries
      run-tests]
  :i [(utils/dom :a dom)
      (posts :a blog)])

(df test-dom-element [] -> Bool
  :d "Verifies DOM element construction and field access"
  (let [(elem (dom/dom-element "button" [["id" "submit-btn"] ["class" "primary"]] ["Click Me"]))]
    (assert (!= elem nil) "element is nil")
    (assert (= (.-tag elem) "button") "tag is not button")
    (assert (= (list-len (.-attrs elem)) 2) "attrs count is not 2")
    (assert (= (list-len (.-children elem)) 1) "children count is not 1")
    (let [(empty-elem (dom/dom-element "div" [] []))]
      (assert (= (.-tag empty-elem) "div") "empty div tag mismatch")
      (assert (= (list-len (.-attrs empty-elem)) 0) "empty div has attrs")
      (assert (= (list-len (.-children empty-elem)) 0) "empty div has children"))
    true))

(df test-dom-query [] -> Bool
  :d "Verifies recursive DOM element search by tag name"
  (let [(tree (dom/dom-element "main" [["id" "root"]]
                [(dom/dom-element "nav" []
                   [(dom/dom-element "a" [["href" "/"]] ["Home"])])
                 (dom/dom-element "section" [["class" "content"]]
                   [(dom/dom-element "article" []
                      [(dom/dom-element "h1" [] ["Headline"])
                       (dom/dom-element "p" [] ["Paragraph"])])])]))]
    (let [(found-h1 (dom/dom-query tree "h1"))]
      (assert (!= found-h1 nil) "h1 element not found")
      (assert (= (.-tag found-h1) "h1") "found tag is not h1")
      (assert (= (list-len (.-children found-h1)) 1) "h1 child count mismatch"))
    (let [(found-a (dom/dom-query tree "a"))]
      (assert (!= found-a nil) "anchor element not found")
      (assert (= (.-tag found-a) "a") "found tag is not a"))
    (let [(absent (dom/dom-query tree "footer"))]
      (assert (= absent nil) "nonexistent element did not return nil"))
    (let [(absent-nil (dom/dom-query nil "div"))]
      (assert (= absent-nil nil) "query on nil root did not return nil"))
    true))

(df test-format-vdom-node [] -> Bool
  :d "Verifies canonical HTML/XML serialization for leaf and nested elements"
  (do
    (let [(leaf (dom/dom-element "span" [] ["Hello"]))]
      (assert (= (dom/format-vdom-node leaf) "<span>Hello</span>") "leaf formatting mismatch"))
    (let [(leaf-with-attr (dom/dom-element "input" [["type" "text"] ["name" "q"]] []))]
      (assert (= (dom/format-vdom-node leaf-with-attr) "<input type=\"text\" name=\"q\"></input>") "input formatting mismatch"))
    (let [(nested (dom/dom-element "div" [["id" "main"]]
                    [(dom/dom-element "h1" [] ["Title"])
                     (dom/dom-element "p" [] ["Content"])]))]
      (assert (= (dom/format-vdom-node nested) "<div id=\"main\"><h1>Title</h1><p>Content</p></div>") "nested formatting mismatch"))
    (assert (= (dom/format-vdom-node nil) "") "nil node format should be empty string")
    (assert (= (dom/format-vdom-node "plain text") "plain text") "plain text format mismatch")
    true))

(df test-web-lib-queries [] -> Bool
  :d "Verifies web library blog data queries, category filtering, and post retrieval"
  (let [(all-posts (blog/get-all-posts))]
    (assert (= (list-len all-posts) 21) "total blog posts count should be 21")
    (let [(arch-posts (blog/filter-by-category "Architecture & Language Theory"))]
      (assert (> (list-len arch-posts) 0) "category filter returned empty list")
      (assert (<= (list-len arch-posts) 21) "category filter exceeded total"))
    (let [(flagship (blog/get-flagship-posts))]
      (assert (> (list-len flagship) 0) "flagship posts should not be empty"))
    (let [(published (blog/get-published-posts))]
      (assert (> (list-len published) 0) "published posts should not be empty"))
    (let [(asl-tag-posts (blog/filter-by-tag "AgentScript"))]
      (assert (> (list-len asl-tag-posts) 0) "tag filter for AgentScript should return posts"))
    (let [(valid-post (blog/get-post-by-slug "the-agentic-toolchain-and-native-action-loops"))]
      (assert (!= valid-post nil) "failed to retrieve canonical post by slug")
      (assert (= (.-slug valid-post) "the-agentic-toolchain-and-native-action-loops") "slug mismatch"))
    (let [(missing-post (blog/get-post-by-slug "unknown-post-slug"))]
      (assert (= missing-post nil) "unknown slug should return nil"))
    true))

(df run-tests [] -> Bool
  :d "Executes all pure ASL web utility test cases"
  (and (test-dom-element)
       (test-dom-query)
       (test-format-vdom-node)
       (test-web-lib-queries)))
