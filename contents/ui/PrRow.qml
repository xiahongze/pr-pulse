import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

// One pull request: state octicon, title, repo/number/author/age, review tag and CI badge.
Rectangle {
    id: row
    required property var pr
    required property var colors
    required property string age
    signal filterRepo(string repo)
    signal filterAuthor(string author)
    readonly property var stateStyle: ({
        open: {icon: "git-pull-request", tone: colors.open, text: i18n("Open")},
        draft: {icon: "git-pull-request-draft", tone: colors.neutral, text: i18n("Draft")},
        merged: {icon: "git-merge", tone: colors.merged, text: i18n("Merged")},
        closed: {icon: "git-pull-request-closed", tone: colors.closed, text: i18n("Closed")}
    })[pr.state] || {icon: "git-pull-request", tone: colors.neutral, text: pr.state}
    readonly property var ciStyle: ({
        success: {icon: "check", tone: colors.open, text: i18n("Checks passing")},
        failure: {icon: "x", tone: colors.closed, text: i18n("Checks failing")},
        pending: {icon: "dot-fill", tone: colors.pending, text: i18n("Checks running")}
    })[pr.ci] || null
    readonly property var reviewStyle: ({
        approved: {icon: "check", tone: colors.open, text: i18n("Approved")},
        changes_requested: {icon: "file-diff", tone: colors.closed, text: i18n("Changes requested")},
        review_required: {icon: "eye", tone: colors.pending, text: i18n("Review required")}
    })[pr.review] || null
    readonly property string roleText: [
        pr.roles.indexOf("authored") >= 0 ? i18n("author") : "",
        pr.roles.indexOf("assigned") >= 0 ? i18n("assignee") : "",
        pr.roles.indexOf("review") >= 0 ? i18n("reviewer") : ""
    ].filter(Boolean).join(" · ")

    implicitHeight: content.implicitHeight + 16
    radius: 8
    color: mouse.containsMouse ? Qt.alpha(colors.ink, 0.07) : "transparent"

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouseEvent => mouseEvent.button === Qt.RightButton ? context.popup() : Qt.openUrlExternally(row.pr.url)
    }

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10

        Octicon {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            name: row.stateStyle.icon
            color: row.stateStyle.tone
            size: 16
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Controls.Label {
                Layout.fillWidth: true
                text: row.pr.title
                color: row.colors.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Controls.Label { text: row.pr.repo + " #" + row.pr.number; color: row.colors.muted; font.pixelSize: 11 }
                Controls.Label { text: "· " + row.pr.author; color: row.colors.muted; font.pixelSize: 11 }
                Controls.Label { text: "· " + row.age; color: row.colors.muted; font.pixelSize: 11 }
                Repeater {
                    model: row.pr.labels.slice(0, 3)
                    delegate: Rectangle {
                        required property var modelData
                        height: 16
                        width: labelText.implicitWidth + 10
                        radius: 8
                        color: Qt.alpha(modelData.color, 0.18)
                        border.color: Qt.alpha(modelData.color, 0.6)
                        Controls.Label { id: labelText; anchors.centerIn: parent; text: modelData.name; color: row.colors.ink; font.pixelSize: 9 }
                    }
                }
            }
            RowLayout {
                spacing: 8
                visible: row.roleText !== "" || row.reviewStyle !== null
                Rectangle {
                    visible: row.reviewStyle !== null
                    implicitHeight: 16
                    implicitWidth: reviewRow.implicitWidth + 10
                    radius: 8
                    color: row.reviewStyle ? Qt.alpha(row.reviewStyle.tone, 0.14) : "transparent"
                    RowLayout {
                        id: reviewRow
                        anchors.centerIn: parent
                        spacing: 3
                        Octicon { name: row.reviewStyle ? row.reviewStyle.icon : ""; color: row.reviewStyle ? row.reviewStyle.tone : "transparent"; size: 10 }
                        Controls.Label { text: row.reviewStyle ? row.reviewStyle.text : ""; color: row.reviewStyle ? row.reviewStyle.tone : "transparent"; font.pixelSize: 9; font.bold: true }
                    }
                }
                Controls.Label {
                    visible: row.roleText !== ""
                    text: row.roleText.toUpperCase()
                    color: row.colors.muted
                    opacity: 0.85
                    font.pixelSize: 9
                    font.letterSpacing: 0.8
                }
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 6
            Badge { style: row.ciStyle }
        }
    }

    component Badge: Item {
        property var style: null
        visible: style !== null
        implicitWidth: 16
        implicitHeight: 16
        Octicon { anchors.centerIn: parent; name: parent.style ? parent.style.icon : ""; color: parent.style ? parent.style.tone : "transparent"; size: 16 }
        HoverHandler { id: hover }
        Controls.ToolTip.visible: hover.hovered && style !== null
        Controls.ToolTip.text: style ? style.text : ""
        Controls.ToolTip.delay: 300
    }

    Controls.Menu {
        id: context
        Controls.MenuItem { text: i18n("Open in Browser"); icon.name: "internet-services"; onTriggered: Qt.openUrlExternally(row.pr.url) }
        Controls.MenuItem { text: i18n("Open Files Changed"); icon.name: "vcs-diff"; onTriggered: Qt.openUrlExternally(row.pr.url + "/files") }
        Controls.MenuItem { text: i18n("Open Checks"); icon.name: "run-build"; onTriggered: Qt.openUrlExternally(row.pr.url + "/checks") }
        Controls.MenuSeparator {}
        Controls.MenuItem { text: i18n("Only %1", row.pr.repo); icon.name: "view-filter"; onTriggered: row.filterRepo(row.pr.repo) }
        Controls.MenuItem { text: i18n("Only by %1", row.pr.author); icon.name: "user"; onTriggered: row.filterAuthor(row.pr.author) }
    }
}
