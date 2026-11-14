(module asl-ui/harness
  :x [Act press enter Sent Fault broken missing ambiguous inert mount findAll find send snapshot faultText]
  :i [(asl-ui/view :a ui)])

enum Act (press) (enter s: String)

enum Fault (broken found: (List ui/Problem)) (missing role: ui/Role label: String) (ambiguous role: ui/Role label: String) (inert id: String)

schema Sent
  code: Int64
  value: String

fn mount v: ui/View -> (Result ui/Item Fault)
  (match (ui/build v) ((ok item) (ok item)) ((err found) (err (broken found))))

fn findAll root: ui/Item role: ui/Role -> (List ui/Item)
  (filter (fn [i] (= i.role role)) (ui/items root))

fn find root: ui/Item role: ui/Role label: String -> (Result ui/Item Fault)
  (let [(hits (filter (fn [i] (= i.label label)) (findAll root role)))]
    (match (listHead hits)
      ((none) (err (missing role label)))
      ((some hit) (if (= (listLength hits) 1) (ok hit) (err (ambiguous role label))))))

fn sentBy item: ui/Item value: String -> (Result Sent Fault)
  (match item.msg ((some code) (ok (Sent :code code :value value))) ((none) (err (inert item.id))))

fn send item: ui/Item act: Act -> (Result Sent Fault)
  (match act
    ((press) (if (or (= item.role (ui/buttonRole)) (= item.role (ui/switchRole))) (sentBy item "") (err (inert item.id))))
    ((enter s) (if (= item.role (ui/textboxRole)) (sentBy item s) (err (inert item.id)))))

fn quote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn stateText state: ui/State -> String
  (match state
    ((ui/stateless) "")
    ((ui/valued s) (str " :value " (quote s)))
    ((ui/switched on) (str " :on " (if on "true" "false"))))

fn msgText msg: (Option Int64) -> String
  (match msg ((some code) (str " :msg " (stringFromInt64 code))) ((none) ""))

fn snapshotAt depth: Int64 item: ui/Item -> String
  (str (stringRepeat "  " depth) "(:" (ui/roleName item.role) " :id " (quote item.id)
    (if (stringEmpty? item.label) "" (str " :label " (quote item.label)))
    (stateText item.state) (msgText item.msg)
    (stringJoin (map (fn [kid] (str "\n" (snapshotAt (+ depth 1) kid))) item.kids) "") ")")

fn snapshot item: ui/Item -> String
  (snapshotAt 0 item)

fn faultText fault: Fault -> String
  (match fault
    ((broken found) (stringJoin (map ui/problemText found) "; "))
    ((missing role label) (str "no " (ui/roleName role) " labelled " (quote label)))
    ((ambiguous role label) (str "more than one " (ui/roleName role) " labelled " (quote label)))
    ((inert id) (str "the node " id " does not answer this act")))
