.pragma library

// Fathom's Agents dropdown (#14): what it shows, as the kit's factory draws
// it. The records are read by Omarchy's own Main.qml and Agent.qml
// (copied); the rules below that turn a record into words are ported from
// Omarchy's agents panel (shell/plugins/agents/Panel.qml, MIT) as plain
// functions, so they can be tested. Node tests: tests/bar.test.mjs.
//
// `t(key)` gives words: Fathom's own keys, and Omarchy's for keys starting
// with "@" (every language Omarchy has); `tn(key, n)` the plural form of an
// Omarchy key; `num(n, decimals)` a number in the reader's locale.

// "%1 of %2" filled in, as QML's arg() does.
function fill(s) {
  var out = String(s)
  for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
  return out
}

// ---- Limit windows (Omarchy's rules).

// Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
// them ("5h window"); both land on the same record.
function windowIsLong(text) {
  return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
    || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
}

function windowSpanMs(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
  if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
  var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
  if (hours) return Number(hours[1]) * 3600 * 1000
  var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
  if (minutes) return Number(minutes[1]) * 60 * 1000
  return 0
}

function windowTitle(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0) return "Monthly"
  if (windowIsLong(text)) return "Weekly"
  if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
  var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
  return plain === "" ? "Limit" : plain
}

// A collector that already titles a limit is believed over its label; a
// window whose reset has passed is empty until the next reading.
function limitWindow(label, percent, resetAt, title, now) {
  var reset = new Date(String(resetAt || "")).getTime()
  var expired = isFinite(reset) && reset <= now
  return {
    title: String(title || "") !== "" ? String(title) : windowTitle(label),
    percent: expired ? 0 : Number(percent),
    resetAt: expired ? "" : String(resetAt || "")
  }
}

function limitWindows(limits, now) {
  var out = []
  var list = limits || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var percent = Number(entry.percent)
    if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title, now))
  }
  return out
}

// A model-scoped window ("Fable Weekly") runs on the clock of the window it's
// named for, so it's shown with that one; with nothing to join, on its own.
function scopedPart(title) {
  var match = String(title || "").match(/^(.+) (Session|Weekly|Monthly)$/)
  return match ? { model: match[1], window: match[2] } : null
}

function displayWindows(limits, now) {
  var windows = limitWindows(limits, now)
  var out = []
  var byTitle = {}
  for (var i = 0; i < windows.length; i++) {
    if (scopedPart(windows[i].title)) continue
    windows[i].scoped = []
    out.push(windows[i])
    byTitle[windows[i].title] = windows[i]
  }
  for (var j = 0; j < windows.length; j++) {
    var part = scopedPart(windows[j].title)
    if (!part) continue
    var base = byTitle[part.window]
    if (base) base.scoped.push({ title: part.model, percent: windows[j].percent, resetAt: windows[j].resetAt })
    else { windows[j].scoped = []; out.push(windows[j]) }
  }
  return out
}

// The fullest window: the one that stops the next prompt.
function bindingWindow(limits, now) {
  var windows = limitWindows(limits, now)
  var best = null
  for (var i = 0; i < windows.length; i++) if (!best || windows[i].percent > best.percent) best = windows[i]
  return best
}

function formatDuration(ms, t, num) {
  if (!(ms > 0)) return t("@agents.durationNow")
  var minutes = Math.floor(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return fill(t("@agents.durationDaysHours"), num(days), num(hours % 24))
  if (hours > 0) return fill(t("@agents.durationHoursMinutes"), num(hours), num(minutes % 60))
  return fill(t("@agents.durationMinutes"), num(Math.max(1, minutes)))
}

// Window titles stay English in the records; what reaches the screen is
// translated.
function windowDisplayTitle(title, t) {
  var value = String(title || "")
  if (value === "Session") return t("@agents.windowSession")
  if (value === "Weekly") return t("@agents.windowWeekly")
  if (value === "Monthly") return t("@agents.windowMonthly")
  if (value === "Spend limit") return t("@agents.windowSpendLimit")
  if (value === "Limit") return t("@agents.windowLimit")
  var part = scopedPart(value)
  if (part && part.window === "Session") return fill(t("@agents.modelSession"), part.model)
  if (part && part.window === "Weekly") return fill(t("@agents.modelWeekly"), part.model)
  if (part && part.window === "Monthly") return fill(t("@agents.modelMonthly"), part.model)
  return value
}

// One window as a meter: its name (with any model's own allowance on the
// same clock), how much is used and when it resets; the urgent colour from
// 90%, as Omarchy's alarm.
function windowMeter(key, w, now, t, num) {
  var label = windowDisplayTitle(w.title, t)
  for (var i = 0; i < (w.scoped || []).length; i++)
    label += " · " + w.scoped[i].title + " " + num(Math.round(w.scoped[i].percent * 100)) + "%"
  var trail = num(Math.round(w.percent * 100)) + "%"
  var reset = w.resetAt !== "" ? new Date(w.resetAt).getTime() - now : -1
  if (w.resetAt !== "" && isFinite(reset)) trail += " · " + formatDuration(reset, t, num)
  return { type: "meter", key: key, label: label, trail: trail, value: Math.max(0, Math.min(1, w.percent)), alarm: w.percent >= 0.9 }
}

// ---- Status and help (Omarchy's words for the collectors' English).

function statusDisplayText(status, t) {
  var value = String(status || "")
  if (value === "Balance unavailable") return t("@agents.balanceUnavailable")
  if (value === "Out of credits") return t("@agents.outOfCredits")
  var limits = value.match(/^(.+) limits unavailable$/)
  if (limits) return fill(t("@agents.providerLimitsUnavailable"), limits[1])
  var provider = value.match(/^(.+) unavailable$/)
  if (provider) return fill(t("@agents.providerUnavailable"), provider[1])
  if (value === "Sign-in expired") return t("@agents.signInExpired")
  if (value === "Waiting for auth") return t("@agents.waitingForAuth")
  if (value === "Limits paused") return t("@agents.limitsPaused")
  return value
}

function helpDisplayText(text, t) {
  var value = String(text || "")
  switch (value) {
  case "Run `claude auth login` to restore authoritative usage.":
    return fill(t("@agents.helpRunToRestoreUsage"), "`claude auth login`")
  case "Run `codex login` to authenticate.":
    return fill(t("@agents.helpRunToAuthenticate"), "`codex login`")
  case "Start Grok, or run `grok login`, to sign in.":
    return fill(t("@agents.helpStartOrRunToSignIn"), "Grok", "`grok login`")
  case "Start Grok to see its limits; signing in again is not needed.":
    return fill(t("@agents.helpStartToSeeLimits"), "Grok")
  case "Grok's saved sign-in expired. Start Grok to refresh it.":
    return fill(t("@agents.helpSignInExpired"), "Grok")
  case "Set FIREWORKS_API_KEY, run `firectl set-api-key`, or sign in to Fireworks in pi or opencode.":
    return fill(t("@agents.helpFireworksSignIn"), "FIREWORKS_API_KEY", "`firectl set-api-key`")
  case "codex not found in PATH":
    return fill(t("@agents.helpNotInPath"), "codex")
  case "Fireworks usage scan failed":
    return fill(t("@agents.helpScanFailed"), "Fireworks")
  }
  return value
}

// The agents omarchy-agent-account-add signs in.
var SIGN_IN = ["claude", "codex", "grok"]

function needsSignIn(p) {
  if (!p || SIGN_IN.indexOf(p.providerId) < 0) return false
  var status = String(p.usageStatusText || "")
  return status === "Sign-in expired" || status === "Waiting for auth"
}

// What keeps the numbers from being current, beside the last ones known.
function usageNote(p, t) {
  if (!p || needsSignIn(p)) return ""
  var status = String(p.usageStatusText || "")
  var stale = p.limitsStale === true || p.stale === true
  if (status === "" && !(stale && String(p.authHelpText || "") !== "")) return ""
  return helpDisplayText(p.authHelpText, t) || statusDisplayText(status, t)
}

function planLabel(p, t) {
  var tier = String(p && p.tierLabel || "")
  if (tier === "Prepaid") return t("@agents.tierPrepaid")
  return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1)
}

// ---- Balance (prepaid agents).

function balanceAlarming(b) { return !!b && b.funded > 0 && b.remaining / b.funded <= 0.1 }

function formatMoney(value, currency, num) {
  var code = String(currency || "USD").toUpperCase()
  var prefix = code === "USD" ? "$" : code === "EUR" ? "€" : code === "GBP" ? "£" : code + " "
  var amount = Number(value)
  return prefix + num(isFinite(amount) ? amount : 0, 2)
}

function balanceDetailText(b, t, num) {
  if (!b || !(b.funded > 0)) return ""
  var spent = formatMoney(b.spent, b.currency, num), funded = formatMoney(b.funded, b.currency, num)
  return fill(t(b.estimated ? "@agents.balanceSpentEstimated" : "@agents.balanceSpent"), spent, funded)
}

function freeResets(credits, now, t, tn, num) {
  if (!credits || !(Number(credits.available) > 0)) return ""
  var count = Number(credits.available)
  var expires = new Date(String(credits.nextExpiresAt || "")).getTime()
  if (isFinite(expires) && expires > now) return fill(tn("@agents.freeResetsExpires", count), num(count), formatDuration(expires - now, t, num))
  return fill(tn("@agents.freeResets", count), num(count))
}

// ---- The line under the title: what the token counts add up to.

// `modelName(id)` and `tokens(n)` are Omarchy's (Main.qml), `dayName(date)`
// the locale's day.
function summaryPhrases(providers, tn, t, num, modelName, tokens, dayName) {
  var week = 0, today = 0, prompts = 0, sessions = 0
  var byDay = {}, byModel = {}
  for (var i = 0; i < (providers || []).length; i++) {
    var p = providers[i]
    var days = p.recentDays || []
    for (var d = 0; d < days.length; d++) {
      var n = Number(days[d].messageCount || 0)
      week += n
      byDay[days[d].date] = (byDay[days[d].date] || 0) + n
    }
    today += Number(p.todayTotalTokens || 0)
    if (p.hasPromptStats !== false) { prompts += Number(p.todayPrompts || 0); sessions += Number(p.todaySessions || 0) }
    var models = p.modelUsage || {}
    for (var id in models) {
      var b = models[id] || {}
      var total = Number(b.inputTokens || 0) + Number(b.outputTokens || 0) + Number(b.cacheReadInputTokens || 0) + Number(b.cacheCreationInputTokens || 0)
      var name = modelName(id)
      byModel[name] = (byModel[name] || 0) + total
    }
  }
  var out = []
  if (week > 0) out.push(fill(tn("@agents.tokensThisWeek", week), tokens(week)))
  if (today > 0) out.push(fill(tn("@agents.tokensToday", today), tokens(today)))
  var top = ""
  for (var m in byModel) if (top === "" || byModel[m] > byModel[top]) top = m
  if (top !== "" && byModel[top] > 0) out.push(fill(t("@agents.mostlyModel"), top))
  var busiest = ""
  for (var day in byDay) if (busiest === "" || byDay[day] > byDay[busiest]) busiest = day
  if (busiest !== "" && byDay[busiest] > 0) out.push(fill(t("@agents.busiestDay"), dayName(busiest)))
  if (prompts > 0) out.push(fill(tn("@agents.promptsToday", prompts), num(prompts)))
  if (sessions > 0) out.push(fill(tn("@agents.sessionsToday", sessions), num(sessions)))
  return out
}

// Whether any limit or balance is nearly used up (the bar icon lights).
function alarming(providers, now) {
  for (var i = 0; i < (providers || []).length; i++) {
    var w = bindingWindow(providers[i].limits, now)
    if (w && w.percent >= 0.9) return true
    if (balanceAlarming(providers[i].balance)) return true
  }
  return false
}

// Omarchy's starters for "make something cool": the default agent on a new
// theme, plugin or app.
var STARTERS = [
  { key: "theme", glyph: 0xF03D8, word: "@agents.theme", prompt: "Make me a new Omarchy theme. Ask me what look or inspiration I have in mind, then build it following the Omarchy skill's theming guide and switch to it." },
  { key: "plugin", glyph: 0xF0431, word: "@agents.plugin", prompt: "Make me a new Omarchy shell plugin. Ask me what I'd like it to do, then build it following the Omarchy skill's plugin guide and enable it." },
  { key: "app", glyph: 0xF08C6, word: "@agents.app", prompt: "Make me a new app for my Omarchy desktop. Ask me what it should do, then build it following the omarchy-app skill and install it so it shows up in the app launcher." }
]

// ---- The dropdown.

// `v`: providers (Omarchy's subscribed providers, in its order), now (ms),
// adding (the agents to add are showing), footer (sync words or ""),
// iconFor(provider id) -> image URL.
function sections(v, t, tn, num) {
  var out = []
  var now = v.now || Date.now()
  var providers = v.providers || []
  if (providers.length === 0)
    out.push({ type: "text", text: t("@agents.signInIntro"), dim: true })
  for (var i = 0; i < providers.length; i++) {
    var p = providers[i]
    var id = p.providerId
    var accounts = p.accounts && p.accounts.length > 1 ? p.accounts : []
    out.push({ type: "heading", key: "agent " + id, icon: v.iconFor ? v.iconFor(id) : "", glyph: String.fromCodePoint(0xF16A3),
               text: p.providerName, detail: planLabel(p, t) })
    if (needsSignIn(p))
      out.push({ type: "actions", key: "signin", buttons: [{ key: id, label: t("@agents.signInRequired"), glyph: String.fromCodePoint(0xF0342), primary: true }] })
    var note = usageNote(p, t)
    if (note !== "") out.push({ type: "text", text: note, dim: true })
    if (accounts.length === 0) {
      var windows = displayWindows(p.limits, now)
      for (var w = 0; w < windows.length; w++) out.push(windowMeter("limit " + id + " " + w, windows[w], now, t, num))
    } else {
      for (var a = 0; a < accounts.length; a++) {
        var acct = accounts[a]
        var detail = [String(acct.plan || ""), freeResets(acct.resetCredits, now, t, tn, num)].filter(function(s) { return s !== "" }).join(" · ")
        out.push({ type: "rows", key: "account " + id, rows: [{
          key: String(acct.id), glyph: String.fromCodePoint(0xF0004), name: String(acct.label || acct.id || ""), detail: detail,
          trail: acct.active ? t("@agents.active") : t("@agents.use"), active: acct.active === true, clickable: acct.active !== true }] })
        var aw = displayWindows(acct.limits || [], now)
        for (var k = 0; k < aw.length; k++) out.push(windowMeter("limit " + id + " " + acct.id + " " + k, aw[k], now, t, num))
      }
      var auto = !!p.accountSwitch && p.accountSwitch.mode === "auto"
      var threshold = p.accountSwitch ? Number(p.accountSwitch.threshold || 95) : 95
      out.push({ type: "switch", key: "autoswitch " + id, glyph: String.fromCodePoint(0xF0453), name: t("@agents.autoswitch"),
                 detail: fill(t("@agents.switchAutoAt"), num(threshold)), on: auto })
    }
    if (p.balance) {
      var b = p.balance
      out.push({ type: "meter", key: "balance " + id, label: t("@agents.balance"), trail: formatMoney(b.remaining, b.currency, num),
                 value: b.funded > 0 ? Math.max(0, Math.min(1, b.remaining / b.funded)) : 0, alarm: balanceAlarming(b) })
      var bd = balanceDetailText(b, t, num)
      if (bd !== "") out.push({ type: "text", text: bd, dim: true })
    }
    var resets = accounts.length === 0 ? freeResets(p.resetCredits, now, t, tn, num) : ""
    if (resets !== "") out.push({ type: "text", text: resets, dim: true })
  }
  out.push({ type: "actions", key: "do", buttons: [
    { key: "launch", label: t("@agents.startDefaultAgent"), glyph: String.fromCodePoint(0xF018D), primary: true },
    { key: "add", label: t("@agents.addAccount"), glyph: String.fromCodePoint(0xF0415) } ] })
  out.push({ type: "actions", key: "add", hidden: !v.adding, buttons: SIGN_IN.map(function(pid) {
    return { key: pid, label: pid === "claude" ? "Claude Code" : pid === "codex" ? "Codex" : "Grok" } }) })
  out.push({ type: "rows", key: "starter", title: t("@agents.makeSomethingCool"), rows: STARTERS.map(function(s) {
    var word = t(s.word)
    return { key: s.key, glyph: String.fromCodePoint(s.glyph), name: word, detail: fill(t("@agents.startOnNew"), word) } }) })
  if (v.footer) out.push({ type: "text", text: v.footer, dim: true })
  return out
}

function starterPrompt(key) {
  for (var i = 0; i < STARTERS.length; i++) if (STARTERS[i].key === key) return STARTERS[i].prompt
  return ""
}
