import QtQuick 2.15

Item {
    id: page
    signal navigateBack()

    BoundaryRecordScreen {
        anchors.fill: parent
        phoneMode: false
        onBack: page.navigateBack()
    }
}
