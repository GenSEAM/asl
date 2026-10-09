(module aslVdom/examples/card :x [CardProps card renderCard] :i [(aslVdom/vdom :a v) (aslVdom/html :a h)])

(schema CardProps (:f title String) (:f description String) (:f badge String) (:f actionLabel String))

fn card props: CardProps -> v/VNode
  (h/div (h/attrsOf (list (h/attr "class" "card") (h/attr "role" "region"))) (list (h/div (h/attrsOf (list (h/attr "class" "card-header"))) (list (h/span (h/attrsOf (list (h/attr "class" "badge"))) (list (v/text props.badge))) (h/h2 (h/attrsOf (list (h/attr "class" "card-title"))) (list (v/text props.title))))) (h/div (h/attrsOf (list (h/attr "class" "card-body"))) (list (h/p (h/attrsOf (list (h/attr "class" "card-description"))) (list (v/text props.description))))) (h/div (h/attrsOf (list (h/attr "class" "card-footer"))) (list (h/button (h/attrsOf (list (h/attr "class" "btn btn-primary") (h/attr "type" "button"))) (list (v/text props.actionLabel)))))))

fn renderCard title: String desc: String badge: String action: String -> v/VNode
  (card (CardProps :title title :description desc :badge badge :actionLabel action))
