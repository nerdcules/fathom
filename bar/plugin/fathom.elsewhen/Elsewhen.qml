import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Model.js" as Model
import "Elsewhen.js" as W

// Fathom's world clock on the bar (#14): Omarchy's world clock (Elsewhen,
// by Jason Fried) with Fathom's own dropdown: one row per city with its
// time, whether it's day or night there, the day when it isn't today, how
// far it is from here (or from UTC) and its temperature; a city search to
// add one, and one to say where here is; moving and removing a city; and
// 24-hour time, UTC offsets and °C or °F. A clone of omarchy.elsewhen
// (manifest.json): turning it on puts it where Omarchy's was, with its
// settings (the cities, here, hour24, offsetMode, units); turning it off
// puts Omarchy's back, with its globe, daylight strips and people, which
// this one leaves out. It answers to omarchy.elsewhen as Omarchy's does
// (`omarchy-shell omarchy.elsewhen open|close|toggle|refresh|times|add|
// remove|here`).
//
// Elsewhen's own model (Model.js) is copied unchanged, and its fetching is
// done as its Panel.qml (MIT) does it: a `date` probe for each zone's offset
// (on opening and every five minutes, for DST), timedatectl's zone list and
// the geocoder for the search, the geocoder and open-meteo for each city's
// temperature, and timedatectl (through Omarchy's passwordless rule) when
// here moves to another zone.
Panel {
  id: root
  moduleName: "omarchy.elsewhen"
  ipcTarget: "omarchy.elsewhen"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return key.charAt(0) === "@" ? Commons.I18n.t(key.substring(1)) : catalog.t(key) }

  // ---- Settings (Elsewhen's).
  readonly property var zones: Model.parseCities(setting("cities", null), setting("zones", ""))
  readonly property var zoneIds: zones.map(function(z) { return z.id })
  readonly property bool needsSeed: zones.length === 0
  readonly property var probeIds: needsSeed ? zoneIds.concat(Model.seedCandidateZones()) : zoneIds
  readonly property var formatLocale: Qt.locale(Commons.I18n.formatLocale)
  readonly property bool hour24: Model.resolveHour24(setting("hour24", ""), Model.usesTwentyFourHour(formatLocale.timeFormat(Locale.ShortFormat)))
  readonly property string offsetMode: setting("offsetMode", "home") === "utc" ? "utc" : "home"
  readonly property string units: Model.resolveUnits(setting("units", ""), formatLocale.measurementSystem === Locale.ImperialUSSystem ? "F" : "C")
  readonly property var words: {
    var locale = formatLocale
    return {
      t: Commons.I18n.t, tn: Commons.I18n.tn, fmt: Commons.I18n.formatNumber, am: locale.amText, pm: locale.pmText,
      date: function(parts) { return new Date(parts.year, parts.month, parts.day, 12).toLocaleString(locale, Commons.I18n.t("elsewhen.dateFormat")) }
    }
  }

  // Written to this item's entry in shell.json; an undefined value removes
  // its key (Elsewhen's).
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) {
      if (values[key] === undefined) delete entry[key]
      else entry[key] = values[key]
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function setZones(next) {
    if (next === zones) return
    persistSettings({ cities: Model.serializeCities(next), zones: undefined })
    refresh()
    refreshFacts()
  }

  // ---- State.
  property var probe: ({})
  property var searchProbe: ({})
  property string zoneCatalogText: ""
  property var facts: ({})
  property var geo: ({})
  property var fallbackGeo: ({})
  property var weather: ({})
  property int localOffsetMinutes: -(new Date().getTimezoneOffset())
  property string localZone: ""
  property double nowMs: Date.now()
  property bool probeQueued: false
  property bool searchProbeQueued: false
  property bool factsQueued: false

  readonly property var rows: Model.rows(zones, probe, nowMs, localOffsetMinutes, hour24, words)
  readonly property var hereZone: Model.resolveHere(setting("here", null), setting("homeCity", ""), localZone)
  readonly property string homeCity: hereZone ? hereZone.label : ""
  readonly property string localTime: {
    var here = Model.localParts(nowMs)
    var text = Model.formatTime(here, hour24, words)
    return hour24 ? text : text + " " + Model.meridiem(here, words)
  }

  // ---- The dropdown's own state.
  property int chosen: -1
  property string searchMode: ""      // "", "add" or "here"
  property string query: ""
  property int matchIndex: 0
  readonly property var zoneOptions: Model.zoneOptions(zoneCatalogText, searchMode === "here" ? [] : zones)
  readonly property var matches: {
    if (searchMode === "") return []
    var offline = Model.searchZones(zoneOptions, query, 6)
    var merged = Model.mergePlaces(offline, placesFor(query), searchMode === "here" ? [] : zones, 10)
    return merged.map(function(m) {
      var known = root.searchProbe[m.value]
      return { label: m.label, value: m.value, region: m.region || "", lat: m.lat, lon: m.lon,
               utc: known === undefined ? "" : Model.utcOffsetLabel(known.offsetMinutes, root.words) }
    })
  }
  onMatchesChanged: probeSearchZones()

  function startSearch(mode) {
    if (mode === "here" && localZone === "") return
    searchMode = mode; query = ""; matchIndex = 0; chosen = -1
    loadCatalog()
  }
  function stopSearch() {
    searchMode = ""; query = ""; matchIndex = 0
    if (panel.loadedContent) panel.loadedContent.rest()
  }
  function pick(m) {
    if (!m) return
    var place = m.lat !== undefined ? { lat: m.lat, lon: m.lon, region: m.region } : undefined
    if (searchMode === "here") setHere({ label: m.label, id: m.value, lat: m.lat, lon: m.lon, region: m.region })
    else setZones(Model.addZone(zones, m.value, m.label, place))
    stopSearch()
  }
  function moveChosen(step) {
    var to = chosen + step
    if (chosen < 0 || to < 0 || to >= zones.length) return
    setZones(Model.moveZone(zones, chosen, to))
    chosen = to
  }
  function removeChosen() {
    if (chosen < 0 || chosen >= zones.length) return
    setZones(Model.removeZoneAt(zones, chosen))
    chosen = Math.min(chosen, zones.length - 2)
  }

  // ---- Here (Elsewhen's): a city on this machine's zone renames here; one
  // on another zone moves the machine's clock there first.
  function setHere(pickedHere) {
    var next = Model.hereAfterPick(zones, hereZone, pickedHere, localZone)
    if (!next) return
    if (next.zoneChange !== "") {
      if (timezoneProc.running) return
      timezoneProc.pending = { here: next.here, zoneChange: next.zoneChange }
      timezoneProc.command = Model.timezoneCommand(next.zoneChange)
      timezoneProc.running = true
      return
    }
    applyHere(next)
  }
  function applyHere(next) {
    var values = { here: next.here === null ? undefined : next.here, homeCity: undefined }
    if (next.zones && next.zones !== zones) { values.cities = Model.serializeCities(next.zones); values.zones = undefined }
    persistSettings(values)
    refreshFacts()
  }
  function notify(title) { Util.execArgv(["omarchy-notification-send", title]) }

  function tick() {
    nowMs = Date.now()
    localOffsetMinutes = -(new Date().getTimezoneOffset())
  }

  // The local city and four more round the clock from it, on a first run.
  function seedFirstRun() {
    var offs = ({})
    for (var id in probe) offs[id] = probe[id].offsetMinutes
    var seeded = localZone === "" || !hereZone ? [] : Model.seedZones({ label: hereZone.label, id: localZone }, offs, 4)
    if (seeded.length > 0 && hereZone.lat !== undefined) seeded[0] = Object.assign({}, seeded[0], hereZone)
    if (seeded.length === 0) seeded = Model.parseZones(Model.DEFAULT_ZONES)
    if (seeded.length === 0) return
    persistSettings({ cities: Model.serializeCities(seeded), zones: undefined })
    refresh()
    refreshFacts()
  }

  // ---- Place search (Elsewhen's): the geocoder's places for a query, once
  // the typing pauses, kept for the session.
  property var placeCache: ({})
  property string placeWanted: ""
  function requestPlaces(text) {
    var q = Model.placeQuery(text)
    if (q === "" || placeCache[q] !== undefined) return
    placeWanted = q
    placeDebounce.restart()
  }
  function lookupPlaces() {
    var q = placeWanted
    if (q === "" || placeCache[q] !== undefined || placeProc.running) return
    placeProc.query = q
    placeProc.command = ["curl", "-fsS", "--max-time", "8", Model.geocodeUrl(q)]
    placeProc.running = true
  }
  function placesFor(text) {
    var q = Model.placeQuery(text)
    return q === "" ? [] : (placeCache[q] || [])
  }
  function placesPending(text) {
    var q = Model.placeQuery(text)
    return q !== "" && placeCache[q] === undefined
  }

  // ---- Fetching (Elsewhen's).
  function refresh() {
    if (probeIds.length === 0) return
    if (probeProc.running) { probeQueued = true; return }
    probeProc.running = true
  }
  function probeSearchZones() {
    var ids = []
    for (var i = 0; i < matches.length; i++) if (ids.indexOf(matches[i].value) < 0) ids.push(matches[i].value)
    if (ids.length === 0) return
    if (searchProc.running) { searchProbeQueued = true; return }
    searchProc.command = Model.probeCommand(ids, false)
    searchProc.running = true
  }
  readonly property var factsRequest: {
    var out = zones.slice()
    if (hereZone) out.push(hereZone)
    return out
  }
  readonly property var pinnedGeo: {
    var out = {}
    factsRequest.forEach(function(row) { if (row.lat !== undefined) out[Model.factsKey(row)] = { lat: row.lat, lon: row.lon } })
    return out
  }
  function refreshFacts() {
    if (zones.length === 0) return
    if (geoProc.running || weatherProc.running) { factsQueued = true; return }
    var missing = factsRequest.filter(function(row) { var key = Model.factsKey(row); return !geo[key] && !pinnedGeo[key] })
    if (missing.length === 0) { fetchWeather(); return }
    geoProc.rows = missing
    geoProc.command = ["bash", "-c", 'for url; do curl -fsS --max-time 8 "$url"; printf "\\n\\036\\n"; done', "bash"]
      .concat(missing.map(function(row) { return Model.geocodeUrl(row.label) }))
    geoProc.running = true
  }
  function coordsFor(key) { return pinnedGeo[key] || geo[key] || fallbackGeo[key] || null }
  function fetchWeather() {
    var now = Date.now()
    var stale = factsRequest.map(Model.factsKey).filter(function(key) { return coordsFor(key) && Model.weatherStale(weather[key], now, coordsFor(key)) })
    if (stale.length === 0) { publishFacts(); return }
    weatherProc.keys = stale
    weatherProc.points = stale.map(coordsFor)
    weatherProc.command = ["curl", "-fsS", "--max-time", "8", Model.forecastUrl(stale.map(coordsFor))]
    weatherProc.running = true
  }
  function publishFacts() {
    var coords = {}
    var keys = factsRequest.map(Model.factsKey)
    keys.forEach(function(key) { coords[key] = coordsFor(key) })
    facts = Model.mergeFacts(keys, coords, weather)
    if (!factsQueued) return
    factsQueued = false
    Qt.callLater(refreshFacts)
  }
  function loadCatalog() {
    if (zoneCatalogText !== "" || catalogProc.running) return
    catalogProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      chosen = -1; searchMode = ""; query = ""
      tick(); refresh(); refreshFacts(); loadCatalog()
      if (panel.loadedContent) panel.loadedContent.rest()
    }
  }
  Component.onCompleted: refresh()

  Process {
    id: probeProc
    command: Model.probeCommand(root.probeIds, true)
    stdout: StdioCollector {
      onStreamFinished: {
        root.probe = Model.parseProbe(text)
        var lz = Model.localZoneFromProbe(text)
        if (lz !== "") root.localZone = lz
        if (root.needsSeed) root.seedFirstRun()
        root.tick()
        Qt.callLater(function() { if (!root.probeQueued) return; root.probeQueued = false; root.refresh() })
      }
    }
  }
  Process {
    id: searchProc
    stdout: StdioCollector {
      onStreamFinished: {
        var merged = {}
        for (var known in root.searchProbe) merged[known] = root.searchProbe[known]
        var fresh = Model.parseProbe(text)
        for (var id in fresh) merged[id] = fresh[id]
        root.searchProbe = merged
        Qt.callLater(function() { if (!root.searchProbeQueued) return; root.searchProbeQueued = false; root.probeSearchZones() })
      }
    }
  }
  Process {
    id: catalogProc
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector { onStreamFinished: root.zoneCatalogText = text }
  }
  FileView { id: zoneTab; path: "/usr/share/zoneinfo/zone1970.tab"; printErrors: false }
  Process {
    id: geoProc
    property var rows: []
    stdout: StdioCollector {
      onStreamFinished: {
        var answers = text.split("\n\u001e\n")
        var nextGeo = Object.assign({}, root.geo)
        var nextFallback = {}
        geoProc.rows.forEach(function(row, i) {
          var key = Model.factsKey(row)
          var found = Model.pickGeocode(answers[i] || "", row.id)
          var place = found.place || Model.zoneTabCoords(zoneTab.text(), row.id)
          if (!place) return
          if (found.answered) nextGeo[key] = place
          else nextFallback[key] = place
        })
        root.geo = nextGeo
        root.fallbackGeo = nextFallback
        root.fetchWeather()
      }
    }
  }
  Process {
    id: timezoneProc
    property var pending: null
    onExited: function(exitCode) {
      var next = pending
      pending = null
      if (!next) return
      if (exitCode !== 0) { root.notify(Commons.I18n.t("elsewhen.timezoneFailed").arg(next.zoneChange)); return }
      root.localZone = next.zoneChange
      root.applyHere(next)
      root.tick()
      root.refresh()
      root.notify(Commons.I18n.t("elsewhen.timezoneChanged").arg(root.homeCity).arg(next.zoneChange))
    }
  }
  Timer { id: placeDebounce; interval: 300; onTriggered: root.lookupPlaces() }
  Process {
    id: placeProc
    property string query: ""
    onRunningChanged: if (!running) Qt.callLater(root.lookupPlaces)
    stdout: StdioCollector {
      onStreamFinished: {
        var next = Object.assign({}, root.placeCache)
        next[placeProc.query] = Model.placeOptions(text)
        root.placeCache = next
        Qt.callLater(root.lookupPlaces)
      }
    }
  }
  Process {
    id: weatherProc
    property var keys: []
    property var points: []
    stdout: StdioCollector {
      onStreamFinished: {
        root.weather = Object.assign({}, root.weather, Model.parseForecast(text, weatherProc.keys, Date.now(), weatherProc.points))
        root.publishFacts()
      }
    }
  }
  Timer { interval: 900000; running: root.opened; repeat: true; onTriggered: root.refreshFacts() }
  Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.tick() }
  Timer { interval: 300000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  ShellIpc {
    target: "omarchy.elsewhen"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function globe(): string { return "disabled" }
    function times(): string { root.tick(); return JSON.stringify(root.rows) }
    function add(zone: string, label: string): string {
      root.setZones(Model.addZone(root.zones, zone, label))
      return Model.serializeZones(root.zones)
    }
    function remove(zone: string): string { root.setZones(Model.removeZone(root.zones, zone)); return Model.serializeZones(root.zones) }
    function who(city: string, people: string): string {
      var name = String(city).trim().toLowerCase()
      for (var i = 0; i < root.zones.length; i++) {
        if (root.zones[i].label.toLowerCase() !== name) continue
        root.setZones(Model.setPeopleAt(root.zones, i, Model.parsePeople(people)))
        return JSON.stringify(root.zones[i].people || [])
      }
      return "no city named " + city
    }
    function here(city: string): string {
      if (root.localZone === "") return "zone not known yet"
      root.setHere({ label: city, id: root.localZone })
      return root.homeCity
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    text: String.fromCodePoint(0xF01E7)
    tooltipText: Commons.I18n.t("elsewhen.worldClock")
    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    padding: 0
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.round(380 * Skin.u))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(760 * Skin.u))

    content: DropCard {
      title: root.t("@elsewhen.worldClock")
      subtitle: root.homeCity !== "" ? Commons.I18n.t("elsewhen.hereIn").arg(root.localTime).arg(root.homeCity)
                                     : Commons.I18n.t("elsewhen.here").arg(root.localTime)
      glyph: String.fromCodePoint(0xF01E7)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
      keyHandler: function(e) {
        var act = W.keyAction(e.key, e.text)
        if (act === "remove" && root.chosen >= 0) root.removeChosen()
        else if (act === "add") root.startSearch("add")
        else return false
        return true
      }

      DropSections {
        width: parent.width
        model: W.sections({
          rows: root.rows,
          offsets: root.rows.map(function(r) {
            if (!r.ready) return ""
            return root.offsetMode === "utc" ? Model.utcOffsetLabel(r.offsetMinutes, root.words) : r.relative
          }),
          temps: root.zones.map(function(z) { return Model.tempLabel(root.facts[Model.factsKey(z)], root.units, root.words) }),
          chosen: root.chosen, adding: root.searchMode === "add", choosingHere: root.searchMode === "here",
          query: root.query, matches: root.matches, matchIndex: root.matchIndex, searching: root.placesPending(root.query),
          hour24: root.hour24, utc: root.offsetMode === "utc", units: root.units, loading: root.zoneCatalogText === ""
        }, root.t)
        onPicked: function(key, value) {
          if (key === "cities") root.chosen = root.chosen === Number(value) ? -1 : Number(value)
          else if (key === "city") {
            if (value === "up") root.moveChosen(-1)
            else if (value === "down") root.moveChosen(1)
            else if (value === "remove") root.removeChosen()
          } else if (key === "do") root.startSearch(value)
          else if (key === "show") {
            if (value === "hour24") root.persistSettings({ hour24: !root.hour24 })
            else if (value === "utc") root.persistSettings({ offsetMode: root.offsetMode === "utc" ? "home" : "utc" })
            else if (value === "units") root.persistSettings({ units: root.units === "C" ? "F" : "C" })
          } else if (key === "add" || key === "here") root.pick(root.matches[Number(value)])
        }
        onEdited: function(key, text) {
          if (key !== "add" && key !== "here") return
          root.query = text; root.matchIndex = 0
          root.requestPlaces(text)
        }
        onMoved: function(key, value) { if (key === "add" || key === "here") root.matchIndex = value }
        onSubmitted: function(key, values) { if (key === "add" || key === "here") root.pick(root.matches[values.chosen]) }
        onCancelled: function(key) { if (key === "add" || key === "here") root.stopSearch() }
      }
    }
  }
}
