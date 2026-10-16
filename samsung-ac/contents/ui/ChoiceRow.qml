import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// A titled row of mutually exclusive buttons; hidden when there are no options.
ColumnLayout {
    id: row

    property string title
    property var options: []
    property string current
    property var labels: ({})
    signal chosen(string value)

    visible: options && options.length > 0
    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    PlasmaComponents.Label {
        text: row.title
        opacity: 0.7
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: row.options

            PlasmaComponents.Button {
                required property string modelData
                text: row.labels[modelData] || modelData
                checkable: true
                checked: modelData === row.current
                onClicked: {
                    // Keep the binding; the parent updates `current` optimistically
                    checked = Qt.binding(() => modelData === row.current)
                    row.chosen(modelData)
                }
            }
        }
    }
}
