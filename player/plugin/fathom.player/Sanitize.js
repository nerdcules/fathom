.pragma library

// Text from mpv comes from the web (video titles), so it is untrusted. Bar
// labels and tooltips are drawn by Omarchy components whose text format the
// plugin cannot set, so markup is neutralised here instead: angle brackets and
// ampersands become look-alike characters, control and line-separator
// characters become spaces, and the length is capped.
function plain(value, maxLength) {
  var s = value === undefined || value === null ? "" : String(value)
  var cap = maxLength > 0 ? maxLength : 300
  if (s.length > cap) s = s.slice(0, cap)
  s = s
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ")
    .replace(/</g, "‹")
    .replace(/>/g, "›")
    .replace(/&/g, "＆")
  return s.replace(/\s+/g, " ").trim()
}

// Shorten to at most n characters, ending in an ellipsis when cut.
function ellipsize(value, n) {
  var s = String(value)
  if (n < 2 || s.length <= n) return s
  return s.slice(0, n - 1).replace(/\s+$/, "") + "…"
}

// 75 -> "1:15", 3725 -> "1:02:05". Anything not a finite, non-negative number is "--:--".
function clock(seconds) {
  var t = Number(seconds)
  if (!isFinite(t) || t < 0) return "--:--"
  t = Math.floor(t)
  var h = Math.floor(t / 3600)
  var m = Math.floor((t % 3600) / 60)
  var s = t % 60
  var ss = s < 10 ? "0" + s : String(s)
  if (h > 0) return h + ":" + (m < 10 ? "0" + m : m) + ":" + ss
  return m + ":" + ss
}
