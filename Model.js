.pragma library

// Pure presentation helpers for the Nauta widget. The portal protocol lives
// in bin/nauta; everything here is a function of the JSON that helper prints,
// so the strings the bar and panel show can be read (and changed) in one
// place.

// Glyphs verified against JetBrainsMono Nerd Font's cmap. Nerd Font icons live
// above U+FFFF, so they are built from codepoints: a "\uF05A9" escape is
// U+F05A followed by a literal 9 in JavaScript, not the wifi glyph.
function codepoint(code) {
  return String.fromCodePoint(code)
}

var GLYPH_WEB = codepoint(0xF059F)           // md-web
var GLYPH_WIFI = codepoint(0xF05A9)          // md-wifi
var GLYPH_WIFI_OFF = codepoint(0xF05AA)      // md-wifi_off
var GLYPH_REFRESH = codepoint(0xF0450)       // md-refresh
var GLYPH_TRASH = codepoint(0xF0A7A)         // md-trash_can_outline
var GLYPH_STAR = codepoint(0xF04CE)          // md-star
var GLYPH_STAR_OUTLINE = codepoint(0xF04D2)  // md-star_outline
var GLYPH_LOGOUT = codepoint(0xF0343)        // md-logout
var GLYPH_LOCK = codepoint(0xF033E)          // md-lock
var GLYPH_ALERT = codepoint(0xF0028)         // md-alert_circle
var GLYPH_ACCOUNT = codepoint(0xF0004)       // md-account
var GLYPH_CHECK = codepoint(0xF05E0)         // md-check_circle
var GLYPH_PLUS = codepoint(0xF0415)          // md-plus
var GLYPH_PENCIL = codepoint(0xF03EB)        // md-pencil

function parseJSON(text) {
  var raw = String(text === undefined || text === null ? "" : text).replace(/^\s+|\s+$/g, "")
  if (raw === "") return null
  try {
    var value = JSON.parse(raw)
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

function pad2(value) {
  var n = Math.max(0, Math.floor(Number(value) || 0))
  return (n < 10 ? "0" : "") + n
}

// Full clock for the panel: "1:05:09".
function formatClock(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  return Math.floor(total / 3600) + ":" + pad2(Math.floor(total / 60) % 60) + ":" + pad2(total % 60)
}

// Compact form for the bar: "1:05" with hours, "05:09" without.
function formatCompact(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  if (total >= 3600) return Math.floor(total / 3600) + ":" + pad2(Math.floor(total / 60) % 60)
  return pad2(Math.floor(total / 60)) + ":" + pad2(total % 60)
}

function barLabel(loggedIn, seconds, mode) {
  if (mode !== "remaining") return ""
  if (!loggedIn) return ""
  return formatCompact(seconds)
}

function statusMeta(state, loggedIn, seconds, ssid) {
  if (loggedIn) return "Conectado · quedan " + formatClock(seconds)
  if (state === "portal") return "Portal Nauta · falta autenticarse"
  if (state === "online") return "En línea · sin sesión del plugin"
  if (state === "offline") return ssid ? "Sin conexión a internet" : "Sin conexión"
  return "Comprobando la conexión…"
}

function stateHint(state, loggedIn, nauta, hasAccounts) {
  if (loggedIn) return "La cuenta está autenticada. Puedes cerrar sesión cuando quieras."
  if (state === "portal") {
    if (!nauta) return "Hay un portal cautivo en esta red, pero no parece ser el de Nauta."
    if (!hasAccounts) return "Portal Nauta detectado. Guarda una cuenta para conectarte."
    return "Portal Nauta detectado. Elige la cuenta con la que quieres conectarte."
  }
  if (state === "online") return "Hay internet, pero esta sesión no la abrió el plugin, así que no puede leer el tiempo restante."
  if (state === "offline") return "No hay respuesta de la red. Revisa la WiFi e inténtalo de nuevo."
  return "Comprobando el estado de la conexión…"
}

function accountTitle(account) {
  if (!account) return ""
  var label = String(account.label || "").replace(/^\s+|\s+$/g, "")
  if (label !== "") return label
  return localPart(account.user)
}

function localPart(user) {
  var value = String(user || "")
  var at = value.indexOf("@")
  return at > 0 ? value.substring(0, at) : value
}

function accountSubtitle(account) {
  if (!account) return ""
  var user = String(account.user || "")
  if (account.hasPassword === false) return user + " · sin contraseña guardada"
  return user
}

function normalizeUserPreview(user) {
  var value = String(user || "").replace(/^\s+|\s+$/g, "")
  if (value === "") return ""
  if (value.indexOf("@") === -1) value += "@nauta.com.cu"
  return value
}

function validateAccount(user, password, passwordOptional) {
  var value = String(user || "").replace(/^\s+|\s+$/g, "")
  if (value === "") return { ok: false, message: "Escribe el usuario de Nauta." }
  if (value.indexOf("@") === 0 || value.indexOf("@") === value.length - 1)
    return { ok: false, message: "El usuario no es válido." }
  if (passwordOptional !== true && String(password || "") === "")
    return { ok: false, message: "Escribe la contraseña." }
  return { ok: true, message: "" }
}

function stateColor(state, loggedIn, dim, foreground, urgent) {
  if (loggedIn) return foreground
  if (state === "portal") return urgent
  if (state === "offline") return dim
  return foreground
}

function iconGlyph(state, loggedIn) {
  if (loggedIn || state === "online") return GLYPH_WEB
  if (state === "portal") return GLYPH_LOCK
  return GLYPH_WIFI_OFF
}

function canAutoLogin(autoLogin, state, loggedIn, nauta, account) {
  return autoLogin === true
    && state === "portal"
    && loggedIn !== true
    && nauta === true
    && account !== null
    && account !== undefined
    && account.hasPassword !== false
}
