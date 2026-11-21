import QtQuick
import "kit"
import QtQuick.Layouts
import "."
import "kit/Format.js" as F

// Personalise: Fathom's accent, window frame, corners, how see-through
// panels are and their glow, plus the bar, the wallpaper and the
// screensaver. Changes to the
// look wait in a draft, shown in the preview, until Apply hands them to
// `fathom-look set`, which rebuilds the theme and refreshes it. The bar and
// the wallpaper are Omarchy's own settings and change at once, as do the
// screensaver's (`fathom-look screensaver …`).
GridLayout {
  id: page

  // `fathom-look state`. (Not `state`: every Item has one already.)
  property var lookState: null
  property bool busy: false
  property string message: ""
  property bool failed: false

  signal applyRequested(var args)
  signal barRequested(string mode)
  signal wallpaperRequested(string path)
  // `fathom-look screensaver <args>`: settings run here; the preview and
  // Omarchy's picture picker and text editor open over the desktop, so the
  // deck steps aside for them (handOff).
  signal screensaverRequested(var args)
  signal screensaverHandOff(var args)

  readonly property var saved: F.lookClean(lookState ? lookState.look : null)
  property var draft: F.lookClean(null)
  readonly property bool dirty: !F.lookSame(draft, saved)
  readonly property var wallpapers: lookState && Array.isArray(lookState.wallpapers) ? lookState.wallpapers : []
  readonly property bool blur: !!lookState && lookState.blur === true
  readonly property var saver: lookState && lookState.screensaver ? lookState.screensaver : null

  // 30 -> "30 s", 150 -> "2.5 min", 3600 -> "1 h".
  function duration(seconds) {
    if (seconds < 60) return Skin.t("look.ss.sec").arg(Skin.n(seconds))
    if (seconds < 3600 || seconds % 3600 !== 0) return Skin.t("look.ss.min").arg(Skin.n(seconds / 60, seconds % 60 === 0 ? 0 : 1))
    return Skin.t("look.ss.hour").arg(Skin.n(seconds / 3600))
  }

  columns: 3
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  // The draft follows the saved look when that changes (an Apply, or
  // fathom-look run elsewhere); a reading that only changed the bar or the
  // wallpaper leaves it alone.
  property var lastSaved: F.lookClean(null)
  onSavedChanged: if (!F.lookSame(saved, lastSaved)) { lastSaved = saved; draft = saved }
  function change(key, value) {
    var next = F.lookClean(draft)
    next[key] = value
    draft = next
  }

  function summary() {
    if (!lookState) return [{ tone: page.failed ? "bad" : "stopped", text: page.failed ? page.message : Skin.t("loading") }]
    var out = []
    if (dirty) out.push({ tone: "warn", text: Skin.t("look.summary.draft") })
    out.push({ tone: "ok", text: Skin.t("look.summary.accent").arg(saved.accent)
      .arg(Skin.t(saved.frameStyle === "solid" ? "look.frameSolid" : "look.frameGradient").toLowerCase()) })
    out.push({ tone: "ok", text: Skin.t("look.summary.shape").arg(Skin.n(saved.corners)).arg(Skin.n(saved.opacity)) })
    if (!lookState.fathomOn) out.push({ tone: "warn", text: Skin.t("look.summary.off") })
    return out
  }

  // A round colour to pick. The chosen one wears a ring.
  component Swatch: Rectangle {
    id: swatch
    property string hex: ""
    property string name: ""
    property bool chosen: false
    signal picked()
    width: 30 * Skin.u
    height: width
    radius: width / 2
    color: hex
    border.width: chosen ? 3 : (swatchMouse.containsMouse ? 2 : 0)
    border.color: chosen ? Skin.fg : Skin.tint(Skin.fg, 0.6)
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: name
    Keys.onReturnPressed: picked()
    Keys.onEnterPressed: picked()
    Keys.onSpacePressed: picked()
    FocusRing {}
    MouseArea {
      id: swatchMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: swatch.picked()
    }
    Tip { target: swatch; text: swatch.name; show: swatchMouse.containsMouse }
  }

  // A row of swatches and a field for any other colour.
  component ColourPicker: ColumnLayout {
    id: picker
    property string value: ""
    signal chose(string hex)
    onValueChanged: if (!hexField.activeFocus) hexField.text = value
    Layout.fillWidth: true
    spacing: 10 * Skin.u
    Flow {
      Layout.fillWidth: true
      spacing: 10 * Skin.u
      Repeater {
        model: F.LOOK_SWATCHES
        delegate: Swatch {
          required property var modelData
          hex: modelData.hex
          name: Skin.t("look.colour." + modelData.key)
          chosen: picker.value === modelData.hex
          onPicked: picker.chose(modelData.hex)
        }
      }
    }
    RowLayout {
      spacing: 10 * Skin.u
      Rectangle {
        width: 22 * Skin.u
        height: width
        radius: 6 * Skin.u
        color: F.lookHex(hexField.text) || picker.value
      }
      Rectangle {
        Layout.preferredWidth: 120 * Skin.u
        implicitHeight: 30 * Skin.u
        radius: 8 * Skin.u
        color: Skin.tint(Skin.fg, 0.06)
        border.width: 1
        border.color: hexField.activeFocus ? Skin.tint(Skin.accent, 0.7) : Skin.faint
        TextInput {
          id: hexField
          anchors.fill: parent
          anchors.leftMargin: 10 * Skin.u
          anchors.rightMargin: 10 * Skin.u
          verticalAlignment: TextInput.AlignVCenter
          color: Skin.fg
          selectionColor: Skin.tint(Skin.accent, 0.4)
          font.family: Skin.fontFamily
          font.pixelSize: 14 * Skin.u
          maximumLength: 7
          validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
          text: picker.value
          // Typing a whole colour takes it; Return or leaving the field puts
          // back the chosen one if what's typed isn't a colour.
          onTextEdited: if (F.lookHex(text) !== "") picker.chose(F.lookHex(text))
          onEditingFinished: text = picker.value
          Accessible.name: Skin.t("look.hexName")
        }
      }
      Label {
        text: Skin.t("look.hexHint")
        color: Skin.dim
        font.pixelSize: 12 * Skin.u
        Layout.fillWidth: true
      }
    }
  }

  // A labelled slider over whole numbers. Arrow keys step by one.
  component NumberSlider: ColumnLayout {
    id: slider
    property string title: ""
    property string valueText: ""
    property int from: 0
    property int to: 100
    property int value: 0
    signal moved(int value)
    Layout.fillWidth: true
    spacing: 6 * Skin.u
    RowLayout {
      Layout.fillWidth: true
      Label { text: slider.title; Layout.fillWidth: true }
      Label { text: slider.valueText; color: Skin.dim; font.pixelSize: 13 * Skin.u }
    }
    Item {
      id: track
      Layout.fillWidth: true
      implicitHeight: 22 * Skin.u
      activeFocusOnTab: true
      Accessible.role: Accessible.Slider
      Accessible.name: slider.title
      readonly property real ratio: (slider.value - slider.from) / Math.max(1, slider.to - slider.from)
      Keys.onLeftPressed: slider.moved(Math.max(slider.from, slider.value - 1))
      Keys.onRightPressed: slider.moved(Math.min(slider.to, slider.value + 1))
      Rectangle {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6 * Skin.u
        radius: height / 2
        color: Skin.tint(Skin.fg, 0.14)
        Rectangle {
          width: Math.max(height, parent.width * track.ratio)
          height: parent.height
          radius: height / 2
          color: Skin.accent
        }
      }
      Rectangle {
        id: lookKnob
        x: track.width * track.ratio - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * Skin.u
        height: width
        radius: width / 2
        color: Skin.fg
      }
      FocusRing { target: lookKnob; shown: track.activeFocus }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -6 * Skin.u
        cursorShape: Qt.PointingHandCursor
        function at(x) {
          var r = Math.max(0, Math.min(1, (x - 6 * Skin.u) / track.width))
          return Math.round(slider.from + r * (slider.to - slider.from))
        }
        onPressed: function(e) { track.forceActiveFocus(); slider.moved(at(e.x)) }
        onPositionChanged: function(e) { if (pressed) slider.moved(at(e.x)) }
      }
    }
  }

  // ------------------------------------------------ Colour
  Card {
    title: Skin.t("look.colourTitle")
    glyph: ""

    Empty {
      visible: !page.lookState && page.failed
      text: page.message
      color: Skin.warn
    }

    SectionTitle { text: Skin.t("look.accent") }
    ColourPicker {
      value: page.draft.accent
      onChose: function(hex) { page.change("accent", hex) }
    }
    Empty { text: Skin.t("look.accentDetail"); font.pixelSize: 12 * Skin.u }

    SectionTitle { text: Skin.t("look.frame") }
    Row {
      spacing: 8 * Skin.u
      Pill {
        text: Skin.t("look.frameGradient")
        selected: page.draft.frameStyle === "gradient"
        onClicked: page.change("frameStyle", "gradient")
      }
      Pill {
        text: Skin.t("look.frameSolid")
        selected: page.draft.frameStyle === "solid"
        onClicked: page.change("frameStyle", "solid")
      }
    }
    ColourPicker {
      visible: page.draft.frameStyle === "gradient"
      value: page.draft.frame
      onChose: function(hex) { page.change("frame", hex) }
    }
    Empty {
      text: page.draft.frameStyle === "gradient" ? Skin.t("look.frameGradientDetail") : Skin.t("look.frameSolidDetail")
      font.pixelSize: 12 * Skin.u
    }
  }

  // ------------------------------------------------ Shape and glass
  // Three across: Shape and Preview take both rows, and the Screensaver
  // card sits under Colour.
  Card {
    title: Skin.t("look.shapeTitle")
    Layout.rowSpan: page.columns >= 3 ? 2 : 1
    glyph: ""

    NumberSlider {
      title: Skin.t("look.corners")
      from: 0
      to: 30
      value: page.draft.corners
      valueText: page.draft.corners === 0 ? Skin.t("look.square") : Skin.t("look.px").arg(Skin.n(page.draft.corners))
      onMoved: function(v) { page.change("corners", v) }
    }
    Empty { text: Skin.t("look.cornersDetail"); font.pixelSize: 12 * Skin.u }

    NumberSlider {
      title: Skin.t("look.opacity")
      from: 60
      to: 100
      value: page.draft.opacity
      valueText: Skin.t("look.percent").arg(Skin.n(page.draft.opacity))
      onMoved: function(v) { page.change("opacity", v) }
    }
    Empty {
      text: page.blur ? Skin.t("look.opacityDetail") : Skin.t("look.opacityNoBlur")
      color: page.blur ? Skin.dim : Skin.warn
      font.pixelSize: 12 * Skin.u
    }

    SectionTitle { text: Skin.t("look.glow") }
    Row {
      spacing: 8 * Skin.u
      Pill { text: Skin.t("look.on"); selected: page.draft.glow; onClicked: page.change("glow", true) }
      Pill { text: Skin.t("look.off"); selected: !page.draft.glow; onClicked: page.change("glow", false) }
    }

    SectionTitle { text: Skin.t("look.bar") }
    Row {
      spacing: 8 * Skin.u
      Repeater {
        model: ["glassy", "opaque", "none"]
        delegate: Pill {
          required property string modelData
          text: Skin.t("look.bar." + modelData)
          selected: !!page.lookState && page.lookState.bar === modelData
          enabledAction: !!page.lookState && !page.busy
          onClicked: page.barRequested(modelData)
        }
      }
    }
    Empty { text: Skin.t("look.barDetail"); font.pixelSize: 12 * Skin.u }
  }

  // ------------------------------------------------ Preview and wallpaper
  Card {
    title: Skin.t("look.previewTitle")
    Layout.rowSpan: page.columns >= 3 ? 2 : 1
    glyph: ""
    subtitle: page.dirty ? Skin.t("look.notApplied") : ""
    subtitleColor: Skin.warn

    // The desktop in small: the wallpaper, a window in its frame and a panel
    // as Fathom draws one, at the draft's real corner size.
    Item {
      id: preview
      Layout.fillWidth: true
      implicitHeight: width * 9 / 16
      clip: true

      readonly property color accent: page.draft.accent
      readonly property real panelAlpha: page.blur ? page.draft.opacity / 100 : 1

      Rectangle { anchors.fill: parent; color: Skin.bg; radius: 10 * Skin.u }
      Image {
        anchors.fill: parent
        source: page.lookState && page.lookState.wallpaper ? "file://" + page.lookState.wallpaper : ""
        sourceSize.width: 640
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.85
      }

      // A window: the frame is the border's gradient (or the accent), the
      // window's own background inside it.
      Rectangle {
        id: frame
        x: parent.width * 0.06
        y: parent.height * 0.1
        width: parent.width * 0.58
        height: parent.height * 0.78
        radius: page.draft.corners
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: preview.accent }
          GradientStop { position: 1; color: page.draft.frameStyle === "gradient" ? page.draft.frame : preview.accent }
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: Math.max(0, page.draft.corners - 2)
          color: Skin.bg
          Column {
            anchors { left: parent.left; top: parent.top; margins: 12 * Skin.u }
            spacing: 6 * Skin.u
            Repeater {
              model: [0.7, 0.5, 0.62, 0.4]
              delegate: Rectangle {
                required property real modelData
                width: frame.width * modelData
                height: 6 * Skin.u
                radius: height / 2
                color: Skin.tint(Skin.fg, 0.18)
              }
            }
          }
        }
      }

      // A panel, as Card and the Start menu draw theirs.
      Rectangle {
        id: mockPanel
        x: parent.width * 0.5
        y: parent.height * 0.3
        width: parent.width * 0.44
        height: parent.height * 0.58
        radius: page.draft.corners
        color: Skin.tint(Skin.bg, preview.panelAlpha)
        border.width: 1
        border.color: Skin.tint(preview.accent, Skin.edgeAlpha)
        clip: true
        Rectangle {
          visible: page.draft.glow
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
          height: parent.height * 0.5
          radius: mockPanel.radius
          gradient: Gradient {
            GradientStop { position: 0; color: Skin.tint(preview.accent, 0.09) }
            GradientStop { position: 1; color: "transparent" }
          }
        }
        Column {
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 * Skin.u }
          spacing: 8 * Skin.u
          Label { text: Skin.t("look.previewPanel"); font.pixelSize: 12 * Skin.u }
          Rectangle {
            width: parent.width * 0.6
            height: 18 * Skin.u
            radius: height / 2
            color: Skin.tint(preview.accent, 0.30)
          }
          Rectangle {
            width: parent.width
            height: 5 * Skin.u
            radius: height / 2
            color: Skin.tint(Skin.fg, 0.14)
            Rectangle { width: parent.width * 0.62; height: parent.height; radius: height / 2; color: preview.accent }
          }
        }
      }
    }

    SectionTitle { text: Skin.t("look.wallpaper") }
    Flow {
      Layout.fillWidth: true
      spacing: 10 * Skin.u
      Repeater {
        model: page.wallpapers
        delegate: Rectangle {
          id: thumb
          required property var modelData
          readonly property bool current: !!page.lookState && page.lookState.wallpaper === modelData.path
          width: 112 * Skin.u
          height: 63 * Skin.u
          radius: 8 * Skin.u
          color: Skin.faint
          border.width: current ? 2 : (thumbMouse.containsMouse ? 1 : 0)
          border.color: current ? Skin.accent : Skin.tint(Skin.fg, 0.6)
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.name
          FocusRing {}
          Keys.onReturnPressed: page.wallpaperRequested(modelData.path)
          Keys.onSpacePressed: page.wallpaperRequested(modelData.path)
          Image {
            anchors.fill: parent
            anchors.margins: 3
            source: "file://" + thumb.modelData.path
            sourceSize.width: 224
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
          MouseArea {
            id: thumbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !page.busy
            onClicked: page.wallpaperRequested(thumb.modelData.path)
          }
          Tip { target: thumb; text: thumb.modelData.name; show: thumbMouse.containsMouse }
        }
      }
    }
    Empty {
      visible: !!page.lookState && page.wallpapers.length === 0
      text: Skin.t("look.noWallpapers")
    }

    footer: [
      Pill {
        primary: true
        text: page.busy ? Skin.t("look.applying") : Skin.t("look.apply")
        enabledAction: page.dirty && !page.busy && !!page.lookState
        onClicked: page.applyRequested(F.lookArgs(page.draft))
      },
      Pill {
        text: Skin.t("look.undo")
        enabledAction: page.dirty && !page.busy
        onClicked: page.draft = page.saved
      },
      Pill {
        text: Skin.t("look.fathom")
        tip: Skin.t("look.fathomTip")
        enabledAction: !page.busy && !F.lookSame(page.draft, F.LOOK_DEFAULTS)
        onClicked: page.draft = F.lookClean(F.LOOK_DEFAULTS)
      },
      Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: page.busy ? Skin.t("look.applyingDetail") : page.message
        color: page.failed ? Skin.urgent : Skin.dim
        font.pixelSize: 12 * Skin.u
      }
    ]
  }

  // ------------------------------------------------ Screensaver
  Card {
    title: Skin.t("look.ssTitle")
    glyph: "\uf108"

    // Off is one of the choices: picking a time turns it on.
    SectionTitle { text: Skin.t("look.ssAfter") }
    Flow {
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      Pill {
        text: Skin.t("look.off")
        selected: !!page.saver && !page.saver.on
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverRequested(["off"])
      }
      Repeater {
        model: [60, 150, 300, 600, 900, 1800]
        delegate: Pill {
          required property int modelData
          text: page.duration(modelData)
          selected: !!page.saver && page.saver.on && page.saver.after === modelData
          enabledAction: !!page.saver && !page.busy
          onClicked: page.screensaverRequested(["after", String(modelData)])
        }
      }
    }

    SectionTitle { text: Skin.t("look.ssLock") }
    Flow {
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      Repeater {
        model: [300, 600, 900, 1800, 3600, 0]
        delegate: Pill {
          required property int modelData
          text: modelData === 0 ? Skin.t("look.ssNever") : page.duration(modelData)
          selected: !!page.saver && page.saver.lockAfter === modelData
          enabledAction: !!page.saver && !page.busy
          onClicked: page.screensaverRequested(["lock-after", String(modelData)])
        }
      }
    }
    Empty {
      visible: !!page.saver && page.saver.lockAfter === 0
      text: Skin.t("look.ssLockNever")
      color: Skin.warn
      font.pixelSize: 12 * Skin.u
    }

    SectionTitle { text: Skin.t("look.ssShows") }
    Flow {
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      // Fathom's screensaver (./install.sh --screensaver), when it's the one in use.
      Pill {
        visible: !!page.saver && page.saver.blueprint === true
        text: Skin.t("look.ssShows.blueprint")
        tip: Skin.t("look.ssShows.blueprintTip")
        selected: !!page.saver && page.saver.shows === "blueprint"
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverRequested(["shows", "blueprint"])
      }
      Pill {
        text: Skin.t("look.ssShows.omarchy")
        selected: !!page.saver && page.saver.shows === "omarchy"
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverRequested(["shows", "omarchy"])
      }
      Pill {
        text: Skin.t("look.ssShows.fathom")
        selected: !!page.saver && page.saver.shows === "fathom"
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverRequested(["shows", "fathom"])
      }
      Pill {
        text: Skin.t("look.ssShows.picture")
        tip: Skin.t("look.ssShows.pictureTip")
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverHandOff(["shows", "picture"])
      }
      Pill {
        text: Skin.t("look.ssShows.text")
        tip: Skin.t("look.ssShows.textTip")
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverHandOff(["shows", "text"])
      }
    }
    Empty {
      visible: !!page.saver && page.saver.shows === "custom"
      text: Skin.t("look.ssShowsCustom")
      font.pixelSize: 12 * Skin.u
    }
    Empty {
      visible: !!page.saver && !!page.saver.service
      text: page.saver && page.saver.service ? Skin.t("look.ssService").arg(page.saver.service) : ""
      font.pixelSize: 12 * Skin.u
    }

    footer: [
      Pill {
        text: Skin.t("look.ssPreview")
        glyph: "\uf04b"
        enabledAction: !!page.saver && !page.busy
        onClicked: page.screensaverHandOff(["preview"])
      }
    ]
  }
}
