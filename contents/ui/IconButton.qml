import QtQuick
import QtQuick.Controls as Controls

// Small themed button so the header stays legible in forced light/dark modes.
Rectangle {
    id: button
    property string icon: "sync"
    property string tooltip: ""
    property bool checkable: false
    property bool checked: false
    property bool spinning: false
    property color ink: "black"
    property color accent: "steelblue"
    signal clicked()
    implicitWidth: 28
    implicitHeight: 28
    radius: 6
    color: checked ? Qt.alpha(accent, 0.18) : mouse.containsMouse ? Qt.alpha(ink, 0.1) : "transparent"
    opacity: enabled ? 1 : 0.5
    Octicon {
        id: glyph
        anchors.centerIn: parent
        name: button.icon
        color: button.checked ? button.accent : button.ink
        RotationAnimator on rotation { running: button.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: glyph.rotation = 0 }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (button.checkable) button.checked = !button.checked; button.clicked() }
    }
    Controls.ToolTip.visible: mouse.containsMouse && tooltip !== ""
    Controls.ToolTip.text: tooltip
    Controls.ToolTip.delay: 500
}
