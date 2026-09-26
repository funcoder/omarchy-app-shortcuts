import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Shortcut cheat sheet for the focused window.
//
// Summoned from a keybinding while an app has focus: shortcuts.py works out
// what that app is (a web app by site, the program in the foreground of a
// terminal, or the window's own app) and returns its stored shortcuts plus the
// Hyprland keybindings. An app met for the first time is looked up with Claude
// in the background; the sheet polls until the result lands.
//
// Keys: type to filter, Tab / Left / Right switch between the app and
// Hyprland, Up / Down / Page Up / Page Down scroll, Ctrl+R looks the app up
// again, Escape clears the filter and then closes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property var app: null
  property string status: ""
  property string errorText: ""
  property string source: ""
  property var appSections: []
  property var hyprSections: []
  property int tab: 0
  property string filterText: ""

  readonly property string pluginId: (manifest && manifest.id) || "funcoder.app-shortcuts"
  readonly property string helper: {
    var url = String(Qt.resolvedUrl("shortcuts.py"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.lg
  property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(30), Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(6))
  property int keysWidth: Math.round((cardWidth - contentMargin * 2) * 0.38)

  readonly property string appName: app ? String(app.name || app.key) : "No window"
  readonly property var tabs: [appName, "Hyprland"]

  // ---- state -----------------------------------------------------------------

  function open(payloadJson) {
    opened = true
    loading = true
    app = null
    status = ""
    errorText = ""
    source = ""
    appSections = []
    hyprSections = []
    tab = 0
    filterText = ""
    rebuild()
    currentProc.command = [helper, "current"]
    currentProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    pollTimer.stop()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  function parse(raw) {
    try {
      return JSON.parse(String(raw || "").trim() || "{}")
    } catch (e) {
      return { status: "failed", error: "Could not read helper output" }
    }
  }

  function applyCurrent(raw) {
    var data = parse(raw)
    loading = false
    hyprSections = Array.isArray(data.hyprland) ? data.hyprland : []
    applyApp(data)
    if (!app) tab = 1
    rebuild()
  }

  function applyApp(data) {
    app = data.app || null
    status = String(data.status || (data.error ? "failed" : ""))
    errorText = String(data.error || "")
    source = String(data.source || "")
    appSections = Array.isArray(data.sections) ? data.sections : []
    if (status === "pending") pollTimer.start()
    else pollTimer.stop()
    rebuild()
  }

  function relookup() {
    if (!app || status === "pending") return
    Quickshell.execDetached([helper, "lookup", app.key, "--force", "--background"])
    status = "pending"
    appSections = []
    rebuild()
    pollTimer.start()
  }

  function setTab(index) {
    tab = (index + tabs.length) % tabs.length
    list.contentY = 0
    rebuild()
  }

  function setFilter(text) {
    filterText = text
    list.contentY = 0
    rebuild()
  }

  function scrollBy(delta) {
    var maxY = Math.max(0, list.contentHeight - list.height)
    list.contentY = Math.max(0, Math.min(maxY, list.contentY + delta))
  }

  function rebuild() {
    rowsModel.clear()
    var sections = tab === 0 ? appSections : hyprSections
    var needle = filterText.toLowerCase()
    for (var i = 0; i < sections.length; i++) {
      var section = sections[i] || {}
      var matches = []
      var shortcuts = Array.isArray(section.shortcuts) ? section.shortcuts : []
      for (var j = 0; j < shortcuts.length; j++) {
        var s = shortcuts[j] || {}
        var keys = String(s.keys || "")
        var action = String(s.action || "")
        if (needle === "" || keys.toLowerCase().indexOf(needle) !== -1 || action.toLowerCase().indexOf(needle) !== -1)
          matches.push({ keys: keys, action: action })
      }
      if (matches.length === 0) continue
      rowsModel.append({ header: true, title: String(section.title || ""), keys: "", action: "" })
      for (var k = 0; k < matches.length; k++)
        rowsModel.append({ header: false, title: "", keys: matches[k].keys, action: matches[k].action })
    }
  }

  function kindText() {
    if (!app) return "Nothing focused"
    var key = String(app.key || "")
    if (app.kind === "web") return "Web app · " + key.replace(/^web:/, "")
    if (app.kind === "tui") return "Terminal program · " + key.replace(/^tui:/, "")
    if (app.kind === "shell") return "Omarchy plugin · " + key.replace(/^shell:/, "")
    return "App"
  }

  function emptyText() {
    if (loading) return "Reading the focused window…"
    if (tab === 0) {
      if (!app) return "No window has focus"
      if (status === "pending") return app && app.key === "tui:nvim"
        ? "Reading your Neovim keymaps…" : "Looking up " + appName + " shortcuts with Claude…"
      if (status === "failed") return "Lookup failed: " + (errorText || "unknown error")
    }
    if (filterText !== "") return "No matches for “" + filterText + "”"
    return tab === 0 ? "No shortcuts known for " + appName : "No Hyprland keybindings found"
  }

  function footerText() {
    var parts = ["Tab switch", "Esc close"]
    if (tab === 0 && app && status !== "pending") parts.unshift("Ctrl+R look up again")
    if (tab === 0 && source === "user") parts.unshift("Edited by you")
    else if (tab === 0 && source === "claude") parts.unshift("Looked up by Claude")
    else if (tab === 0 && source === "nvim") parts.unshift("Read from your Neovim config")
    return parts.join("  ·  ")
  }

  ListModel { id: rowsModel }

  // ---- processes -------------------------------------------------------------

  Process {
    id: currentProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCurrent(text)
    }
  }

  Process {
    id: pollProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.parse(text)
        if (root.opened && root.app && data.app && data.app.key === root.app.key) root.applyApp(data)
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    onTriggered: {
      if (!root.opened || !root.app) { stop(); return }
      if (pollProc.running) return
      pollProc.command = [root.helper, "show", root.app.key]
      pollProc.running = true
    }
  }

  IpcHandler {
    target: root.pluginId

    function toggle(): void { root.shell ? root.shell.toggle(root.pluginId, "{}") : root.toggle() }
    function close(): void { root.dismiss() }
  }

  // ---- window ----------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "funcoder-app-shortcuts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
          } else if (ctrl && event.key === Qt.Key_R) {
            root.relookup()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
            root.setTab(root.tab + 1)
          } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
            root.setTab(root.tab - 1)
          } else if (event.key === Qt.Key_Down) {
            root.scrollBy(root.rowHeight)
          } else if (event.key === Qt.Key_Up) {
            root.scrollBy(-root.rowHeight)
          } else if (event.key === Qt.Key_PageDown) {
            root.scrollBy(list.height - root.rowHeight)
          } else if (event.key === Qt.Key_PageUp) {
            root.scrollBy(-(list.height - root.rowHeight))
          } else if (event.key === Qt.Key_Home) {
            list.contentY = 0
          } else if (event.key === Qt.Key_End) {
            root.scrollBy(list.contentHeight)
          } else if (!ctrl && event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: layout
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Title and tabs.
        Item {
          id: header
          width: parent.width
          height: Math.max(titleColumn.implicitHeight, tabRow.implicitHeight)

          Column {
            id: titleColumn
            anchors.left: parent.left
            anchors.right: tabRow.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.appName
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.kindText()
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Row {
            id: tabRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Repeater {
              model: root.tabs

              Rectangle {
                required property int index
                required property string modelData
                readonly property bool active: index === root.tab

                width: Math.min(Style.space(180), tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2)
                height: tabLabel.implicitHeight + Style.spacing.controlPaddingY * 2
                radius: root.cornerRadius
                color: active ? root.selectedBackground : "transparent"

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  width: Math.min(implicitWidth, parent.width - Style.spacing.controlPaddingX * 2)
                  textFormat: Text.PlainText
                  text: parent.modelData
                  color: parent.active ? root.selectedText : root.foreground
                  opacity: parent.active ? 1 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTab(parent.index)
                }
              }
            }
          }
        }

        // Filter.
        Text {
          id: filterLine
          width: parent.width
          textFormat: Text.PlainText
          text: root.filterText || "Type to filter…"
          color: root.foreground
          opacity: root.filterText ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.border
          opacity: 0.35
        }

        Item {
          width: parent.width
          height: parent.height - header.height - filterLine.height - Math.max(1, Style.space(1))
            - footer.height - root.contentSpacing * 4

          ListView {
            id: list
            anchors.fill: parent
            model: rowsModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              required property bool header
              required property string title
              required property string keys
              required property string action

              width: list.width
              height: header ? root.rowHeight + Style.spacing.sm : root.rowHeight

              Text {
                visible: parent.header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.sm
                textFormat: Text.PlainText
                text: parent.title.toUpperCase()
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
                elide: Text.ElideRight
              }

              Rectangle {
                visible: !parent.header
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(root.keysWidth, keysLabel.implicitWidth + Style.spacing.controlPaddingX * 2)
                height: keysLabel.implicitHeight + Style.spacing.xs * 2
                radius: root.cornerRadius
                color: root.selectedBackground

                Text {
                  id: keysLabel
                  anchors.centerIn: parent
                  width: Math.min(implicitWidth, root.keysWidth - Style.spacing.controlPaddingX * 2)
                  textFormat: Text.PlainText
                  text: parent.parent.keys
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }

              Text {
                visible: !parent.header
                anchors.left: parent.left
                anchors.leftMargin: root.keysWidth + root.contentSpacing
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.action
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width
            visible: rowsModel.count === 0
            textFormat: Text.PlainText
            text: root.emptyText()
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }

        Text {
          id: footer
          width: parent.width
          textFormat: Text.PlainText
          text: root.footerText()
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideLeft
        }
      }
    }
  }
}
