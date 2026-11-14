(module asl-ui/exampleForm
  :x [Msg setName send unknown Model code msgOf start step view]
  :i [(asl-ui/view :a ui) (asl-ui/semTokens :a t)])

enum Msg (setName s: String) (send) (unknown)

schema Model
  name: String
  sent: Bool

fn code m: Msg -> Int64
  (match m ((setName s) 1) ((send) 2) ((unknown) 0))

fn msgOf n: Int64 value: String -> Msg
  (cond ((= n 1) (setName value)) ((= n 2) (send)) (else (unknown)))

fn start -> Model
  (Model :name "" :sent false)

fn step msg: Msg m: Model -> Model
  (match msg
    ((setName s) (with (with m :name s) :sent false))
    ((send) (with m :sent (not (stringEmpty? (stringTrim m.name)))))
    ((unknown) m))

fn view m: Model -> ui/View
  (ui/stack (t/md) (ui/start) [(ui/field "Name" m.name (code (setName ""))) (ui/button "Send" (t/strong) (code (send))) (ui/when m.sent (ui/note (t/success) (str "Thanks, " m.name)))])
