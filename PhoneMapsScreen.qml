import QtQuick 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: mapsScreen
    spacing: 0
    signal back()

    PhoneSubScreenHeader {
        Layout.fillWidth: true
        title: qsTr("Offline maps")
        onBackClicked: mapsScreen.back()
    }
    MapsSetupPage {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }
}
