import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

// Runs contents/code/stctl.py and hands its JSON output to a callback.
Item {
    id: ctl
    visible: false

    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../code/stctl.py").toString().replace(/^file:\/\//, ""))
    property int seq: 0
    property var callbacks: ({})

    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function run(args, cb) {
        // The trailing comment keeps identical commands from collapsing into one source.
        const src = "python3 " + shq(script) + " " + args.map(shq).join(" ") + " # " + (++seq)
        callbacks[src] = cb
        exec.connectSource(src)
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            exec.disconnectSource(source)
            const cb = ctl.callbacks[source]
            delete ctl.callbacks[source]
            let result
            try {
                result = JSON.parse(data.stdout)
            } catch (e) {
                result = { error: (data.stderr || data.stdout || "Saída inválida do stctl.py").trim(), code: "error" }
            }
            if (cb) cb(result)
        }
    }
}
