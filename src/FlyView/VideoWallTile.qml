import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

Rectangle {
    id: tile

    required property string camId
    required property string camName
    required property string hdUrl
    required property string sdUrl
    required property Item   stageItem
    required property bool   isMain

    property string qualityMode: "AUTO" // "AUTO", "SD", "HD"
    property bool   containMode: true
    property bool   maximized:   false

    // Saved pre-maximize geometry
    property rect   savedRect: Qt.rect(0, 0, 320, 200)

    signal swapRequested(string camId)
    signal bringToFrontRequested(string camId)
    signal sendToBackRequested(string camId)
    signal geometryCommitted(string camId, real nx, real ny, real nw, real nh)
    signal qualityChanged(string camId, string q)
    signal containChanged(string camId, bool contain)

    readonly property var    wallMgr:      QGroundControl.videoManager.videoWallManager
    readonly property string effectiveQuality: qualityMode === "AUTO" ? (isMain ? "HD" : "SD") : qualityMode
    readonly property string activeUri:    (effectiveQuality === "SD" && sdUrl.length > 0) ? sdUrl : hdUrl

    property bool _decoding: false
    property bool _streaming: false
    property size _videoSize: Qt.size(0, 0)

    color:        "#0d1117"
    border.color: hoverHandler.hovered ? "#38bdf8" : (isMain ? "#1e3a5f" : "#2d3748")
    border.width: hoverHandler.hovered ? 2 : 1
    radius:       4
    clip:         true

    onActiveUriChanged: {
        if (wallMgr && videoOut) {
            wallMgr.setTileUri(camId, activeUri)
        }
    }

    Component.onCompleted: {
        if (wallMgr) {
            wallMgr.attachTile(camId, videoOut, activeUri)
        }
    }

    Component.onDestruction: {
        if (wallMgr) {
            wallMgr.detachTile(camId)
        }
    }

    Connections {
        target: wallMgr
        function onTileStateChanged(changedId) {
            if (changedId === tile.camId) {
                tile._decoding = wallMgr.isDecoding(tile.camId)
                tile._streaming = wallMgr.isStreaming(tile.camId)
                tile._videoSize = wallMgr.videoSize(tile.camId)
            }
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    VideoOutput {
        id:           videoOut
        anchors.fill: parent
        fillMode:     tile.containMode ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
    }

    MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) {
            tile.bringToFrontRequested(tile.camId)
            mouse.accepted = true
        }
        onDoubleClicked: {
            QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen
        }
    }

    // Waiting / Status placeholder
    Column {
        anchors.centerIn: parent
        spacing:          6
        visible:          !tile._decoding

        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  tile.camName
            color: "#e2e8f0"
            font.bold: true
            font.pointSize: ScreenTools.defaultFontPointSize
        }

        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  tile.activeUri.length > 0
                   ? (tile._streaming ? qsTr("Декодування...") : qsTr("Підключення WebRTC..."))
                   : qsTr("URL не вказано")
            color: "#94a3b8"
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    // Bottom-left info pill
    Rectangle {
        anchors.left:   parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 22
        width:  infoRow.implicitWidth + 12
        radius: 4
        color:  Qt.rgba(0, 0, 0, 0.65)
        visible: hoverHandler.hovered || !tile._decoding

        Row {
            id: infoRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                width: 8; height: 8; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: tile._decoding ? "#22c55e" : (tile._streaming ? "#eab308" : "#ef4444")
            }

            QGCLabel {
                text: tile.camName + " [" + tile.effectiveQuality + "]"
                      + (tile._videoSize.width > 0 ? (" " + tile._videoSize.width + "×" + tile._videoSize.height) : "")
                color: "#f8fafc"
                font.pointSize: ScreenTools.smallFontPointSize * 0.9
            }
        }
    }

    // Top drag & control bar (.wth)
    Rectangle {
        id: headerBar
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height:        30
        color:         Qt.rgba(0.06, 0.09, 0.14, 0.85)
        opacity:       hoverHandler.hovered ? 1.0 : 0.0
        visible:       opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 120 } }

        // Drag area covering the title portion
        MouseArea {
            id: dragArea
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            anchors.right:  controlsRow.left
            cursorShape:    Qt.SizeAllCursor

            property point startMouseStage
            property real  startX
            property real  startY

            onPressed: function(mouse) {
                tile.bringToFrontRequested(tile.camId)
                if (tile.maximized) {
                    return
                }
                startMouseStage = mapToItem(tile.stageItem, mouse.x, mouse.y)
                startX = tile.x
                startY = tile.y
            }

            onPositionChanged: function(mouse) {
                if (!pressed || tile.maximized || !tile.stageItem) {
                    return
                }
                var cur = mapToItem(tile.stageItem, mouse.x, mouse.y)
                var dx = cur.x - startMouseStage.x
                var dy = cur.y - startMouseStage.y
                tile.x = Math.max(0, Math.min(tile.stageItem.width - tile.width, startX + dx))
                tile.y = Math.max(0, Math.min(tile.stageItem.height - tile.height, startY + dy))
            }

            onReleased: {
                if (!tile.maximized) {
                    tile.geometryCommitted(tile.camId, tile.x, tile.y, tile.width, tile.height)
                }
            }

            QGCLabel {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left:           parent.left
                anchors.leftMargin:     8
                anchors.right:          parent.right
                elide:                  Text.ElideRight
                text:                   tile.camName
                color:                  "#f1f5f9"
                font.bold:              true
                font.pointSize:         ScreenTools.smallFontPointSize
            }
        }

        Row {
            id: controlsRow
            anchors.right:          parent.right
            anchors.rightMargin:    4
            anchors.verticalCenter: parent.verticalCenter
            spacing:                3

            // Quality cycle: AUTO -> SD -> HD
            Repeater {
                model: ["AUTO", "SD", "HD"]
                delegate: Rectangle {
                    required property string modelData
                    width: 34; height: 22; radius: 3
                    color: tile.qualityMode === modelData ? "#0284c7" : "#1e293b"
                    border.color: "#475569"
                    border.width: 1

                    QGCLabel {
                        anchors.centerIn: parent
                        text: modelData === "AUTO" ? qsTr("Авто") : modelData
                        color: "#ffffff"
                        font.pointSize: ScreenTools.smallFontPointSize * 0.82
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            tile.qualityMode = modelData
                            tile.qualityChanged(tile.camId, modelData)
                        }
                    }
                }
            }

            // Aspect ratio (contain / cover)
            Rectangle {
                width: 24; height: 22; radius: 3
                color: tile.containMode ? "#1e293b" : "#0284c7"
                border.color: "#475569"; border.width: 1
                QGCLabel { anchors.centerIn: parent; text: "⛶"; color: "#ffffff"; font.pointSize: ScreenTools.smallFontPointSize * 0.9 }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        tile.containMode = !tile.containMode
                        tile.containChanged(tile.camId, tile.containMode)
                    }
                }
            }

            // Maximize / Restore
            Rectangle {
                width: 24; height: 22; radius: 3
                color: tile.maximized ? "#0284c7" : "#1e293b"
                border.color: "#475569"; border.width: 1
                QGCLabel { anchors.centerIn: parent; text: "▣"; color: "#ffffff"; font.pointSize: ScreenTools.smallFontPointSize * 0.9 }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!tile.stageItem) return
                        if (!tile.maximized) {
                            tile.savedRect = Qt.rect(tile.x, tile.y, tile.width, tile.height)
                            tile.maximized = true
                            tile.bringToFrontRequested(tile.camId)
                            tile.x = 0
                            tile.y = 0
                            tile.width = tile.stageItem.width
                            tile.height = tile.stageItem.height
                        } else {
                            tile.maximized = false
                            tile.x = tile.savedRect.x
                            tile.y = tile.savedRect.y
                            tile.width = tile.savedRect.width
                            tile.height = tile.savedRect.height
                        }
                    }
                }
            }

            // Z-order Up
            Rectangle {
                width: 22; height: 22; radius: 3
                color: "#1e293b"; border.color: "#475569"; border.width: 1
                QGCLabel { anchors.centerIn: parent; text: "▲"; color: "#ffffff"; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: tile.bringToFrontRequested(tile.camId)
                }
            }

            // Z-order Down
            Rectangle {
                width: 22; height: 22; radius: 3
                color: "#1e293b"; border.color: "#475569"; border.width: 1
                QGCLabel { anchors.centerIn: parent; text: "▼"; color: "#ffffff"; font.pointSize: ScreenTools.smallFontPointSize * 0.8 }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: tile.sendToBackRequested(tile.camId)
                }
            }
        }
    }

    // Center Swap button (.wswap ⇄)
    Rectangle {
        id: swapBtn
        anchors.centerIn: parent
        width:  46
        height: 46
        radius: 23
        color:  swapMouse.containsMouse ? Qt.rgba(0.01, 0.52, 0.78, 0.92) : Qt.rgba(0.06, 0.09, 0.14, 0.78)
        border.color: "#38bdf8"
        border.width: 1.5
        opacity: hoverHandler.hovered ? 1.0 : 0.0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 120 } }

        QGCLabel {
            anchors.centerIn: parent
            text:  "⇄"
            color: "#ffffff"
            font.pointSize: ScreenTools.largeFontPointSize * 1.1
            font.bold: true
        }

        MouseArea {
            id: swapMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    tile.swapRequested(tile.camId)
        }
    }

    // Bottom-right resize handle (.wrs)
    Rectangle {
        id: resizeHandle
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        width:  18
        height: 18
        color:  "transparent"
        visible: !tile.maximized && hoverHandler.hovered

        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#94a3b8"
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.moveTo(4, 16); ctx.lineTo(16, 4)
                ctx.moveTo(9, 16); ctx.lineTo(16, 9)
                ctx.moveTo(14, 16); ctx.lineTo(16, 14)
                ctx.stroke()
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape:  Qt.SizeFDiagCursor

            property point startMouseStage
            property real  startW
            property real  startH

            onPressed: function(mouse) {
                tile.bringToFrontRequested(tile.camId)
                startMouseStage = mapToItem(tile.stageItem, mouse.x, mouse.y)
                startW = tile.width
                startH = tile.height
            }

            onPositionChanged: function(mouse) {
                if (!pressed || !tile.stageItem) return
                var cur = mapToItem(tile.stageItem, mouse.x, mouse.y)
                var maxW = tile.stageItem.width - tile.x
                var maxH = tile.stageItem.height - tile.y
                tile.width = Math.max(140, Math.min(maxW, startW + (cur.x - startMouseStage.x)))
                tile.height = Math.max(90, Math.min(maxH, startH + (cur.y - startMouseStage.y)))
            }

            onReleased: {
                tile.geometryCommitted(tile.camId, tile.x, tile.y, tile.width, tile.height)
            }
        }
    }
}
