import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "mich.nauta"
  ipcTarget: "mich.nauta"
  manageIpc: false

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); service.refreshAccounts(); return "ok" }
    function status(): string {
      return JSON.stringify({
        state: service.connState,
        loggedIn: service.loggedIn,
        remaining: service.remaining,
        width: root.width,
        implicitWidth: root.implicitWidth,
        buttonWidth: button.width,
        buttonImplicitWidth: button.implicitWidth,
        barLabel: root.barLabel,
        text: button.text
      })
    }
  }

  // Qt.resolvedUrl keeps this working wherever the plugin is installed.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    url = url.replace(/^file:\/\//, "")
    return url.replace(/\/$/, "")
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string barLabelMode: setting("barLabel", "remaining")
  readonly property string barLabel: Model.barLabel(service.loggedIn, service.liveRemaining, barLabelMode)
  readonly property string barIcon: Model.iconGlyph(service.connState, service.loggedIn)
  readonly property string tooltip: "Nauta · " + Model.statusMeta(service.connState, service.loggedIn, service.liveRemaining, service.ssid)
  readonly property bool needsAttention: !service.loggedIn && service.connState === "portal"

  property bool adding: false
  property string editingUser: ""
  property string formUser: ""
  property string formPassword: ""
  property string formLabel: ""
  property bool formDefault: false
  property string formError: ""
  property string pendingDelete: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function resetForm() {
    editingUser = ""
    formUser = ""
    formPassword = ""
    formLabel = ""
    formDefault = false
    formError = ""
  }

  function startEdit(account) {
    if (!account) return
    editingUser = String(account.user || "")
    formUser = editingUser
    formPassword = ""
    formLabel = String(account.label || "")
    formDefault = account.isDefault === true
    formError = ""
    adding = true
    Qt.callLater(function() { userField.forceActiveFocus() })
  }

  function submitForm(connect) {
    formError = ""
    var editing = editingUser !== ""
    var check = Model.validateAccount(formUser, formPassword, editing)
    if (!check.ok) {
      formError = check.message
      return
    }
    if (editing)
      service.updateAccount(editingUser, formUser, formLabel, formPassword, connect)
    else
      service.addAccount(formUser, formPassword, formLabel, formDefault, connect)
  }

  function requestDelete(user) {
    if (pendingDelete === user) {
      pendingDelete = ""
      service.removeAccount(user)
      return
    }
    pendingDelete = user
    deleteReset.restart()
  }

  onOpenedChanged: {
    if (opened) {
      service.refreshAccounts()
      service.refresh()
      if (service.accounts.length === 0) adding = true
      Qt.callLater(function() { if (contentFocus) contentFocus.forceActiveFocus() })
    } else {
      adding = false
      pendingDelete = ""
      resetForm()
    }
  }

  Service {
    id: service
    settings: root.settings
    helperPath: root.pluginDir + "/bin/nauta"
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon + (root.barLabel !== "" ? "  " + root.barLabel : "")
    fontFamily: root.fontFamily
    active: root.needsAttention
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        service.refresh()
        service.refreshAccounts()
      } else if (buttonCode === Qt.MiddleButton) {
        if (service.loggedIn) service.logout()
        else if (service.defaultAccount()) service.login(service.defaultAccount().user)
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: contentFocus
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Item {
        id: contentFocus
        width: 0
        height: 0
        focus: true
        Keys.onEscapePressed: root.close()
      }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Nauta"
          meta: Model.statusMeta(service.connState, service.loggedIn, service.liveRemaining, service.ssid)
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: service.loggedIn || service.connState === "online" ? 1.0 : 0.55
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.barIcon
              color: Model.stateColor(service.connState, service.loggedIn, root.dim, root.foreground, root.urgent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              checked: service.autoLogin
              foreground: root.foreground
              onToggled: root.persistSettings({ autoLogin: !service.autoLogin })
              PanelToolTip {
                visible: parent.containsMouse
                text: service.autoLogin ? "Inicio de sesión automático activado" : "Inicio de sesión automático desactivado"
                fontFamily: root.fontFamily
              }
            }
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            visible: service.ssid !== ""
            Layout.fillWidth: true
            text: "WiFi: " + service.ssid
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          PanelActionButton {
            iconText: Model.GLYPH_REFRESH
            tooltipText: "Volver a comprobar"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !service.busy
            onClicked: {
              service.refresh()
              service.refreshAccounts()
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: service.actionStatus !== "" && service.lastError === ""
          text: service.actionStatus
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: service.lastError !== ""
          text: service.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ------------------------------------------------------- live session

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: service.loggedIn

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "SESIÓN ACTIVA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: service.activeUser
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                text: "tiempo restante"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              textFormat: Text.PlainText
              text: Model.formatClock(service.liveRemaining)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title * 1.35
              font.bold: true
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Cerrar sesión"
              iconText: Model.GLYPH_LOGOUT
              foreground: root.foreground
              bordered: true
              focusable: true
              enabled: !service.busy
              onClicked: service.logout()
            }

            Item { Layout.fillWidth: true }
          }
        }

        // ------------------------------------------------------------ hint

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: !service.loggedIn
          text: Model.stateHint(service.connState, service.loggedIn, service.nautaNetwork, service.accounts.length > 0)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---------------------------------------------------------- accounts

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "CUENTAS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: service.accounts.length === 0
          text: "Todavía no hay cuentas guardadas."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          id: accountColumn
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: service.accounts

            delegate: CursorSurface {
              id: accountRow
              required property var modelData
              required property int index

              readonly property bool current: service.loggedIn && String(modelData.user) === String(service.activeUser)
              readonly property bool confirming: root.pendingDelete === String(modelData.user)

              width: accountColumn.width
              foreground: root.foreground
              hasCursor: rowMouse.containsMouse

              implicitHeight: accountRowLayout.implicitHeight + Style.spacing.rowPaddingX

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !service.busy && !accountRow.current
                onClicked: service.login(accountRow.modelData.user)
              }

              RowLayout {
                id: accountRowLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: accountRow.current ? Model.GLYPH_CHECK : Model.GLYPH_ACCOUNT
                  color: accountRow.current ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      Layout.fillWidth: true
                      text: Model.accountTitle(accountRow.modelData)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: accountRow.modelData.isDefault === true
                      text: "predeterminada"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: Model.accountSubtitle(accountRow.modelData)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                PanelActionButton {
                  iconText: Model.GLYPH_PENCIL
                  tooltipText: "Editar esta cuenta"
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  enabled: !service.busy
                  onClicked: root.startEdit(accountRow.modelData)
                }

                PanelActionButton {
                  iconText: accountRow.modelData.isDefault === true ? Model.GLYPH_STAR : Model.GLYPH_STAR_OUTLINE
                  tooltipText: accountRow.modelData.isDefault === true
                    ? "Quitar como predeterminada"
                    : "Usar como predeterminada para el inicio automático"
                  foreground: accountRow.modelData.isDefault === true ? root.foreground : root.dim
                  fontFamily: root.fontFamily
                  enabled: !service.busy
                  onClicked: accountRow.modelData.isDefault === true
                    ? service.clearDefaultAccount()
                    : service.setDefaultAccount(accountRow.modelData.user)
                }

                PanelActionButton {
                  iconText: Model.GLYPH_WIFI
                  tooltipText: accountRow.current ? "Sesión activa" : "Conectar con esta cuenta"
                  foreground: accountRow.current ? root.foreground : root.dim
                  fontFamily: root.fontFamily
                  enabled: !service.busy && !accountRow.current
                  onClicked: service.login(accountRow.modelData.user)
                }

                PanelActionButton {
                  iconText: accountRow.confirming ? Model.GLYPH_ALERT : Model.GLYPH_TRASH
                  tooltipText: accountRow.confirming ? "Confirma para eliminar" : "Eliminar esta cuenta"
                  foreground: accountRow.confirming ? root.urgent : root.dim
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  enabled: !service.busy
                  onClicked: root.requestDelete(accountRow.modelData.user)
                }
              }
            }
          }
        }

        // --------------------------------------------------------- add form

        Button {
          visible: !root.adding
          text: "Añadir cuenta"
          iconText: Model.GLYPH_PLUS
          foreground: root.foreground
          bordered: true
          focusable: true
          enabled: !service.busy
          onClicked: {
            root.resetForm()
            root.adding = true
            Qt.callLater(function() { userField.forceActiveFocus() })
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.adding

          PanelSectionHeader {
            text: root.editingUser !== "" ? "EDITAR CUENTA" : "NUEVA CUENTA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: userField
            width: parent.width
            foreground: root.foreground
            placeholderText: "usuario o usuario@nauta.com.cu"
            text: root.formUser
            onTextEdited: root.formUser = text
            onAccepted: passwordField.forceActiveFocus()
            Keys.onEscapePressed: root.close()
          }

          TextField {
            id: passwordField
            width: parent.width
            foreground: root.foreground
            password: true
            placeholderText: root.editingUser !== ""
              ? "contraseña (vacío para mantener la actual)"
              : "contraseña"
            text: root.formPassword
            onTextEdited: root.formPassword = text
            onAccepted: labelField.forceActiveFocus()
            Keys.onEscapePressed: root.close()
          }

          TextField {
            id: labelField
            width: parent.width
            foreground: root.foreground
            placeholderText: "etiqueta (opcional)"
            text: root.formLabel
            onTextEdited: root.formLabel = text
            onAccepted: root.submitForm(false)
            Keys.onEscapePressed: root.close()
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            visible: root.editingUser === ""

            ToggleSwitch {
              checked: root.formDefault
              foreground: root.foreground
              onToggled: root.formDefault = !root.formDefault
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: "Predeterminada"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.formError !== ""
            text: root.formError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.editingUser !== "" ? "Guardar cambios" : "Guardar"
              foreground: root.foreground
              bordered: true
              focusable: true
              enabled: !service.busy
              onClicked: root.submitForm(false)
            }

            Button {
              text: "Guardar y conectar"
              foreground: root.foreground
              bordered: true
              focusable: true
              enabled: !service.busy
              onClicked: root.submitForm(true)
            }

            Item { Layout.fillWidth: true }

            Button {
              text: "Cancelar"
              foreground: root.dim
              focusable: true
              onClicked: {
                root.adding = false
                root.resetForm()
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Las contraseñas se guardan en el llavero del sistema. El tiempo se consulta al portal de ETECSA."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Timer {
    id: deleteReset
    interval: 4000
    repeat: false
    onTriggered: root.pendingDelete = ""
  }

  Timer {
    interval: 6000
    running: service.actionStatus !== "" && !service.busy
    repeat: false
    onTriggered: service.actionStatus = ""
  }

  Connections {
    target: service
    function onAccountSaved(user) {
      if (String(user) !== "") {
        root.adding = false
        root.resetForm()
      }
    }
  }
}
