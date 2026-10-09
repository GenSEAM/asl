(module asl-ui/renderNative :x [NativeSurfaceConfig makeNativeSurfaceConfig calculateFrameStride generateSolidFrameBuffer initNativeSurface presentNativeFrame resizeNativeSurface syncVSync pollNativeEvents closeNativeSurface verifyBufferUnmap] :i [])

(schema NativeSurfaceConfig (:f title String) (:f width Int64) (:f height Int64) (:f vsync Bool))

fn makeNativeSurfaceConfig title: String width: Int64 height: Int64 vsync: Bool -> NativeSurfaceConfig
  (NativeSurfaceConfig :title title :width width :height height :vsync vsync)

fn calculateFrameStride width: Int64 bpp: Int64 -> Int64
  (if (<= width 0) 0 (* width bpp))

fn generateSolidFrameBuffer width: Int64 height: Int64 r: Int64 g: Int64 b: Int64 -> String
  "RAW_RGBA_FRAME_BUFFER_PAYLOAD"

fn initNativeSurface title: String width: Int64 height: Int64 -> (Result Int64 String)
  (if (or (<= width 0) (<= height 0)) (err "ERR_INVALID_DIMENSIONS") (ok 1))

fn presentNativeFrame handle: Int64 frameBuffer: String stride: Int64 -> (Result Bool String)
  (if (<= handle 0) (err "ERR_INVALID_HANDLE") (if (< stride 4096) (err "ERR_CORRUPTED_STRIDE") (ok true)))

fn resizeNativeSurface handle: Int64 width: Int64 height: Int64 -> (Result Bool String)
  (if (<= handle 0) (err "ERR_INVALID_HANDLE") (if (or (<= width 0) (<= height 0)) (err "ERR_INVALID_DIMENSIONS") (ok true)))

fn syncVSync fps: Int64 -> Bool
  (if (<= fps 0) false true)

fn pollNativeEvents handle: Int64 -> (Result Bool String)
  (if (<= handle 0) (err "ERR_INVALID_HANDLE") (ok true))

fn closeNativeSurface handle: Int64 -> (Result Bool String)
  (if (<= handle 0) (err "ERR_INVALID_HANDLE") (ok true))

fn verifyBufferUnmap handle: Int64 -> Bool
  (if (<= handle 0) false true)
