import QtQuick 2.15

// Navigation page: the field view. Zoom / centre / perspective live on the map;
// record / section / clear live on the persistent bottom banner.
Item {
    id: page
    FieldView {
        id: fieldView
        anchors.fill: parent
    }
}
