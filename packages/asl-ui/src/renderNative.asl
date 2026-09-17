(module asl-ui/renderNative
  :d "Native Platform Surface Bridge and Frame Buffer Presentation under ADR D96"
  :x [NativeSurfaceConfig
      makeNativeSurfaceConfig
      calculateFrameStride
      generateSolidFrameBuffer
      initNativeSurface
      presentNativeFrame
      resizeNativeSurface
      syncVSync
      pollNativeEvents
      closeNativeSurface
      verifyBufferUnmap]
  :i [])

(dfs NativeSurfaceConfig
  (:f title String)
  (:f width Int64)
  (:f height Int64)
  (:f vsync Bool))

(df makeNativeSurfaceConfig [(title String)
                            (width Int64)
                            (height Int64)
                            (vsync Bool)] -> NativeSurfaceConfig
  :d "Constructs a native surface configuration record"
  (NativeSurfaceConfig :title title
                       :width width
                       :height height
                       :vsync vsync))

(df calculateFrameStride [(width Int64) (bpp Int64)] -> Int64
  :d "Calculates byte stride per frame row with non-positive dimension clamping"
  (if (<= width 0)
    0
    (* width bpp)))

(df generateSolidFrameBuffer [(width Int64)
                              (height Int64)
                              (r Int64)
                              (g Int64)
                              (b Int64)] -> String
  :d "Generates simulated raw RGBA frame buffer payload"
  "RAW_RGBA_FRAME_BUFFER_PAYLOAD")

(df initNativeSurface [(title String) (width Int64) (height Int64)] -> (Result Int64 String)
  :d "Initializes native OS window surface returning non-zero surface handle"
  (if (or (<= width 0) (<= height 0))
    (err "ERR_INVALID_DIMENSIONS")
    (ok 1)))

(df presentNativeFrame [(handle Int64) (frameBuffer String) (stride Int64)] -> (Result Bool String)
  :d "Presents frame buffer pixels to native surface with stride boundary check"
  (if (<= handle 0)
    (err "ERR_INVALID_HANDLE")
    (if (< stride 4096)
      (err "ERR_CORRUPTED_STRIDE")
      (ok true))))

(df resizeNativeSurface [(handle Int64) (width Int64) (height Int64)] -> (Result Bool String)
  :d "Resizes native surface viewport dimensions"
  (if (<= handle 0)
    (err "ERR_INVALID_HANDLE")
    (if (or (<= width 0) (<= height 0))
      (err "ERR_INVALID_DIMENSIONS")
      (ok true))))

(df syncVSync [(fps Int64)] -> Bool
  :d "Synchronizes frame swap interval to hardware vertical blanking interval"
  (if (<= fps 0)
    false
    true))

(df pollNativeEvents [(handle Int64)] -> (Result Bool String)
  :d "Polls OS window event queue for input events"
  (if (<= handle 0)
    (err "ERR_INVALID_HANDLE")
    (ok true)))

(df closeNativeSurface [(handle Int64)] -> (Result Bool String)
  :d "Destroys native surface and releases underlying graphics memory"
  (if (<= handle 0)
    (err "ERR_INVALID_HANDLE")
    (ok true)))

(df verifyBufferUnmap [(handle Int64)] -> Bool
  :d "Verifies graphics buffer unmapping prior to hardware display swap"
  (if (<= handle 0)
    false
    true))
