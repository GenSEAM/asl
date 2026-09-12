(module asl-web/App
  :d "AgentScript Official Web Application Root Shell in pure ASL."
  :x [render-app-shell app]
  :i [(asl-text/string :a s)])

(df render-app-shell (view-content)
  :d "App layout container with cosmic landscape background, navbar, view container, and footer."
  (s/concat
    "<div class=\"min-h-screen bg-ground text-ink flex flex-col relative w-full max-w-[100vw] overflow-x-hidden\">"
    "<div class=\"relative z-10 flex-1 flex flex-col\">"
    view-content
    "</div>"
    "</div>"))

(df app ()
  (render-app-shell ""))
