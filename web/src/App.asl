(module aslWeb/App
  :d "AgentScript Official Web Application Root Shell in pure ASL."
  :x [renderAppShell renderApp mountApp app]
  :i [(asl-text/string :a s)])

(df renderAppShell (viewContent)
  :d "App layout container with cosmic landscape background, navbar, view container, and footer."
  (s/concat
    "<div class=\"min-h-screen bg-ground text-ink flex flex-col relative w-full max-w-[100vw] overflow-x-hidden\">"
    "<div class=\"relative z-10 flex-1 flex flex-col\">"
    viewContent
    "</div>"
    "</div>"))

(df renderApp (route)
  :d "Renders the full application frame for a route"
  (renderAppShell route))

(df mountApp (route)
  :d "Mounts application directly via Vanilla JS DOM manipulation"
  "document.querySelector('.asl-app-root').innerHTML = renderApp(route)")

(df app ()
  (renderAppShell ""))
