(module asl-web/app
  :d "Root Application Shell and Layout Router in pure AgentScript"
  :x [app-routes render-view render-app]
  :i [(core/strings :a s)
      (components/Navbar :a nav)
      (components/Footer :a foot)
      (views/HomeView :a home)
      (views/DocsView :a docs)
      (views/BlogView :a blog)
      (views/StudioView :a studio)
      (views/PlaygroundView :a play)
      (views/RoadmapView :a road)
      (views/EcosystemView :a eco)])

(df app-routes [] -> (List Str)
  :d "Returns list of registered application route paths"
  ["/" "/studio" "/playground" "/ecosystem" "/roadmap" "/docs" "/blog"])

(df render-view [(route Str)] -> Str
  :d "Resolves and renders page view by active route path"
  (if (= route "/studio")
    (studio/render-studio-view)
    (if (= route "/playground")
      (play/render-playground-view)
      (if (= route "/ecosystem")
        (eco/render-ecosystem-view)
        (if (= route "/roadmap")
          (road/render-roadmap-view)
          (if (= route "/docs")
            (docs/render-docs-view)
            (if (= route "/blog")
              (blog/render-blog-view)
              (home/render-home-view))))))))

(df render-app [(current-route Str)] -> Str
  :d "Renders root application container with navigation, content view, and footer"
  (s/concat
    "<div class=\"min-h-screen bg-ground text-ink flex flex-col relative w-full overflow-x-hidden\">"
    (s/concat
      (nav/navbar-view)
      (s/concat
        "<div class=\"relative z-10 flex-1 flex flex-col\">"
        (s/concat
          (render-view current-route)
          (s/concat
            "</div>"
            (s/concat (foot/footer-view) "</div>")))))))
