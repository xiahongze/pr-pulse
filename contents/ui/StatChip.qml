import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

// Count chip in GitHub's state colour; clicking it toggles the matching filter.
Rectangle {
    id: chip
    property string icon: "git-pull-request"
    property color tone: "green"
    property color ink: "black"
    property int count: 0
    property string label: ""
    property bool active: false
    signal clicked()
    implicitHeight: 26
    implicitWidth: row.implicitWidth + 16
    radius: 13
    color: active ? Qt.alpha(tone, 0.22) : mouse.containsMouse ? Qt.alpha(tone, 0.14) : Qt.alpha(tone, 0.08)
    border.color: active ? tone : Qt.alpha(tone, 0.35)
    border.width: 1
    opacity: count > 0 || active ? 1 : 0.55
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Octicon { name: chip.icon; color: chip.tone; size: 14 }
        Controls.Label { text: chip.count; color: chip.ink; font.bold: true; font.pixelSize: 12 }
        Controls.Label { text: chip.label; color: chip.ink; opacity: 0.8; font.pixelSize: 11 }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
