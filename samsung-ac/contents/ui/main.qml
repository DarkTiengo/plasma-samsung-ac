import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    // capability -> attribute -> value, from `stctl.py status`
    property var caps: ({})
    property var disabled: []
    property string errorText: ""
    property bool needsAuth: false
    property bool busy: false
    // State of the display light when the model only exposes the write-only `execute` path
    property bool displayOnLocal: true

    readonly property string deviceId: Plasmoid.configuration.deviceId
    readonly property string deviceName: Plasmoid.configuration.deviceName || i18n("Ar-condicionado")
    readonly property bool loaded: Object.keys(caps).length > 0
    readonly property bool isOn: val("switch", "switch") === "on"
    readonly property var setpoint: val("thermostatCoolingSetpoint", "coolingSetpoint")
    readonly property var roomTemp: val("temperatureMeasurement", "temperature")
    readonly property var humidity: val("relativeHumidityMeasurement", "humidity")
    readonly property string mode: val("airConditionerMode", "airConditionerMode") || ""
    readonly property string optionalMode: val("custom.airConditionerOptionalMode", "acOptionalMode") || ""
    readonly property real minTemp: val("custom.thermostatSetpointControl", "minimumSetpoint") || 16
    readonly property real maxTemp: val("custom.thermostatSetpointControl", "maximumSetpoint") || 30

    readonly property var modeLabels: ({
        cool: i18n("Frio"), heat: i18n("Quente"), dry: i18n("Desumidificar"),
        wind: i18n("Ventilar"), fan: i18n("Ventilar"), auto: i18n("Auto"),
        aIComfort: i18n("AI Comfort")
    })
    readonly property var fanLabels: ({
        auto: i18n("Auto"), low: i18n("Baixa"), medium: i18n("Média"),
        high: i18n("Alta"), turbo: i18n("Turbo")
    })
    readonly property var optionalLabels: ({
        off: i18n("Nenhum"), windFree: i18n("WindFree"), windFreeSleep: i18n("WindFree Sono"),
        speed: i18n("Speed"), sleep: i18n("Sono"), quiet: i18n("Silencioso"),
        smart: i18n("Smart"), eco: i18n("Eco"), energySaving: i18n("Economia"),
        longWind: i18n("Longo alcance"), comfort: i18n("Conforto"), twoStep: i18n("2 estágios")
    })
    readonly property var swingLabels: ({
        fixed: i18n("Fixo"), all: i18n("Todas"), vertical: i18n("Vertical"),
        horizontal: i18n("Horizontal"), indirect: i18n("Indireto"), direct: i18n("Direto")
    })

    function has(cap) {
        return caps[cap] !== undefined && disabled.indexOf(cap) < 0
    }

    function val(cap, attr) {
        const c = caps[cap]
        return c ? c[attr] : undefined
    }

    function setLocal(cap, attr, value) {
        const c = Object.assign({}, caps)
        c[cap] = Object.assign({}, c[cap])
        c[cap][attr] = value
        caps = c
    }

    function handleError(r) {
        errorText = r.error
        needsAuth = r.code === "not_authorized"
    }

    function refresh() {
        if (!deviceId) {
            return
        }
        busy = true
        ctl.run(["status", deviceId], r => {
            busy = false
            if (r.error) {
                handleError(r)
                return
            }
            caps = r.caps
            disabled = r.disabled || []
            errorText = ""
            needsAuth = false
        })
    }

    // optimistic: [attribute, value] applied locally right away
    function send(cap, command, args, optimistic) {
        if (!deviceId) {
            return
        }
        if (optimistic) {
            setLocal(cap, optimistic[0], optimistic[1])
        }
        ctl.run(["cmd", deviceId, cap, command, JSON.stringify(args || [])], r => {
            if (r.error) {
                handleError(r)
            }
            // The cloud takes a moment to reflect the device's new state
            followUp.restart()
        })
    }

    function setPower(on) {
        send("switch", on ? "on" : "off", [], ["switch", on ? "on" : "off"])
    }

    property real pendingSetpoint: NaN

    function nudgeSetpoint(delta) {
        const base = isNaN(pendingSetpoint) ? (setpoint || 24) : pendingSetpoint
        pendingSetpoint = Math.max(minTemp, Math.min(maxTemp, base + delta))
        setLocal("thermostatCoolingSetpoint", "coolingSetpoint", pendingSetpoint)
        setpointTimer.restart()
    }

    function setDisplay(on) {
        if (has("samsungce.airConditionerLighting")) {
            send("samsungce.airConditionerLighting", "setLightingLevel", [on ? "on" : "off"], ["lighting", on ? "on" : "off"])
        } else {
            // Legacy OCF path; Samsung's option name is inverted (Light_On turns the display off)
            displayOnLocal = on
            send("execute", "execute", ["mode/vs/0", { "x.com.samsung.da.options": [on ? "Light_Off" : "Light_On"] }])
        }
    }

    function modeIcon() {
        if (!isOn) return "system-shutdown"
        switch (mode) {
        case "heat": return "temperature-warm"
        case "dry": return "raindrop"
        case "wind": case "fan": return "weather-clouds-wind"
        case "auto": case "aIComfort": return "temperature-normal"
        default: return "weather-snow"
        }
    }

    function fmtTemp(t) {
        return t === undefined || t === null ? "–" : (Math.round(t * 10) / 10) + " °C"
    }

    Plasmoid.icon: modeIcon()
    toolTipMainText: deviceName
    toolTipSubText: {
        if (!deviceId) return i18n("Clique com o botão direito → Configurar")
        if (errorText) return errorText
        if (!loaded) return i18n("Carregando…")
        if (!isOn) return i18n("Desligado · ambiente %1", fmtTemp(roomTemp))
        let parts = [modeLabels[mode] || mode, fmtTemp(setpoint)]
        if (optionalMode && optionalMode !== "off") parts.push(optionalLabels[optionalMode] || optionalMode)
        return parts.join(" · ") + "\n" + i18n("Ambiente %1", fmtTemp(roomTemp))
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Atualizar")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: root.isOn ? i18n("Desligar") : i18n("Ligar")
            icon.name: "system-shutdown"
            enabled: root.loaded
            onTriggered: root.setPower(!root.isOn)
        }
    ]

    compactRepresentation: CompactRepresentation { ac: root }
    fullRepresentation: FullRepresentation { ac: root }

    onExpandedChanged: if (expanded) refresh()
    onDeviceIdChanged: {
        caps = {}
        refresh()
    }

    StCtl { id: ctl }

    Timer {
        interval: Math.max(15, Plasmoid.configuration.pollInterval) * 1000
        running: root.deviceId !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: followUp
        interval: 3000
        onTriggered: root.refresh()
    }

    Timer {
        id: setpointTimer
        interval: 800
        onTriggered: {
            root.send("thermostatCoolingSetpoint", "setCoolingSetpoint", [root.pendingSetpoint])
            root.pendingSetpoint = NaN
        }
    }
}
