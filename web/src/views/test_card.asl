(ns asl.web.views.playground.cards)

(df renderPlaygroundCards ()
  "<div>cards</div>")

(df test-render-cards [] -> Bool
  :d "Verifies card markup generation"
  (let [(html (renderPlaygroundCards))]
    (assert (string-contains? html "cards") "Rendered cards must contain cards text")
    (assert (string-contains? html "div") "Rendered cards must contain div container")
    true))
