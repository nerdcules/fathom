import QtQuick
import QtQuick.Layouts
import "."
import "Format.js" as F

// The Start menu: search or ask, pinned apps, recent work, and quick
// switches. Plain QtQuick so it renders outside the shell for testing;
// Panel.qml supplies the apps (from the desktop's app list) and `menu`
// (from `fathom-start menu`), and acts on its signals.
Item {
  id: start

  // [{id, name, comment, icon (URL or ""), keywords}]
  property var apps: []
  // {projects, status, config, home} from `fathom-start menu`.
  property var menu: null
  property bool shown: true

  property string query: ""
  property bool allApps: false
  property int selected: 0

  signal closeRequested()
  signal launchApp(string id)
  signal openPage(string page)
  signal openProject(string how, string path)
  signal askRequested(string text, string path)
  signal actionRequested(string id)
  signal pinRequested(string id, bool pin)

  readonly property var projects: menu && Array.isArray(menu.projects) ? menu.projects : []
  readonly property var status: menu ? menu.status : null
  readonly property var pinnedIds: menu && menu.config && Array.isArray(menu.config.pinned) ? menu.config.pinned : []
  readonly property var suggestions: menu && menu.config && Array.isArray(menu.config.suggestions) ? menu.config.suggestions : []
  readonly property string home: menu ? String(menu.home || "") : ""
  readonly property var recent: projects.length > 0 ? projects[0] : null

  readonly property var builtins: [
    { id: "fathom:deck", name: Skin.t("start.deck"), glyph: "", page: "deck", keywords: "docker containers dotnet ai system" },
    { id: "fathom:care", name: Skin.t("start.care"), glyph: "", page: "care", keywords: "disk updates warnings clean space" },
    { id: "fathom:sentinel", name: Skin.t("start.sentinel"), glyph: "\uf132", page: "sentinel", keywords: "security firewall network devices" },
    { id: "fathom:pulse", name: Skin.t("start.pulse"), glyph: "\uf0e7", page: "pulse", keywords: "opentelemetry traces services map latency errors" },
    { id: "fathom:crumbs", name: Skin.t("start.crumbs"), glyph: "\uf1e0", page: "crumbs", keywords: "cookies trackers tracking privacy browser edge chromium block" },
    { id: "fathom:look", name: Skin.t("start.look"), glyph: "\uf1fc", page: "look", keywords: "personalize theme colour color accent corners wallpaper transparency glass appearance" }
  ]

  readonly property var actions: [
    { id: "deck", name: Skin.t("start.deck"), detail: Skin.t("start.deckDetail"), glyph: "", page: "deck", keywords: "docker containers dotnet ai" },
    { id: "care", name: Skin.t("start.care"), detail: Skin.t("start.careDetail"), glyph: "", page: "care", keywords: "disk updates warnings clean space" },
    { id: "sentinel", name: Skin.t("start.sentinel"), detail: Skin.t("start.sentinelDetail"), glyph: "\uf132", page: "sentinel", keywords: "security firewall network devices lockdown" },
    { id: "pulse", name: Skin.t("start.pulse"), detail: Skin.t("start.pulseDetail"), glyph: "\uf0e7", page: "pulse", keywords: "opentelemetry traces services map latency errors" },
    { id: "crumbs", name: Skin.t("start.crumbs"), detail: Skin.t("start.crumbsDetail"), glyph: "\uf1e0", page: "crumbs", keywords: "cookies trackers tracking privacy browser edge chromium block" },
    { id: "look", name: Skin.t("start.look"), detail: Skin.t("start.lookDetail"), glyph: "\uf1fc", page: "look", keywords: "personalize theme colour color accent corners wallpaper transparency glass appearance" },
    { id: "focus", name: Skin.t("start.focusToggle"), detail: Skin.t("start.focusDetail"), glyph: "", keywords: "do not disturb dnd notifications quiet" },
    { id: "play", name: Skin.t("start.play"), detail: Skin.t("start.playDetail"), glyph: "", keywords: "youtube video mini player" },
    { id: "about", name: Skin.t("start.about"), detail: Skin.t("start.aboutDetail"), glyph: "\uf05a", keywords: "credits licence version who made" },
    { id: "lock", name: Skin.t("start.lock"), glyph: "", keywords: "screen" },
    { id: "suspend", name: Skin.t("start.suspend"), glyph: "", keywords: "sleep" },
    { id: "logout", name: Skin.t("start.logout"), glyph: "", keywords: "sign out", confirm: true },
    { id: "reboot", name: Skin.t("start.reboot"), glyph: "", keywords: "restart", confirm: true },
    { id: "shutdown", name: Skin.t("start.shutdown"), glyph: "", keywords: "power off", confirm: true }
  ]

  readonly property var pinned: {
    var out = []
    for (var i = 0; i < pinnedIds.length; i++) {
      var item = itemFor(pinnedIds[i])
      if (item) out.push(item)
    }
    return out
  }

  readonly property var sortedApps: {
    var list = (apps || []).slice()
    list.sort(function(a, b) { return String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1 })
    return list
  }

  readonly property var results: {
    var q = query.trim()
    if (q === "") return []
    var out = F.search(q, apps, projects, actions, 7)
    out.push({ kind: "ask", item: { text: q, path: "", where: "~" } })
    if (recent) out.push({ kind: "ask", item: { text: q, path: recent.path, where: recent.name } })
    return out
  }

  function itemFor(id) {
    for (var b = 0; b < builtins.length; b++) if (builtins[b].id === id) return builtins[b]
    for (var i = 0; i < apps.length; i++) if (apps[i].id === id) return apps[i]
    return null
  }

  function isPinned(id) { return pinnedIds.indexOf(id) !== -1 }

  function openItem(item) {
    if (item.page) start.openPage(item.page)
    else start.launchApp(item.id)
  }

  function runAction(a) {
    if (a.id === "about") { aboutCard.visible = true; return }
    if (a.page) { start.openPage(a.page); return }
    if (a.confirm) {
      Skin.ask(Skin.t("start.confirm." + a.id), Skin.t("start.confirmBody"), a.name,
               function() { start.actionRequested(a.id) })
      return
    }
    start.actionRequested(a.id)
  }

  function run(r) {
    if (!r) return
    if (r.kind === "app") start.launchApp(r.item.id)
    else if (r.kind === "project") start.openProject("editor", r.item.path)
    else if (r.kind === "action") runAction(r.item)
    else if (r.kind === "ask") start.askRequested(r.item.text, r.item.path)
  }

  function ask(text) {
    start.askRequested(text, recent ? recent.path : "")
  }

  function projectDetail(p) {
    var parts = [F.tildePath(F.parentOf(p.path), home)]
    if (p.tech && p.tech.length > 0) parts.push(p.tech.join(", "))
    if (p.branch) parts.push(p.branch + (p.dirty ? "*" : ""))
    var a = F.since(p.when, Date.now() / 1000)
    if (a) parts.push(Skin.tn("care.ago." + a.unit, a.n).arg(Skin.n(a.n)))
    return parts.join(" · ")
  }

  function focusSearch() {
    search.forceActiveFocus()
  }

  onShownChanged: if (shown) { search.text = ""; allApps = false; focusSearch() }

  // ---------------------------------------------------------------- parts

  component Tile: Item {
    id: tile
    property var item: null
    property bool pinnedTile: false
    width: 112 * Skin.u
    height: 96 * Skin.u
    Accessible.role: Accessible.Button
    Accessible.name: item ? item.name : ""
    activeFocusOnTab: true
    Keys.onReturnPressed: start.openItem(item)
    Keys.onSpacePressed: start.openItem(item)

    Rectangle {
      anchors.fill: parent
      radius: 12 * Skin.u
      color: tileMouse.pressed ? Skin.tint(Skin.accent, 0.22)
        : (tileMouse.containsMouse || tile.activeFocus ? Skin.faint : "transparent")
      border.width: tile.activeFocus ? 1 : 0
      border.color: Skin.accent
    }
    Column {
      anchors.centerIn: parent
      spacing: 8 * Skin.u
      AppIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        source: tile.item && tile.item.icon ? tile.item.icon : ""
        glyph: tile.item && tile.item.glyph ? tile.item.glyph : ""
        name: tile.item ? tile.item.name : ""
      }
      Label {
        width: tile.width - 12 * Skin.u
        horizontalAlignment: Text.AlignHCenter
        text: tile.item ? tile.item.name : ""
        font.pixelSize: 12 * Skin.u
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (!tile.item) return
        if (mouse.button === Qt.RightButton) start.pinRequested(tile.item.id, !start.isPinned(tile.item.id))
        else start.openItem(tile.item)
      }
    }
    Tip {
      target: tile
      show: tileMouse.containsMouse && !!tile.item
      text: tile.item ? (start.isPinned(tile.item.id) ? Skin.t("start.unpinTip") : Skin.t("start.pinTip")) : ""
    }
  }

  // ---------------------------------------------------------------- scene

  // A light scrim: click outside the menu to close it.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.28)
    MouseArea { anchors.fill: parent; onClicked: start.closeRequested() }
  }

  Rectangle {
    id: panel
    width: Math.min(parent.width - 64 * Skin.u, 860 * Skin.u)
    height: Math.min(parent.height - 96 * Skin.u, column.implicitHeight + 56 * Skin.u)
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(32 * Skin.u, parent.height * 0.09)
    // The windows' corners, not scaled: Omarchy's panels share them too.
    radius: Skin.radius
    color: Skin.tint(Skin.bg, Skin.panelAlpha)
    border.width: 1
    border.color: Skin.tint(Skin.accent, Skin.edgeAlpha)
    clip: true
    opacity: start.shown ? 1 : 0
    scale: start.shown ? 1 : 0.97
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: 160 * Skin.motion; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 160 * Skin.motion; easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent }

    // The gradient frame's glow, along the top edge.
    Rectangle {
      visible: Skin.glow
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
      height: 90 * Skin.u
      radius: panel.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Skin.tint(Skin.accent, 0.09) }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: 28 * Skin.u
      spacing: 18 * Skin.u

      Label {
        text: Skin.t("start.title")
        font.pixelSize: 26 * Skin.u
        font.weight: Font.Light
        Layout.fillWidth: true
      }

      // Search or ask.
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 52 * Skin.u
        radius: 14 * Skin.u
        color: Skin.tint(Skin.fg, 0.06)
        border.width: 1
        border.color: search.activeFocus ? Skin.tint(Skin.accent, 0.7) : Skin.tint(Skin.accent, 0.25)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 18 * Skin.u
          anchors.rightMargin: 12 * Skin.u
          spacing: 12 * Skin.u
          Label { text: ""; color: Skin.accent; font.pixelSize: 17 * Skin.u }
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextInput {
              id: search
              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              color: Skin.fg
              selectionColor: Skin.tint(Skin.accent, 0.4)
              font.family: Skin.fontFamily
              font.pixelSize: 17 * Skin.u
              clip: true
              maximumLength: 2000
              focus: true
              onTextChanged: { start.query = text; start.selected = 0 }
              Keys.onDownPressed: start.selected = Math.min(start.results.length - 1, start.selected + 1)
              Keys.onUpPressed: start.selected = Math.max(0, start.selected - 1)
              Keys.onReturnPressed: start.run(start.results[start.selected])
              Keys.onEnterPressed: start.run(start.results[start.selected])
              Keys.onEscapePressed: {
                if (aboutCard.visible) aboutCard.visible = false
                else if (text !== "") text = ""
                else if (start.allApps) start.allApps = false
                else start.closeRequested()
              }
            }
            Label {
              anchors.verticalCenter: parent.verticalCenter
              visible: search.text === ""
              text: Skin.t("start.placeholder")
              color: Skin.dim
              font.pixelSize: 17 * Skin.u
            }
          }
          Rectangle {
            implicitWidth: keyHint.implicitWidth + 16 * Skin.u
            implicitHeight: 24 * Skin.u
            radius: 6 * Skin.u
            color: Skin.faint
            Label { id: keyHint; anchors.centerIn: parent; text: "super"; color: Skin.dim; font.pixelSize: 11 * Skin.u }
          }
        }
      }

      // ------------------------------------------------ results
      ColumnLayout {
        visible: start.query.trim() !== ""
        Layout.fillWidth: true
        spacing: 4 * Skin.u
        Repeater {
          model: start.results
          delegate: ListRow {
            id: resultRow
            required property var modelData
            required property int index
            readonly property var r: modelData
            clickable: true
            current: index === start.selected
            showDot: false
            iconSource: r.kind === "app" ? (r.item.icon || "") : ""
            iconGlyph: r.kind === "app" ? "" : (r.kind === "ask" ? "\u2726" : (r.kind === "project" ? "\uf07b" : (r.item.glyph || "")))
            iconName: r.kind === "app" ? r.item.name : ""
            name: r.kind === "ask" ? Skin.t("start.ask").arg(r.item.text) : r.item.name
            detail: r.kind === "app" ? (r.item.comment || "")
              : r.kind === "project" ? start.projectDetail(r.item)
              : r.kind === "action" ? (r.item.detail || "")
              : Skin.t("start.askIn").arg(r.item.where)
            right1: Skin.t("start.kind." + r.kind)
            onClicked: start.run(r)
            onHoveredChanged: if (hovered) start.selected = resultRow.index
          }
        }
      }

      // ------------------------------------------------ home
      ColumnLayout {
        visible: start.query.trim() === "" && !start.allApps
        Layout.fillWidth: true
        spacing: 16 * Skin.u

        Flow {
          Layout.fillWidth: true
          spacing: 8 * Skin.u
          Repeater {
            model: start.suggestions
            delegate: Pill {
              required property var modelData
              glyph: "✦"
              glyphColor: Skin.violet
              text: modelData
              onClicked: start.ask(modelData)
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          SectionTitle { text: Skin.t("start.pinned"); Layout.topMargin: 0 }
          Pill { text: Skin.t("start.allApps"); onClicked: start.allApps = true }
        }
        Grid {
          id: pinnedGrid
          Layout.fillWidth: true
          columns: Math.max(1, Math.floor(width / (112 * Skin.u)))
          Repeater {
            model: start.pinned
            delegate: Tile {
              required property var modelData
              item: modelData
              width: pinnedGrid.width / pinnedGrid.columns
            }
          }
        }

        SectionTitle { text: Skin.t("start.recent"); visible: start.projects.length > 0 }
        Repeater {
          model: start.projects.slice(0, 5)
          delegate: ListRow {
            id: prow
            required property var modelData
            showDot: false
            clickable: true
            name: modelData.name
            detail: start.projectDetail(modelData)
            onClicked: start.openProject("editor", modelData.path)
            Pill { glyph: ""; tip: Skin.t("start.openEditor"); onClicked: start.openProject("editor", prow.modelData.path) }
            Pill { glyph: ""; tip: Skin.t("start.openTerminal"); onClicked: start.openProject("terminal", prow.modelData.path) }
            Pill { glyph: "✦"; glyphColor: Skin.violet; tip: Skin.t("start.openClaude"); onClicked: start.openProject("claude", prow.modelData.path) }
            Pill { glyph: ""; tip: Skin.t("start.openFiles"); onClicked: start.openProject("files", prow.modelData.path) }
          }
        }
      }

      // ------------------------------------------------ all apps
      ColumnLayout {
        visible: start.query.trim() === "" && start.allApps
        Layout.fillWidth: true
        spacing: 12 * Skin.u
        RowLayout {
          Layout.fillWidth: true
          SectionTitle { text: Skin.t("start.allAppsTitle").arg(Skin.n(start.sortedApps.length)); Layout.topMargin: 0 }
          Pill { text: Skin.t("start.back"); onClicked: start.allApps = false }
        }
        Flickable {
          id: appsFlick
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(allGrid.implicitHeight, 440 * Skin.u)
          contentHeight: allGrid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Grid {
            id: allGrid
            width: appsFlick.width
            columns: Math.max(1, Math.floor(width / (112 * Skin.u)))
            Repeater {
              model: start.allApps ? start.sortedApps : []
              delegate: Tile {
                required property var modelData
                item: modelData
                width: allGrid.width / allGrid.columns
              }
            }
          }
        }
      }

      // ------------------------------------------------ footer
      Rectangle { Layout.fillWidth: true; height: 1; color: Skin.faint; Layout.topMargin: 4 * Skin.u }
      RowLayout {
        Layout.fillWidth: true
        spacing: 10 * Skin.u
        Rectangle {
          width: 32 * Skin.u
          height: width
          radius: width / 2
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Skin.accent }
            GradientStop { position: 1; color: Skin.violet }
          }
          Label {
            anchors.centerIn: parent
            text: start.status ? String(start.status.name || start.status.user || "?").charAt(0).toUpperCase() : ""
            color: Skin.bg
            font.weight: Font.Bold
            font.pixelSize: 14 * Skin.u
          }
        }
        Label {
          text: start.status ? (start.status.name || start.status.user) + " · " + start.status.host : ""
          color: Skin.dim
          font.pixelSize: 13 * Skin.u
          Layout.fillWidth: true
        }
        Pill {
          visible: !!start.status && start.status.docker !== "missing"
          glyph: "●"
          glyphColor: start.status && start.status.docker === "active" ? Skin.ok : Skin.dim
          text: "Docker"
          tip: start.status && start.status.docker === "active" ? Skin.t("start.dockerOn") : Skin.t("start.dockerOff")
          onClicked: start.openPage("deck")
        }
        Pill {
          glyph: ""
          text: Skin.t("start.focus")
          selected: !!start.status && start.status.focus === true
          tip: start.status && start.status.focus ? Skin.t("start.focusOn") : Skin.t("start.focusOff")
          onClicked: start.actionRequested("focus")
        }
        Pill {
          glyph: "\uf05a"
          tip: Skin.t("start.about")
          onClicked: aboutCard.visible = !aboutCard.visible
        }
        Pill {
          id: powerButton
          glyph: ""
          tip: Skin.t("start.power")
          onClicked: powerMenu.visible = !powerMenu.visible
        }
      }
    }
  }

  // The power menu, opening upward from its button. Esc or a click
  // elsewhere closes it.
  Rectangle {
    id: powerMenu
    visible: false
    z: 50
    width: 200 * Skin.u
    height: powerColumn.implicitHeight + 16 * Skin.u
    radius: 14 * Skin.u
    color: Skin.tint(Skin.bg, 0.97)
    border.width: 1
    border.color: Skin.tint(Skin.accent, 0.3)
    x: {
      var p = powerButton.mapToItem(start, powerButton.width, 0)
      return Math.min(start.width - width - 8, p.x - width)
    }
    y: powerButton.mapToItem(start, 0, 0).y - height - 8 * Skin.u
    Column {
      id: powerColumn
      anchors.fill: parent
      anchors.margins: 8 * Skin.u
      Repeater {
        model: ["lock", "suspend", "logout", "reboot", "shutdown"]
        delegate: ListRow {
          required property var modelData
          width: powerColumn.width
          showDot: false
          clickable: true
          name: Skin.t("start." + modelData)
          onClicked: {
            powerMenu.visible = false
            for (var i = 0; i < start.actions.length; i++) if (start.actions[i].id === modelData) start.runAction(start.actions[i])
          }
        }
      }
    }
  }

  // About Fathom: the hexagon logo, the wordmark and whose idea it was.
  // A click anywhere closes it, as does Esc in the search field.
  Rectangle {
    id: aboutCard
    visible: false
    z: 60
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    radius: 14 * Skin.u
    MouseArea { anchors.fill: parent; onClicked: aboutCard.visible = false }

    Rectangle {
      id: aboutEdge
      anchors.centerIn: parent
      width: Math.min(parent.width - 48 * Skin.u, 440 * Skin.u)
      height: aboutColumn.implicitHeight + 60 * Skin.u
      radius: 16 * Skin.u
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Skin.accent }
        GradientStop { position: 1; color: Skin.violet }
      }
      Rectangle {
        anchors.fill: parent
        anchors.margins: 1.5
        radius: aboutEdge.radius - 1.5
        color: Skin.tint(Skin.bg, 0.98)

        Column {
          id: aboutColumn
          anchors.centerIn: parent
          width: parent.width - 56 * Skin.u
          spacing: 10 * Skin.u

          // The logo as art/make-art.py draws it: a hexagon inside a
          // hexagon, pointed at the top.
          Canvas {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 84 * Skin.u
            height: width
            onPaint: {
              var c = getContext("2d")
              c.reset()
              c.strokeStyle = Skin.accent
              c.lineJoin = "round"
              c.lineWidth = width * 0.075
              var sizes = [0.44, 0.19]
              for (var k = 0; k < sizes.length; k++) {
                c.beginPath()
                for (var i = 0; i < 6; i++) {
                  var a = (-90 + 60 * i) * Math.PI / 180
                  var x = width / 2 + width * sizes[k] * Math.cos(a)
                  var y = height / 2 + width * sizes[k] * Math.sin(a)
                  if (i === 0) c.moveTo(x, y); else c.lineTo(x, y)
                }
                c.closePath()
                c.stroke()
              }
            }
          }
          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "FATHOM"
            color: Skin.accent
            font.pixelSize: 30 * Skin.u
            font.weight: Font.Medium
            font.letterSpacing: 10 * Skin.u
            leftPadding: font.letterSpacing
          }
          Label {
            width: parent.width
            text: Skin.t("start.aboutPurpose")
            color: Skin.fg
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14 * Skin.u
            lineHeight: 1.15
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.6
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 0.3; color: Skin.accent }
              GradientStop { position: 0.7; color: Skin.violet }
              GradientStop { position: 1; color: "transparent" }
            }
          }
          Label {
            width: parent.width
            text: Skin.t("start.aboutCredit")
            color: Skin.fg
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13 * Skin.u
            font.weight: Font.DemiBold
          }
          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Skin.t("start.aboutLicence")
            color: Skin.dim
            font.pixelSize: 12 * Skin.u
          }
          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "github.com/nerdcules/fathom"
            color: Skin.accent
            font.pixelSize: 12 * Skin.u
          }
          Item { width: 1; height: 4 * Skin.u }
          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Skin.t("start.aboutClose")
            color: Skin.dim
            font.pixelSize: 11 * Skin.u
          }
        }
      }
    }
  }
}
