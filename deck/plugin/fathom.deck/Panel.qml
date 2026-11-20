import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."

// Fathom's Command Deck, with its two pages, Deck and Care, and the Start
// menu. The shell loads
// this only while it's open, so it reads the machine (through `fathom-deck
// status` and `fathom-care status`) only then: every few seconds while it's
// on screen, never in the background. Care's hourly check runs from a
// systemd timer instead.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string page: "deck"
  property var info: null
  property var care: null
  property var sentinel: null
  property var pulse: null
  property string pulseRange: "15m"
  property var agents: null
  property var startMenu: null
  // Personalise: `fathom-look state`, and the change in flight.
  property var look: null
  property bool lookBusy: false
  property string lookMessage: ""
  property bool lookFailed: false
  // Crumbs: `fathom-crumbs status`, the chosen domain and its cookies.
  property var crumbs: null
  property var crumbsDetail: null
  property string crumbsSelected: ""
  property bool crumbsBusy: false
  property string crumbsMessage: ""
  property bool crumbsFailed: false
  property var apps: []
  property string error: ""
  property var busy: ({})
  property var cleaning: ({})

  readonly property string home: Quickshell.env("HOME")
  readonly property string deckTool: home + "/.local/bin/fathom-deck"
  readonly property string careTool: home + "/.local/bin/fathom-care"
  readonly property string startTool: home + "/.local/bin/fathom-start"
  readonly property string playerTool: home + "/.local/bin/fathom-player"
  readonly property string sentinelTool: home + "/.local/bin/fathom-sentinel"
  readonly property string pulseTool: home + "/.local/bin/fathom-pulse"
  readonly property string lookTool: home + "/.local/bin/fathom-look"
  readonly property string crumbsTool: home + "/.local/bin/fathom-crumbs"
  readonly property string updateTool: home + "/.local/bin/fathom-update"
  readonly property string pluginId: (manifest && manifest.id) || "fathom.deck"
  // Care runs its own check when it's this stale (the timer may be off).
  readonly property int staleSeconds: 3 * 3600

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  // The look every part reads.
  Binding { target: Skin; property: "fg"; value: Commons.Color.foreground }
  Binding { target: Skin; property: "bg"; value: Commons.Color.background }
  Binding { target: Skin; property: "accent"; value: Commons.Color.accent }
  Binding { target: Skin; property: "urgent"; value: Commons.Color.urgent }
  Binding { target: Skin; property: "fontFamily"; value: Style.font.family }
  Binding { target: Skin; property: "motion"; value: Style.duration(100) / 100 }
  Binding { target: Skin; property: "locale"; value: Qt.locale(Commons.I18n.formatLocale) }
  Binding { target: Skin; property: "strings"; value: catalog }
  Binding { target: Skin; property: "radius"; value: Style.cornerRadius }
  Binding { target: Skin; property: "glassAlpha"; value: Commons.Color.menu.background.a }
  Binding { target: Skin; property: "edgeAlpha"; value: Commons.Color.menu.border.a }

  // The glow is Fathom's own, so it lives only in look.json (fathom-look);
  // the rest of the look reaches here through the theme.
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/fathom/look.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var look = JSON.parse(text())
        Skin.glow = look.glow !== false
      } catch (e) { Skin.glow = true }
    }
    onLoadFailed: Skin.glow = true
  }
  Component.onCompleted: Skin.fmt = function(v, d) { return Commons.I18n.formatNumber(v, d) }

  // `shell summon fathom.deck '{"page":"care"}'` (or "deck", "start",
  // "sentinel", "pulse", "crumbs", "look").
  // Asking for the page that is already showing closes it, so one key opens
  // and closes it.
  function open(payloadJson) {
    var wanted = "deck"
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && ["care", "start", "sentinel", "pulse", "crumbs", "look"].indexOf(payload.page) !== -1) wanted = payload.page
      // Crumbs can open on one domain's cookies.
      if (wanted === "crumbs" && payload && typeof payload.domain === "string" && /^[a-z0-9.-]{1,253}$/.test(payload.domain)) {
        crumbsSelected = payload.domain
        crumbsDetailProc.running = false
        crumbsDetailProc.running = true
        if (opened && page === wanted) { refresh(); return }
      }
    } catch (e) {}
    if (opened && page === wanted) {
      dismiss()
      return
    }
    page = wanted
    opened = true
    if (!blurProc.running) blurProc.running = true
    refresh()
  }

  // Host-initiated close (`shell hide`). Esc and the scrim go through
  // dismiss() so the shell's idea of what is open stays right.
  function close() {
    opened = false
    pause.stop()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function refresh() {
    if (!opened) return
    if (page === "start") {
      // Start reads once when it opens (and after a change), not on a timer.
      if (!startProc.running) startProc.running = true
      apps = collectApps()
    } else if (page === "deck") {
      if (!deckProc.running) deckProc.running = true
    } else if (page === "sentinel") {
      if (!sentinelProc.running) sentinelProc.running = true
    } else if (page === "crumbs") {
      if (!crumbsProc.running) crumbsProc.running = true
      if (crumbsSelected !== "" && !crumbsDetailProc.running) crumbsDetailProc.running = true
    } else if (page === "look") {
      // Read when it opens and after each change, not on a timer.
      if (!lookProc.running) lookProc.running = true
    } else if (page === "pulse") {
      if (!pulseProc.running) pulseProc.running = true
      if (!agentsProc.running) agentsProc.running = true
    } else if (!careProc.running) {
      careProc.running = true
    }
  }

  function setPage(p) {
    page = p
    pause.stop()
    refresh()
    // Keys go to whichever view now shows.
    Qt.callLater(function() {
      if (root.page === "start") startView.focusSearch()
      else view.forceActiveFocus()
    })
  }

  function without(map, keys) {
    var next = ({})
    for (var k in map) if (keys.indexOf(k) === -1) next[k] = map[k]
    return next
  }

  function withKeys(map, keys) {
    var next = without(map, keys)
    for (var i = 0; i < keys.length; i++) next[keys[i]] = true
    return next
  }

  function parse(text) {
    try {
      var parsed = JSON.parse(text)
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.error = catalog.t("readFailed").arg(String(e).slice(0, 120))
      return null
    }
  }

  // Run a command and refresh when it ends; `then` runs first.
  function run(command, then) {
    var proc = actionComponent.createObject(root, { command: command, then: then || null })
    proc.running = true
  }

  // Run something that may ask for a password or opens its own window:
  // close the deck so nothing sits on top of it.
  function handOff(command) {
    Quickshell.execDetached(command)
    dismiss()
  }

  function containerAction(action, name) {
    if (busy[name] === true) return
    busy = withKeys(busy, [name])
    run([deckTool, "container", action, name], function() { root.busy = root.without(root.busy, [name]) })
  }

  function clean(ids, needsRoot) {
    if (ids.length === 0) return
    if (needsRoot) {
      handOff([careTool, "clean", "--notify"].concat(ids))
      return
    }
    cleaning = withKeys(cleaning, ids)
    run([careTool, "clean"].concat(ids), function() { root.cleaning = root.without(root.cleaning, ids) })
  }

  function restartUnit(scope, unit) {
    if (scope === "user") run([careTool, "restart", "user", unit])
    else handOff([careTool, "restart", "system", unit])
  }

  // ------------------------------------------------ Start

  // The desktop's apps, as plain objects for StartView.
  function collectApps() {
    var values = DesktopEntries.applications.values || []
    var out = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      out.push({
        id: String(e.id || ""),
        name: String(e.name || e.id || ""),
        comment: String(e.genericName || e.comment || ""),
        icon: iconUrl(e.icon),
        keywords: Array.isArray(e.keywords) ? e.keywords.join(" ") : String(e.keywords || "")
      })
    }
    return out
  }

  function iconUrl(icon) {
    var value = String(icon || "")
    if (value === "") return ""
    if (value.charAt(0) === "/") return "file://" + value
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    return Quickshell.iconPath(value, true) || ""
  }

  // As Omarchy's own launcher does: terminal apps through its TUI launcher,
  // the rest through gtk-launch in their own scope.
  function launchApp(id) {
    var entry = DesktopEntries.byId(id)
    if (entry && entry.runInTerminal) {
      var command = (entry.command || []).filter(function(w) { return !/^%[a-zA-Z]$/.test(String(w)) })
      if (command.length > 0) { handOff(["omarchy-launch-tui"].concat(command)); return }
    }
    handOff(["uwsm-app", "--", "gtk-launch", String(id) + ".desktop"])
  }

  function startAction(id) {
    if (id === "focus") run([startTool, "focus"])
    else if (id === "play") handOff([playerTool, "play"])
    else handOff([startTool, "power", id])
  }

  // ------------------------------------------------ Personalise

  // One change at a time: `fathom-look set …` (rebuilds and refreshes the
  // theme, a few seconds), `bar <mode>` or `wallpaper <file>`.
  function lookRun(args, doneText) {
    if (lookBusy) return
    lookBusy = true
    lookFailed = false
    lookMessage = ""
    lookActProc.doneText = doneText
    lookActProc.command = [lookTool].concat(args)
    lookActProc.running = true
  }

  // ------------------------------------------------ Crumbs

  function crumbsSelect(domain) {
    crumbsSelected = crumbsSelected === domain ? "" : domain
    if (crumbsSelected !== "") {
      crumbsDetailProc.running = false
      crumbsDetailProc.running = true
    }
  }

  // Forgetting runs as you; changing the rules asks for your password, so
  // the deck steps aside and the result comes as a notification.
  function crumbsForget(domain, browser) {
    if (crumbsBusy) return
    crumbsBusy = true
    crumbsFailed = false
    crumbsMessage = ""
    crumbsActProc.command = [crumbsTool, "forget", domain, browser]
    crumbsActProc.running = true
  }

  function check() {
    if (!checkProc.running) checkProc.running = true
  }

  // Is blur on? Decides how see-through the deck is (Skin.glass).
  Process {
    id: blurProc
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        // Unreadable: keep the last answer (solid by default), no banner.
        try {
          var o = JSON.parse(text)
          Skin.glass = o.bool !== undefined ? !!o.bool : !!o.int
        } catch (e) {}
      }
    }
  }

  Process {
    id: deckProc
    command: [root.deckTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (parsed && parsed.system) { root.info = parsed; root.error = "" }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("fathom.deck:", msg.slice(0, 400))
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  Process {
    id: careProc
    command: [root.careTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (!parsed || !parsed.disk) return
        root.care = parsed
        root.error = ""
        var stale = !parsed.checkedAt || parsed.time - parsed.checkedAt > root.staleSeconds
        if (stale && parsed.checking !== true) root.check()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("fathom.deck (care):", msg.slice(0, 400))
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  // The app list fills in after the shell starts, and changes as apps are
  // installed; keep Start's copy current while it shows.
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { if (root.opened && root.page === "start") root.apps = root.collectApps() }
  }

  Process {
    id: sentinelProc
    command: [root.sentinelTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (parsed && parsed.firewall) { root.sentinel = parsed; root.error = "" }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  Process {
    id: pulseProc
    command: [root.pulseTool, "status", root.pulseRange]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (parsed && parsed.running !== undefined) { root.pulse = parsed; root.error = "" }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = catalog.t("readFailed").arg("exit " + exitCode)
      if (root.opened) pause.restart()
    }
  }

  // Claude Code's day. It needs no service, and a failure here leaves the
  // rest of the page alone: the card keeps what it last showed.
  Process {
    id: agentsProc
    command: [root.pulseTool, "agents"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && Array.isArray(parsed.projects)) root.agents = parsed
        } catch (e) {}
      }
    }
  }

  Process {
    id: startProc
    command: [root.startTool, "menu"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = root.parse(text)
        if (parsed && parsed.config) { root.startMenu = parsed; root.error = "" }
      }
    }
  }

  Process {
    id: crumbsProc
    command: [root.crumbsTool, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && Array.isArray(parsed.domains)) { root.crumbs = parsed; root.crumbsFailed = false; return }
        } catch (e) {}
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.crumbsBusy) {
        root.crumbsFailed = true
        root.crumbsMessage = catalog.t("crumbs.missing")
      }
      if (root.opened && root.page === "crumbs") pause.restart()
    }
  }

  Process {
    id: crumbsDetailProc
    command: [root.crumbsTool, "cookies", root.crumbsSelected]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && Array.isArray(parsed.cookies)) root.crumbsDetail = parsed
        } catch (e) {}
      }
    }
  }

  Process {
    id: crumbsActProc
    stdout: StdioCollector { id: crumbsOut }
    stderr: StdioCollector { id: crumbsErr }
    onExited: function(exitCode) {
      root.crumbsBusy = false
      root.crumbsFailed = exitCode !== 0
      var said = exitCode === 0 ? crumbsOut.text : crumbsErr.text
      root.crumbsMessage = String(said || "").trim().replace(/^fathom-crumbs: /, "").split("\n").join(" · ").slice(0, 240)
      if (!crumbsProc.running) crumbsProc.running = true
      if (root.crumbsSelected !== "" && !crumbsDetailProc.running) crumbsDetailProc.running = true
    }
  }

  Process {
    id: lookProc
    command: [root.lookTool, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && parsed.look) { root.look = parsed; return }
        } catch (e) {}
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.lookBusy) {
        root.lookFailed = true
        root.lookMessage = catalog.t("look.missing")
      }
    }
  }

  Process {
    id: lookActProc
    property string doneText: ""
    stderr: StdioCollector { id: lookErr }
    onExited: function(exitCode) {
      root.lookBusy = false
      root.lookFailed = exitCode !== 0
      root.lookMessage = exitCode === 0 ? doneText : String(lookErr.text || "").trim().replace(/^fathom-look: /, "").slice(0, 200)
      // Glassy turns blur on and the others may turn it off.
      if (!blurProc.running) blurProc.running = true
      if (!lookProc.running) lookProc.running = true
    }
  }

  Process {
    id: checkProc
    command: [root.careTool, "check"]
    onExited: root.refresh()
  }

  // The next reading starts a little after the last one finished. Start
  // doesn't poll.
  Timer {
    id: pause
    onTriggered: if (root.page !== "start" && root.page !== "look") root.refresh()
    // Crumbs copies the browsers' files each time, so less often.
    interval: root.page === "deck" ? 2500 : (root.page === "crumbs" ? 15000 : 5000)
  }

  Component {
    id: actionComponent
    Process {
      property var then: null
      onExited: function(exitCode) {
        if (typeof then === "function") then()
        root.refresh()
        destroy()
      }
    }
  }

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "fathom-deck"

    Stage {
      anchors.fill: parent

      DeckView {
        id: view
        anchors.fill: parent
        visible: root.page !== "start"
        shown: window.contentRevealed && visible
        page: root.page === "start" ? "deck" : root.page
        info: root.info
        care: root.care
        error: root.error
        busy: root.busy
        cleaning: root.cleaning
        checking: checkProc.running

        onCloseRequested: root.dismiss()
        onPageRequested: function(p) { root.setPage(p) }
        onContainerAction: function(action, name) { root.containerAction(action, name) }
        onLogsRequested: function(name) { root.handOff([root.deckTool, "logs", name]) }
        onDockerRequested: root.handOff([root.deckTool, "docker"])
        onCopyRequested: function(text) { Quickshell.execDetached(["wl-copy", text]) }
        onCleanRequested: function(ids, needsRoot) { root.clean(ids, needsRoot) }
        onRestartRequested: function(scope, unit) { root.restartUnit(scope, unit) }
        onUnitLogRequested: function(scope, unit) { root.handOff([root.careTool, "log", scope, unit]) }
        onUpdateRequested: root.handOff([root.careTool, "update"])
        // Reinstalling restarts the shell (and may ask for a password), so
        // the deck steps aside; a notification says how it went.
        onFathomUpdateRequested: root.handOff([root.updateTool, "--notify", "apply"])
        onCheckRequested: root.check()
        sentinel: root.sentinel
        // Firewall changes ask for your password, so the deck steps aside.
        onLockdownRequested: function(on) { root.handOff([root.sentinelTool, "lockdown", on ? "on" : "off"]) }
        onBlockRequested: function(ip) { root.handOff([root.sentinelTool, "block", ip]) }
        onUnblockRequested: function(ip) { root.handOff([root.sentinelTool, "unblock", ip]) }
        onTrustRequested: function(mac, trust) { root.run([root.sentinelTool, trust ? "trust" : "forget", mac]) }
        onCheckFilesRequested: root.handOff([root.sentinelTool, "check-files"])
        onSentinelLogRequested: function(what) { root.handOff([root.sentinelTool, "log", what]) }
        onSnitchRequested: root.handOff(["uwsm-app", "--", "opensnitch-ui"])
        pulse: root.pulse
        agents: root.agents
        pulseRange: root.pulseRange
        onPulseRangeRequested: function(range) {
          root.pulseRange = range
          if (!pulseProc.running) pulseProc.running = true
        }
        // Claude Code opens in a terminal, so the deck steps aside.
        onAskRequested: function(text) { root.handOff([root.startTool, "ask", text]) }
        look: root.look
        lookBusy: root.lookBusy
        lookMessage: root.lookMessage
        lookFailed: root.lookFailed
        onLookApplyRequested: function(args) { root.lookRun(args, catalog.t("look.applied")) }
        onLookBarRequested: function(mode) { root.lookRun(["bar", mode], catalog.t("look.barDone")) }
        onLookWallpaperRequested: function(path) { root.lookRun(["wallpaper", path], catalog.t("look.wallpaperDone")) }
        onLookScreensaverRequested: function(args) { root.lookRun(["screensaver"].concat(args), catalog.t("look.ssDone")) }
        onLookScreensaverHandOff: function(args) { root.handOff([root.lookTool, "screensaver"].concat(args)) }
        crumbs: root.crumbs
        crumbsDetail: root.crumbsDetail
        crumbsSelected: root.crumbsSelected
        crumbsBusy: root.crumbsBusy
        crumbsMessage: root.crumbsMessage
        crumbsFailed: root.crumbsFailed
        onCrumbsSelectRequested: function(domain) { root.crumbsSelect(domain) }
        onCrumbsApplyRequested: function(args) { root.handOff([root.crumbsTool, "--notify"].concat(args)) }
        onCrumbsClearRequested: root.handOff([root.crumbsTool, "--notify", "clear"])
        onCrumbsForgetRequested: function(domain, browser) { root.crumbsForget(domain, browser) }
      }

      StartView {
        id: startView
        anchors.fill: parent
        visible: root.page === "start"
        shown: window.contentRevealed && visible
        apps: root.apps
        menu: root.startMenu

        onCloseRequested: root.dismiss()
        onLaunchApp: function(id) { root.launchApp(id) }
        onOpenPage: function(p) { root.setPage(p) }
        onOpenProject: function(how, path) { root.handOff([root.startTool, "open", how, path]) }
        onAskRequested: function(text, path) {
          root.handOff(path ? [root.startTool, "ask", text, path] : [root.startTool, "ask", text])
        }
        onActionRequested: function(id) { root.startAction(id) }
        onPinRequested: function(id, pin) { root.run([root.startTool, pin ? "pin" : "unpin", id]) }
      }
    }

    onContentRevealedChanged: if (contentRevealed) {
      if (root.page === "start") startView.focusSearch()
      else view.forceActiveFocus()
    }
  }
}
