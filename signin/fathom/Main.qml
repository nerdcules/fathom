// Fathom sign-in screen for SDDM (Qt 6).
//
// Preview without signing out:
//   sddm-greeter-qt6 --test-mode --theme ~/Work/fathom/signin/fathom

import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Rectangle {
  id: root
  width: 1440
  height: 900
  color: "#060a13"

  // Everything is sized against a 1440x900 design, so it keeps its
  // proportions on any screen.
  readonly property real u: Math.max(0.6, Math.min(width / 1440, height / 900))

  readonly property color accent: config.accent || "#4cc9f0"
  readonly property color accent2: config.accent2 || "#9d8cff"
  readonly property color fg: "#e6f0ff"
  readonly property color muted: "#a9b9d1"
  readonly property color surface: Qt.rgba(14 / 255, 23 / 255, 41 / 255, 0.85)
  readonly property color line: "#2a4566"
  readonly property color danger: "#ff6b81"
  readonly property color warn: "#ffb547"
  readonly property color accentInk: "#04111d"
  readonly property string sans: "Adwaita Sans"
  readonly property string mono: "JetBrainsMono Nerd Font"

  // Users and sessions, copied out of SDDM's models so they can be indexed.
  property var users: []
  property var sessions: []
  property int userIndex: 0
  property int sessionIndex: Math.max(0, sessionModel.lastIndex)

  readonly property var user: users[userIndex] || ({ name: userModel.lastUser || "", realName: userModel.lastUser || "" })

  property bool busy: false
  property bool failed: false
  property var now: new Date()

  function addUser(i, name, realName) {
    var a = users.slice()
    a[i] = { name: name, realName: realName && realName.length ? realName : name }
    users = a
    if (name === userModel.lastUser)
      userIndex = i
  }

  function addSession(i, name, file) {
    var a = sessions.slice()
    a[i] = { name: name, file: file || "" }
    sessions = a
  }

  // Like Omarchy's own greeter, start the uwsm-managed Hyprland session when
  // there is one; otherwise the last session used.
  function chooseSession() {
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i]
      if (s && (s.name + " " + s.file).indexOf("uwsm") !== -1) {
        sessionIndex = i
        return
      }
    }
  }

  function initial(name) {
    return name && name.length ? name.charAt(0).toUpperCase() : "?"
  }

  function submit() {
    if (busy || !user.name)
      return
    busy = true
    failed = false
    closeMenus()
    sddm.login(user.name, password.text, sessionIndex)
    busyTimeout.restart()
  }

  function closeMenus() {
    sessionMenu.visible = false
    powerMenu.visible = false
  }

  function hexPoints(cx, cy, r) {
    var p = []
    for (var i = 0; i <= 6; i++) {
      var a = (-90 + 60 * i) * Math.PI / 180
      p.push(Qt.point(cx + r * Math.cos(a), cy + r * Math.sin(a)))
    }
    return p
  }

  Repeater {
    model: userModel
    delegate: Item { Component.onCompleted: root.addUser(index, model.name, model.realName) }
  }

  Repeater {
    model: sessionModel
    delegate: Item { Component.onCompleted: root.addSession(index, model.name, model.file) }
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      busyTimeout.stop()
      root.busy = false
      root.failed = true
      password.text = ""
      shake.restart()
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      busyTimeout.stop()
    }
  }

  // If SDDM never answers (test mode does not), let the person try again.
  Timer {
    id: busyTimeout
    interval: 15000
    onTriggered: root.busy = false
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  // ---------- Reusable pieces ----------

  component Hexagon: Shape {
    id: hex
    property real radius: 12
    property real strokeWidth: 2
    property color strokeColor: root.accent
    width: radius * 2 + strokeWidth * 2
    height: width
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: hex.strokeColor
      strokeWidth: hex.strokeWidth
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: root.hexPoints(hex.width / 2, hex.height / 2, hex.radius) }
    }
  }

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property string glyph: ""
    property string accessibleName: label
    property bool highlighted: false
    // Flat buttons (menu rows) have no frame until hovered or focused.
    property bool flat: false
    signal activated()

    height: 44 * root.u
    width: Math.max(height, content.implicitWidth + 28 * root.u)
    radius: 12 * root.u
    color: highlighted ? Qt.rgba(76 / 255, 201 / 255, 240 / 255, 0.16)
         : flat ? (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
         : root.surface
    border.width: Math.max(1, root.u)
    border.color: activeFocus || mouse.containsMouse ? root.accent : (flat ? "transparent" : root.line)
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: activated()
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()

    Behavior on border.color { ColorAnimation { duration: 120 } }

    Row {
      id: content
      // Menu rows read left to right; standalone buttons centre their label.
      x: pill.flat ? 14 * root.u : (pill.width - width) / 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8 * root.u
      Text {
        visible: pill.glyph.length > 0
        text: pill.glyph
        color: root.fg
        font.family: root.mono
        font.pixelSize: 16 * root.u
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: pill.label.length > 0
        text: pill.label
        color: root.fg
        font.family: root.sans
        font.pixelSize: 13 * root.u
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.activated()
    }
  }

  // ---------- Backdrop ----------

  Image {
    id: bg
    anchors.fill: parent
    source: config.background || "background.webp"
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
  }

  // Clicking outside an open menu closes it.
  MouseArea {
    anchors.fill: parent
    enabled: sessionMenu.visible || powerMenu.visible
    onClicked: root.closeMenus()
  }

  Item {
    id: stage
    anchors.fill: parent
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    // ---------- Top bar ----------

    Row {
      x: 48 * root.u
      y: 40 * root.u
      spacing: 12 * root.u
      Item {
        width: 28 * root.u
        height: width
        anchors.verticalCenter: parent.verticalCenter
        Hexagon { anchors.centerIn: parent; radius: 12 * root.u; strokeWidth: 2 * root.u }
        Hexagon { anchors.centerIn: parent; radius: 5 * root.u; strokeWidth: 2 * root.u }
      }
      Text {
        text: "FATHOM"
        color: root.fg
        font.family: root.sans
        font.weight: Font.DemiBold
        font.pixelSize: 13 * root.u
        font.letterSpacing: 1.8 * root.u
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 48 * root.u
      y: 44 * root.u
      text: sddm.hostName
      color: root.muted
      font.family: root.mono
      font.pixelSize: 12 * root.u
    }

    // ---------- Clock ----------

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 92 * root.u
      spacing: 12 * root.u
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(root.now, "HH:mm")
        color: root.fg
        font.family: root.sans
        font.weight: Font.Light
        font.pixelSize: 112 * root.u
        font.letterSpacing: -3 * root.u
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(root.now, "dddd, d MMMM")
        color: root.muted
        font.family: root.sans
        font.pixelSize: 17 * root.u
      }
    }

    // ---------- Sign-in ----------

    Column {
      id: signin
      anchors.horizontalCenter: parent.horizontalCenter
      y: 330 * root.u
      width: 400 * root.u
      spacing: 18 * root.u

      Item {
        id: avatar
        width: 120 * root.u
        height: width
        anchors.horizontalCenter: parent.horizontalCenter

        Rectangle {
          id: ring
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.width: 2 * root.u
          border.color: root.failed ? root.danger : root.accent
          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.failed ? root.danger : root.accent
            shadowBlur: 1.0
            blurMax: 48
            shadowOpacity: 0.9
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
          }
          SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: !root.busy
            NumberAnimation { to: 0.7; duration: 2400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 2400; easing.type: Easing.InOutSine }
          }
          RotationAnimation on rotation {
            running: root.busy
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1600
          }
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: 8 * root.u
          radius: width / 2
          color: "#0f1c33"
          Text {
            anchors.centerIn: parent
            text: root.initial(root.user.realName)
            color: root.fg
            font.family: root.sans
            font.weight: Font.Light
            font.pixelSize: 40 * root.u
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.user.realName
        color: root.fg
        font.family: root.sans
        font.weight: Font.DemiBold
        font.pixelSize: 22 * root.u
      }

      Rectangle {
        id: field
        width: parent.width
        height: 52 * root.u
        radius: 14 * root.u
        color: root.surface
        border.width: Math.max(1, 1.5 * root.u)
        border.color: root.failed ? root.danger : (password.activeFocus ? root.accent : root.line)
        Behavior on border.color { ColorAnimation { duration: 150 } }
        transform: Translate { id: nudge }

        TextInput {
          id: password
          anchors.left: parent.left
          anchors.right: go.left
          anchors.leftMargin: 18 * root.u
          anchors.rightMargin: 10 * root.u
          anchors.verticalCenter: parent.verticalCenter
          echoMode: TextInput.Password
          passwordCharacter: "•"
          color: root.fg
          selectionColor: root.accent
          selectedTextColor: root.accentInk
          font.family: root.sans
          font.pixelSize: 16 * root.u
          font.letterSpacing: 1 * root.u
          clip: true
          focus: true
          enabled: !root.busy
          activeFocusOnTab: true
          Accessible.name: "Password"
          onTextChanged: if (text.length) root.failed = false
          onAccepted: root.submit()
          Keys.onEscapePressed: {
            if (sessionMenu.visible || powerMenu.visible)
              root.closeMenus()
            else
              text = ""
          }
        }

        Text {
          anchors.left: password.left
          anchors.verticalCenter: parent.verticalCenter
          visible: password.text.length === 0
          text: "Password"
          color: root.muted
          font: password.font
        }

        Rectangle {
          id: go
          width: 44 * root.u
          height: width
          radius: 10 * root.u
          anchors.right: parent.right
          anchors.rightMargin: 4 * root.u
          anchors.verticalCenter: parent.verticalCenter
          color: goMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
          opacity: root.busy ? 0.5 : 1
          Accessible.role: Accessible.Button
          Accessible.name: "Sign in"
          Text {
            anchors.centerIn: parent
            text: ""
            color: root.accentInk
            font.family: root.mono
            font.pixelSize: 18 * root.u
          }
          MouseArea {
            id: goMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.submit()
          }
        }
      }

      // One line for whatever matters most right now, so nothing jumps.
      Text {
        width: parent.width
        height: 20 * root.u
        horizontalAlignment: Text.AlignHCenter
        font.family: root.sans
        font.pixelSize: 13 * root.u
        text: root.busy ? "Signing in…"
            : root.failed ? "That password didn’t work. Try again."
            : keyboard.capsLock ? "Caps Lock is on"
            : ""
        color: root.failed ? root.danger : keyboard.capsLock && !root.busy ? root.warn : root.muted
      }

      PillButton {
        visible: root.users.length > 1
        anchors.horizontalCenter: parent.horizontalCenter
        glyph: ""
        label: "Switch user"
        onActivated: {
          root.userIndex = (root.userIndex + 1) % root.users.length
          root.failed = false
          password.text = ""
          password.forceActiveFocus()
        }
      }
    }

    SequentialAnimation {
      id: shake
      NumberAnimation { target: nudge; property: "x"; to: -12 * root.u; duration: 50 }
      NumberAnimation { target: nudge; property: "x"; to: 12 * root.u; duration: 70 }
      NumberAnimation { target: nudge; property: "x"; to: -7 * root.u; duration: 60 }
      NumberAnimation { target: nudge; property: "x"; to: 7 * root.u; duration: 60 }
      NumberAnimation { target: nudge; property: "x"; to: 0; duration: 50 }
    }

    // ---------- Bottom-right controls ----------

    Row {
      id: controls
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: 48 * root.u
      anchors.bottomMargin: 48 * root.u
      spacing: 8 * root.u

      PillButton {
        id: sessionButton
        visible: root.sessions.length > 0
        label: (root.sessions[root.sessionIndex] || { name: "Session" }).name
        glyph: ""
        accessibleName: "Session: " + label
        onActivated: {
          powerMenu.visible = false
          sessionMenu.visible = !sessionMenu.visible
        }
      }

      PillButton {
        visible: keyboard.layouts.length > 0
        label: keyboard.layouts.length > 0 ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
        accessibleName: "Keyboard layout: " + label
        onActivated: if (keyboard.layouts.length > 1) keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
      }

      PillButton {
        id: powerButton
        visible: sddm.canSuspend || sddm.canReboot || sddm.canPowerOff
        glyph: ""
        accessibleName: "Power"
        onActivated: {
          sessionMenu.visible = false
          powerMenu.visible = !powerMenu.visible
        }
      }
    }

    // ---------- Menus ----------

    Rectangle {
      id: sessionMenu
      visible: false
      anchors.right: controls.right
      anchors.bottom: controls.top
      anchors.bottomMargin: 10 * root.u
      width: 300 * root.u
      height: sessionColumn.implicitHeight + 16 * root.u
      radius: 14 * root.u
      color: Qt.rgba(10 / 255, 16 / 255, 32 / 255, 0.96)
      border.width: Math.max(1, root.u)
      border.color: root.line

      Column {
        id: sessionColumn
        x: 8 * root.u
        y: 8 * root.u
        width: parent.width - 16 * root.u
        spacing: 4 * root.u
        Repeater {
          model: root.sessions
          delegate: PillButton {
            width: sessionColumn.width
            label: modelData ? modelData.name : ""
            highlighted: index === root.sessionIndex
            flat: true
            onActivated: {
              root.sessionIndex = index
              sessionMenu.visible = false
              password.forceActiveFocus()
            }
          }
        }
      }
    }

    Rectangle {
      id: powerMenu
      visible: false
      anchors.right: controls.right
      anchors.bottom: controls.top
      anchors.bottomMargin: 10 * root.u
      width: 200 * root.u
      height: powerColumn.implicitHeight + 16 * root.u
      radius: 14 * root.u
      color: Qt.rgba(10 / 255, 16 / 255, 32 / 255, 0.96)
      border.width: Math.max(1, root.u)
      border.color: root.line

      Column {
        id: powerColumn
        x: 8 * root.u
        y: 8 * root.u
        width: parent.width - 16 * root.u
        spacing: 4 * root.u
        PillButton { visible: sddm.canSuspend; width: powerColumn.width; glyph: ""; label: "Sleep"; flat: true; onActivated: sddm.suspend() }
        PillButton { visible: sddm.canReboot; width: powerColumn.width; glyph: ""; label: "Restart"; flat: true; onActivated: sddm.reboot() }
        PillButton { visible: sddm.canPowerOff; width: powerColumn.width; glyph: ""; label: "Shut down"; flat: true; onActivated: sddm.powerOff() }
      }
    }
  }

  Component.onCompleted: {
    Qt.callLater(chooseSession)
    password.forceActiveFocus()
  }
}
