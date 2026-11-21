import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "kit"
import "Model.js" as Model
import "Weather.js" as W

// Fathom's weather on the bar (#14): Omarchy's weather icon, with Fathom's
// own dropdown under it. A clone of omarchy.weather (manifest.json): turning
// it on puts it where Omarchy's was, with its settings; turning it off puts
// Omarchy's back. It answers to omarchy.weather as Omarchy's does
// (`omarchy-shell omarchy.weather open|close|toggle|edit`, and
// omarchy-notification-weather's toggle).
//
// Fetched as Omarchy's panel fetches (its Panel.qml, MIT): wttr.in for the
// conditions, open-meteo for the coming days (and the conditions, when the
// place's coordinates are known), the place from Omarchy's weather.json, or
// with none set, from geo.omarchy.org; every refreshMinutes (setting,
// default 15), with up to three retries a round. The entry's `unit`
// setting picks °C or °F as Omarchy's does. The place is changed here
// through omarchy-weather-location, as in Omarchy's.
//
// The button: a click opens the dropdown, a right-click sends the weather
// as a notification, a middle-click fetches it again.
Panel {
  id: root
  moduleName: "omarchy.weather"
  ipcTarget: "omarchy.weather"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  // ---- What's fetched (Omarchy's).
  property var report: null
  property var dailyForecastReport: null
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  property var detectedLocationState: ({ name: "", latitude: null, longitude: null })
  property bool detectingLocation: false
  readonly property bool autoLocation: Model.isAutoLocation(configuredLocationState)
  onAutoLocationChanged: if (autoLocation) detectLocation()
  readonly property var locationState: Model.effectiveLocation(configuredLocationState, detectedLocationState)
  readonly property string locationQuery: Model.wttrLocationQuery(locationState.name, locationState.latitude, locationState.longitude)
  onLocationQueryChanged: {
    if (savingLocation) savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    Qt.callLater(refresh)
  }

  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property bool hasCoordinates: !isNaN(parseFloat(String(locationState.latitude))) && !isNaN(parseFloat(String(locationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var current: (hasCoordinates && openMeteoCurrent) ? openMeteoCurrent
    : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""
  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)
  readonly property string reportLocation: configuredLocation || (autoLocation ? detectedLocationState.name : "")
    || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTemp: current ? number(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit: "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels: current ? Model.formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC, useImperial, Commons.I18n.formatNumber) : ""
  readonly property string reportWind: current ? (useImperial ? number(current.windspeedMiles) + " mph" : number(current.windspeedKmph) + " km/h") : ""
  readonly property string reportHumidity: current ? number(current.humidity) + "%" : ""
  // The bar's icon, and the dropdown's.
  property string label: ""

  property int forecastRetries: 0
  property int dailyForecastRetries: 0

  // ---- Changing the place.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string searchText: ""
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  function number(value) {
    if (value === undefined || value === null || value === "") return ""
    return Commons.I18n.formatNumber(value)
  }

  readonly property var days: {
    var locale = Qt.locale(Commons.I18n.formatLocale)
    var list = Model.buildForecastDays(report, dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    return list.map(function(day) {
      return {
        key: String(day.date),
        glyph: Model.dayIcon(day),
        name: Model.dayName(day.date, function(date) { return locale.standaloneDayName(date.getDay(), Locale.ShortFormat) }),
        max: Model.bareTempForDay(day, "max", root.useImperial, Commons.I18n.formatNumber),
        min: Model.bareTempForDay(day, "min", root.useImperial, Commons.I18n.formatNumber)
      }
    })
  }

  function refresh() {
    forecastRetries = 0
    dailyForecastRetries = 0
    if (detectingLocation && locationQuery === "") return
    if (!forecastProc.running) forecastProc.running = true
    refreshDailyForecast(null)
  }

  function detectLocation() {
    if (locationProc.running) return
    detectingLocation = true
    locationProc.running = true
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return
    var lat = parseFloat(String(root.locationState.latitude))
    var lon = parseFloat(String(root.locationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=4"
      + "&timezone=auto"
    dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    dailyForecastProc.running = true
  }

  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    searchText = configuredLocation
  }
  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    if (panel.loadedContent) panel.loadedContent.rest()
  }
  function commitLocation(text, chosen) {
    var location = Model.locationCommit(text, locationSuggestions, chosen)
    if (location.name === "") { clearLocation(); return }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = { name: location.name, latitude: location.latitude, longitude: location.longitude }
    persistLocation(location.name, location.latitude, location.longitude)
  }
  function clearLocation() {
    persistLocation("", null, null)
    cancelEditingLocation()
  }
  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = { name: suggestion.name, latitude: suggestion.latitude, longitude: suggestion.longitude }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }
  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }
  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }
  function requestGeocode() {
    var query = root.searchText.trim()
    if (query.length < 2) { locationSuggestions = []; return }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }
  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function suppressCentreReveal(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function") root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: {
    if (opened) {
      locationFile.reload()
      refresh()
      if (panel.loadedContent) panel.loadedContent.rest()
      Qt.callLater(function() { if (root.opened) root.suppressCentreReveal(true) })
    } else {
      suppressCentreReveal(false)
      if (editingLocation) cancelEditingLocation()
    }
  }

  // As Omarchy's: no icon yet, no button on the bar.
  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }
  // The first read can race the shell starting (Omarchy's note); once more.
  Timer { interval: 1500; running: true; onTriggered: root.locationFile.reload() }

  Process {
    id: forecastProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.scheduleForecastRetry(); return }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr")) root.finishSavingLocation()
          if (!root.hasCoordinates) root.refreshDailyForecast(parsed)
        } catch (e) {
          root.scheduleForecastRetry()
        }
      }
    }
  }
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }
  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }
  // Unlike Omarchy's: when the last retry fails too, a place being saved
  // stops waiting for open-meteo, showing what wttr.in gave. Without this
  // the field said "Loading…" for good: in the test VM, where open-meteo
  // answered 403 to every request, this copy of Omarchy's logic still said
  // it minutes after the last retry, and Omarchy's own panel's spinner was
  // still turning 8 seconds after a save.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3) {
      if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
      return
    }
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }
  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }
  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.scheduleDailyForecastRetry(); return }
        try {
          var parsed = JSON.parse(raw)
          var parsedCurrent = Model.openMeteoCurrentCondition(parsed)
          root.dailyForecastReport = parsed
          root.label = Model.currentIcon(parsedCurrent, root.label)
          root.dailyForecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo")) root.finishSavingLocation()
        } catch (e) {
          root.scheduleDailyForecastRetry()
        }
      }
    }
  }
  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }
  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }
  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.savingLocation) return
      root.locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }
  // Omarchy's own lookup: city and coordinates from Cloudflare's view of this
  // network, in weather.json's shape.
  Process {
    id: locationProc
    command: ["curl", "-fsS", "--max-time", "4", "https://geo.omarchy.org/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.detectingLocation = false
        var detected = Model.parseLocationFile(text)
        var query = Model.wttrLocationQuery(detected.name, detected.latitude, detected.longitude)
        if (query !== "" && query !== root.locationQuery) root.detectedLocationState = detected
        else if (root.locationQuery === "") root.refresh()
      }
    }
  }
  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.autoLocation) root.detectLocation()
      root.refresh()
    }
  }

  ShellIpc {
    target: "omarchy.weather"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.open(); root.startEditingLocation() }
  }

  DropTheme { strings: catalog; screen: panel.screen }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    slotSize: Style.bar.statusSlot
    tooltipText: ""
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
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
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Math.round(680 * Skin.u))

    content: DropCard {
      title: root.reportTemp !== "" ? root.reportTemp + root.tempUnit : catalog.t("weather.title")
      subtitle: root.reportLocation
      glyph: root.label !== "" ? root.label : String.fromCodePoint(0xF0590)
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }

      DropSections {
        width: parent.width
        model: W.sections({
          hasCurrent: !!root.current, feels: root.reportFeels, wind: root.reportWind, humidity: root.reportHumidity,
          location: root.reportLocation, editing: root.editingLocation, saving: root.savingLocation,
          query: root.searchText, results: root.locationSuggestions, chosen: root.suggestionIndex, days: root.days
        }, function(k) { return catalog.t(k) })
        onPicked: function(key, value) {
          if (key === "location") root.startEditingLocation()
          else if (key === "search") root.pickSuggestion(root.locationSuggestions[Number(value)])
          else if (key === "searchActions" && value === "auto") root.clearLocation()
          else if (key === "searchActions" && value === "cancel") root.cancelEditingLocation()
        }
        onEdited: function(key, text) {
          if (key !== "search" || root.savingLocation) return
          root.searchText = text
          geocodeDebounce.restart()
        }
        onMoved: function(key, value) { if (key === "search") root.suggestionIndex = Math.round(value) }
        onSubmitted: function(key, values) { if (key === "search") root.commitLocation(values.text, values.chosen) }
        onCancelled: function(key) { if (key === "search") root.cancelEditingLocation() }
      }
    }
  }
}
