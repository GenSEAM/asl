(module asl-ui
  :d "Pure AgentScript Universal Declarative UI, Elm Runtime & Frame Arena Substrate"
  :x [VNode
      makeVNode
      makeText
      makeButton
      makeInput
      makeContainer
      makeCanvas
      makeModal
      makeList
      validateKeyUniqueness
      Msg
      makeMsg
      Cmd
      makeCmd
      CounterModel
      makeCounterModel
      RuntimeStepResult
      makeStepResult
      renderCounterView
      dispatchMsg
      stepRuntime
      MutationRecord
      makeMutationRecord
      FrameArena
      makeFrameArena
      allocFrameNode
      tryAllocFrameNode
      swapArenas
      getArenaAllocatedBytes
      diffVNodes
      hasMutationKind
      LayoutConstraints
      makeConstraints
      Dimensions
      makeDimensions
      Rect
      makeRect
      LayoutBox
      makeLayoutBox
      clampDim
      resolveConstraint
      measure
      arrange
      gridStep
      TypographyToken
      makeTypographyToken
      getTypographyToken
      ColorToken
      makeColorToken
      ThemePalette
      makeThemePalette
      defaultDarkTheme
      defaultLightTheme
      calculateLuminance
      calculateContrastRatio
      verifyWcagAa
      verifyWcagAaa
      validateThemeContrast
      AXNode
      makeAXNode
      makeEmptyAXNode
      mapTagToAriaRole
      resolveAccessibleName
      projectAccessibilityTree
      getFocusTrappedTargets
      SemanticReceipt
      makeSemanticReceipt
      queryAxNodeByAnchor
      queryAllAxNodesByRole
      describeAxNode
      dispatchSemanticAction
      DomPatch
      makeDomPatch
      makeEmptyDomPatch
      applyDomMutations
      renderToHtml
      handleWebResize
      NativeSurfaceConfig
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
  :i [(asl-ui/vnode :a vnode)
      (asl-ui/runtime :a runtime)
      (asl-ui/arena :a arena)
      (asl-ui/layout :a layout)
      (asl-ui/tokens :a tokens)
      (asl-ui/theme :a theme)
      (asl-ui/ax :a ax)
      (asl-ui/query :a query)
      (asl-ui/renderWeb :a renderWeb)
      (asl-ui/renderNative :a renderNative)])
