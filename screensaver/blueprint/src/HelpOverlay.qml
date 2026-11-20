import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: overlay
    signal dismissed

    Rectangle {
        anchors.fill: parent
        color: "#aa0b1e38"
        MouseArea { anchors.fill: parent; onClicked: overlay.dismissed() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 520)
        height: grid.implicitHeight + 72
        color: "#1a4a86"
        border.color: "#ecf4ff"
        border.width: 1.5
        radius: theme.radius

        Label {
            id: heading
            anchors { top: parent.top; left: parent.left; margins: 22 }
            text: qsTr("KEYS")
            font.pixelSize: 15
            font.letterSpacing: 3
            color: "#ecf4ff"
        }

        GridLayout {
            id: grid
            anchors { top: heading.bottom; left: parent.left; right: parent.right; margins: 22; topMargin: 14 }
            columns: 2
            columnSpacing: 24
            rowSpacing: 8

            Repeater {
                model: [
                    ["Space  →", qsTr("Next sheet")],
                    ["←  Backspace", qsTr("Previous sheet")],
                    ["Enter", qsTr("Finish inking this sheet")],
                    ["P", qsTr("Pause or resume")],
                    ["F", qsTr("Toggle fullscreen")],
                    ["Click", qsTr("Next sheet (right click: previous)")],
                    ["?", qsTr("Show or hide these keys")],
                    ["Ctrl + I", qsTr("About this app")],
                    ["Q  Esc", qsTr("Quit")]
                ]
                delegate: Label {
                    required property var modelData
                    required property int index
                    text: modelData[0]
                    Layout.row: index
                    Layout.column: 0
                    font.family: "monospace"
                    font.pixelSize: 14
                    color: "#ecf4ff"
                    opacity: 0.9
                }
            }
            Repeater {
                model: [
                    qsTr("Next sheet"), qsTr("Previous sheet"), qsTr("Finish inking this sheet"), qsTr("Pause or resume"),
                    qsTr("Toggle fullscreen"), qsTr("Next sheet (right click: previous)"), qsTr("Show or hide these keys"), qsTr("Quit")
                ]
                delegate: Label {
                    required property string modelData
                    required property int index
                    text: modelData
                    Layout.row: index
                    Layout.column: 1
                    Layout.fillWidth: true
                    font.pixelSize: 14
                    color: "#ecf4ff"
                }
            }
        }
    }
}
