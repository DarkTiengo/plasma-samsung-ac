import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full

    property var ac

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredWidth: Kirigami.Units.gridUnit * 23
    Layout.preferredHeight: implicitHeight
    spacing: Kirigami.Units.largeSpacing

    // --- header ----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true

        Kirigami.Heading {
            level: 3
            text: ac.deviceName
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        PlasmaComponents.BusyIndicator {
            running: ac.busy
            visible: ac.busy
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Atualizar")
            onClicked: ac.refresh()
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
        }
        PlasmaComponents.Switch {
            enabled: ac.loaded
            checked: ac.isOn
            onToggled: ac.setPower(checked)
        }
    }

    // --- not configured / errors ------------------------------------------
    PlasmaExtras.PlaceholderMessage {
        visible: ac.deviceId === "" || (ac.needsAuth && !ac.loaded)
        Layout.fillWidth: true
        iconName: "configure"
        text: ac.deviceId === "" ? i18n("Nenhum aparelho selecionado") : i18n("Autorização necessária")
        explanation: i18n("Abra as configurações do widget para conectar à SmartThings.")
        helpfulAction: QQC2.Action {
            text: i18n("Configurar…")
            icon.name: "configure"
            onTriggered: Plasmoid.internalAction("configure").trigger()
        }
    }

    PlasmaComponents.Label {
        visible: ac.errorText !== "" && !(ac.needsAuth && !ac.loaded)
        text: ac.errorText
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        maximumLineCount: 4
        elide: Text.ElideRight
    }

    // --- temperature --------------------------------------------------------
    RowLayout {
        visible: ac.loaded
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.ToolButton {
            icon.name: "list-remove"
            enabled: ac.setpoint > ac.minTemp
            onClicked: ac.nudgeSetpoint(-1)
        }
        PlasmaComponents.Label {
            text: ac.fmtTemp(ac.setpoint)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.4
            opacity: ac.isOn ? 1 : 0.5
        }
        PlasmaComponents.ToolButton {
            icon.name: "list-add"
            enabled: ac.setpoint < ac.maxTemp
            onClicked: ac.nudgeSetpoint(1)
        }
    }

    PlasmaComponents.Label {
        visible: ac.loaded
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: -Kirigami.Units.largeSpacing
        opacity: 0.7
        text: {
            let s = i18n("Ambiente %1", ac.fmtTemp(ac.roomTemp))
            if (ac.has("relativeHumidityMeasurement") && ac.humidity !== null && ac.humidity !== undefined)
                s += " · " + i18n("Umidade %1%", Math.round(ac.humidity))
            return s
        }
    }

    // --- modes --------------------------------------------------------------
    ChoiceRow {
        visible: ac.loaded && ac.has("airConditionerMode") && options.length > 0
        title: i18n("Modo")
        options: ac.val("airConditionerMode", "supportedAcModes") || []
        current: ac.mode
        labels: ac.modeLabels
        onChosen: v => ac.send("airConditionerMode", "setAirConditionerMode", [v], ["airConditionerMode", v])
    }

    ChoiceRow {
        visible: ac.loaded && ac.has("custom.airConditionerOptionalMode") && options.length > 0
        title: i18n("Modos especiais")
        options: ac.val("custom.airConditionerOptionalMode", "supportedAcOptionalMode") || []
        current: ac.optionalMode
        labels: ac.optionalLabels
        onChosen: v => ac.send("custom.airConditionerOptionalMode", "setAcOptionalMode", [v], ["acOptionalMode", v])
    }

    ChoiceRow {
        visible: ac.loaded && ac.has("airConditionerFanMode") && options.length > 0
        title: i18n("Ventilador")
        options: ac.val("airConditionerFanMode", "supportedAcFanModes") || []
        current: ac.val("airConditionerFanMode", "fanMode") || ""
        labels: ac.fanLabels
        onChosen: v => ac.send("airConditionerFanMode", "setFanMode", [v], ["fanMode", v])
    }

    ChoiceRow {
        visible: ac.loaded && ac.has("fanOscillationMode") && options.length > 0
        title: i18n("Oscilação")
        options: ac.val("fanOscillationMode", "supportedFanOscillationModes") || []
        current: ac.val("fanOscillationMode", "fanOscillationMode") || ""
        labels: ac.swingLabels
        onChosen: v => ac.send("fanOscillationMode", "setFanOscillationMode", [v], ["fanOscillationMode", v])
    }

    // --- toggles ------------------------------------------------------------
    Flow {
        visible: ac.loaded
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.Switch {
            visible: ac.has("samsungce.airConditionerLighting") || ac.has("execute")
            text: i18n("Display")
            checked: ac.has("samsungce.airConditionerLighting")
                     ? ac.val("samsungce.airConditionerLighting", "lighting") !== "off"
                     : ac.displayOnLocal
            onToggled: ac.setDisplay(checked)
        }
        PlasmaComponents.Switch {
            visible: ac.has("samsungce.airConditionerBeep")
            text: i18n("Bip")
            checked: ac.val("samsungce.airConditionerBeep", "beep") === "on"
            onToggled: ac.send("samsungce.airConditionerBeep", checked ? "on" : "off", [], ["beep", checked ? "on" : "off"])
        }
        PlasmaComponents.Switch {
            visible: ac.has("custom.autoCleaningMode")
            text: i18n("Auto-limpeza")
            checked: ac.val("custom.autoCleaningMode", "autoCleaningMode") === "on"
            onToggled: {
                const v = checked ? "on" : "off"
                ac.send("custom.autoCleaningMode", "setAutoCleaningMode", [v], ["autoCleaningMode", v])
            }
        }
    }

    // --- energy -------------------------------------------------------------
    PlasmaComponents.Label {
        readonly property var pc: ac.val("powerConsumptionReport", "powerConsumption")
        visible: ac.loaded && ac.has("powerConsumptionReport") && !!pc
        opacity: 0.7
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: !pc ? "" : i18n("Consumo: %1 W agora · %2 kWh acumulado",
                              Math.round(pc.power || 0),
                              ((pc.energy || 0) / 1000).toFixed(1))
    }

    // Leftover height goes below the controls instead of between them
    Item {
        Layout.fillHeight: true
    }
}
