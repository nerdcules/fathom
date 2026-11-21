import QtQuick
import "kit"
import QtQuick.Layouts
import QtQuick.Shapes
import "."
import "kit/Format.js" as F

// Crumbs: the cookies every browser here keeps, from `fathom-crumbs status`.
// A map of which sites led to which trackers, every domain with its
// cookies, and Fathom's cookie rules: block third-party cookies, Edge's
// tracking prevention and a list of blocked domains. Rule changes wait in a
// draft until Apply, which asks for your password.
GridLayout {
  id: page

  // `fathom-crumbs status`, and `fathom-crumbs cookies <selected>`.
  property var crumbs: null
  property var detail: null
  property string selected: ""
  property bool busy: false
  property string message: ""
  property bool failed: false
  property bool wide: true

  signal selectRequested(string domain)
  signal applyRequested(var args)
  signal clearRequested()
  signal forgetRequested(string domain, string browser)

  readonly property var domains: crumbs && Array.isArray(crumbs.domains) ? crumbs.domains : []
  readonly property var browsers: crumbs && Array.isArray(crumbs.browsers) ? crumbs.browsers : []
  readonly property var totals: crumbs ? crumbs.totals : null
  readonly property bool hasEdge: browsers.some(function(b) { return b.family === "edge" })
  readonly property var saved: F.crumbsRules(crumbs ? crumbs.rules : null)
  property var draft: F.crumbsRules(null)
  readonly property bool dirty: !F.crumbsRulesSame(draft, saved)
  property var lastSaved: F.crumbsRules(null)
  onSavedChanged: if (!F.crumbsRulesSame(saved, lastSaved)) { lastSaved = saved; draft = saved }

  property string filter: "trackers"
  readonly property var shown: domains.filter(function(d) {
    if (filter === "trackers") return !!d.category
    if (filter === "blocked") return page.isBlocked(d.domain)
    return true
  })
  readonly property var chosen: {
    for (var i = 0; i < domains.length; i++) if (domains[i].domain === selected) return domains[i]
    return null
  }

  columns: wide ? 3 : 1
  columnSpacing: 20 * Skin.u
  rowSpacing: 20 * Skin.u

  function isBlocked(domain) { return draft.blocked.indexOf(domain) !== -1 }
  function toggleBlock(domain) {
    var next = F.crumbsRules(draft)
    var i = next.blocked.indexOf(domain)
    if (i === -1) next.blocked.push(domain)
    else next.blocked.splice(i, 1)
    draft = F.crumbsRules(next)
  }
  function setRule(key, value) {
    var next = F.crumbsRules(draft)
    next[key] = value
    draft = F.crumbsRules(next)
  }

  function categoryColor(c) {
    if (c === "Advertising" || c === "Fingerprinting" || c === "Cryptomining") return Skin.urgent
    if (c === "Social") return Skin.violet
    if (c === "Analytics") return Skin.warn
    if (c === "Content") return Skin.blue
    return Skin.dim
  }
  function categoryName(c) { return c ? Skin.t("crumbs.cat." + c) : Skin.t("crumbs.cat.none") }
  function browserName(id) {
    for (var i = 0; i < browsers.length; i++) if (browsers[i].id === id) return browsers[i].name
    return id
  }
  function expiryText(expires) {
    var e = F.crumbsExpiry(expires, crumbs ? crumbs.time : Date.now() / 1000)
    if (e.unit === "session" || e.unit === "expired") return Skin.t("crumbs.expiry." + e.unit)
    return Skin.tn("crumbs.expiry." + e.unit, e.n).arg(Skin.n(e.n))
  }
  function domainLine(d) {
    var parts = []
    if (d.company) parts.push(d.company)
    parts.push(categoryName(d.category))
    if (d.sites.length > 0) parts.push(Skin.tn("crumbs.linkedFrom", d.sites.length).arg(Skin.n(d.sites.length)))
    if (!d.visited && d.category) parts.push(Skin.t("crumbs.neverVisited"))
    return parts.join(" · ")
  }
  function cookieLine(c) {
    var parts = [c.host.replace(/^\./, "") + c.path, browserName(c.browser), expiryText(c.expires)]
    var flags = []
    if (c.secure) flags.push("Secure")
    if (c.httpOnly) flags.push("HttpOnly")
    flags.push("SameSite=" + c.sameSite)
    parts.push(flags.join(" "))
    if (c.partition) parts.push(Skin.t("crumbs.partitioned").arg(c.partition))
    parts.push(Skin.size(c.size))
    return parts.join(" · ")
  }

  function summary() {
    if (!crumbs) return [{ tone: page.failed ? "bad" : "stopped", text: page.failed ? page.message : Skin.t("loading") }]
    var out = []
    out.push({ tone: totals.trackers > 0 ? "warn" : "ok",
               text: Skin.tn("crumbs.summary.trackers", totals.trackers).arg(Skin.n(totals.trackers)).arg(Skin.n(totals.trackerCookies)) })
    out.push({ tone: "ok", text: Skin.tn("crumbs.summary.cookies", totals.cookies).arg(Skin.n(totals.cookies))
      .arg(Skin.n(totals.domains)).arg(Skin.n(browsers.length)) })
    out.push({ tone: saved.thirdParty || saved.blocked.length > 0 ? "ok" : "warn",
               text: saved.thirdParty ? Skin.t("crumbs.summary.thirdBlocked")
                 : (saved.blocked.length > 0 ? Skin.tn("crumbs.summary.blocked", saved.blocked.length).arg(Skin.n(saved.blocked.length))
                 : Skin.t("crumbs.summary.noRules")) })
    if (dirty) out.push({ tone: "warn", text: Skin.t("crumbs.summary.draft") })
    return out
  }

  // ------------------------------------------------ Map
  Card {
    Layout.columnSpan: page.wide ? 2 : 1
    title: Skin.t("crumbs.mapTitle")
    glyph: "\uf1e0"
    subtitle: page.crumbs ? Skin.t("crumbs.mapSubtitle") : ""

    Empty {
      visible: !!page.crumbs && map.layout.domains.length === 0
      text: Skin.t("crumbs.mapEmpty")
    }

    Item {
      id: map
      visible: layout.domains.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: Math.max(220 * Skin.u, Math.max(layout.sites.length, layout.domains.length) * (boxH + 6 * Skin.u))
      // As many as fit the card on this screen without scrolling.
      readonly property var layout: F.crumbsMap(page.domains, page.crumbs ? page.crumbs.links : [], 8, 9)
      readonly property real boxW: Math.min(250 * Skin.u, width * 0.34)
      readonly property real boxH: 26 * Skin.u
      readonly property var leftY: F.crumbsColumn(layout.sites.length, height, boxH)
      readonly property var rightY: F.crumbsColumn(layout.domains.length, height, boxH)
      readonly property var siteIndex: {
        var o = {}
        for (var i = 0; i < layout.sites.length; i++) o[layout.sites[i]] = i
        return o
      }
      readonly property var domainIndex: {
        var o = {}
        for (var i = 0; i < layout.domains.length; i++) o[layout.domains[i].domain] = i
        return o
      }
      // The domain or site under the mouse, to light up its lines.
      property string hot: ""

      Repeater {
        model: map.layout.links
        delegate: Shape {
          id: line
          required property var modelData
          // The columns are worked out with the layout; for a moment after
          // it changes a line can ask before they're ready.
          readonly property real y1: (map.leftY[map.siteIndex[modelData.site]] || 0) + map.boxH / 2
          readonly property real y2: (map.rightY[map.domainIndex[modelData.domain]] || 0) + map.boxH / 2
          readonly property bool lit: map.hot === modelData.site || map.hot === modelData.domain || page.selected === modelData.domain
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          z: lit ? 1 : 0
          ShapePath {
            fillColor: "transparent"
            strokeColor: line.lit ? Skin.accent : Skin.tint(Skin.fg, 0.22)
            strokeWidth: (line.lit ? 2 : 1.2) * Skin.u
            // Solid: stored under that site, so certain. Dashed: set within
            // seconds of a visit there, so likely.
            strokeStyle: line.modelData.how === "partition" ? ShapePath.SolidLine : ShapePath.DashLine
            dashPattern: [4, 3]
            startX: map.boxW
            startY: line.y1
            PathCubic {
              x: map.width - map.boxW
              y: line.y2
              control1X: map.width / 2
              control1Y: line.y1
              control2X: map.width / 2
              control2Y: line.y2
            }
          }
        }
      }

      // Sites you visited, on the left.
      Repeater {
        model: map.layout.sites
        delegate: Rectangle {
          id: siteBox
          required property string modelData
          required property int index
          x: 0
          y: map.leftY[index] || 0
          width: map.boxW
          height: map.boxH
          radius: height / 2
          color: Skin.stateFill(Skin.faint, false, siteHover.hovered, false)
          z: 2
          HoverHandler { id: siteHover; onHoveredChanged: map.hot = hovered ? siteBox.modelData : "" }
          Label {
            anchors.fill: parent
            anchors.leftMargin: 12 * Skin.u
            anchors.rightMargin: 12 * Skin.u
            verticalAlignment: Text.AlignVCenter
            text: siteBox.modelData
            font.pixelSize: Skin.text.body
          }
        }
      }

      // Where their cookies came from, on the right.
      Repeater {
        model: map.layout.domains
        delegate: Rectangle {
          id: domainBox
          required property var modelData
          required property int index
          readonly property color tone: page.categoryColor(modelData.category)
          x: map.width - map.boxW
          y: map.rightY[index] || 0
          width: map.boxW
          height: map.boxH
          radius: height / 2
          z: 2
          color: page.selected === modelData.domain ? Skin.tint(tone, 0.32)
            : (domainHover.hovered ? Skin.tint(tone, 0.24) : Skin.tint(tone, 0.14))
          border.width: page.selected === modelData.domain ? 1 : 0
          border.color: tone
          HoverHandler {
            id: domainHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: map.hot = hovered ? domainBox.modelData.domain : ""
          }
          MouseArea { anchors.fill: parent; onClicked: page.selectRequested(domainBox.modelData.domain) }
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 12 * Skin.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * Skin.u
            Dot { tone: domainBox.tone; anchors.verticalCenter: parent.verticalCenter }
            Label {
              text: domainBox.modelData.domain
              font.pixelSize: Skin.text.body
              width: map.boxW - 90 * Skin.u
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Label {
            anchors.right: parent.right
            anchors.rightMargin: 12 * Skin.u
            anchors.verticalCenter: parent.verticalCenter
            text: page.isBlocked(domainBox.modelData.domain) ? Skin.t("crumbs.blockedShort") : Skin.n(domainBox.modelData.sites.length)
            color: page.isBlocked(domainBox.modelData.domain) ? Skin.ok : Skin.dim
            font.pixelSize: Skin.text.detail
          }
          Tip {
            target: domainBox
            text: page.domainLine(domainBox.modelData)
            show: domainHover.hovered
          }
        }
      }
    }

    // The key.
    Flow {
      visible: map.visible
      Layout.fillWidth: true
      spacing: 16 * Skin.u
      Repeater {
        model: ["Advertising", "Social", "Analytics", "Content"]
        delegate: Row {
          required property string modelData
          spacing: 6 * Skin.u
          Dot { tone: page.categoryColor(modelData); anchors.verticalCenter: parent.verticalCenter }
          Label { text: page.categoryName(modelData); color: Skin.dim; font.pixelSize: Skin.text.detail }
        }
      }
      Label { text: Skin.t("crumbs.keyLines"); color: Skin.dim; font.pixelSize: Skin.text.detail }
    }
  }

  // ------------------------------------------------ Protection
  Card {
    title: Skin.t("crumbs.rulesTitle")
    glyph: "\uf132"
    subtitle: page.dirty ? Skin.t("crumbs.notApplied") : ""
    subtitleColor: Skin.warn

    Empty {
      visible: !!page.crumbs && !page.crumbs.helper
      text: Skin.t("crumbs.noHelper")
      color: Skin.warn
    }

    SectionTitle { text: Skin.t("crumbs.browsers") }
    Repeater {
      model: page.browsers
      delegate: ListRow {
        required property var modelData
        tone: modelData.running ? Skin.ok : Skin.dim
        name: modelData.name + (modelData.profile !== "Default" ? " · " + modelData.profile : "")
        detail: (modelData.running ? Skin.t("crumbs.running") : Skin.t("crumbs.closed"))
          + (modelData.takesRules ? "" : " · " + Skin.t("crumbs.noRules"))
        right1: Skin.tn("crumbs.cookieCount", modelData.cookies).arg(Skin.n(modelData.cookies))
        right2: Skin.tn("crumbs.domainCount", modelData.domains).arg(Skin.n(modelData.domains))
      }
    }

    SectionTitle { text: Skin.t("crumbs.thirdParty") }
    Row {
      spacing: 8 * Skin.u
      Pill { text: Skin.t("crumbs.allowed"); selected: !page.draft.thirdParty; onClicked: page.setRule("thirdParty", false) }
      Pill { text: Skin.t("crumbs.blocked"); selected: page.draft.thirdParty; onClicked: page.setRule("thirdParty", true) }
    }
    Empty { text: Skin.t("crumbs.thirdPartyDetail"); font.pixelSize: Skin.text.detail }

    SectionTitle { visible: page.hasEdge; text: Skin.t("crumbs.prevention") }
    Flow {
      visible: page.hasEdge
      Layout.fillWidth: true
      spacing: 8 * Skin.u
      Repeater {
        model: F.CRUMBS_LEVELS
        delegate: Pill {
          required property string modelData
          text: Skin.t("crumbs.level." + modelData)
          selected: page.draft.prevention === modelData
          onClicked: page.setRule("prevention", modelData)
        }
      }
    }

    SectionTitle { text: Skin.tn("crumbs.blockedList", page.draft.blocked.length).arg(Skin.n(page.draft.blocked.length)) }
    Empty {
      visible: page.draft.blocked.length === 0
      text: Skin.t("crumbs.blockedNone")
      font.pixelSize: Skin.text.detail
    }
    Flow {
      Layout.fillWidth: true
      spacing: 6 * Skin.u
      Repeater {
        model: page.draft.blocked
        delegate: Pill {
          required property string modelData
          text: modelData
          glyph: "\uf00d"
          glyphColor: Skin.dim
          tip: Skin.t("crumbs.unblock")
          onClicked: page.toggleBlock(modelData)
        }
      }
    }
    Empty { text: Skin.t("crumbs.rulesDetail"); font.pixelSize: Skin.text.detail }

    footer: [
      Pill {
        primary: true
        text: page.busy ? Skin.t("crumbs.applying") : Skin.t("crumbs.apply")
        tip: Skin.t("crumbs.applyTip")
        enabledAction: page.dirty && !page.busy && !!page.crumbs && page.crumbs.helper
        onClicked: page.applyRequested(F.crumbsArgs(page.draft))
      },
      Pill {
        text: Skin.t("crumbs.undo")
        enabledAction: page.dirty && !page.busy
        onClicked: page.draft = page.saved
      },
      Pill {
        text: Skin.t("crumbs.clear")
        tip: Skin.t("crumbs.clearTip")
        enabledAction: !page.busy && !!page.crumbs && page.crumbs.helper
          && (page.saved.thirdParty || page.saved.blocked.length > 0 || page.saved.prevention !== "default")
        onClicked: Skin.ask(Skin.t("crumbs.clearAsk"), Skin.t("crumbs.clearAskBody"), Skin.t("crumbs.clear"),
                            function() { page.clearRequested() })
      },
      Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: page.message
        color: page.failed ? Skin.urgent : Skin.dim
        font.pixelSize: Skin.text.detail
        wrapMode: Text.WordWrap
        maximumLineCount: 3
      }
    ]
  }

  // ------------------------------------------------ Domains
  Card {
    title: Skin.t("crumbs.domainsTitle")
    glyph: "\uf0ac"
    subtitle: page.crumbs ? Skin.t("crumbs.listSource." + page.crumbs.trackerList.source) : ""

    Row {
      spacing: 8 * Skin.u
      Repeater {
        model: ["trackers", "all", "blocked"]
        delegate: Pill {
          required property string modelData
          text: Skin.t("crumbs.filter." + modelData)
          selected: page.filter === modelData
          onClicked: page.filter = modelData
        }
      }
    }
    Empty {
      visible: !!page.crumbs && page.shown.length === 0
      text: Skin.t("crumbs.empty." + page.filter)
    }
    Repeater {
      model: page.shown
      delegate: ListRow {
        required property var modelData
        tone: page.categoryColor(modelData.category)
        name: modelData.domain
        detail: page.domainLine(modelData)
        right1: Skin.tn("crumbs.cookieCount", modelData.cookies).arg(Skin.n(modelData.cookies))
        right2: page.isBlocked(modelData.domain) ? Skin.t("crumbs.blockedShort") : ""
        clickable: true
        current: page.selected === modelData.domain
        onClicked: page.selectRequested(modelData.domain)
        Pill {
          text: page.isBlocked(modelData.domain) ? Skin.t("crumbs.unblock") : Skin.t("crumbs.block")
          onClicked: page.toggleBlock(modelData.domain)
        }
      }
    }
  }

  // ------------------------------------------------ One domain's cookies
  Card {
    id: detailCard
    Layout.columnSpan: page.wide ? 2 : 1
    title: page.selected !== "" ? page.selected : Skin.t("crumbs.detailTitle")
    glyph: "\uf1c0"
    subtitle: page.chosen ? page.domainLine(page.chosen) : ""
    subtitleColor: page.chosen ? page.categoryColor(page.chosen.category) : Skin.dim

    Empty {
      visible: page.selected === ""
      text: Skin.t("crumbs.detailHint")
    }
    Empty {
      visible: page.selected !== "" && !detailCard.ready
      text: Skin.t("loading")
    }

    readonly property bool ready: !!page.detail && page.detail.domain.domain === page.selected

    Label {
      visible: detailCard.ready && !!page.chosen && page.chosen.sites.length > 0
      Layout.fillWidth: true
      text: page.chosen ? Skin.t("crumbs.ledFrom").arg(page.chosen.sites.join(", ")) : ""
      color: Skin.dim
      font.pixelSize: Skin.text.detail
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
    }
    Label {
      visible: !!page.chosen && page.chosen.hosts.length > 0
      Layout.fillWidth: true
      text: page.chosen ? Skin.t("crumbs.hosts").arg(page.chosen.hosts.join(", ")) : ""
      color: Skin.dim
      font.pixelSize: Skin.text.detail
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
    }

    Repeater {
      model: detailCard.ready ? page.detail.cookies : []
      delegate: ListRow {
        required property var modelData
        tone: modelData.tracker ? page.categoryColor(page.chosen ? page.chosen.category : null) : Skin.dim
        name: modelData.purpose ? modelData.name + "  ·  " + modelData.purpose : modelData.name
        detail: page.cookieLine(modelData)
      }
    }
    Empty {
      visible: page.selected !== ""
      text: Skin.t("crumbs.valuesHidden")
      font.pixelSize: Skin.text.detail
    }

    footer: [
      Pill {
        visible: page.selected !== ""
        text: page.isBlocked(page.selected) ? Skin.t("crumbs.unblock") : Skin.t("crumbs.block")
        onClicked: page.toggleBlock(page.selected)
      },
      Repeater {
        model: detailCard.ready && !!page.chosen ? page.chosen.browsers : []
        delegate: Pill {
          required property string modelData
          readonly property var b: {
            for (var i = 0; i < page.browsers.length; i++) if (page.browsers[i].id === modelData) return page.browsers[i]
            return null
          }
          text: Skin.t("crumbs.forget").arg(b ? b.name : modelData)
          tip: b && b.running ? Skin.t("crumbs.forgetRunning").arg(b.name) : Skin.t("crumbs.forgetTip")
          enabledAction: !!b && !b.running && !page.busy
          onClicked: Skin.ask(Skin.t("crumbs.forgetAsk").arg(page.selected), Skin.t("crumbs.forgetAskBody").arg(b.name),
                              Skin.t("crumbs.forgetShort"), function() { page.forgetRequested(page.selected, modelData) })
        }
      }
    ]
  }
}
