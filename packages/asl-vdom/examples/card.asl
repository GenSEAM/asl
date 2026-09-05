(module asl-vdom/examples/card
  :d "Clean, idiomatic ASL Card component transpiling to React 19 TSX"
  :x [CardProps card render-card]
  :i [(vdom :a v) (html :a h)])

(dfs CardProps
  (:f title String "Card primary title")
  (:f description String "Card body summary description")
  (:f badge String "Status badge label")
  (:f action-label String "Call to action button label"))

(df card [(props CardProps)] -> v/VNode
  :d "Renders an accessible Card container element with header, body, and footer"
  (h/div (h/attrs-of (list (h/attr "class" "card") (h/attr "role" "region")))
    (list
      (h/div (h/attrs-of (list (h/attr "class" "card-header")))
        (list
          (h/span (h/attrs-of (list (h/attr "class" "badge")))
            (list (v/text (.-badge props))))
          (h/h2 (h/attrs-of (list (h/attr "class" "card-title")))
            (list (v/text (.-title props))))))
      (h/div (h/attrs-of (list (h/attr "class" "card-body")))
        (list
          (h/p (h/attrs-of (list (h/attr "class" "card-description")))
            (list (v/text (.-description props))))))
      (h/div (h/attrs-of (list (h/attr "class" "card-footer")))
        (list
          (h/button (h/attrs-of (list (h/attr "class" "btn btn-primary") (h/attr "type" "button")))
            (list (v/text (.-action-label props)))))))))

(df render-card [(title String) (desc String) (badge String) (action String)] -> v/VNode
  :d "Constructs and renders a card with explicit arguments"
  (card (CardProps
          :title title
          :description desc
          :badge badge
          :action-label action)))
