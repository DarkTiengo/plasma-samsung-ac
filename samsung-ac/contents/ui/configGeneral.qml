import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_deviceId
    property string cfg_deviceName
    property alias cfg_pollInterval: pollSpin.value

    property bool authorized: false
    property var devices: []
    property string message: ""
    property bool messageIsError: false

    function report(r, okText) {
        messageIsError = !!r.error
        message = r.error ? r.error : (okText || "")
    }

    function loadState() {
        ctl.run(["state"], r => {
            authorized = !!r.authorized
            if (r.client_id && clientIdField.text === "") clientIdField.text = r.client_id
            if (r.redirect_uri) redirectField.text = r.redirect_uri
            if (authorized) loadDevices()
        })
    }

    function loadDevices() {
        ctl.run(["devices"], r => {
            if (r.error) {
                report(r)
                return
            }
            devices = r.devices
            if (devices.length === 0) {
                report({}, i18n("Nenhum ar-condicionado encontrado nesta conta."))
            } else if (!cfg_deviceId && devices.length === 1) {
                cfg_deviceId = devices[0].deviceId
                cfg_deviceName = devices[0].label
            }
        })
    }

    Component.onCompleted: loadState()

    StCtl { id: ctl }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Conta SmartThings")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Status:")
            text: page.authorized ? i18n("✔ Autorizado") : i18n("Não autorizado")
            color: page.authorized ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
        }

        QQC2.TextField {
            id: clientIdField
            Kirigami.FormData.label: i18n("Client ID:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }

        Kirigami.PasswordField {
            id: secretField
            Kirigami.FormData.label: i18n("Client Secret:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            placeholderText: page.authorized ? i18n("(salvo — só preencha para reautorizar)") : ""
        }

        QQC2.TextField {
            id: redirectField
            Kirigami.FormData.label: i18n("Redirect URI:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            text: "https://httpbin.org/get"
        }

        QQC2.Button {
            text: i18n("1. Abrir página de autorização")
            icon.name: "internet-services"
            enabled: clientIdField.text !== "" && secretField.text !== "" && redirectField.text !== ""
            onClicked: ctl.run(["setup", clientIdField.text, secretField.text, redirectField.text], r => {
                if (r.error) {
                    page.report(r)
                    return
                }
                Qt.openUrlExternally(r.url)
                page.report({}, i18n("Faça login, autorize e cole abaixo o \"code\" (ou a URL/página inteira de retorno)."))
            })
        }

        QQC2.TextField {
            id: codeField
            Kirigami.FormData.label: i18n("Code:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            placeholderText: i18n("code, URL ou página do httpbin")
        }

        QQC2.Button {
            text: i18n("2. Concluir autorização")
            icon.name: "dialog-ok"
            enabled: codeField.text !== ""
            onClicked: ctl.run(["auth-code", codeField.text], r => {
                page.report(r, i18n("Autorizado com sucesso!"))
                if (!r.error) {
                    codeField.text = ""
                    secretField.text = ""
                    page.loadState()
                }
            })
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.message !== ""
            text: page.message
            type: page.messageIsError ? Kirigami.MessageType.Error : Kirigami.MessageType.Information
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Aparelho")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Ar-condicionado:")

            QQC2.ComboBox {
                id: deviceCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                model: page.devices
                textRole: "label"
                displayText: currentIndex >= 0 ? currentText : (page.cfg_deviceName || i18n("(nenhum)"))
                currentIndex: page.devices.findIndex(d => d.deviceId === page.cfg_deviceId)
                onActivated: index => {
                    page.cfg_deviceId = page.devices[index].deviceId
                    page.cfg_deviceName = page.devices[index].label
                }
            }
            QQC2.Button {
                icon.name: "view-refresh"
                text: i18n("Buscar")
                enabled: page.authorized
                onClicked: page.loadDevices()
            }
        }

        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: i18n("Atualizar a cada (s):")
            from: 15
            to: 600
            stepSize: 15
        }
    }
}
