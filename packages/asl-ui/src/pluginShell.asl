(module asl-ui/pluginShell
  :x [UIPlugin PluginShell makeUIPlugin makePluginShell registerPlugin unregisterPlugin findPluginsInSlot renderSlot isValidSlot?]
  :i [])

(schema UIPlugin
  (:f id String)
  (:f title String)
  (:f targetSlot String)
  (:f renderContent String))

(schema PluginShell
  (:f activePlugins (List UIPlugin))
  (:f supportedSlots (List String)))

fn makeUIPlugin id: String title: String slot: String content: String -> UIPlugin
  (UIPlugin :id id :title title :targetSlot slot :renderContent content)

fn isValidSlot? slot: String -> Bool
  (or (= slot "header")
      (or (= slot "sidebar")
          (or (= slot "workspace")
              (= slot "footer"))))

fn makePluginShell -> PluginShell
  (PluginShell
    :activePlugins (list)
    :supportedSlots (list "header" "sidebar" "workspace" "footer"))

fn isPluginRegistered? shell: PluginShell pluginId: String -> Bool
  (listAny? (fn [(p UIPlugin)] (= p.id pluginId)) shell.activePlugins)

fn registerPlugin shell: PluginShell plugin: UIPlugin -> (Result PluginShell String)
  (if (stringEmpty? plugin.id)
    (err "ERR_PLUGIN_EMPTY_ID")
    (if (not (isValidSlot? plugin.targetSlot))
      (err "ERR_PLUGIN_INVALID_SLOT")
      (if (isPluginRegistered? shell plugin.id)
        (err "ERR_PLUGIN_ALREADY_REGISTERED")
        (let [(updatedPlugins (listAppend shell.activePlugins (list plugin)))]
          (ok (with shell :activePlugins updatedPlugins))))))

fn unregisterPlugin shell: PluginShell pluginId: String -> (Result PluginShell String)
  (if (not (isPluginRegistered? shell pluginId))
    (err "ERR_PLUGIN_NOT_FOUND")
    (let [(filtered (filter (fn [(p UIPlugin)] (!= p.id pluginId)) shell.activePlugins))]
      (ok (with shell :activePlugins filtered))))

fn findPluginsInSlot shell: PluginShell slot: String -> (List UIPlugin)
  (filter (fn [(p UIPlugin)] (= p.targetSlot slot)) shell.activePlugins)

fn renderSlot shell: PluginShell slot: String -> String
  (let [(plugins (findPluginsInSlot shell slot))
        (contents (map (fn [(p UIPlugin)] p.renderContent) plugins))
        (joined (stringJoin contents "\n"))]
    (str "<div class=\"slot-" slot "\">\n" joined "\n</div>"))
