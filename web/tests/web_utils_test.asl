(module aslWeb/webUtilsTest
  :d "Verification suite for pure ASL DOM and web utilities"
  :x [testDomElement
      testDomQuery
      testFormatVdomNode
      testWebLibQueries
      runTests]
  :i [(aslWeb/dom :a dom)
      (aslWeb/blogPosts :a blog)])

(df testDomElement [] -> Bool
  :d "Verifies DOM element construction and field access"
  (let [(elem (dom/domElement "button" [["id" "submit-btn"] ["class" "primary"]] ["Click Me"]))]
    (assert (!= elem nil) "element is nil")
    (assert (= (.-tag elem) "button") "tag is not button")
    (assert (= (listLen (.-attrs elem)) 2) "attrs count is not 2")
    (assert (= (listLen (.-children elem)) 1) "children count is not 1")
    (let [(emptyElem (dom/domElement "div" [] []))]
      (assert (= (.-tag emptyElem) "div") "empty div tag mismatch")
      (assert (= (listLen (.-attrs emptyElem)) 0) "empty div has attrs")
      (assert (= (listLen (.-children emptyElem)) 0) "empty div has children"))
    true))

(df testDomQuery [] -> Bool
  :d "Verifies recursive DOM element search by tag name"
  (let [(tree (dom/domElement "main" [["id" "root"]]
                [(dom/domElement "nav" []
                   [(dom/domElement "a" [["href" "/"]] ["Home"])])
                 (dom/domElement "section" [["class" "content"]]
                   [(dom/domElement "article" []
                      [(dom/domElement "h1" [] ["Headline"])
                       (dom/domElement "p" [] ["Paragraph"])])])]))]
    (let [(foundH1 (dom/domQuery tree "h1"))]
      (assert (!= foundH1 nil) "h1 element not found")
      (assert (= (.-tag foundH1) "h1") "found tag is not h1")
      (assert (= (listLen (.-children foundH1)) 1) "h1 child count mismatch"))
    (let [(foundA (dom/domQuery tree "a"))]
      (assert (!= foundA nil) "anchor element not found")
      (assert (= (.-tag foundA) "a") "found tag is not a"))
    (let [(absent (dom/domQuery tree "footer"))]
      (assert (= absent nil) "nonexistent element did not return nil"))
    (let [(absentNil (dom/domQuery nil "div"))]
      (assert (= absentNil nil) "query on nil root did not return nil"))
    true))

(df testFormatVdomNode [] -> Bool
  :d "Verifies canonical HTML/XML serialization for leaf and nested elements"
  (do
    (let [(leaf (dom/domElement "span" [] ["Hello"]))]
      (assert (= (dom/formatVdomNode leaf) "<span>Hello</span>") "leaf formatting mismatch"))
    (let [(leafWithAttr (dom/domElement "input" [["type" "text"] ["name" "q"]] []))]
      (assert (= (dom/formatVdomNode leafWithAttr) "<input type=\"text\" name=\"q\"></input>") "input formatting mismatch"))
    (let [(nested (dom/domElement "div" [["id" "main"]]
                    [(dom/domElement "h1" [] ["Title"])
                     (dom/domElement "p" [] ["Content"])]))]
      (assert (= (dom/formatVdomNode nested) "<div id=\"main\"><h1>Title</h1><p>Content</p></div>") "nested formatting mismatch"))
    (assert (= (dom/formatVdomNode nil) "") "nil node format should be empty string")
    (assert (= (dom/formatVdomNode "plain text") "plain text") "plain text format mismatch")
    true))

(df testWebLibQueries [] -> Bool
  :d "Verifies web library blog data queries, category filtering, and post retrieval"
  (let [(allPosts (blog/getAllPosts))]
    (assert (= (listLen allPosts) 23) "total blog posts count should be 23")
    (let [(archPosts (blog/filterByCategory "Architecture & Language Theory"))]
      (assert (> (listLen archPosts) 0) "category filter returned empty list")
      (assert (<= (listLen archPosts) 23) "category filter exceeded total"))
    (let [(flagship (blog/getFlagshipPosts))]
      (assert (> (listLen flagship) 0) "flagship posts should not be empty"))
    (let [(published (blog/getPublishedPosts))]
      (assert (> (listLen published) 0) "published posts should not be empty"))
    (let [(aslTagPosts (blog/filterByTag "AgentScript"))]
      (assert (> (listLen aslTagPosts) 0) "tag filter for AgentScript should return posts"))
    (let [(validPost (blog/getPostBySlug "the-agentic-toolchain-and-native-action-loops"))]
      (assert (!= validPost nil) "failed to retrieve canonical post by slug")
      (assert (= (.-slug validPost) "the-agentic-toolchain-and-native-action-loops") "slug mismatch"))
    (let [(missingPost (blog/getPostBySlug "unknown-post-slug"))]
      (assert (= missingPost nil) "unknown slug should return nil"))
    true))

(df runTests [] -> Bool
  :d "Executes all pure ASL web utility test cases"
  (and (testDomElement)
       (testDomQuery)
       (testFormatVdomNode)
       (testWebLibQueries)))
