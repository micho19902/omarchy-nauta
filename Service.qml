import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the Nauta widget knows about the network, the portal session and
// the saved accounts. The portal protocol itself lives in bin/nauta so this
// file only orders one helper run at a time and turns its JSON into state.
Item {
  id: root

  property var settings: ({})
  property string helperPath: ""

  readonly property bool autoLogin: setting("autoLogin", true) === true
  readonly property int refreshIntervalSec: Math.max(10, Number(setting("refreshIntervalSec", 30)) || 30)

  // "online" | "portal" | "offline" | "unknown"
  property string connState: "unknown"
  property bool nautaNetwork: false
  property bool loggedIn: false
  property string activeUser: ""
  property string remaining: ""
  property int remainingSeconds: 0
  property double sampledAt: 0
  property string ssid: ""
  property string lastError: ""
  property string actionStatus: ""
  property var accounts: []
  property string defaultUser: ""
  property bool busy: false
  property string busyAction: ""
  property int tick: 0

  property var jobQueue: []
  property var currentJob: null
  property string pendingStdin: ""
  property double lastAutoAttempt: 0
  property int autoFailures: 0

  signal accountSaved(string user)

  readonly property int liveRemaining: {
    var beat = tick // keeps the countdown ticking once a second
    if (!loggedIn) return 0
    if (sampledAt <= 0) return remainingSeconds
    var elapsed = Math.max(0, Math.floor((Date.now() - sampledAt) / 1000))
    return Math.max(0, remainingSeconds - elapsed)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function defaultAccount() {
    for (var i = 0; i < accounts.length; i++) {
      if (accounts[i].isDefault) return accounts[i]
    }
    return null
  }

  function accountFor(user) {
    var wanted = String(user || "").toLowerCase()
    for (var i = 0; i < accounts.length; i++) {
      if (String(accounts[i].user || "").toLowerCase() === wanted) return accounts[i]
    }
    return null
  }

  // ------------------------------------------------------------- job runner
  //
  // One Process, one queue: the portal answers slowly and a login must never
  // race a status probe. Jobs are { name, args, stdin, meta }.

  function enqueue(name, args, stdinText, meta) {
    jobQueue.push({ name: name, args: args, stdin: stdinText || "", meta: meta || ({}) })
    pump()
  }

  function pump() {
    if (proc.running || jobQueue.length === 0) return
    var job = jobQueue.shift()
    currentJob = job
    pendingStdin = job.stdin
    proc.stdinEnabled = job.stdin !== ""
    proc.stdoutText = ""
    proc.stderrText = ""
    proc.command = [helperPath].concat(job.args)
    proc.running = true
  }

  function finishJob(code, stdoutText, stderrText) {
    var job = currentJob
    currentJob = null

    var data = Model.parseJSON(stdoutText)
    var message = ""
    if (data && data.ok === false) message = String(data.error || "El cliente Nauta devolvió un error.")
    if (!data) {
      message = String(stderrText || "").replace(/^\s+|\s+$/g, "")
      if (message === "") message = code === 0 ? "El cliente Nauta no devolvió datos." : "El cliente Nauta falló (código " + code + ")."
    }

    if (job && job.name === "status") {
      // A status probe is background work: it never blocks the panel and its
      // failure is only worth surfacing when nothing better is on screen.
      if (data && data.ok !== false) applyStatus(data)
      else if (lastError === "") lastError = message
      maybeAutoLogin()
      Qt.callLater(root.pump)
      return
    }

    busy = false
    busyAction = ""

    if (!data || data.ok === false) {
      lastError = message
      if (job && job.name === "login") autoFailures++
      actionStatus = ""
    } else {
      lastError = ""
      handleSuccess(job, data)
    }

    tick++
    Qt.callLater(root.pump)
  }

  function handleSuccess(job, data) {
    if (!job) return
    if (job.name === "login") {
      applyLogin(data)
      actionStatus = "Conectado con " + String(data.user || "")
      autoFailures = 0
      return
    }
    if (job.name === "logout") {
      loggedIn = false
      activeUser = ""
      remaining = ""
      remainingSeconds = 0
      sampledAt = 0
      actionStatus = String(data.message || "Sesión cerrada.")
      Qt.callLater(root.refresh)
      return
    }
    if (job.name === "accounts") {
      applyAccounts(data)
      return
    }
    if (job.name === "add") {
      applyAccounts(data)
      actionStatus = "Cuenta guardada: " + String(data.user || "")
      accountSaved(String(data.user || ""))
      if (job.meta.connect === true) login(data.user)
      return
    }
    if (job.name === "update") {
      applyAccounts(data)
      actionStatus = "Cuenta actualizada: " + String(data.user || "")
      accountSaved(String(data.user || ""))
      if (job.meta.connect === true) login(data.user)
      return
    }
    if (job.name === "remove") {
      applyAccounts(data)
      actionStatus = "Cuenta eliminada."
      return
    }
    if (job.name === "default") {
      applyAccounts(data)
      actionStatus = job.meta && job.meta.clear === true
        ? "Cuenta predeterminada desmarcada."
        : "Cuenta predeterminada actualizada."
      return
    }
    if (job.name === "password") {
      applyAccounts(data)
      actionStatus = "Contraseña actualizada."
      return
    }
  }

  property string lastPortalSsid: ""

  function applyStatus(data) {
    var prevState = connState
    var prevSsid = ssid

    connState = String(data.state || "unknown")
    nautaNetwork = data.nauta === true
    ssid = String(data.ssid || "")
    loggedIn = data.loggedIn === true

    if (loggedIn) {
      activeUser = String(data.user || "")
      remaining = String(data.remaining || "")
      remainingSeconds = Number(data.remainingSeconds || 0)
      sampledAt = Number(data.sampledAt || 0) * 1000
      autoFailures = 0
      if (lastPortalSsid !== "") lastPortalSsid = ""
    } else {
      remaining = ""
      remainingSeconds = 0
      sampledAt = 0
      if (String(data.user || "") !== "") activeUser = String(data.user)
      if (prevState !== "portal" && connState === "portal" && nautaNetwork) {
        if (lastPortalSsid !== ssid) {
          lastPortalSsid = ssid
          Quickshell.execDetached(["notify-send", "-a", "Nauta", "-i", "gcr-password", "Nauta: Autenticación requerida", "Hay que iniciar sesión en el portal de ETECSA para tener internet."])
        }
      }
      if (connState !== "portal") {
        lastPortalSsid = ""
      }
    }

    if (connState === "online") autoFailures = 0
    if (data.error !== undefined && String(data.error) !== "") lastError = String(data.error)
    else if (!busy) lastError = ""
  }

  function applyLogin(data) {
    loggedIn = data.loggedIn !== false
    connState = "online"
    activeUser = String(data.user || "")
    remaining = String(data.remaining || "")
    remainingSeconds = Number(data.remainingSeconds || 0)
    sampledAt = Number(data.sampledAt || 0) * 1000
    if (data.warning !== undefined && String(data.warning) !== "") lastError = String(data.warning)
    Qt.callLater(root.refresh)
  }

  function applyAccounts(data) {
    accounts = data.accounts || []
    defaultUser = String(data.default || "")
    maybeAutoLogin()
  }

  // ------------------------------------------------------------- operations

  function refresh() {
    if (helperPath === "" || busy) return
    enqueue("status", ["status"], "")
  }

  function refreshAccounts() {
    if (helperPath === "" || busy) return
    enqueue("accounts", ["accounts"], "")
  }

  function login(user) {
    if (busy || user === undefined || user === null || String(user) === "") return
    busy = true
    busyAction = "login"
    lastError = ""
    actionStatus = "Conectando con " + String(user) + "…"
    enqueue("login", ["login", "--account", String(user)], "")
  }

  function logout() {
    if (busy) return
    busy = true
    busyAction = "logout"
    lastError = ""
    actionStatus = "Cerrando sesión…"
    enqueue("logout", ["logout"], "")
  }

  function addAccount(user, password, label, makeDefault, connect) {
    if (busy) return
    var check = Model.validateAccount(user, password)
    if (!check.ok) {
      lastError = check.message
      return
    }
    busy = true
    busyAction = "add"
    lastError = ""
    actionStatus = "Guardando la cuenta…"
    var args = ["account-add", "--user", String(user).replace(/^\s+|\s+$/g, ""), "--label", String(label || "")]
    if (makeDefault === true) args.push("--default")
    enqueue("add", args, String(password), { connect: connect === true })
  }

  function updateAccount(user, newUser, label, password, connect) {
    if (busy) return
    var check = Model.validateAccount(newUser, password, true)
    if (!check.ok) {
      lastError = check.message
      return
    }
    busy = true
    busyAction = "update"
    lastError = ""
    actionStatus = "Guardando los cambios…"
    var args = ["account-update", "--user", String(user), "--new-user", String(newUser), "--label", String(label || "")]
    var secret = String(password || "")
    if (secret === "") args.push("--no-password")
    enqueue("update", args, secret, { connect: connect === true })
  }

  function removeAccount(user) {
    if (busy) return
    busy = true
    busyAction = "remove"
    lastError = ""
    enqueue("remove", ["account-remove", "--user", String(user)], "")
  }

  function setDefaultAccount(user) {
    if (busy) return
    busy = true
    busyAction = "default"
    lastError = ""
    enqueue("default", ["account-default", "--user", String(user)], "", { clear: false })
  }

  function clearDefaultAccount() {
    if (busy) return
    busy = true
    busyAction = "default"
    lastError = ""
    enqueue("default", ["account-default", "--clear"], "", { clear: true })
  }

  function changePassword(user, password) {
    if (busy) return
    if (String(password || "") === "") {
      lastError = "Escribe la contraseña."
      return
    }
    busy = true
    busyAction = "password"
    lastError = ""
    enqueue("password", ["account-password", "--user", String(user)], String(password))
  }

  // -------------------------------------------------------------- auto-login

  function maybeAutoLogin() {
    var account = defaultAccount()
    if (!Model.canAutoLogin(autoLogin, connState, loggedIn, nautaNetwork, account)) return
    if (busy || helperPath === "") return
    var wait = autoFailures > 0 ? 120000 : 15000
    if (Date.now() - lastAutoAttempt < wait) return
    lastAutoAttempt = Date.now()
    actionStatus = "Iniciando sesión automáticamente con " + account.user + "…"
    login(account.user)
  }

  // -------------------------------------------------------------------- i/o

  Process {
    id: proc
    property string stdoutText: ""
    property string stderrText: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: proc.stdoutText = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: proc.stderrText = String(text || "")
    }
    onStarted: {
      if (root.pendingStdin !== "") {
        proc.write(root.pendingStdin)
        root.pendingStdin = ""
      }
      // The helper reads the password until EOF. Closing stdin is what makes
      // that read return: writing alone leaves account-add waiting forever.
      proc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.finishJob(exitCode, proc.stdoutText, proc.stderrText)
    }
  }

  Timer {
    // Poll briskly while waiting for the portal, lazily once connected.
    interval: root.loggedIn ? Math.max(60, root.refreshIntervalSec) * 1000 : root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: if (!root.busy) root.refresh()
  }

  Timer {
    interval: 1000
    running: root.loggedIn
    repeat: true
    onTriggered: root.tick++
  }

  Component.onCompleted: {
    refreshAccounts()
    refresh()
  }
}
