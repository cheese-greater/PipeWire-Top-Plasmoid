.pragma library

// Parses the output of `pw-top -b -n 2` and formats the values for display.
// pw-top prints one table per iteration; the first one has no timing data yet,
// so only the last table is used.

var fixedColumnCount = 9; // S ID QUANT RATE WAIT BUSY W/Q B/Q ERR

function parseAudioFormat(formatText) {
    var match = /^([A-Za-z]+)(\d+)\S*\s+(\d+)\s+(\d+)$/.exec(formatText);
    if (!match) {
        return null;
    }
    var bitDepth = parseInt(match[2], 10);
    var channelCount = parseInt(match[3], 10);
    var sampleRate = parseInt(match[4], 10);
    return {
        bitDepth: bitDepth,
        bitsPerSecond: bitDepth * channelCount * sampleRate,
        channelCount: channelCount,
        isFloat: match[1].charAt(0) === "F",
        sampleFormat: formatText.split(/\s+/)[0],
        sampleRate: sampleRate
    };
}

function parseRow(line, nameColumnOffset) {
    var columns = line.slice(0, nameColumnOffset).trim().split(/\s+/);
    if (columns.length < fixedColumnCount) {
        return null;
    }
    var formatText = columns.slice(fixedColumnCount).join(" ");
    var nameText = line.slice(nameColumnOffset);
    var isStream = /^\s*\+\s/.test(nameText);
    return {
        audioFormat: parseAudioFormat(formatText),
        errorCount: parseInt(columns[8], 10) || 0,
        formatText: formatText,
        id: parseInt(columns[1], 10),
        isStream: isStream,
        name: nameText.replace(/^\s*\+\s/, "").trim(),
        quantum: parseInt(columns[2], 10) || 0,
        rate: parseInt(columns[3], 10) || 0,
        state: columns[0]
    };
}

// Returns the nodes in the running state, in pw-top order (each driver is
// followed by the streams attached to it).
function parseRunningNodes(output) {
    var lines = output.split("\n");
    var headerIndex = -1;
    for (var lineIndex = lines.length - 1; lineIndex >= 0; lineIndex--) {
        if (/^S\s+ID\s/.test(lines[lineIndex])) {
            headerIndex = lineIndex;
            break;
        }
    }
    if (headerIndex < 0) {
        return [];
    }
    var nameColumnOffset = lines[headerIndex].indexOf("NAME");
    var runningNodes = [];
    for (var rowIndex = headerIndex + 1; rowIndex < lines.length; rowIndex++) {
        var node = parseRow(lines[rowIndex], nameColumnOffset);
        if (node && node.state === "R") {
            runningNodes.push(node);
        }
    }
    return runningNodes;
}

// Maps node id to { name, description } from `pw-dump` output.
function parseNodeDescriptions(dumpOutput) {
    var descriptionsById = {};
    var objects = JSON.parse(dumpOutput);
    for (var objectIndex = 0; objectIndex < objects.length; objectIndex++) {
        var object = objects[objectIndex];
        if (object.type !== "PipeWire:Interface:Node" || !object.info || !object.info.props) {
            continue;
        }
        var properties = object.info.props;
        descriptionsById[object.id] = {
            description: properties["node.description"] || properties["node.nick"] || "",
            name: properties["node.name"] || ""
        };
    }
    return descriptionsById;
}

function formatSampleRate(sampleRate) {
    return parseFloat((sampleRate / 1000).toFixed(1)) + " kHz";
}

function formatBitDepth(audioFormat) {
    return audioFormat.bitDepth + "-bit" + (audioFormat.isFloat ? " float" : "");
}

function formatBitrate(bitsPerSecond) {
    if (bitsPerSecond >= 1000000) {
        return parseFloat((bitsPerSecond / 1000000).toFixed(2)) + " Mbps";
    }
    return Math.round(bitsPerSecond / 1000) + " kbps";
}

// Short form for the panel, for example "32-bit / 44.1 kHz".
function formatShort(node) {
    if (!node.audioFormat) {
        return node.formatText;
    }
    return formatBitDepth(node.audioFormat) + " / " + formatSampleRate(node.audioFormat.sampleRate);
}

// Long form for the popup, for example "S32LE, 2 ch, 44.1 kHz, 2.82 Mbps, quantum 512 (11.6 ms)".
function formatDetails(node) {
    var parts = [];
    if (node.audioFormat) {
        parts.push(node.audioFormat.sampleFormat);
        parts.push(node.audioFormat.channelCount + " ch");
        parts.push(formatSampleRate(node.audioFormat.sampleRate));
        parts.push(formatBitrate(node.audioFormat.bitsPerSecond));
    } else if (node.formatText) {
        parts.push(node.formatText);
    }
    if (node.quantum > 0 && node.rate > 0) {
        var latencyMilliseconds = (node.quantum / node.rate) * 1000;
        parts.push("quantum " + node.quantum + " (" + latencyMilliseconds.toFixed(1) + " ms)");
    }
    if (node.errorCount > 0) {
        parts.push(node.errorCount + " xruns");
    }
    return parts.join(", ");
}
