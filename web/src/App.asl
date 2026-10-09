(module aslWeb/App :x [renderAppShell renderApp mountApp app] :i [(asl-text/string :a s)])

fn renderAppShell viewContent: Any
  (str "<div class=\"min-h-screen bg-ground text-ink flex flex-col relative w-full max-w-[100vw] overflow-x-hidden\">" "<div class=\"relative z-10 flex-1 flex flex-col\">" viewContent "</div>" "</div>")

fn renderApp route: Any
  (renderAppShell route)

fn mountApp route: Any
  "document.querySelector('.asl-app-root').innerHTML = renderApp(route)"

fn app
  (renderAppShell "")
