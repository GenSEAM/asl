(module asl-ui/semTokens
  :x [Space xs sm md lg xl Tone neutral primary success warn danger TextRole body caption label title display mono
      Radius sharp soft pill Emphasis strong normal weak Length dp Color rgb TextStyle ToneColor
      SpaceScale RadiusScale Palette TextScale Theme ColorRole surface ink inkWeak border linkInk selection focusRing fill onFill
      defaultTheme spaceOf radiusOf textOf colorOf spaceName radiusName textName toneName emphasisName
      allSpaces allRadii allTextRoles allTones luminance contrast]
  :i [])

enum Space (xs) (sm) (md) (lg) (xl)

enum Tone (neutral) (primary) (success) (warn) (danger)

enum TextRole (body) (caption) (label) (title) (display) (mono)

enum Radius (sharp) (soft) (pill)

enum Emphasis (strong) (normal) (weak)

enum Length (dp n: Int64)

enum Color (rgb r: Int64 g: Int64 b: Int64)

enum ColorRole (surface) (ink) (inkWeak) (border) (linkInk) (selection) (focusRing) (fill t: Tone) (onFill t: Tone)

schema TextStyle
  size: Length
  line: Length
  weight: Int64
  fixedPitch: Bool

schema ToneColor
  fill: Color
  onFill: Color

schema SpaceScale
  xs: Length
  sm: Length
  md: Length
  lg: Length
  xl: Length

schema RadiusScale
  sharp: Length
  soft: Length
  pill: Length

schema Palette
  surface: Color
  ink: Color
  inkWeak: Color
  border: Color
  linkInk: Color
  selection: Color
  focusRing: Color
  neutral: ToneColor
  primary: ToneColor
  success: ToneColor
  warn: ToneColor
  danger: ToneColor

schema TextScale
  body: TextStyle
  caption: TextStyle
  label: TextStyle
  title: TextStyle
  display: TextStyle
  mono: TextStyle

schema Theme
  name: String
  stroke: Length
  space: SpaceScale
  radius: RadiusScale
  palette: Palette
  text: TextScale

fn defaultTheme -> Theme
  (Theme :name "light" :stroke (dp 1)
    :space (SpaceScale :xs (dp 4) :sm (dp 8) :md (dp 16) :lg (dp 24) :xl (dp 40))
    :radius (RadiusScale :sharp (dp 0) :soft (dp 6) :pill (dp 999))
    :palette (Palette :surface (rgb 255 255 255) :ink (rgb 26 26 26) :inkWeak (rgb 89 89 89) :border (rgb 118 118 118)
      :linkInk (rgb 11 87 208) :selection (rgb 207 224 255) :focusRing (rgb 11 87 208)
      :neutral (ToneColor :fill (rgb 232 232 232) :onFill (rgb 26 26 26))
      :primary (ToneColor :fill (rgb 11 87 208) :onFill (rgb 255 255 255))
      :success (ToneColor :fill (rgb 20 108 46) :onFill (rgb 255 255 255))
      :warn (ToneColor :fill (rgb 255 209 102) :onFill (rgb 26 26 26))
      :danger (ToneColor :fill (rgb 179 38 30) :onFill (rgb 255 255 255)))
    :text (TextScale
      :body (TextStyle :size (dp 16) :line (dp 24) :weight 400 :fixedPitch false)
      :caption (TextStyle :size (dp 13) :line (dp 18) :weight 400 :fixedPitch false)
      :label (TextStyle :size (dp 14) :line (dp 20) :weight 600 :fixedPitch false)
      :title (TextStyle :size (dp 20) :line (dp 28) :weight 600 :fixedPitch false)
      :display (TextStyle :size (dp 28) :line (dp 36) :weight 700 :fixedPitch false)
      :mono (TextStyle :size (dp 14) :line (dp 20) :weight 400 :fixedPitch true)))

fn spaceOf theme: Theme s: Space -> Length
  (match s ((xs) theme.space.xs) ((sm) theme.space.sm) ((md) theme.space.md) ((lg) theme.space.lg) ((xl) theme.space.xl))

fn radiusOf theme: Theme r: Radius -> Length
  (match r ((sharp) theme.radius.sharp) ((soft) theme.radius.soft) ((pill) theme.radius.pill))

fn textOf theme: Theme role: TextRole -> TextStyle
  (match role ((body) theme.text.body) ((caption) theme.text.caption) ((label) theme.text.label) ((title) theme.text.title) ((display) theme.text.display) ((mono) theme.text.mono))

fn toneColor theme: Theme t: Tone -> ToneColor
  (match t ((neutral) theme.palette.neutral) ((primary) theme.palette.primary) ((success) theme.palette.success) ((warn) theme.palette.warn) ((danger) theme.palette.danger))

fn colorOf theme: Theme role: ColorRole -> Color
  (match role
    ((surface) theme.palette.surface)
    ((ink) theme.palette.ink)
    ((inkWeak) theme.palette.inkWeak)
    ((border) theme.palette.border)
    ((linkInk) theme.palette.linkInk)
    ((selection) theme.palette.selection)
    ((focusRing) theme.palette.focusRing)
    ((fill t) (toneColor theme t).fill)
    ((onFill t) (toneColor theme t).onFill))

fn spaceName s: Space -> String
  (match s ((xs) "xs") ((sm) "sm") ((md) "md") ((lg) "lg") ((xl) "xl"))

fn radiusName r: Radius -> String
  (match r ((sharp) "sharp") ((soft) "soft") ((pill) "pill"))

fn textName role: TextRole -> String
  (match role ((body) "body") ((caption) "caption") ((label) "label") ((title) "title") ((display) "display") ((mono) "mono"))

fn toneName t: Tone -> String
  (match t ((neutral) "neutral") ((primary) "primary") ((success) "success") ((warn) "warn") ((danger) "danger"))

fn emphasisName e: Emphasis -> String
  (match e ((strong) "strong") ((normal) "normal") ((weak) "weak"))

fn allSpaces -> (List Space)
  [(xs) (sm) (md) (lg) (xl)]

fn allRadii -> (List Radius)
  [(sharp) (soft) (pill)]

fn allTextRoles -> (List TextRole)
  [(body) (caption) (label) (title) (display) (mono)]

fn allTones -> (List Tone)
  [(neutral) (primary) (success) (warn) (danger)]

fn channel v: Int64 -> Float64
  (let [(x (/ (int64ToFloat64 v) 255.0))]
    (if (<= x 0.03928) (/ x 12.92) (pow (/ (+ x 0.055) 1.055) 2.4)))

fn luminance c: Color -> Float64
  (match c ((rgb r g b) (+ (+ (* 0.2126 (channel r)) (* 0.7152 (channel g))) (* 0.0722 (channel b)))))

fn contrast a: Color b: Color -> Float64
  (let [(x (luminance a)) (y (luminance b))]
    (/ (+ (max x y) 0.05) (+ (min x y) 0.05)))
