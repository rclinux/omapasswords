pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/Gen.js" as Gen

// The OmaPasswords panel: three fresh passwords every time it opens. Click one
// (or press its number) to copy it. Nothing is stored; the values are dropped
// when the panel closes, and the clipboard is emptied after `clearAfter`
// seconds if it still holds the copied password.
//
// Keys: 1/2/3 copy, Up/Down (or j/k) move, Enter copies the highlighted one,
// r = new passwords, Esc = close.
Panel {
  id: root
  moduleName: "io.github.rclinux.omapasswords"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int clearAfter: 30
  property bool showBits: true

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---- state ---------------------------------------------------------------------------
  property var values: ["", "", ""]
  property string status: "idle"      // idle, reading, ready, error
  property int cursor: 0
  property int copiedIndex: -1
  property string lastCopied: ""      // only kept until the clipboard is cleared
  property int copyCount: 0           // bumped on every copy
  property int checkingCopy: 0        // which copy the running clipboard check belongs to
  property string pendingCopy: ""     // handed to wl-copy's stdin, then dropped
  property int remaining: 0           // seconds until the clipboard is cleared
  property string toast: ""
  property int attempts: 0

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Tones {
    id: pal
    foreground: root.barForeground
    urgent: root.bar ? root.bar.urgent : Color.urgent
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
    } else {
      values = ["", "", ""]
      status = "idle"
      if (copiedIndex >= 0 && remaining <= 0) copiedIndex = -1
    }
  }

  // ---- generating ----------------------------------------------------------------------
  function refresh() {
    if (randProc.running) return
    attempts = 0
    if (remaining <= 0) {
      copiedIndex = -1
      toast = ""
    }
    status = "reading"
    randProc.running = true
  }

  function useBytes(text) {
    // A read that finishes after the panel closed must not bring the passwords back.
    if (!root.opened) return
    var bytes = Gen.parseOd(text)
    if (!bytes || bytes.length < Gen.BYTES_PER_READ) {
      fail()
      return
    }
    var v = Gen.generateAll(bytes)
    if (v === null) {
      // Too many rejected bytes; astronomically rare, but read again rather than settle.
      attempts += 1
      if (attempts < 3) Qt.callLater(function() { randProc.running = true })
      else fail()
      return
    }
    values = v
    status = "ready"
  }

  // Never fall back to Math.random: without a secure source there are no passwords.
  function fail() {
    values = ["", "", ""]
    status = "error"
  }

  Process {
    id: randProc
    command: ["od", "-An", "-v", "-tu1", "-N" + Gen.BYTES_PER_READ, "/dev/urandom"]
    stdout: StdioCollector {
      onStreamFinished: root.useBytes(text)
    }
  }

  // ---- copying -------------------------------------------------------------------------
  // The password goes to wl-copy on stdin, never as an argument, so it can't be
  // seen in the process list. --sensitive asks clipboard managers not to keep it.
  function copyAt(index) {
    if (status !== "ready" || index < 0 || index >= values.length || values[index] === "") return
    if (copyProc.running) return
    pendingCopy = values[index]
    // Only kept for the clipboard check; with clearing off there is no check.
    lastCopied = clearAfter > 0 ? values[index] : ""
    copyCount += 1
    copiedIndex = index
    cursor = index
    copyProc.stdinEnabled = true
    copyProc.running = true
    remaining = clearAfter
    toast = clearAfter > 0 ? "" : "Copied"
  }

  Process {
    id: copyProc
    command: ["wl-copy", "--sensitive"]
    stdinEnabled: true
    onStarted: {
      write(root.pendingCopy)
      root.pendingCopy = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.toast = "Couldn’t copy: is wl-clipboard installed?"
        root.lastCopied = ""
        root.copiedIndex = -1
        root.remaining = 0
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.remaining > 0
    onTriggered: {
      root.remaining -= 1
      if (root.remaining <= 0) {
        root.checkingCopy = root.copyCount
        pasteProc.running = true
      }
    }
  }

  // Clear only if the clipboard still holds what we put there.
  Process {
    id: pasteProc
    command: ["wl-paste", "-n"]
    stdout: StdioCollector {
      onStreamFinished: {
        // A newer copy started while this check ran; it has its own countdown.
        if (root.checkingCopy !== root.copyCount) return
        if (root.lastCopied !== "" && text === root.lastCopied) {
          clearProc.running = true
          root.toast = "Clipboard cleared"
        } else {
          root.toast = ""
        }
        root.lastCopied = ""
        root.copiedIndex = -1
      }
    }
  }

  Process {
    id: clearProc
    command: ["wl-copy", "--clear"]
  }

  function footline() {
    if (status === "error") return ""
    if (remaining > 0) return "Copied · clipboard clears in " + remaining + " s"
    return toast
  }

  function hints() {
    var out = []
    if (status === "ready") {
      out.push({ k: "1–3", t: "copy" })
      out.push({ k: "enter", t: "copy highlighted" })
    }
    out.push({ k: "r", t: "new passwords" })
    out.push({ k: "esc", t: "close" })
    return out
  }

  // ---- layout ---------------------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.cursor = Math.max(0, Math.min(Gen.KINDS.length - 1, root.cursor + (dy > 0 ? 1 : -1)))
      }
      // Enter fires both returnRequested and activateRequested; handle activate alone.
      onActivateRequested: root.copyAt(root.cursor)
      onTextKey: function(text) {
        if (text === "1" || text === "2" || text === "3") root.copyAt(parseInt(text, 10) - 1)
        else if (text === "r") root.refresh()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        // ---- header -----------------------------------------------------------------------
        Item {
          width: parent.width
          height: Math.max(headText.implicitHeight, actions.height) + Style.space(4)

          Text {
            id: lock
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.top: parent.top
            anchors.topMargin: Style.space(2)
            textFormat: Text.PlainText
            text: ""
            color: root.status === "error" ? pal.critical : pal.calm
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Column {
            id: headText
            anchors.left: lock.right
            anchors.leftMargin: Style.space(12)
            anchors.right: actions.left
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(3)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.status === "error" ? "Couldn’t read the random source" : "Passwords"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.status === "error"
                ? "OmaPasswords reads /dev/urandom with od. Press r to try again."
                : "Made from your system’s secure random source. Nothing is saved."
              color: pal.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(2)

            PanelActionButton {
              iconText: ""
              tooltipText: "New passwords  (r)"
              foreground: root.barForeground
              fontFamily: root.fontFamily
              enabled: !randProc.running
              opacity: enabled ? 1 : 0.35
              onClicked: root.refresh()
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ---- the three passwords ------------------------------------------------------------
        Repeater {
          model: Gen.KINDS.length

          delegate: Rectangle {
            id: row
            required property int index
            readonly property var kind: Gen.KINDS[index]
            readonly property bool current: root.cursor === index
            readonly property bool copied: root.copiedIndex === index && root.remaining > 0

            width: content.width
            height: rowText.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: current || hover.containsMouse ? pal.washStrong : pal.wash
            border.width: 1
            border.color: copied ? pal.calm : (current ? pal.hairline : "transparent")

            Column {
              id: rowText
              x: Style.space(12)
              y: Style.space(9)
              width: parent.width - Style.space(24)
              spacing: Style.space(4)

              Item {
                width: parent.width
                height: label.implicitHeight

                Text {
                  id: label
                  anchors.left: parent.left
                  textFormat: Text.PlainText
                  text: (row.index + 1) + "  " + row.kind.name
                  color: pal.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  anchors.right: parent.right
                  textFormat: Text.PlainText
                  text: row.copied ? "copied" : (root.showBits ? Math.round(Gen.bits(row.kind)) + " bits" : "")
                  color: row.copied ? pal.calm : pal.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.values[row.index] !== "" ? root.values[row.index] : (root.status === "reading" ? "…" : "—")
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WrapAnywhere
              }
            }

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.status === "ready" ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.copyAt(row.index)
            }
          }
        }

        // ---- footer -------------------------------------------------------------------------------
        PanelSeparator { foreground: root.barForeground }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.footline()
          color: pal.calm
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          leftPadding: Style.space(4)
        }

        Flow {
          width: parent.width
          leftPadding: Style.space(4)
          spacing: Style.space(10)

          Repeater {
            model: root.hints()
            delegate: Row {
              id: hint
              required property var modelData
              spacing: Style.space(5)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(Style.space(16), keyLabel.implicitWidth + Style.space(8))
                height: keyLabel.implicitHeight + Style.space(4)
                radius: Style.cornerRadius
                color: pal.wash
                border.width: 1
                border.color: pal.hairline

                Text {
                  id: keyLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: hint.modelData.k
                  color: pal.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: hint.modelData.t
                color: pal.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
