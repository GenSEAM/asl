(module aslWeb/views/testCard)

fn renderPlaygroundCards
  "<div>cards</div>"

fn testRenderCards -> Bool
  (let [(html (renderPlaygroundCards))] (assert (stringContains? html "cards") "Rendered cards must contain cards text") (assert (stringContains? html "div") "Rendered cards must contain div container") true)
