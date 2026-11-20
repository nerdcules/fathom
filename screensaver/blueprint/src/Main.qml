import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window
import Blueprint 1.0

ApplicationWindow {
    id: win
    width: 1280
    height: 800
    minimumWidth: 480
    minimumHeight: 300
    visible: true
    title: slideshow.title.length ? qsTr("Blueprint · %1").arg(slideshow.title) : "Blueprint"
    color: "#1a4a86"
    visibility: slideshow.screensaver || win.fullscreen ? Window.FullScreen : Window.AutomaticVisibility

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    property bool aboutVisible: false
    property bool fullscreen: startFullscreen
    property bool wasActive: false

    // As a screensaver, losing focus means the pointer went to another monitor.
    onActiveChanged: {
        if (active) wasActive = true
        else if (slideshow.screensaver && wasActive) Qt.quit()
    }

    Shortcut { enabled: !slideshow.screensaver; sequence: "Ctrl+I"; context: Qt.ApplicationShortcut; onActivated: win.aboutVisible = !win.aboutVisible }
    Shortcut { enabled: !slideshow.screensaver; sequences: ["Space", "Right", "N"]; context: Qt.ApplicationShortcut; onActivated: slideshow.next() }
    Shortcut { enabled: !slideshow.screensaver; sequences: ["Left", "Backspace", "B"]; context: Qt.ApplicationShortcut; onActivated: slideshow.previous() }
    Shortcut { enabled: !slideshow.screensaver; sequences: ["Return", "Enter"]; context: Qt.ApplicationShortcut; onActivated: slideshow.finishDrawing() }
    Shortcut { enabled: !slideshow.screensaver; sequence: "P"; context: Qt.ApplicationShortcut; onActivated: slideshow.togglePause() }
    Shortcut { enabled: !slideshow.screensaver; sequence: "F"; context: Qt.ApplicationShortcut; onActivated: win.fullscreen = !win.fullscreen }
    Shortcut { enabled: !slideshow.screensaver; sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { enabled: !slideshow.screensaver; sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut {
        enabled: !slideshow.screensaver
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (win.aboutVisible) win.aboutVisible = false
            else if (win.helpVisible) win.helpVisible = false
            else if (win.fullscreen) win.fullscreen = false
            else Qt.quit()
        }
    }

    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        SheetView {
            anchors.fill: parent
            show: slideshow
        }

        // Any input ends a screensaver. The pointer's first report is where it
        // already was when the window mapped, so only movement after it counts.
        MouseArea {
            id: input
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            cursorShape: slideshow.screensaver ? Qt.BlankCursor : Qt.ArrowCursor
            property point origin
            property bool haveOrigin: false
            onPositionChanged: (mouse) => {
                if (!slideshow.screensaver) return
                if (!haveOrigin) { origin = Qt.point(mouse.x, mouse.y); haveOrigin = true; return }
                if (Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) > 8) Qt.quit()
            }
            onPressed: (mouse) => {
                if (slideshow.screensaver) Qt.quit()
                else if (mouse.button === Qt.LeftButton) slideshow.next()
                else if (mouse.button === Qt.RightButton) slideshow.previous()
            }
            onWheel: (wheel) => { if (slideshow.screensaver) Qt.quit(); else wheel.accepted = false }
        }

        Item {
            focus: true
            Keys.onPressed: (event) => { if (slideshow.screensaver) { Qt.quit(); event.accepted = true } }
        }

        // Paused and problems are the only things the sheet itself can't say.
        Label {
            anchors { right: parent.right; top: parent.top; margins: 14 }
            visible: slideshow.paused && !slideshow.screensaver
            text: qsTr("PAUSED")
            font.pixelSize: 13
            font.letterSpacing: 2
            color: "#ecf4ff"
            background: Rectangle { color: "#1a4a86"; border.color: "#ecf4ff"; radius: Math.min(4, theme.radius) }
            padding: 6
            leftPadding: 10
            rightPadding: 10
        }

        Label {
            anchors { left: parent.left; top: parent.top; margins: 14 }
            visible: slideshow.problems.length > 0 && !slideshow.screensaver
            width: Math.min(parent.width - 28, 640)
            wrapMode: Text.Wrap
            text: qsTr("Some diagram files were skipped:\n%1").arg(slideshow.problems)
            font.pixelSize: 12
            color: "#ffd6d6"
            background: Rectangle { color: "#1a2a46"; border.color: "#ffd6d6"; radius: Math.min(4, theme.radius) }
            padding: 8
        }

        HelpOverlay {
            anchors.fill: parent
            visible: win.helpVisible && !slideshow.screensaver
            onDismissed: win.helpVisible = false
        }
    }

    AboutOverlay {
        visible: win.aboutVisible
        appName: "blueprint"
        purpose: qsTr("Software patterns and architectures, drawn as blueprints")
        repository: ""
        onDismissed: win.aboutVisible = false
    }
}
