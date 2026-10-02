import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

// Compact dropdown filter: shows the current choice, highlights when narrowed from its default.
Rectangle {
    id: pill
    property var options: []          // [{text, value, count?}]
    property string value: ""
    property string defaultValue: ""
    property string icon: "filter"
    property color ink: "black"
    property color muted: "gray"
    property color accent: "steelblue"
    property color surface: "white"
    property color edge: "lightgray"
    signal picked(string value)
    readonly property bool narrowed: value !== defaultValue
    readonly property var current: options.find(o => o.value === value) || options[0] || ({text: ""})
    implicitHeight: 26
    implicitWidth: Math.min(row.implicitWidth + 18, 170)
    radius: 6
    color: mouse.containsMouse || menu.visible ? Qt.alpha(ink, 0.08) : surface
    border.color: narrowed ? accent : edge
    border.width: 1
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 5
        Octicon { name: pill.icon; color: pill.narrowed ? pill.accent : pill.muted; size: 12 }
        Controls.Label {
            Layout.fillWidth: true
            text: pill.current.text
            color: pill.narrowed ? pill.accent : pill.ink
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Controls.Label { text: "▾"; color: pill.muted; font.pixelSize: 10 }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.popup(pill, 0, pill.height + 2) }
    Controls.Menu {
        id: menu
        Instantiator {
            model: pill.options
            delegate: Controls.MenuItem {
                required property var modelData
                text: modelData.count !== undefined ? modelData.text + "  (" + modelData.count + ")" : modelData.text
                checkable: true
                checked: modelData.value === pill.value
                onTriggered: pill.picked(modelData.value)
            }
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)
        }
    }
}
