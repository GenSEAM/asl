(module aslHarness/capabilities :x [Capability CapabilityLink CapabilitySelection CapabilitySelectionReceipt makeCapability makeCapabilityLink makeCapabilitySelectionReceipt countCapabilityHits countCapabilityExclusions capabilityScore calculateSpentTokens collectSelectedMarkers selectCapabilities defaultCapabilities svgPlayground svgPlaygroundScenario])

(schema CapabilityLink (:f target Str) (:f strength I64))

(schema Capability (:f marker Str) (:f principle Str) (:f scope Str) (:f appliesTo (List Str)) (:f excludes (List Str)) (:f links (List CapabilityLink)) (:f required Bool) (:f defaultLoad Bool) (:f membership I64) (:f payload Str))

(schema CapabilitySelectionReceipt (:f query Str) (:f selectedCount I64) (:f spentTokens I64) (:f budgetCeiling I64) (:f enabled Bool) (:f selectedMarkers (List Str)))

(schema CapabilitySelection (:f selected (List Capability)) (:f budget I64) (:f optional Bool) (:f svgPrompt Str) (:f receipt CapabilitySelectionReceipt))

fn makeCapabilityLink target: Str strength: I64 -> CapabilityLink
  (CapabilityLink :target target :strength strength)

fn makeCapability marker: Str principle: Str scope: Str appliesTo: (List Str) excludes: (List Str) links: (List CapabilityLink) required: Bool defaultLoad: Bool membership: I64 payload: Str -> Capability
  (Capability :marker marker :principle principle :scope scope :appliesTo appliesTo :excludes excludes :links links :required required :defaultLoad defaultLoad :membership membership :payload payload)

fn makeCapabilitySelectionReceipt query: Str selectedCount: I64 spentTokens: I64 budgetCeiling: I64 enabled: Bool selectedMarkers: (List Str) -> CapabilitySelectionReceipt
  (CapabilitySelectionReceipt :query query :selectedCount selectedCount :spentTokens spentTokens :budgetCeiling budgetCeiling :enabled enabled :selectedMarkers selectedMarkers)

fn countCapabilityHits terms: (List Str) query: Str -> I64
  (if (listEmpty? terms) 0 (let [(head (optionOr (listHead terms) "")) (tail (optionOr (listTail terms) (list)))] (if (stringContains? query head) (+ 1 (countCapabilityHits tail query)) (countCapabilityHits tail query))))

fn countCapabilityExclusions terms: (List Str) query: Str -> I64
  (if (listEmpty? terms) 0 (let [(head (optionOr (listHead terms) "")) (tail (optionOr (listTail terms) (list)))] (if (stringContains? query head) (+ 1 (countCapabilityExclusions tail query)) (countCapabilityExclusions tail query))))

fn capabilityScore cap: Capability query: Str -> I64
  (let [(exclusions (countCapabilityExclusions cap.excludes query))] (if (> exclusions 0) 0 (let [(markerHit (if (stringContains? query cap.marker) 5 0)) (taskHits (* 2 (countCapabilityHits cap.appliesTo query))) (scopeBonus (if (= cap.scope "universal") 2 0)) (requiredBonus (if cap.required 1 0))] (+ markerHit (+ taskHits (+ scopeBonus (+ requiredBonus (/ cap.membership 20))))))))

fn calculateSpentTokens caps: (List Capability) -> I64
  (if (listEmpty? caps) 0 (let [(head (optionOr (listHead caps) (makeCapability "" "" "conditional" (list) (list) (list) false false 0 ""))) (tail (optionOr (listTail caps) (list)))] (+ (stringLength head.payload) (calculateSpentTokens tail))))

fn collectSelectedMarkers caps: (List Capability) -> (List Str)
  (if (listEmpty? caps) (list) (let [(head (optionOr (listHead caps) (makeCapability "" "" "conditional" (list) (list) (list) false false 0 ""))) (tail (optionOr (listTail caps) (list)))] (listAppend (list head.marker) (collectSelectedMarkers tail))))

fn selectCapabilitiesLoop caps: (List Capability) query: Str budget: I64 spent: I64 acc: (List Capability) -> (List Capability)
  (if (listEmpty? caps) acc (let [(head (optionOr (listHead caps) (makeCapability "" "" "conditional" (list) (list) (list) false false 0 ""))) (tail (optionOr (listTail caps) (list))) (score (capabilityScore head query))] (if (and (> score 0) (<= (+ spent (stringLength head.payload)) budget)) (selectCapabilitiesLoop tail query budget (+ spent (stringLength head.payload)) (listAppend acc (list head))) (selectCapabilitiesLoop tail query budget spent acc))))

fn svgPlaygroundScenario scenario: Str -> Str
  (if (= scenario "icon") "(:svg :v \"0 0 48 48\" (:title \"System Node Icon\") (:desc \"Accessible system node vector icon\") (:rect :x 0 :y 0 :w 48 :h 48 :f \"#FFFFFF\") (:g (:circle :cx 24 :cy 24 :r 18 :f \"#0B0C0C\" :s \"#1D70B8\" :sw 2) (:txt :x 18 :y 30 :f \"#FFFFFF\" :sz 16 \"A\")))" (if (= scenario "diagram") "(:svg :v \"0 0 480 240\" (:title \"Architecture Diagram\") (:desc \"Component connectivity diagram with accessible semantic groups\") (:rect :x 0 :y 0 :w 480 :h 240 :f \"#F3F2F1\") (:g (:rect :x 40 :y 60 :w 160 :h 100 :f \"#FFFFFF\" :s \"#0B0C0C\" :sw 2) (:txt :x 60 :y 110 :f \"#0B0C0C\" :sz 18 \"Harness Engine\")) (:g (:rect :x 280 :y 60 :w 160 :h 100 :f \"#FFFFFF\" :s \"#0B0C0C\" :sw 2) (:txt :x 300 :y 110 :f \"#0B0C0C\" :sz 18 \"Capability Bus\")))" "(:svg :v \"0 0 400 300\" (:title \"Poster Layout\") (:desc \"High-impact accessible poster with focal point and contrast\") (:rect :x 0 :y 0 :w 400 :h 300 :f \"#F7F4EE\") (:rect :x 32 :y 32 :w 336 :h 236 :f \"#1E3A5F\") (:txt :x 56 :y 96 :f \"#FFFFFF\" :sz 28 \"AgentScript\") (:txt :x 56 :y 136 :f \"#D8E7F2\" :sz 16 \"Sovereign Engineering Standard\"))"))

fn svgPlayground -> Str
  (svgPlaygroundScenario "poster")

fn selectCapabilities caps: (List Capability) query: Str budget: I64 enabled: Bool -> CapabilitySelection
  (let [(selected (if enabled (selectCapabilitiesLoop caps query budget 0 (list)) (list))) (svgPrompt (if (and enabled (stringContains? query "svg")) (svgPlayground) "")) (spent (calculateSpentTokens selected)) (markers (collectSelectedMarkers selected)) (receipt (makeCapabilitySelectionReceipt query (listLength selected) spent budget enabled markers))] (CapabilitySelection :selected selected :budget budget :optional true :svgPrompt svgPrompt :receipt receipt))

fn defaultCapabilities -> (List Capability)
  (list (makeCapability "visualHierarchy" "Establish one focal point and a readable order." "universal" (list "poster" "logo" "diagram" "svg") (list "denseDataTable") (list (makeCapabilityLink "contrast" 90) (makeCapabilityLink "composition" 80)) true true 100 "Set focal point, hierarchy and scale before decoration.") (makeCapability "contrast" "Keep text and essential marks distinguishable from their background." "universal" (list "svg" "poster" "accessibility") (list "incidentalDecoration") (list (makeCapabilityLink "visualHierarchy" 90) (makeCapabilityLink "functionalColour" 85)) true true 100 "Check text contrast against background: WCAG AA normal text 4.5:1, non-text 3.0:1.") (makeCapability "composition" "Use spacing, alignment and repetition to make relationships legible." "conditional" (list "svg" "poster" "illustration") (list "rawDataExport") (list (makeCapabilityLink "visualHierarchy" 80) (makeCapabilityLink "spacingScale" 75)) false true 80 "Group related elements, align edges and leave deliberate negative space.") (makeCapability "viewBox" "Define a stable SVG user-space rectangle for responsive mapping." "conditional" (list "svg" "icon" "diagram") (list "rasterPhoto") (list (makeCapabilityLink "contrast" 40) (makeCapabilityLink "responsiveLayout" 90)) true true 100 "Specify a four-number viewBox (min-x min-y w h) and keep width and height semantics explicit.") (makeCapability "evidenceLed" "Tie a visual choice to audience, task and observable evidence." "universal" (list "poster" "dashboard" "svg") (list "pureDecoration") (list (makeCapabilityLink "visualHierarchy" 60) (makeCapabilityLink "functionalColour" 70)) true true 90 "State audience, task and evidence before choosing style or colour.") (makeCapability "responsiveLayout" "Ensure layout scales across viewports and zoom levels without clipping." "conditional" (list "svg" "poster" "diagram") (list "fixedPixelCanvas") (list (makeCapabilityLink "viewBox" 90) (makeCapabilityLink "composition" 70)) true true 95 "Scale proportionally up to 200 percent zoom without clipping or horizontal overflow.") (makeCapability "accessibleText" "Provide readable typography with accessible names and descriptions." "universal" (list "svg" "poster" "accessibility" "diagram") (list "unlabelledVector") (list (makeCapabilityLink "contrast" 95) (makeCapabilityLink "visualHierarchy" 80)) true true 95 "Supply non-empty title and desc for informative graphics, aria-hidden for decorative.") (makeCapability "functionalColour" "Use colour purposefully with clear hierarchy and redundant non-colour cues." "conditional" (list "svg" "poster" "diagram" "dashboard") (list "monochromeTerminal") (list (makeCapabilityLink "contrast" 85) (makeCapabilityLink "evidenceLed" 70)) true true 85 "Never convey critical state by color alone, pair colors with shapes, icons or text.") (makeCapability "spacingScale" "Apply harmonic spacing increments for visual rhythm and grouping." "conditional" (list "poster" "diagram" "svg") (list "arbitraryPixels") (list (makeCapabilityLink "composition" 75) (makeCapabilityLink "visualHierarchy" 65)) false true 80 "Use 4/8/12/16/24/32/40/48/64 pixel harmonic scale for margins, padding and gutters.") (makeCapability "groupSemantics" "Organize multi-part vector elements into semantic container groups." "conditional" (list "svg" "diagram" "icon") (list "flatPrimitives") (list (makeCapabilityLink "composition" 70) (makeCapabilityLink "accessibleText" 60)) false true 85 "Group related shapes in semantic g containers with transform and style isolation."))
