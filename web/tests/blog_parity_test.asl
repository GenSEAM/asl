(module asl-web/blog-parity-test
  :d "Parity and Schema Invariant Verification for Canonical Blog Posts"
  :x [test-blog-posts-count
      test-blog-posts-slugs
      test-blog-posts-invariants
      test-blog-query-helpers
      run-tests]
  :i [(posts :a blog)])

(df test-blog-posts-count [] -> Bool
  :d "Verifies total blog post catalog contains exactly 19 articles"
  (let [(all-posts (blog/get-all-posts))]
    (assert (= (list-len all-posts) 19) "post count is not 19")
    true))

(df test-blog-posts-slugs [] -> Bool
  :d "Verifies presence of all 19 canonical slugs across catalog"
  (do
    (assert (!= (blog/get-post-by-slug "why-llms-struggle-with-python-and-rust") nil) "missing slug 1")
    (assert (!= (blog/get-post-by-slug "token-economy-and-structural-compression") nil) "missing slug 2")
    (assert (!= (blog/get-post-by-slug "from-vibe-code-to-wasm-in-0-04ms") nil) "missing slug 3")
    (assert (!= (blog/get-post-by-slug "the-token-tax-and-interface-compression") nil) "missing slug 4")
    (assert (!= (blog/get-post-by-slug "the-token-density-fallacy-and-machine-understandability") nil) "missing slug 5")
    (assert (!= (blog/get-post-by-slug "the-deterministic-agent-os") nil) "missing slug 6")
    (assert (!= (blog/get-post-by-slug "the-agent-operational-circle") nil) "missing slug 7")
    (assert (!= (blog/get-post-by-slug "the-agentic-toolchain-and-native-action-loops") nil) "missing slug 8")
    (assert (!= (blog/get-post-by-slug "inter-agent-protocols-and-wire-frames") nil) "missing slug 9")
    (assert (!= (blog/get-post-by-slug "agent-script-the-optimal-agent-language") nil) "missing slug 10")
    (assert (!= (blog/get-post-by-slug "the-agent-native-developer-cockpit") nil) "missing slug 11")
    (assert (!= (blog/get-post-by-slug "multi-dimensional-observability-for-autonomous-systems") nil) "missing slug 12")
    (assert (!= (blog/get-post-by-slug "epistemic-grounding-and-anti-hallucination-firewalls") nil) "missing slug 13")
    (assert (!= (blog/get-post-by-slug "zero-server-in-browser-agent-runtimes") nil) "missing slug 14")
    (assert (!= (blog/get-post-by-slug "cross-dialect-sql-without-hallucinations") nil) "missing slug 15")
    (assert (!= (blog/get-post-by-slug "git-native-agent-memory-and-vector-recall") nil) "missing slug 16")
    (assert (!= (blog/get-post-by-slug "kill-80-percent-agent-code-bloat") nil) "missing slug 17")
    (assert (!= (blog/get-post-by-slug "why-llms-break-on-svg-xml") nil) "missing slug 18")
    (assert (!= (blog/get-post-by-slug "universal-cross-platform-glue-without-drift") nil) "missing slug 19")
    true))

(df test-blog-posts-invariants [] -> Bool
  :d "Verifies that all posts satisfy strict schema invariants"
  (let [(posts (blog/get-all-posts))]
    (assert (> (list-len posts) 0) "posts list is empty")
    (let [(p1 (blog/get-post-by-slug "why-llms-struggle-with-python-and-rust"))]
      (assert (!= p1 nil) "p1 is nil")
      (assert (!= (.-title p1) "") "p1 title is empty")
      (assert (!= (.-date p1) "") "p1 date is empty")
      (assert (!= (.-author p1) "") "p1 author is empty")
      (assert (!= (.-category p1) "") "p1 category is empty")
      (assert (!= (.-read-time p1) "") "p1 read-time is empty")
      (assert (!= (.-excerpt p1) "") "p1 excerpt is empty")
      (assert (!= (.-content p1) "") "p1 content is empty")
      (assert (> (list-len (.-tags p1)) 0) "p1 tags empty"))
    (let [(p19 (blog/get-post-by-slug "universal-cross-platform-glue-without-drift"))]
      (assert (!= p19 nil) "p19 is nil")
      (assert (!= (.-title p19) "") "p19 title is empty")
      (assert (!= (.-date p19) "") "p19 date is empty")
      (assert (!= (.-author p19) "") "p19 author is empty")
      (assert (!= (.-category p19) "") "p19 category is empty")
      (assert (!= (.-read-time p19) "") "p19 read-time is empty")
      (assert (!= (.-excerpt p19) "") "p19 excerpt is empty")
      (assert (!= (.-content p19) "") "p19 content is empty")
      (assert (> (list-len (.-tags p19)) 0) "p19 tags empty"))
    true))

(df test-blog-query-helpers [] -> Bool
  :d "Verifies query helper functions: filters, nil lookup, and flagship retrieval"
  (do
    (assert (= (blog/get-post-by-slug "nonexistent-slug") nil) "nonexistent slug did not return nil")
    (assert (> (list-len (blog/get-flagship-posts)) 0) "flagship posts empty")
    (assert (> (list-len (blog/get-published-posts)) 0) "published posts empty")
    (assert (> (list-len (blog/filter-by-tag "Pure ASL")) 0) "filter-by-tag Pure ASL empty")
    (assert (> (list-len (blog/filter-by-category "Language Theory")) 0) "filter-by-category empty")
    true))

(df run-tests [] -> Bool
  :d "Executes all blog parity test cases"
  (and (test-blog-posts-count)
       (test-blog-posts-slugs)
       (test-blog-posts-invariants)
       (test-blog-query-helpers)))
