import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    property var snapshot: ({prs: [], counts: {}, viewer: "", generated_label: "", error: null})
    property var error: null
    property bool busy: false
    property bool refreshQueued: false
    property string pendingCommand: ""
    property int refreshId: 0
    property double now: Date.now()
    property string search: ""

    property bool isDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    property bool forcedDark: Plasmoid.configuration.themeMode === "dark"
    property bool forcedLight: Plasmoid.configuration.themeMode === "light"
    property bool forced: forcedDark || forcedLight
    // System mode follows the Plasma colour scheme; status colours pick GitHub's light or dark variant from its luminance.
    property bool dark: forcedDark || (!forcedLight && luminance(Kirigami.Theme.backgroundColor) < 0.5)
    // GitHub Primer functional colour tokens (light / dark).
    property var colors: ({
        surface: forcedDark ? "#0d1117" : forcedLight ? "#ffffff" : Kirigami.Theme.backgroundColor,
        card: forcedDark ? "#151b23" : forcedLight ? "#f6f8fa" : Qt.alpha(Kirigami.Theme.textColor, 0.04),
        ink: forcedDark ? "#f0f6fc" : forcedLight ? "#1f2328" : Kirigami.Theme.textColor,
        muted: forcedDark ? "#9198a1" : forcedLight ? "#59636e" : Qt.alpha(Kirigami.Theme.textColor, 0.65),
        border: forced ? (dark ? "#3d444d" : "#d1d9e0") : Qt.alpha(Kirigami.Theme.textColor, 0.18),
        accent: dark ? "#4493f8" : "#0969da",
        open: dark ? "#3fb950" : "#1a7f37",
        neutral: dark ? "#9198a1" : "#59636e",
        merged: dark ? "#ab7df8" : "#8250df",
        closed: dark ? "#f85149" : "#d1242f",
        pending: dark ? "#d29922" : "#9a6700"
    })

    readonly property var prs: snapshot.prs || []
    readonly property var counts: snapshot.counts || ({})
    readonly property int activeCount: (counts.open || 0) + (counts.draft || 0)
    readonly property var attention: prs.filter(needsAttention)
    readonly property int badgeCount: Plasmoid.configuration.badgeMode === "attention" ? attention.length : Plasmoid.configuration.badgeMode === "open" ? activeCount : 0
    readonly property var filtered: prs.filter(matches)
    readonly property var repoOptions: optionList(i18n("All repos"), prs.map(pr => pr.repo))
    readonly property var authorOptions: optionList(i18n("All authors"), prs.map(pr => pr.author))
    readonly property bool narrowed: search !== "" || ["filterRole", "filterStatus", "filterCi", "filterRepo", "filterAuthor"].some(key => Plasmoid.configuration[key] !== defaults[key])
    readonly property var defaults: ({filterRole: "all", filterStatus: "active", filterCi: "any", filterRepo: "", filterAuthor: ""})

    Plasmoid.icon: "vcs-merge-request"
    Plasmoid.title: i18n("PR Pulse")
    Plasmoid.status: attention.length > 0 ? PlasmaCore.Types.NeedsAttentionStatus : activeCount > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: i18n("PR Pulse")
    toolTipSubText: error && !prs.length ? errorTitle(error) : i18n("%1 open · %2 need attention · %3 failing CI", activeCount, attention.length, counts.ci_failing || 0)
    // The desktop supplies its own translucent surface below; panel popups keep native Plasma chrome.
    Plasmoid.backgroundHints: isDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    switchWidth: isDesktop ? -1 : 380
    switchHeight: isDesktop ? -1 : 420
    preferredRepresentation: isDesktop ? fullRepresentation : null
    hideOnWindowDeactivate: !Plasmoid.configuration.pin

    Plasmoid.contextualActions: [
        PlasmaCore.Action { text: i18n("Refresh Now"); icon.name: "view-refresh"; onTriggered: root.refresh() },
        PlasmaCore.Action { text: i18n("Open GitHub Pull Requests"); icon.name: "internet-services"; onTriggered: Qt.openUrlExternally("https://github.com/pulls") }
    ]

    compactRepresentation: Item {
        id: compact
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: implicitWidth
        Octicon {
            anchors.centerIn: parent
            size: Math.min(parent.width, parent.height) * 0.78
            name: "git-pull-request"
            color: root.error && !root.prs.length ? Kirigami.Theme.disabledTextColor
                : (root.counts.ci_failing || 0) > 0 ? (root.dark ? "#f85149" : "#d1242f")
                : compactMouse.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        }
        Rectangle {
            // Opacity rather than visible: in the compact wrapper a visible binding here did not re-evaluate on Plasma 6.7.
            opacity: root.badgeCount > 0 ? 1 : 0
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(14, parent.height * 0.45)
            width: Math.max(height, badgeText.implicitWidth + 6)
            radius: height / 2
            color: root.attention.length > 0 ? (root.dark ? "#da3633" : "#cf222e") : (root.dark ? "#238636" : "#1f883d")
            Controls.Label { id: badgeText; anchors.centerIn: parent; text: root.badgeCount > 99 ? "99+" : root.badgeCount; color: "white"; font.pixelSize: parent.height * 0.68; font.bold: true }
        }
        MouseArea { id: compactMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.expanded = !root.expanded }
    }

    fullRepresentation: Rectangle {
        id: panel
        Layout.minimumWidth: 420
        Layout.minimumHeight: 420
        Layout.preferredWidth: 500
        Layout.preferredHeight: 640
        radius: root.isDesktop ? 14 : 0
        color: root.isDesktop
            ? Qt.alpha(root.colors.surface, Math.max(10, Plasmoid.configuration.desktopOpacity) / 100)
            : (root.forced ? root.colors.surface : "transparent")
        // Hand the chosen palette to stock controls (menus, text field) so forced modes stay coherent.
        Kirigami.Theme.inherit: !root.forced
        Kirigami.Theme.textColor: root.colors.ink
        Kirigami.Theme.backgroundColor: root.colors.surface
        Kirigami.Theme.alternateBackgroundColor: root.colors.card
        Kirigami.Theme.disabledTextColor: root.colors.muted
        Kirigami.Theme.highlightColor: root.colors.accent
        Kirigami.Theme.highlightedTextColor: "#ffffff"
        Kirigami.Theme.hoverColor: root.colors.accent
        Kirigami.Theme.focusColor: root.colors.accent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing * 2

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: 9
                    color: Qt.alpha(root.colors.open, 0.14)
                    Octicon { anchors.centerIn: parent; name: "git-pull-request"; color: root.colors.open; size: 20 }
                }
                ColumnLayout {
                    spacing: 1
                    Controls.Label { text: i18n("PR PULSE"); color: root.colors.ink; font.pixelSize: 17; font.bold: true; font.letterSpacing: 2 }
                    Controls.Label {
                        text: root.busy && !root.prs.length ? i18n("FETCHING FROM GITHUB…")
                            : root.error ? errorTitle(root.error).toUpperCase()
                            : root.snapshot.viewer ? i18n("@%1 · %2 OPEN · %3 NEED ATTENTION", root.snapshot.viewer, root.activeCount, root.attention.length)
                            : i18n("WAITING FOR DATA")
                        color: root.error ? root.colors.closed : root.colors.muted
                        font.pixelSize: 10
                        font.family: "monospace"
                    }
                }
                Item { Layout.fillWidth: true }
                IconButton { icon: "person"; tooltip: i18n("Open github.com/pulls"); ink: root.colors.muted; accent: root.colors.accent; onClicked: Qt.openUrlExternally("https://github.com/pulls") }
                IconButton { icon: "sync"; tooltip: i18n("Refresh Now"); spinning: root.busy; ink: root.colors.muted; accent: root.colors.accent; onClicked: root.refresh() }
                // Octicons has no pin glyph; Plasma's own pin icon keeps the "keep open" meaning familiar.
                Rectangle {
                    visible: !root.isDesktop
                    implicitWidth: 28; implicitHeight: 28; radius: 6
                    color: Plasmoid.configuration.pin ? Qt.alpha(root.colors.accent, 0.18) : pinMouse.containsMouse ? Qt.alpha(root.colors.ink, 0.1) : "transparent"
                    Kirigami.Icon { anchors.centerIn: parent; width: 16; height: 16; source: "window-pin"; color: Plasmoid.configuration.pin ? root.colors.accent : root.colors.muted; isMask: true }
                    MouseArea { id: pinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Plasmoid.configuration.pin = !Plasmoid.configuration.pin }
                    Controls.ToolTip.visible: pinMouse.containsMouse
                    Controls.ToolTip.text: i18n("Keep Open")
                    Controls.ToolTip.delay: 500
                }
            }

            // Status summary; each chip toggles the status filter.
            Flow {
                Layout.fillWidth: true
                // Wrap to the available width instead of widening the popup to fit every chip.
                Layout.preferredWidth: 0
                spacing: 6
                StatChip { icon: "git-pull-request"; tone: root.colors.open; ink: root.colors.ink; label: i18n("Open"); count: root.counts.open || 0; active: Plasmoid.configuration.filterStatus === "open"; onClicked: root.toggle("filterStatus", "open") }
                StatChip { icon: "git-pull-request-draft"; tone: root.colors.neutral; ink: root.colors.ink; label: i18n("Draft"); count: root.counts.draft || 0; active: Plasmoid.configuration.filterStatus === "draft"; onClicked: root.toggle("filterStatus", "draft") }
                StatChip { icon: "git-merge"; tone: root.colors.merged; ink: root.colors.ink; label: i18n("Merged"); count: root.counts.merged || 0; active: Plasmoid.configuration.filterStatus === "merged"; onClicked: root.toggle("filterStatus", "merged") }
                StatChip { icon: "git-pull-request-closed"; tone: root.colors.closed; ink: root.colors.ink; label: i18n("Closed"); count: root.counts.closed || 0; active: Plasmoid.configuration.filterStatus === "closed"; onClicked: root.toggle("filterStatus", "closed") }
                StatChip { icon: "x"; tone: root.colors.closed; ink: root.colors.ink; label: i18n("Failing"); count: root.counts.ci_failing || 0; active: Plasmoid.configuration.filterCi === "failure"; onClicked: root.toggle("filterCi", "failure") }
                StatChip { icon: "eye"; tone: root.colors.pending; ink: root.colors.ink; label: i18n("To review"); count: root.counts.review_requested || 0; active: Plasmoid.configuration.filterRole === "review"; onClicked: root.toggle("filterRole", "review") }
            }

            // Search + filters
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Controls.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 28
                    placeholderText: i18n("Search title, repo, #number, label…")
                    placeholderTextColor: root.colors.muted
                    color: root.colors.ink
                    font.pixelSize: 12
                    leftPadding: 8
                    text: root.search
                    onTextChanged: root.search = text
                    background: Rectangle { radius: 6; color: root.colors.card; border.color: searchField.activeFocus ? root.colors.accent : root.colors.border }
                }
                IconButton {
                    visible: root.narrowed
                    icon: "x"
                    tooltip: i18n("Clear filters")
                    ink: root.colors.muted
                    accent: root.colors.accent
                    onClicked: root.clearFilters()
                }
            }
            Flow {
                Layout.fillWidth: true
                // Wrap to the available width instead of widening the popup to fit every chip.
                Layout.preferredWidth: 0
                spacing: 6
                FilterPill {
                    icon: "person"; ink: root.colors.ink; muted: root.colors.muted; accent: root.colors.accent; surface: root.colors.card; edge: root.colors.border
                    value: Plasmoid.configuration.filterRole; defaultValue: "all"
                    options: [{text: i18n("All roles"), value: "all"}, {text: i18n("Authored by me"), value: "authored"}, {text: i18n("Assigned to me"), value: "assigned"}, {text: i18n("Review requested"), value: "review"}]
                    onPicked: v => Plasmoid.configuration.filterRole = v
                }
                FilterPill {
                    icon: "git-pull-request"; ink: root.colors.ink; muted: root.colors.muted; accent: root.colors.accent; surface: root.colors.card; edge: root.colors.border
                    value: Plasmoid.configuration.filterStatus; defaultValue: "active"
                    options: [{text: i18n("Open + draft"), value: "active"}, {text: i18n("Open"), value: "open"}, {text: i18n("Draft"), value: "draft"}, {text: i18n("Merged"), value: "merged"}, {text: i18n("Closed"), value: "closed"}, {text: i18n("Any status"), value: "all"}]
                    onPicked: v => Plasmoid.configuration.filterStatus = v
                }
                FilterPill {
                    icon: "check"; ink: root.colors.ink; muted: root.colors.muted; accent: root.colors.accent; surface: root.colors.card; edge: root.colors.border
                    value: Plasmoid.configuration.filterCi; defaultValue: "any"
                    options: [{text: i18n("Any checks"), value: "any"}, {text: i18n("Failing"), value: "failure"}, {text: i18n("Running"), value: "pending"}, {text: i18n("Passing"), value: "success"}, {text: i18n("No checks"), value: "none"}]
                    onPicked: v => Plasmoid.configuration.filterCi = v
                }
                FilterPill {
                    icon: "git-merge"; ink: root.colors.ink; muted: root.colors.muted; accent: root.colors.accent; surface: root.colors.card; edge: root.colors.border
                    value: Plasmoid.configuration.filterRepo; defaultValue: ""
                    options: root.withCurrent(root.repoOptions, Plasmoid.configuration.filterRepo)
                    onPicked: v => Plasmoid.configuration.filterRepo = v
                }
                FilterPill {
                    icon: "person"; ink: root.colors.ink; muted: root.colors.muted; accent: root.colors.accent; surface: root.colors.card; edge: root.colors.border
                    value: Plasmoid.configuration.filterAuthor; defaultValue: ""
                    options: root.withCurrent(root.authorOptions, Plasmoid.configuration.filterAuthor)
                    onPicked: v => Plasmoid.configuration.filterAuthor = v
                }
            }

            // Error banner; keeps any previous results visible underneath.
            Rectangle {
                visible: root.error !== null
                Layout.fillWidth: true
                implicitHeight: bannerRow.implicitHeight + 16
                radius: 8
                color: Qt.alpha(root.colors.closed, 0.1)
                border.color: Qt.alpha(root.colors.closed, 0.45)
                RowLayout {
                    id: bannerRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    Octicon { Layout.alignment: Qt.AlignTop; name: "x"; color: root.colors.closed }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Controls.Label { text: root.error ? root.errorTitle(root.error) : ""; color: root.colors.ink; font.bold: true; font.pixelSize: 12 }
                        Controls.Label { Layout.fillWidth: true; text: root.error ? root.errorHint(root.error) : ""; color: root.colors.muted; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    TextButton {
                        visible: root.error && ["gh_not_found", "gh_unauthenticated", "python_missing"].indexOf(root.error.code) >= 0
                        text: i18n("Configure…")
                        onClicked: Plasmoid.internalAction("configure").trigger()
                    }
                }
            }

            // PR list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: root.colors.card
                border.color: root.colors.border
                clip: true
                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2
                    clip: true
                    model: root.filtered
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: list.contentHeight > list.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff }
                    delegate: PrRow {
                        required property var modelData
                        width: ListView.view.width - 6
                        pr: modelData
                        colors: root.colors
                        age: root.relative(modelData.updated_at, root.now)
                        onFilterRepo: repo => Plasmoid.configuration.filterRepo = repo
                        onFilterAuthor: author => Plasmoid.configuration.filterAuthor = author
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    width: parent.width - 40
                    spacing: 8
                    Octicon {
                        Layout.alignment: Qt.AlignHCenter
                        name: root.prs.length ? "filter" : "git-pull-request"
                        color: root.colors.muted
                        size: 32
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: root.colors.muted
                        text: root.busy && !root.prs.length ? i18n("Loading pull requests…")
                            : root.prs.length ? i18n("No pull requests match these filters.")
                            : root.error ? i18n("No data yet.")
                            : i18n("Nothing assigned to you or opened by you. Enjoy the quiet.")
                    }
                    TextButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.narrowed && root.prs.length > 0
                        text: i18n("Clear Filters")
                        onClicked: root.clearFilters()
                    }
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    text: i18n("SHOWING %1 OF %2", root.filtered.length, root.prs.length) + (root.snapshot.truncated ? i18n(" · LIMITED") : "")
                    color: root.colors.muted; font.pixelSize: 9; font.family: "monospace"
                }
                Item { Layout.fillWidth: true }
                Controls.Label {
                    text: (root.snapshot.generated_label ? i18n("UPDATED %1", root.snapshot.generated_label) : i18n("NOT YET UPDATED")) + " · " + root.cadence()
                    color: root.colors.muted; font.pixelSize: 9; font.family: "monospace"
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: collector
        engine: "executable"
        interval: 0
        onNewData: function(source, data) {
            if (source !== root.pendingCommand || data["exit code"] === undefined)
                return
            collector.disconnectSource(source)
            root.pendingCommand = ""
            root.busy = false
            refreshTimeout.stop()
            if (data["exit code"] === 127)
                root.error = {code: "python_missing", detail: ""}
            else if (data["exit code"] !== 0 || data["exit status"] !== 0)
                root.error = {code: "collector_failed", detail: (data.stderr || "").trim().split("\n").pop()}
            else {
                try {
                    let result = JSON.parse(data.stdout)
                    if (!Array.isArray(result.prs))
                        throw new Error("Invalid snapshot")
                    root.error = result.error || null
                    // Keep the last good list when GitHub is temporarily unreachable.
                    if (!result.error)
                        root.snapshot = result
                } catch (e) {
                    root.error = {code: "collector_failed", detail: i18n("Invalid collector response")}
                }
            }
            if (root.refreshQueued) {
                root.refreshQueued = false
                Qt.callLater(root.refresh)
            }
        }
    }
    Connections {
        target: Plasmoid.configuration
        function onGhPathChanged() { root.refresh() }
        function onLookbackDaysChanged() { root.refresh() }
        function onReviewRequestsChanged() { root.refresh() }
    }
    Component.onCompleted: Qt.callLater(refresh)
    Timer { interval: Math.max(60, Plasmoid.configuration.refreshSeconds) * 1000; running: true; repeat: true; onTriggered: root.refresh() }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.now = Date.now() }
    Timer {
        id: refreshTimeout
        interval: 45000
        onTriggered: {
            if (root.pendingCommand)
                collector.disconnectSource(root.pendingCommand)
            root.pendingCommand = ""
            root.busy = false
            root.error = {code: "timeout", detail: ""}
        }
    }

    component TextButton: Rectangle {
        id: textButton
        property alias text: label.text
        signal clicked()
        implicitWidth: label.implicitWidth + 20
        implicitHeight: 26
        radius: 6
        color: buttonMouse.containsMouse ? Qt.alpha(root.colors.ink, 0.12) : root.colors.card
        border.color: root.colors.border
        Controls.Label { id: label; anchors.centerIn: parent; color: root.colors.ink; font.pixelSize: 12 }
        MouseArea { id: buttonMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: textButton.clicked() }
    }

    function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function shellQuote(value) { return "'" + String(value).replace(/'/g, "'\\''") + "'" }
    function cadence() {
        let s = Plasmoid.configuration.refreshSeconds
        return s % 60 === 0 ? i18n("%1m AUTO", s / 60) : i18n("%1s AUTO", s)
    }
    function relative(iso, nowMs) {
        let seconds = Math.max(0, (nowMs - Date.parse(iso)) / 1000)
        if (isNaN(seconds)) return ""
        if (seconds < 60) return i18n("just now")
        if (seconds < 3600) return i18n("%1m ago", Math.floor(seconds / 60))
        if (seconds < 86400) return i18n("%1h ago", Math.floor(seconds / 3600))
        if (seconds < 86400 * 30) return i18n("%1d ago", Math.floor(seconds / 86400))
        return Qt.formatDate(new Date(iso), "d MMM yyyy")
    }
    function needsAttention(pr) {
        if (pr.state !== "open" && pr.state !== "draft")
            return false
        return pr.ci === "failure" || pr.roles.indexOf("review") >= 0
            || (pr.review === "changes_requested" && pr.roles.indexOf("authored") >= 0)
    }
    function matches(pr) {
        let c = Plasmoid.configuration
        if (c.filterRole !== "all" && pr.roles.indexOf(c.filterRole) < 0) return false
        if (c.filterStatus === "active" ? (pr.state !== "open" && pr.state !== "draft") : (c.filterStatus !== "all" && pr.state !== c.filterStatus)) return false
        if (c.filterCi !== "any" && pr.ci !== c.filterCi) return false
        if (c.filterRepo && pr.repo !== c.filterRepo) return false
        if (c.filterAuthor && pr.author !== c.filterAuthor) return false
        let q = search.trim().toLowerCase()
        if (!q) return true
        let haystack = [pr.title, pr.repo, "#" + pr.number, pr.author].concat(pr.labels.map(l => l.name)).join(" ").toLowerCase()
        return q.split(/\s+/).every(term => haystack.indexOf(term) >= 0)
    }
    function optionList(allText, values) {
        let tally = {}
        values.forEach(v => tally[v] = (tally[v] || 0) + 1)
        let keys = Object.keys(tally).sort((a, b) => tally[b] - tally[a] || a.localeCompare(b))
        return [{text: allText, value: ""}].concat(keys.map(k => ({text: k, value: k, count: tally[k]})))
    }
    // Keep a saved repo/author choice selectable even after its PRs drop out of the current data.
    function withCurrent(options, value) {
        return !value || options.some(o => o.value === value) ? options : options.concat([{text: value, value: value, count: 0}])
    }
    function toggle(key, value) {
        Plasmoid.configuration[key] = Plasmoid.configuration[key] === value ? defaults[key] : value
    }
    function clearFilters() {
        for (let key in defaults)
            Plasmoid.configuration[key] = defaults[key]
        search = ""
    }
    function errorTitle(e) {
        return ({
            gh_not_found: i18n("GitHub CLI not found"),
            gh_unauthenticated: i18n("GitHub CLI is not logged in"),
            network: i18n("GitHub is unreachable"),
            rate_limited: i18n("GitHub rate limit reached"),
            timeout: i18n("GitHub took too long to respond"),
            python_missing: i18n("Python 3 not found"),
            collector_failed: i18n("Collector failed")
        })[e.code] || i18n("gh request failed")
    }
    function errorHint(e) {
        let hint = ({
            gh_not_found: i18n("Install gh, or set its full path in the widget settings. Plasma may not see your shell PATH."),
            gh_unauthenticated: i18n("Run “gh auth login” in a terminal, then refresh."),
            network: i18n("Showing the last successful results. Retrying on the next refresh."),
            rate_limited: i18n("Showing the last successful results. Try a longer refresh interval."),
            timeout: i18n("Showing the last successful results. Retrying on the next refresh."),
            python_missing: i18n("PR Pulse needs python3 to run its bundled collector.")
        })[e.code] || ""
        return [hint, e.detail].filter(Boolean).join(" ")
    }
    function refresh() {
        if (busy) {
            refreshQueued = true
            return
        }
        if (!collector.valid) {
            error = {code: "collector_failed", detail: i18n("Plasma executable engine unavailable")}
            return
        }
        let scriptUrl = Qt.resolvedUrl("../code/pr_pulse.py").toString()
        let scriptPath = decodeURIComponent(scriptUrl.replace(/^file:\/\//, ""))
        let c = Plasmoid.configuration
        let command = "/usr/bin/env python3 " + shellQuote(scriptPath)
            + " --lookback-days " + Math.max(0, c.lookbackDays)
            + (c.reviewRequests ? " --review-requests" : " --no-review-requests")
            + " --refresh-id " + (++refreshId)
        if (c.ghPath.trim())
            command += " --gh " + shellQuote(c.ghPath.trim())
        pendingCommand = command
        busy = true
        refreshTimeout.restart()
        collector.connectSource(command)
    }
}
