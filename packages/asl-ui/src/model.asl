(module asl-ui/model
  :x [UiNode UiStyle EventHandler SignalBinding makeStyle defaultStyle makeEvent makeBinding makeNode text column button table tableRow cell toVNode measureNode setSignalValue markSignalDirty dirtyCount]
  :i [(asl-ui/vnode :a vnode) (asl-ui/tokens :a tokens) (asl-ui/theme :a theme) (asl-ui/layout :a layout) (aslVdom/signals :a sig)])

(schema UiStyle
  (:f typography tokens/TypographyToken)
  (:f foreground theme/ColorToken)
  (:f background theme/ColorToken)
  (:f spacing Int64))

(schema EventHandler
  (:f event String)
  (:f message String))

(schema SignalBinding
  (:f signalId String))

(schema UiNode
  (:f kind String)
  (:f key String)
  (:f props (Map String String))
  (:f style UiStyle)
  (:f children (List UiNode))
  (:f events (List EventHandler))
  (:f binding (Option SignalBinding))
  (:f text String)
  (:f dirty Bool))

fn makeStyle typography: tokens/TypographyToken foreground: theme/ColorToken background: theme/ColorToken spacingStep: Int64 -> UiStyle
  (UiStyle :typography typography :foreground foreground :background background :spacing (tokens/gridStep spacingStep))

fn defaultStyle -> UiStyle
  (let [(palette (theme/defaultDarkTheme))]
    (makeStyle (tokens/getTypographyToken "body") palette.fgPrimary palette.bgSurface 1))

fn makeEvent event: String message: String -> EventHandler
  (EventHandler :event event :message message)

fn makeBinding signalId: String -> SignalBinding
  (SignalBinding :signalId signalId)

fn makeNode kind: String key: String props: (Map String String) style: UiStyle children: (List UiNode) events: (List EventHandler) binding: (Option SignalBinding) content: String -> UiNode
  (UiNode :kind kind :key key :props props :style style :children children :events events :binding binding :text content :dirty false)

fn text key: String content: String style: UiStyle -> UiNode
  (makeNode "text" key (mapEmpty) style (list) (list) (none) content)

fn column key: String props: (Map String String) style: UiStyle children: (List UiNode) -> UiNode
  (makeNode "column" key props style children (list) (none) "")

fn button key: String props: (Map String String) style: UiStyle children: (List UiNode) events: (List EventHandler) binding: (Option SignalBinding) -> UiNode
  (makeNode "button" key props style children events binding "")

fn table key: String style: UiStyle rows: (List UiNode) -> UiNode
  (makeNode "table" key (mapEmpty) style rows (list) (none) "")

fn tableRow key: String style: UiStyle cells: (List UiNode) -> UiNode
  (makeNode "row" key (mapEmpty) style cells (list) (none) "")

fn cell key: String content: String style: UiStyle -> UiNode
  (makeNode "cell" key (mapEmpty) style (list) (list) (none) content)

fn legacyTag kind: String -> String
  (cond ((= kind "column") "container") ((= kind "row") "container") ((= kind "table") "container") ((= kind "cell") "text") (else kind))

fn legacyProps node: UiNode -> (Map String String)
  (cond ((= node.kind "column") (mapSet node.props "layout" "column")) ((= node.kind "row") (mapSet node.props "layout" "row")) (else node.props))

fn toVNode node: UiNode -> vnode/VNode
  (let [(children (map (fn [(child UiNode)] -> vnode/VNode (toVNode child)) node.children))]
    (vnode/makeVNode (legacyTag node.kind) node.key node.text (legacyProps node) children 0 0 true))

fn measureNode node: UiNode constraints: layout/LayoutConstraints -> layout/Dimensions
  (layout/measure (toVNode node) constraints)

fn markSignalDirty node: UiNode signalId: String -> UiNode
  (let [(isDirty (match node.binding ((some binding) (= binding.signalId signalId)) ((none) false)))
        (children (map (fn [(child UiNode)] -> UiNode (markSignalDirty child signalId)) node.children))]
    (with node :children children :dirty isDirty))

fn setSignalValue root: UiNode signal: sig/Signal value: String -> (Pair UiNode sig/Signal)
  (pair (markSignalDirty root signal.id) (sig/signalSet signal value))

fn dirtyCount node: UiNode -> Int64
  (fold (fn [(count Int64) (child UiNode)] -> Int64 (+ count (dirtyCount child))) (if node.dirty 1 0) node.children)
