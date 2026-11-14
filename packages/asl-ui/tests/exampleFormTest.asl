(module asl-ui/tests/exampleFormTest
  :x [runTests]
  :i [(asl-ui/exampleForm :a ex) (asl-ui/harness :a hn) (asl-ui/lowerHtml :a low) (asl-ui/view :a ui) (asl-ui/semTokens :a t) (asl-html/html :a h)])

fn onClick m: ex/Msg -> h/Attr
  (h/data "msg" (stringFromInt64 (ex/code m)))

fn onInput m: ex/Msg -> h/Attr
  (h/data "msg-input" (stringFromInt64 (ex/code m)))

fn legacyView m: ex/Model -> h/Node
  (h/form [(h/cls "form")] [(h/label [(h/attr "for" "name")] [(h/text "Name")]) (h/input [(h/id "name") (h/typeAttr "text") (h/valueAttr m.name) (onInput (ex/setName ""))]) (h/button [(onClick (ex/send))] [(h/text "Send")]) (if m.sent (h/p [(h/role "status")] [(h/text (str "Thanks, " m.name))]) (h/frag []))])

fn act m: ex/Model role: ui/Role label: String what: hn/Act -> ex/Model
  (match (hn/mount (ex/view m))
    ((err fault) m)
    ((ok root)
      (match (hn/find root role label)
        ((err fault) m)
        ((ok item) (match (hn/send item what) ((ok sent) (ex/step (ex/msgOf sent.code sent.value) m)) ((err fault) m))))))

fn notes m: ex/Model -> (List String)
  (match (hn/mount (ex/view m)) ((ok root) (map (fn [i] i.label) (hn/findAll root (ui/statusRole)))) ((err fault) ["view is broken"]))

fn pageHtml m: ex/Model -> String
  (match (low/page (t/defaultTheme) (ex/view m)) ((ok node) (h/render node)) ((err found) "view is broken"))

fn runTests -> Bool
  (let [(typed (act (ex/start) (ui/textboxRole) "Name" (hn/enter "Ada")))
        (sent (act typed (ui/buttonRole) "Send" (hn/press)))
        (form "<div id=\"group0\" class=\"ui-group ui-stack ui-gap-md ui-align-start\"><div class=\"ui-field\"><label for=\"group0-textbox-name\" class=\"ui-type-label\">Name</label><input id=\"group0-textbox-name\" type=\"text\" value=\"Ada\" class=\"ui-input ui-type-body\" data-msg-input=\"1\"/></div><button type=\"button\" id=\"group0-button-send\" class=\"ui-button ui-emphasis-strong ui-type-label\" data-msg=\"2\">Send</button>")]
    (assert (= (notes (ex/start)) []) "the form starts without a message")
    (assert (= typed (ex/Model :name "Ada" :sent false)) "typing into the Name field reaches the model through its message")
    (assert (= (notes typed) []) "typing alone shows no message")
    (assert (= sent (ex/Model :name "Ada" :sent true)) "pressing Send marks the model sent")
    (assert (= (notes sent) ["Thanks, Ada"]) "after Send the status note greets the typed name")
    (assert (= (notes (act (ex/start) (ui/buttonRole) "Send" (hn/press))) []) "Send with an empty name shows no message")
    (assert (= (notes (act (act (ex/start) (ui/textboxRole) "Name" (hn/enter "  ")) (ui/buttonRole) "Send" (hn/press))) []) "Send with a blank name shows no message")
    (assert (= (notes (act sent (ui/textboxRole) "Name" (hn/enter "Bo"))) []) "typing after Send clears the message")
    (assert (= (ex/step (ex/unknown) sent) sent) "an unknown message keeps the model")
    (assert (= (map (fn [n] (ex/msgOf n "x")) [1 2 7]) [(ex/setName "x") (ex/send) (ex/unknown)]) "codes decode to messages, the field value travels as the argument")
    (assert (= (map ex/code [(ex/setName "x") (ex/send) (ex/unknown)]) [1 2 0]) "messages encode to their codes")
    (assert (stringEndsWith? (pageHtml typed) (str "</style>" form "</div>")) "the typed form lowers to a labelled input and a wired button")
    (assert (stringEndsWith? (pageHtml sent) (str "</style>" form "<p id=\"group0-status2\" role=\"status\" class=\"ui-note ui-tone-success ui-type-body\">Thanks, Ada</p></div>")) "the sent form adds a status note and keeps every other node unchanged")
    (assert (= (h/render (legacyView sent)) "<form class=\"form\"><label for=\"name\">Name</label><input id=\"name\" type=\"text\" value=\"Ada\" data-msg-input=\"1\"/><button type=\"button\" data-msg=\"2\">Send</button><p role=\"status\">Thanks, Ada</p></form>") "the asl-html form of the comparison renders the same widgets")
    true)
