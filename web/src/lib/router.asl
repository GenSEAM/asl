(module asl-web/router
  :d "Declarative Client-Side Router for AgentScript Web in pure ASL"
  :x [Route app-routes match-route is-valid-route?]
  :i [(core/strings :a s)])

(dfe Route
  (:c route-home [] "Landing home view: /")
  (:c route-studio [] "Tri-Studio view: /studio")
  (:c route-playground [] "Playground view: /playground")
  (:c route-ecosystem [] "Ecosystem view: /ecosystem")
  (:c route-roadmap [] "Roadmap view: /roadmap")
  (:c route-docs [] "Documentation view: /docs")
  (:c route-blog [] "Blog view: /blog"))

(df app-routes [] -> (List Str)
  :d "Returns all recognized top-level route paths"
  ["/" "/studio" "/playground" "/ecosystem" "/roadmap" "/docs" "/blog"])

(df is-valid-route? [(path Str)] -> Bool
  :d "Checks whether a path is a recognized application route"
  (or (= path "/")
      (or (= path "/studio")
          (or (= path "/playground")
              (or (= path "/ecosystem")
                  (or (= path "/roadmap")
                      (or (= path "/docs")
                          (or (= path "/blog")
                              (s/starts-with? path "/blog/")))))))))

(df match-route [(path Str)] -> Str
  :d "Normalizes and resolves route target"
  (if (is-valid-route? path)
    path
    "/"))
