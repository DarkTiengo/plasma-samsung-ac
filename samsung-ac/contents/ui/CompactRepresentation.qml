import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Panel item: mode icon + target temperature.
// Left click opens the popup, middle click toggles power, wheel changes the setpoint.
MouseArea {
    id: compact

    property var ac

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    Layout.minimumWidth: vertical ? -1 : row.implicitWidth
    Layout.minimumHeight: vertical ? row.implicitHeight : -1

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    property int wheelDelta: 0

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            if (ac.loaded) ac.setPower(!ac.isOn)
        } else {
            ac.expanded = !ac.expanded
        }
    }

    onWheel: wheel => {
        if (!ac.loaded || !ac.isOn) return
        wheelDelta += wheel.angleDelta.y
        while (wheelDelta >= 120) { wheelDelta -= 120; ac.nudgeSetpoint(1) }
        while (wheelDelta <= -120) { wheelDelta += 120; ac.nudgeSetpoint(-1) }
    }

    GridLayout {
        id: row
        anchors.centerIn: parent
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 0

        Kirigami.Icon {
            source: ac.modeIcon()
            active: compact.containsMouse
            opacity: ac.isOn ? 1 : 0.5
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignCenter
        }

        PlasmaComponents.Label {
            visible: ac.loaded && ac.isOn
            text: ac.setpoint !== undefined ? Math.round(ac.setpoint) + "°" : ""
            font.bold: ac.optionalMode === "windFree"
            Layout.alignment: Qt.AlignCenter
        }
    }

    // Small dot when the widget needs attention (not configured / error)
    Rectangle {
        visible: ac.errorText !== "" || ac.deviceId === ""
        width: Kirigami.Units.smallSpacing * 2
        height: width
        radius: width / 2
        color: Kirigami.Theme.negativeTextColor
        anchors { right: parent.right; top: parent.top }
    }
}
