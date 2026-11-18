import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Rectangle {
    id: root

    property var wallMgr: QGroundControl.videoManager.videoWallManager

    anchors.fill: parent
    color:        Qt.rgba(0, 0, 0, 0.72)
    visible:      false
    z:            1000

    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        anchors.centerIn: parent
        width:  Math.min(parent.width * 0.85, ScreenTools.defaultFontPixelWidth * 78)
        height: Math.min(parent.height * 0.85, ScreenTools.defaultFontPixelHeight * 34)
        radius: 8
        color:  qgcPal.window
        border.color: qgcPal.groupBorder
        border.width: 1

        // Swallow clicks inside the dialog
        MouseArea { anchors.fill: parent }

        QGCPalette { id: qgcPal; colorGroupEnabled: true }

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: ScreenTools.defaultFontPixelWidth * 1.5
            spacing:         ScreenTools.defaultFontPixelHeight * 0.7

            RowLayout {
                Layout.fillWidth: true
                QGCLabel {
                    text:           qsTr("Камери відео-стіни (WebRTC / WHEP / RTSP)")
                    font.bold:      true
                    font.pointSize: ScreenTools.mediumFontPointSize
                    Layout.fillWidth: true
                }
                QGCButton {
                    text: qsTr("Закрити")
                    onClicked: root.visible = false
                }
            }

            // Quick MediaMTX batch add
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: mtxRow.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.8
                color:  qgcPal.windowShade
                radius: 6

                RowLayout {
                    id: mtxRow
                    anchors.fill:    parent
                    anchors.margins: ScreenTools.defaultFontPixelWidth
                    spacing:         8

                    QGCLabel { text: qsTr("MediaMTX:") }

                    QGCTextField {
                        id: mtxHostField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 18
                        placeholderText: "192.168.1.10"
                    }
                    QGCTextField {
                        id: mtxPortField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 7
                        text: "8889"
                    }
                    QGCTextField {
                        id: mtxNamesField
                        Layout.fillWidth: true
                        placeholderText: qsTr("camPoreder, camZad, cam3")
                    }
                    QGCButton {
                        text:    qsTr("+ MediaMTX")
                        primary: true
                        enabled: mtxHostField.text.trim().length > 0 && mtxNamesField.text.trim().length > 0
                        onClicked: {
                            var p = parseInt(mtxPortField.text) || 8889
                            wallMgr.addMediaMtxCameras(mtxHostField.text, p, mtxNamesField.text)
                            mtxNamesField.text = ""
                        }
                    }
                }
            }

            // Add new camera form
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: addGrid.implicitHeight + ScreenTools.defaultFontPixelHeight
                color:  qgcPal.windowShade
                radius: 6

                GridLayout {
                    id: addGrid
                    anchors.fill:    parent
                    anchors.margins: ScreenTools.defaultFontPixelWidth
                    columns:         4
                    columnSpacing:   8
                    rowSpacing:      6

                    QGCLabel { text: qsTr("Назва") }
                    QGCLabel { text: qsTr("HD URL (обов'язково)") }
                    QGCLabel { text: qsTr("SD URL (опціонально)") }
                    Item { width: 1 }

                    QGCTextField {
                        id: nameField
                        Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 14
                        placeholderText: qsTr("Cam 1")
                    }
                    QGCTextField {
                        id: hdField
                        Layout.fillWidth: true
                        placeholderText: "whep://192.168.1.10:8889/cam1/whep"
                    }
                    QGCTextField {
                        id: sdField
                        Layout.fillWidth: true
                        placeholderText: "whep://192.168.1.10:8889/cam1_sd/whep"
                    }
                    QGCButton {
                        text:    qsTr("+ Додати")
                        primary: true
                        enabled: hdField.text.trim().length > 0
                        onClicked: {
                            wallMgr.addCamera(nameField.text, hdField.text, sdField.text)
                            nameField.text = ""
                            hdField.text = ""
                            sdField.text = ""
                        }
                    }
                }
            }

            // Hint
            QGCLabel {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pointSize: ScreenTools.smallFontPointSize
                color: qgcPal.colorGrey
                text: qsTr("Підказка: для MediaMTX використовуйте whep://HOST:8889/STREAM/whep або http://HOST:8889/STREAM/whep. Також підтримуються rtsp:// та udp://.")
            }

            // Camera list
            ListView {
                id: camList
                Layout.fillWidth:  true
                Layout.fillHeight: true
                clip:              true
                spacing:           6
                model:             wallMgr ? wallMgr.cameras : []

                delegate: Rectangle {
                    required property var modelData
                    width:  camList.width
                    height: rowLayout.implicitHeight + 12
                    radius: 4
                    color:  qgcPal.windowShadeDark

                    RowLayout {
                        id: rowLayout
                        anchors.fill:    parent
                        anchors.margins: 6
                        spacing:         8

                        QGCCheckBox {
                            checked: modelData.enabled !== false
                            onClicked: wallMgr.setCameraEnabled(modelData.id, checked)
                        }

                        QGCTextField {
                            id: editName
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 13
                            text: modelData.name
                            onEditingFinished: wallMgr.updateCamera(modelData.id, editName.text, editHd.text, editSd.text)
                        }

                        QGCTextField {
                            id: editHd
                            Layout.fillWidth: true
                            text: modelData.hdUrl
                            onEditingFinished: wallMgr.updateCamera(modelData.id, editName.text, editHd.text, editSd.text)
                        }

                        QGCTextField {
                            id: editSd
                            Layout.fillWidth: true
                            text: modelData.sdUrl
                            placeholderText: qsTr("(як HD)")
                            onEditingFinished: wallMgr.updateCamera(modelData.id, editName.text, editHd.text, editSd.text)
                        }

                        QGCButton {
                            text: qsTr("✕")
                            onClicked: wallMgr.removeCamera(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
