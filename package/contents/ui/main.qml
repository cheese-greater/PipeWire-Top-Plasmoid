import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

import "../code/pwtop.js" as PwTop

PlasmoidItem {
    id: root

    readonly property string topCommand: "LC_ALL=C pw-top -b -n 2"
    readonly property string dumpCommand: "pw-dump"
    readonly property int pollIntervalMilliseconds: 1000

    // Nodes in the running state, drivers followed by their streams.
    property var runningNodes: []
    // Node id to { name, description }, filled from pw-dump on demand.
    property var descriptionsById: ({})
    property string errorMessage: ""

    readonly property var runningDevices: runningNodes.filter(node => !node.isStream)
    readonly property string compactText: runningDevices.map(node => PwTop.formatShort(node)).filter(text => text.length > 0).join("  |  ")

    function displayName(node) {
        const entry = descriptionsById[node.id];
        return entry && entry.name === node.name && entry.description.length > 0 ? entry.description : node.name;
    }

    function handleTopOutput(data) {
        if (data["exit code"] !== 0) {
            errorMessage = (data["stderr"] || "").trim() || "pw-top exited with code " + data["exit code"];
            runningNodes = [];
            return;
        }
        errorMessage = "";
        const parsedNodes = PwTop.parseRunningNodes(data["stdout"] || "");
        // Only reassign on a real change so the popup list is not rebuilt every poll.
        if (JSON.stringify(parsedNodes) !== JSON.stringify(runningNodes)) {
            runningNodes = parsedNodes;
        }
        const hasUnknownDevice = parsedNodes.some(node => {
            const entry = descriptionsById[node.id];
            return !node.isStream && (!entry || entry.name !== node.name);
        });
        if (hasUnknownDevice) {
            executable.connectSource(dumpCommand);
        }
    }

    function handleDumpOutput(data) {
        if (data["exit code"] !== 0) {
            return;
        }
        try {
            const parsedDescriptions = PwTop.parseNodeDescriptions(data["stdout"] || "");
            // Record devices pw-dump did not report so they are not looked up again every poll.
            runningDevices.forEach(node => {
                if (!parsedDescriptions[node.id]) {
                    parsedDescriptions[node.id] = { description: "", name: node.name };
                }
            });
            descriptionsById = parsedDescriptions;
        } catch (parseError) {
            console.warn("pwtop: could not parse pw-dump output:", parseError);
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName === root.topCommand) {
                root.handleTopOutput(data);
            } else if (sourceName === root.dumpCommand) {
                root.handleDumpOutput(data);
            }
        }
    }

    Timer {
        interval: root.pollIntervalMilliseconds
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.topCommand)
    }

    // The table is drawn directly in the panel (or on the desktop); there is no popup.
    preferredRepresentation: fullRepresentation

    // One table row: quantum, rate, format, name. Also used for the column header.
    component NodeRow: Row {
        id: nodeRow

        property bool isHeader: false
        property int fontPixelSize
        property real quantumWidth
        property real rateWidth
        property real formatWidth
        property real nameWidth
        property string quantumText
        property string rateText
        property string formatText
        property string nameText

        spacing: fontPixelSize

        PlasmaComponents.Label {
            font.bold: nodeRow.isHeader
            font.pixelSize: nodeRow.fontPixelSize
            horizontalAlignment: Text.AlignRight
            text: nodeRow.quantumText
            textFormat: Text.PlainText
            width: nodeRow.quantumWidth
        }

        PlasmaComponents.Label {
            font.bold: nodeRow.isHeader
            font.pixelSize: nodeRow.fontPixelSize
            horizontalAlignment: Text.AlignRight
            text: nodeRow.rateText
            textFormat: Text.PlainText
            width: nodeRow.rateWidth
        }

        PlasmaComponents.Label {
            font.bold: nodeRow.isHeader
            font.pixelSize: nodeRow.fontPixelSize
            text: nodeRow.formatText
            textFormat: Text.PlainText
            width: nodeRow.formatWidth
        }

        PlasmaComponents.Label {
            elide: Text.ElideRight
            font.bold: nodeRow.isHeader
            font.pixelSize: nodeRow.fontPixelSize
            text: nodeRow.nameText
            textFormat: Text.PlainText
            width: nodeRow.nameWidth
        }
    }

    fullRepresentation: Item {
        id: display

        readonly property bool isVerticalPanel: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool isHorizontalPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool hasNodes: root.runningNodes.length > 0
        readonly property int defaultFontPixelSize: Math.round(Kirigami.Units.gridUnit / 1.4)
        readonly property int minimumFontPixelSize: 7
        // In a horizontal panel the rows shrink so that all of them fit the panel height.
        readonly property int fontPixelSize: isHorizontalPanel
            ? Math.max(minimumFontPixelSize, Math.min(defaultFontPixelSize, Math.floor(height / Math.max(1, root.runningNodes.length) / 1.4)))
            : defaultFontPixelSize
        readonly property real maximumNameWidth: Kirigami.Units.gridUnit * 18

        function nodeName(node) {
            return (node.isStream ? "+ " : "") + root.displayName(node);
        }

        function widestText(texts) {
            return texts.reduce((widest, text) => Math.max(widest, Math.ceil(fontMetrics.advanceWidth(text))), 0);
        }

        readonly property real quantumWidth: widestText(["QUANT"].concat(root.runningNodes.map(node => String(node.quantum))))
        readonly property real rateWidth: widestText(["RATE"].concat(root.runningNodes.map(node => String(node.rate))))
        readonly property real formatWidth: widestText(["FORMAT"].concat(root.runningNodes.map(node => node.formatText)))
        readonly property real nameWidth: Math.min(maximumNameWidth, widestText(["NAME"].concat(root.runningNodes.map(node => nodeName(node)))))

        readonly property real contentWidth: isVerticalPanel ? stackedColumn.implicitWidth : (hasNodes ? tableColumn.implicitWidth : idleIcon.width)
        readonly property real contentHeight: isVerticalPanel ? (hasNodes ? stackedColumn.implicitHeight : idleIcon.height) : tableColumn.implicitHeight

        Layout.minimumWidth: isVerticalPanel ? -1 : contentWidth
        Layout.preferredWidth: isVerticalPanel ? -1 : contentWidth
        Layout.maximumWidth: isHorizontalPanel ? contentWidth : -1
        Layout.minimumHeight: isHorizontalPanel ? -1 : contentHeight
        Layout.preferredHeight: isHorizontalPanel ? -1 : contentHeight
        Layout.maximumHeight: isVerticalPanel ? contentHeight : -1

        FontMetrics {
            id: fontMetrics
            font.bold: true
            font.family: Kirigami.Theme.defaultFont.family
            font.pixelSize: display.fontPixelSize
        }

        // Only an error gets a tooltip; the table already shows everything else.
        PlasmaCore.ToolTipArea {
            active: root.errorMessage.length > 0
            anchors.fill: parent
            mainText: Plasmoid.title
            subText: root.errorMessage
            textFormat: Text.PlainText
        }

        Kirigami.Icon {
            id: idleIcon
            anchors.centerIn: parent
            height: Math.min(display.isVerticalPanel ? display.width : display.height, Kirigami.Units.iconSizes.smallMedium)
            opacity: 0.5
            source: root.errorMessage.length > 0 ? "dialog-warning" : "audio-card"
            visible: !display.hasNodes
            width: height
        }

        // Horizontal panel and desktop: one line per node, with a header row on the desktop.
        Column {
            id: tableColumn
            anchors.centerIn: parent
            visible: display.hasNodes && !display.isVerticalPanel

            NodeRow {
                fontPixelSize: display.fontPixelSize
                formatText: "FORMAT"
                formatWidth: display.formatWidth
                isHeader: true
                nameText: "NAME"
                nameWidth: display.nameWidth
                quantumText: "QUANT"
                quantumWidth: display.quantumWidth
                rateText: "RATE"
                rateWidth: display.rateWidth
                visible: !display.isHorizontalPanel
            }

            Repeater {
                model: root.runningNodes

                NodeRow {
                    required property var modelData

                    fontPixelSize: display.fontPixelSize
                    formatText: modelData.formatText
                    formatWidth: display.formatWidth
                    nameText: display.nodeName(modelData)
                    nameWidth: display.nameWidth
                    quantumText: modelData.quantum
                    quantumWidth: display.quantumWidth
                    rateText: modelData.rate
                    rateWidth: display.rateWidth
                }
            }
        }

        // Vertical panel: too narrow for a table, so each node is a small stacked block.
        Column {
            id: stackedColumn
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            visible: display.hasNodes && display.isVerticalPanel
            width: display.width

            Repeater {
                model: root.runningNodes

                PlasmaComponents.Label {
                    required property var modelData

                    font.pixelSize: display.minimumFontPixelSize + 2
                    horizontalAlignment: Text.AlignHCenter
                    text: display.nodeName(modelData) + "\n" + modelData.formatText + "\n" + modelData.quantum + " / " + modelData.rate
                    textFormat: Text.PlainText
                    width: stackedColumn.width
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
