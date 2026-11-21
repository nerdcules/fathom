import QtQuick
import "kit"
import "."

// A list page inside Quick settings (#14): Wi-Fi networks or Bluetooth
// devices, with a back button, the on/off switch and one row per network or
// device, styled like the tiles (lit when connected). Plain data in, signals
// out: QuickView turns Quickshell's live objects into `rows` and acts on
// what comes back, so this renders and can be tested without them.
//
// rows: [{key, glyph, name, detail, active, busy, ask}] or {header} for a
// section title. `ask` puts a password field under that row.
Item {
  id: list

  property string title: ""
  property bool on: false
  property bool canToggle: true
  property var rows: []
  property string emptyText: ""
  property string note: ""
  property string askLabel: ""
  property string connectLabel: ""
  property string cancelLabel: ""
  property string workingLabel: ""
  property real maxListHeight: 380 * Skin.u

  signal back()
  signal toggled()
  signal picked(string key)
  signal passwordGiven(string key, string password)
  signal askCancelled()

  implicitHeight: content.implicitHeight

  function g(cp) { return String.fromCodePoint(cp) }

  Column {
    id: content
    width: parent.width
    spacing: 12 * Skin.u

    // Back, the title, and the switch.
    Item {
      width: parent.width
      height: 34 * Skin.u
      Pill {
        id: backButton
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        glyph: list.g(0xF0141)
        Accessible.name: list.title
        onClicked: list.back()
      }
      Label {
        anchors { left: backButton.right; leftMargin: 10 * Skin.u; right: toggle.left; rightMargin: 10 * Skin.u; verticalCenter: parent.verticalCenter }
        text: list.title
        font.pixelSize: 15 * Skin.u
        font.weight: Font.DemiBold
      }
      Pill {
        id: toggle
        visible: list.canToggle
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        primary: list.on
        text: list.on ? Skin.t("quick.on") : Skin.t("quick.off")
        Accessible.role: Accessible.CheckBox
        Accessible.checked: list.on
        onClicked: list.toggled()
      }
    }

    Rectangle { width: parent.width; height: 1; color: Skin.faint }

    Label {
      visible: list.rows.length === 0 && list.emptyText !== ""
      width: parent.width
      text: list.emptyText
      color: Skin.dim
      wrapMode: Text.WordWrap
      font.pixelSize: 13 * Skin.u
    }

    Flickable {
      id: flick
      width: parent.width
      height: Math.min(rowsColumn.implicitHeight, list.maxListHeight)
      contentHeight: rowsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: rowsColumn
        width: flick.width
        spacing: 6 * Skin.u

        Repeater {
          model: list.rows
          delegate: Column {
            id: entry
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            width: rowsColumn.width
            spacing: 6 * Skin.u

            Label {
              visible: entry.isHeader
              width: parent.width
              topPadding: 4 * Skin.u
              text: entry.isHeader ? String(entry.modelData.header) : ""
              color: Skin.dim
              font.pixelSize: 12 * Skin.u
            }

            Rectangle {
              id: rowBox
              visible: !entry.isHeader
              width: parent.width
              height: 50 * Skin.u
              radius: 12 * Skin.u
              readonly property bool lit: entry.modelData.active === true
              color: lit ? Skin.tint(Skin.accent, rowMouse.pressed ? 0.55 : (rowMouse.containsMouse ? 0.45 : 0.36))
                : (rowMouse.pressed ? Skin.tint(Skin.fg, 0.16) : (rowMouse.containsMouse ? Skin.tint(Skin.fg, 0.11) : Skin.tint(Skin.fg, 0.06)))
              border.width: 1
              border.color: lit ? Skin.tint(Skin.accent, 0.8) : Skin.tint(Skin.fg, 0.1)
              Accessible.role: Accessible.Button
              Accessible.name: entry.isHeader ? "" : String(entry.modelData.name || "")

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.picked(String(entry.modelData.key))
              }
              Label {
                id: rowGlyph
                anchors { left: parent.left; leftMargin: 14 * Skin.u; verticalCenter: parent.verticalCenter }
                width: 22 * Skin.u
                text: entry.isHeader ? "" : String(entry.modelData.glyph || "")
                color: rowBox.lit ? Skin.fg : Skin.accent
                font.pixelSize: 18 * Skin.u
              }
              Column {
                anchors { left: rowGlyph.right; leftMargin: 10 * Skin.u; right: working.left; rightMargin: 8 * Skin.u; verticalCenter: parent.verticalCenter }
                spacing: 1
                Label {
                  width: parent.width
                  text: entry.isHeader ? "" : String(entry.modelData.name || "")
                  font.pixelSize: 13 * Skin.u
                  font.weight: Font.DemiBold
                }
                Label {
                  width: parent.width
                  visible: text !== ""
                  text: entry.isHeader ? "" : String(entry.modelData.detail || "")
                  color: rowBox.lit ? Skin.fg : Skin.dim
                  font.pixelSize: 11 * Skin.u
                }
              }
              Label {
                id: working
                anchors { right: parent.right; rightMargin: 14 * Skin.u; verticalCenter: parent.verticalCenter }
                visible: !entry.isHeader && entry.modelData.busy === true
                text: list.workingLabel
                color: Skin.dim
                font.pixelSize: 11 * Skin.u
              }
            }

            // The password, under the row it's for.
            Row {
              id: askRow
              visible: !entry.isHeader && entry.modelData.ask === true
              width: parent.width
              spacing: 8 * Skin.u
              onVisibleChanged: if (visible) password.forceActiveFocus()
              Component.onCompleted: if (visible) password.forceActiveFocus()

              Rectangle {
                width: parent.width - connectButton.width - cancelButton.width - 2 * parent.spacing
                height: 34 * Skin.u
                radius: height / 2
                color: Skin.tint(Skin.fg, 0.06)
                border.width: 1
                border.color: password.activeFocus ? Skin.accent : Skin.tint(Skin.fg, 0.18)
                TextInput {
                  id: password
                  objectName: "password"
                  anchors { fill: parent; leftMargin: 14 * Skin.u; rightMargin: 14 * Skin.u }
                  verticalAlignment: TextInput.AlignVCenter
                  echoMode: TextInput.Password
                  color: Skin.fg
                  font.family: Skin.fontFamily
                  font.pixelSize: 13 * Skin.u
                  clip: true
                  Accessible.name: list.askLabel
                  Keys.onReturnPressed: list.passwordGiven(String(entry.modelData.key), text)
                  Keys.onEnterPressed: list.passwordGiven(String(entry.modelData.key), text)
                  Keys.onEscapePressed: function(e) { list.askCancelled(); e.accepted = true }
                  Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: password.text === ""
                    text: list.askLabel
                    color: Skin.dim
                    font.pixelSize: 13 * Skin.u
                  }
                }
              }
              Pill {
                id: connectButton
                primary: true
                text: list.connectLabel
                onClicked: list.passwordGiven(String(entry.modelData.key), password.text)
              }
              Pill {
                id: cancelButton
                text: list.cancelLabel
                onClicked: list.askCancelled()
              }
            }
          }
        }
      }
    }

    Label {
      visible: list.note !== ""
      width: parent.width
      text: list.note
      color: Skin.dim
      wrapMode: Text.WordWrap
      font.pixelSize: 11 * Skin.u
    }
  }
}
