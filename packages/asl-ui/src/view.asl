(module asl-ui/view
  :x [View text heading note button field toggle link image stack row keyed absent when
      Level top section sub Align start center end stretch
      Role staticRole headingRole statusRole buttonRole textboxRole switchRole linkRole imageRole groupRole
      State stateless valued switched Item Problem clash unnamed
      resolve problems build items roleName interactive? slug problemText]
  :i [(asl-ui/semTokens :a t)])

enum Level (top) (section) (sub)

enum Align (start) (center) (end) (stretch)

enum View
  (text s: String)
  (heading level: Level s: String)
  (note tone: t/Tone s: String)
  (button label: String emphasis: t/Emphasis msg: Int64)
  (field label: String value: String msg: Int64)
  (toggle label: String on: Bool msg: Int64)
  (link label: String url: String)
  (image label: String url: String)
  (stack gap: t/Space align: Align kids: (List View))
  (row gap: t/Space align: Align kids: (List View))
  (keyed key: String v: View)
  (absent)

enum Role (staticRole) (headingRole) (statusRole) (buttonRole) (textboxRole) (switchRole) (linkRole) (imageRole) (groupRole)

enum State (stateless) (valued s: String) (switched on: Bool)

enum Problem (clash id: String) (unnamed id: String role: Role)

schema Item
  id: String
  role: Role
  label: String
  state: State
  msg: (Option Int64)
  view: View
  kids: (List Item)

schema Facts
  role: Role
  label: String
  state: State
  msg: (Option Int64)
  kids: (List View)

fn when show: Bool v: View -> View
  (if show v (absent))

fn roleName r: Role -> String
  (match r ((staticRole) "text") ((headingRole) "heading") ((statusRole) "status") ((buttonRole) "button") ((textboxRole) "textbox") ((switchRole) "switch") ((linkRole) "link") ((imageRole) "image") ((groupRole) "group"))

fn interactive? r: Role -> Bool
  (match r ((buttonRole) true) ((textboxRole) true) ((switchRole) true) ((linkRole) true) ((staticRole) false) ((headingRole) false) ((statusRole) false) ((imageRole) false) ((groupRole) false))

fn slugChar ch: String -> String
  (let [(code (charCode ch))]
    (if (or (>= code 128) (or (and (>= code 97) (<= code 122)) (and (>= code 48) (<= code 57)))) ch "-"))

fn slug s: String -> String
  (stringJoin (map slugChar (stringChars (stringLower (stringTrim s)))) "")

fn leaf role: Role label: String state: State msg: (Option Int64) -> Facts
  (Facts :role role :label label :state state :msg msg :kids [])

fn facts v: View -> Facts
  (match v
    ((text s) (leaf (staticRole) s (stateless) (none)))
    ((heading level s) (leaf (headingRole) s (stateless) (none)))
    ((note tone s) (leaf (statusRole) s (stateless) (none)))
    ((button label emphasis msg) (leaf (buttonRole) label (stateless) (some msg)))
    ((field label value msg) (leaf (textboxRole) label (valued value) (some msg)))
    ((toggle label on msg) (leaf (switchRole) label (switched on) (some msg)))
    ((link label url) (leaf (linkRole) label (valued url) (none)))
    ((image label url) (leaf (imageRole) label (valued url) (none)))
    ((stack gap align kids) (Facts :role (groupRole) :label "" :state (stateless) :msg (none) :kids kids))
    ((row gap align kids) (Facts :role (groupRole) :label "" :state (stateless) :msg (none) :kids kids))
    ((keyed key inner) (facts inner))
    ((absent) (leaf (groupRole) "" (stateless) (none))))

fn bare v: View -> View
  (match v ((keyed key inner) (bare inner)) ((text s) v) ((heading level s) v) ((note tone s) v) ((button label emphasis msg) v) ((field label value msg) v) ((toggle label on msg) v) ((link label url) v) ((image label url) v) ((stack gap align kids) v) ((row gap align kids) v) ((absent) v))

fn segment v: View f: Facts slot: Int64 -> String
  (match v
    ((keyed key inner) (slug key))
    ((text s) (str "text" (stringFromInt64 slot)))
    ((heading level s) (str "heading" (stringFromInt64 slot)))
    ((note tone s) (str "status" (stringFromInt64 slot)))
    ((image label url) (str "image" (stringFromInt64 slot)))
    ((stack gap align kids) (str "group" (stringFromInt64 slot)))
    ((row gap align kids) (str "group" (stringFromInt64 slot)))
    ((absent) (str "absent" (stringFromInt64 slot)))
    ((button label emphasis msg) (str (roleName f.role) "-" (slug f.label)))
    ((field label value msg) (str (roleName f.role) "-" (slug f.label)))
    ((toggle label on msg) (str (roleName f.role) "-" (slug f.label)))
    ((link label url) (str (roleName f.role) "-" (slug f.label))))

fn present? v: View -> Bool
  (not (= (bare v) (absent)))

fn resolveAt path: String slot: Int64 v: View -> Item
  (let [(f (facts v))
        (seg (segment v f slot))
        (id (if (stringEmpty? path) seg (str path "-" seg)))]
    (Item :id id :role f.role :label f.label :state f.state :msg f.msg :view (bare v)
      :kids (map (fn [p] (resolveAt id (pairFirst p) (pairSecond p))) (filter (fn [p] (present? (pairSecond p))) (enumerate f.kids)))))

fn resolve v: View -> Item
  (resolveAt "" 0 v)

fn items item: Item -> (List Item)
  (cons item (listFlatMap items item.kids))

fn repeated sorted: (List String) -> (List String)
  (fold (fn [acc p] (if (and (= (pairFirst p) (pairSecond p)) (not (listContains? acc (pairFirst p)))) (listAppend acc [(pairFirst p)]) acc)) [] (zip sorted (listDrop sorted 1)))

fn problems item: Item -> (List Problem)
  (let [(all (items item))]
    (listAppend
      (map (fn [id] (clash id)) (repeated (listSort (map (fn [i] i.id) all))))
      (map (fn [i] (unnamed i.id i.role)) (filter (fn [i] (and (interactive? i.role) (stringEmpty? (stringTrim i.label)))) all))))

fn build v: View -> (Result Item (List Problem))
  (let [(item (resolve v)) (found (problems item))]
    (if (listEmpty? found) (ok item) (err found)))

fn problemText p: Problem -> String
  (match p
    ((clash id) (str "two nodes share the id " id "; wrap one in (keyed \"name\" ...)"))
    ((unnamed id role) (str "the " (roleName role) " at " id " has no label")))
