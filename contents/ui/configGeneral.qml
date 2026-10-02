import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page
    property string title: ""
    property alias cfg_refreshSeconds: refresh.value
    property alias cfg_ghPath: ghPath.text
    property alias cfg_reviewRequests: reviewRequests.checked
    property alias cfg_lookbackDays: lookback.value
    property alias cfg_themeMode: theme.currentValue
    property alias cfg_desktopOpacity: desktopOpacity.value
    property alias cfg_badgeMode: badge.currentValue
    property alias cfg_pin: pin.checked
    property int cfg_refreshSecondsDefault: 180
    property string cfg_ghPathDefault: ""
    property bool cfg_reviewRequestsDefault: true
    property int cfg_lookbackDaysDefault: 7
    property string cfg_themeModeDefault: "system"
    property int cfg_desktopOpacityDefault: 85
    property string cfg_badgeModeDefault: "open"
    property bool cfg_pinDefault: false
    // Filter values are edited from the widget itself; declared so the config dialog does not warn.
    property string cfg_filterRole
    property string cfg_filterStatus
    property string cfg_filterCi
    property string cfg_filterRepo
    property string cfg_filterAuthor
    property string cfg_filterRoleDefault: "all"
    property string cfg_filterStatusDefault: "active"
    property string cfg_filterCiDefault: "any"
    property string cfg_filterRepoDefault: ""
    property string cfg_filterAuthorDefault: ""

    RowLayout {
        Kirigami.FormData.label: i18n("gh executable:")
        Layout.fillWidth: true
        Controls.TextField {
            id: ghPath
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            placeholderText: i18n("Auto-detect (PATH, /usr/bin, ~/.local/bin, Homebrew…)")
        }
        Controls.Button { icon.name: "document-open"; onClicked: picker.open(); Controls.ToolTip.text: i18n("Browse…"); Controls.ToolTip.visible: hovered }
    }
    Controls.Label {
        text: i18n("Leave empty to auto-detect. Plasma may not inherit your shell PATH, so set this if gh lives somewhere unusual. Authenticate once with “gh auth login”.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        font: Kirigami.Theme.smallFont
        opacity: 0.75
    }
    Controls.SpinBox {
        id: refresh
        Kirigami.FormData.label: i18n("Refresh interval:")
        from: 60; to: 3600; stepSize: 30; editable: true
        textFromValue: v => v % 60 === 0 ? i18np("%1 minute", "%1 minutes", v / 60) : i18n("%1 seconds", v)
        valueFromText: t => { let n = parseInt(t); return /min/.test(t) ? n * 60 : n }
    }
    Controls.CheckBox { id: reviewRequests; Kirigami.FormData.label: i18n("Include:"); text: i18n("PRs awaiting my review") }
    Controls.SpinBox {
        id: lookback
        Kirigami.FormData.label: i18n("Merged/closed history:")
        from: 0; to: 90; editable: true
        textFromValue: v => v === 0 ? i18n("Off") : i18np("%1 day", "%1 days", v)
        valueFromText: t => parseInt(t) || 0
    }
    Controls.ComboBox {
        id: theme
        Kirigami.FormData.label: i18n("Theme:")
        textRole: "text"; valueRole: "value"
        model: [{text: i18n("System"), value: "system"}, {text: i18n("Light"), value: "light"}, {text: i18n("Dark"), value: "dark"}]
    }
    Controls.ComboBox {
        id: badge
        Kirigami.FormData.label: i18n("Panel badge:")
        textRole: "text"; valueRole: "value"
        model: [
            {text: i18n("Open PRs"), value: "open"},
            {text: i18n("Needs attention (failing CI, changes requested, review requests)"), value: "attention"},
            {text: i18n("None"), value: "none"}
        ]
    }
    RowLayout {
        Kirigami.FormData.label: i18n("Desktop opacity:")
        Controls.Slider { id: desktopOpacity; from: 10; to: 100; stepSize: 5; Layout.fillWidth: true }
        Controls.Label { text: Math.round(desktopOpacity.value) + "%"; Layout.minimumWidth: 42 }
    }
    Controls.CheckBox { id: pin; Kirigami.FormData.label: i18n("Taskbar popup:"); text: i18n("Keep open when focus changes") }
    Controls.Label {
        text: i18n("PR data is fetched with your existing gh login and stays on this machine.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    Dialogs.FileDialog {
        id: picker
        title: i18n("Select the gh executable")
        onAccepted: ghPath.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }
}
