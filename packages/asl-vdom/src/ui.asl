(module aslVdom/ui :x [ButtonProps CardProps ListProps ModalProps uiButton uiCard uiList uiModal isValidButtonVariant? isValidButtonSize? isValidButtonProps? isAccessibleModal? isValidListProps? buttonBgToken buttonColorToken buttonPaddingToken buttonRadiusToken listSpacingToken] :i [(aslVdom/vdom :a v) (aslVdom/theme :a t)])

(schema ButtonProps (:f label String) (:f variant String) (:f size String) (:f action String) (:f disabled Bool))

(schema CardProps (:f title String) (:f subtitle String) (:f content v/VNode) (:f footer (Option v/VNode)))

(schema ListProps (:f items (List v/VNode)) (:f direction String) (:f spacing String) (:f divided Bool))

(schema ModalProps (:f title String) (:f isOpen Bool) (:f content v/VNode) (:f onCloseAction String) (:f confirmAction String))

fn isValidButtonVariant? variant: String -> Bool
  (or (= variant "primary") (or (= variant "secondary") (or (= variant "outline") (= variant "ghost"))))

fn isValidButtonSize? size: String -> Bool
  (or (= size "sm") (or (= size "md") (= size "lg")))

fn isValidButtonProps? props: ButtonProps -> Bool
  (and (not (stringEmpty? props.label)) (and (isValidButtonVariant? props.variant) (isValidButtonSize? props.size)))

fn buttonBgToken variant: String -> String
  (cond ((= variant "primary") "var(--color-primary)") ((= variant "secondary") "var(--color-surface)") ((= variant "outline") "transparent") ((= variant "ghost") "transparent") (else "var(--color-primary)"))

fn buttonColorToken variant: String -> String
  (cond ((= variant "primary") "var(--color-background)") ((= variant "secondary") "var(--color-text)") ((= variant "outline") "var(--color-primary)") ((= variant "ghost") "var(--color-text)") (else "var(--color-background)"))

fn buttonPaddingToken size: String -> String
  (cond ((= size "sm") "var(--spacing-sm)") ((= size "md") "var(--spacing-md)") ((= size "lg") "var(--spacing-lg)") (else "var(--spacing-md)"))

fn buttonRadiusToken size: String -> String
  (cond ((= size "sm") "var(--radius-sm)") ((= size "md") "var(--radius-md)") ((= size "lg") "var(--radius-lg)") (else "var(--radius-md)"))

fn uiButton props: ButtonProps -> v/VNode
  (if (not (isValidButtonProps? props)) (v/textNode "") (let [(variant props.variant) (size props.size) (action props.action) (disabled props.disabled) (bg (buttonBgToken variant)) (fg (buttonColorToken variant)) (pad (buttonPaddingToken size)) (rad (buttonRadiusToken size)) (cls (str "ui-button ui-button-" variant " ui-button-" size)) (m0 (mapSet (mapEmpty) "class" cls)) (m1 (mapSet m0 "role" "button")) (m2 (mapSet m1 "type" "button")) (m3 (mapSet m2 "token-bg" bg)) (m4 (mapSet m3 "token-color" fg)) (m5 (mapSet m4 "token-padding" pad)) (m6 (mapSet m5 "token-radius" rad)) (m7 (if (stringEmpty? action) m6 (mapSet m6 "onclick" action))) (m8 (if disabled (mapSet (mapSet m7 "disabled" "true") "aria-disabled" "true") m7))] (v/elem "button" m8 (list (v/text props.label)))))

fn uiCard props: CardProps -> v/VNode
  (let [(title props.title) (subtitle props.subtitle) (content props.content) (titleNode (v/elem "h3" (mapSet (mapSet (mapEmpty) "class" "ui-card-title") "token-color" "var(--color-text)") (list (v/text title)))) (headerChildren (if (stringEmpty? subtitle) (list titleNode) (list titleNode (v/elem "p" (mapSet (mapSet (mapEmpty) "class" "ui-card-subtitle") "token-color" "var(--color-text)") (list (v/text subtitle)))))) (headerNode (v/elem "div" (mapSet (mapEmpty) "class" "ui-card-header") headerChildren)) (contentNode (v/elem "div" (mapSet (mapEmpty) "class" "ui-card-content") (list content))) (cardChildren (mt props.footer ((some fNode) (list headerNode contentNode (v/elem "div" (mapSet (mapEmpty) "class" "ui-card-footer") (list fNode)))) ((none) (list headerNode contentNode)))) (cardAttrs (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "class" "ui-card") "role" "region") "token-bg" "var(--color-surface)") "token-color" "var(--color-text)") "token-radius" "var(--radius-md)") "token-padding" "var(--spacing-md)") "token-border" "var(--color-border)"))] (v/elem "div" cardAttrs cardChildren))

fn listSpacingToken spacing: String -> String
  (cond ((= spacing "xs") "var(--spacing-xs)") ((= spacing "sm") "var(--spacing-sm)") ((= spacing "md") "var(--spacing-md)") ((= spacing "lg") "var(--spacing-lg)") ((= spacing "xl") "var(--spacing-xl)") (else "var(--spacing-md)"))

fn isValidListProps? props: ListProps -> Bool
  (let [(d props.direction) (s props.spacing)] (and (or (= d "vertical") (= d "horizontal")) (or (= s "xs") (or (= s "sm") (or (= s "md") (or (= s "lg") (= s "xl")))))))

fn interleaveDividers items: (List v/VNode) divider: v/VNode -> (List v/VNode)
  (if (<= (listLength items) 1) items (let [(head (mt (listHead items) ((some h) h) ((none) (v/textNode "")))) (rest (optionOr (listTail items) (list)))] (cons head (cons divider (interleaveDividers rest divider)))))

fn uiList props: ListProps -> v/VNode
  (let [(dir (if (= props.direction "horizontal") "horizontal" "vertical")) (spacing props.spacing) (divided props.divided) (items props.items) (spToken (listSpacingToken spacing)) (dividerNode (v/elem "hr" (mapSet (mapSet (mapEmpty) "class" "ui-list-divider") "token-color" "var(--color-border)") (list))) (children (if divided (interleaveDividers items dividerNode) items)) (cls (str "ui-list ui-list-" dir)) (attrs (mapSet (mapSet (mapSet (mapSet (mapEmpty) "class" cls) "role" "list") "token-spacing" spToken) "token-padding" spToken))] (v/elem "div" attrs children))

fn isAccessibleModal? node: v/VNode -> Bool
  (let [(attrs (v/vnodeAttrs node)) (role (mt (mapGet attrs "role") ((some r) r) ((none) ""))) (ariaModal (mt (mapGet attrs "aria-modal") ((some m) m) ((none) "")))] (and (= role "dialog") (= ariaModal "true")))

fn uiModal props: ModalProps -> v/VNode
  (if (not props.isOpen) (v/textNode "") (let [(title props.title) (content props.content) (onClose props.onCloseAction) (confirm props.confirmAction) (closeBtn (v/elem "button" (mapSet (mapSet (mapSet (mapSet (mapEmpty) "class" "ui-modal-close-btn") "type" "button") "aria-label" "Close") "onclick" onClose) (list (v/text "×")))) (headerNode (v/elem "div" (mapSet (mapEmpty) "class" "ui-modal-header") (list (v/elem "h3" (mapSet (mapSet (mapEmpty) "class" "ui-modal-title") "token-color" "var(--color-text)") (list (v/text title))) closeBtn))) (contentNode (v/elem "div" (mapSet (mapEmpty) "class" "ui-modal-content") (list content))) (hasConfirm (not (stringEmpty? confirm))) (footerNode (if hasConfirm (let [(confirmBtn (uiButton (ButtonProps :label "Confirm" :variant "primary" :size "md" :action confirm :disabled false))) (cancelBtn (uiButton (ButtonProps :label "Cancel" :variant "ghost" :size "md" :action onClose :disabled false)))] (v/elem "div" (mapSet (mapEmpty) "class" "ui-modal-footer") (list cancelBtn confirmBtn))) (v/elem "div" (mapSet (mapEmpty) "class" "ui-modal-footer") (list (uiButton (ButtonProps :label "Close" :variant "ghost" :size "md" :action onClose :disabled false)))))) (dialogChildren (list headerNode contentNode footerNode)) (dialogAttrs (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "class" "ui-modal-dialog") "role" "dialog") "aria-modal" "true") "token-bg" "var(--color-surface)") "token-color" "var(--color-text)") "token-radius" "var(--radius-lg)") "token-padding" "var(--spacing-lg)")) (dialogNode (v/elem "div" dialogAttrs dialogChildren)) (modalAttrs (mapSet (mapSet (mapSet (mapSet (mapEmpty) "class" "ui-modal-backdrop") "role" "dialog") "aria-modal" "true") "token-bg" "rgba(0, 0, 0, 0.5)"))] (v/elem "div" modalAttrs (list dialogNode))))
