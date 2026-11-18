import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Rectangle {
    id: wallRoot

    readonly property var wallMgr: QGroundControl.videoManager.videoWallManager

    visible: wallMgr ? wallMgr.wallOpen : false
    color:   "#080b10"
    z:       QGroundControl.zOrderTopMost + 10
    focus:   visible

    property string layoutMode: "pip" // "pip", "grid", "free"
    property var    layoutMap:  ({})  // { [camId]: { x, y, w, h, z, q, contain } }
    property string mainCamId:  ""

    readonly property var enabledCameras: {
        var list = []
        if (!wallMgr) return list
        var all = wallMgr.cameras
        for (var i = 0; i < all.length; ++i) {
            if (all[i].enabled !== false) {
                list.push(all[i])
            }
        }
        return list
    }

    Keys.onEscapePressed: {
        if (camDialog.visible) {
            camDialog.visible = false
        } else if (wallMgr) {
            wallMgr.wallOpen = false
        }
    }

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus()
            loadOrInitLayout()
        }
    }

    onEnabledCamerasChanged: {
        if (visible) {
            loadOrInitLayout()
        }
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function findMainId(map, cams) {
        var bestId = ""
        var bestArea = -1
        for (var i = 0; i < cams.length; ++i) {
            var id = cams[i].id
            var g = map[id]
            if (!g) continue
            var area = g.w * g.h
            if (area > bestArea) {
                bestArea = area
                bestId = id
            }
        }
        return bestId
    }

    function saveLayout() {
        mainCamId = findMainId(layoutMap, enabledCameras)
        if (wallMgr) {
            wallMgr.layoutJson = JSON.stringify({ mode: layoutMode, tiles: layoutMap })
        }
    }

    function applyLayoutToItems() {
        for (var i = 0; i < tileRepeater.count; ++i) {
            var item = tileRepeater.itemAt(i)
            if (!item) continue
            var g = layoutMap[item.camId]
            if (!g) continue
            item.maximized = false
            item.x = g.x
            item.y = g.y
            item.width = g.w
            item.height = g.h
            item.z = g.z
            item.qualityMode = g.q || "AUTO"
            item.containMode = (g.contain !== undefined) ? g.contain : true
        }
        mainCamId = findMainId(layoutMap, enabledCameras)
    }

    function loadOrInitLayout() {
        var cams = enabledCameras
        if (cams.length === 0 || stage.width <= 0 || stage.height <= 0) {
            return
        }

        var loaded = null
        if (wallMgr && wallMgr.layoutJson.length > 0) {
            try {
                loaded = JSON.parse(wallMgr.layoutJson)
            } catch (e) {
                loaded = null
            }
        }

        if (loaded && loaded.tiles) {
            var map = loaded.tiles
            var allPresent = true
            for (var i = 0; i < cams.length; ++i) {
                if (!map[cams[i].id]) {
                    allPresent = false
                    break
                }
            }
            if (allPresent) {
                layoutMode = loaded.mode || "free"
                layoutMap = map
                Qt.callLater(applyLayoutToItems)
                return
            }
        }

        pipLayout()
    }

    function pipLayout() {
        var cams = enabledCameras
        var W = stage.width
        var H = stage.height
        if (cams.length === 0 || W <= 0 || H <= 0) return

        var map = {}
        map[cams[0].id] = {
            x: 0, y: 0, w: W, h: H,
            z: 1, q: "HD", contain: true
        }

        var pipW = clamp(Math.round(W * 0.28), 220, 460)
        var pipH = clamp(Math.round(H * 0.28), 140, 300)
        var gap = 10
        var countSmall = cams.length - 1
        if (countSmall > 0) {
            var availW = W - 24
            if (countSmall * (pipW + gap) - gap > availW) {
                pipW = Math.max(140, Math.floor((availW - (countSmall - 1) * gap) / countSmall))
                pipH = Math.max(90, Math.round(pipW * 0.625))
            }
        }

        for (var i = 1; i < cams.length; ++i) {
            var px = 12 + (i - 1) * (pipW + gap)
            var py = Math.max(12, H - pipH - 12)
            map[cams[i].id] = {
                x: px, y: py, w: pipW, h: pipH,
                z: 2 + i, q: "SD", contain: true
            }
        }

        layoutMode = "pip"
        layoutMap = map
        saveLayout()
        Qt.callLater(applyLayoutToItems)
    }

    function gridLayout() {
        var cams = enabledCameras
        var W = stage.width
        var H = stage.height
        if (cams.length === 0 || W <= 0 || H <= 0) return

        var n = cams.length
        var cols = Math.ceil(Math.sqrt(n))
        var rows = Math.ceil(n / cols)
        var cw = Math.floor(W / cols)
        var ch = Math.floor(H / rows)

        var map = {}
        for (var i = 0; i < n; ++i) {
            var r = Math.floor(i / cols)
            var c = i % cols
            map[cams[i].id] = {
                x: c * cw,
                y: r * ch,
                w: (c === cols - 1) ? (W - c * cw) : cw,
                h: (r === rows - 1) ? (H - r * ch) : ch,
                z: 1,
                q: "SD",
                contain: true
            }
        }

        layoutMode = "grid"
        layoutMap = map
        saveLayout()
        Qt.callLater(applyLayoutToItems)
    }

    function swapWithMain(camId) {
        var cams = enabledCameras
        if (cams.length < 2) return

        var mId = findMainId(layoutMap, cams)
        var partnerId = mId

        if (camId === mId) {
            for (var i = 0; i < cams.length; ++i) {
                if (cams[i].id !== mId) {
                    partnerId = cams[i].id
                    break
                }
            }
        }
        if (!partnerId || partnerId === camId) return

        var a = layoutMap[camId]
        var b = layoutMap[partnerId]
        if (!a || !b) return

        var tmp = { x: a.x, y: a.y, w: a.w, h: a.h, z: a.z }
        a.x = b.x; a.y = b.y; a.w = b.w; a.h = b.h; a.z = b.z
        b.x = tmp.x; b.y = tmp.y; b.w = tmp.w; b.h = tmp.h; b.z = tmp.z

        layoutMode = "free"
        saveLayout()
        applyLayoutToItems()
    }

    function bringToFront(camId) {
        var maxZ = 1
        for (var k in layoutMap) {
            if (layoutMap[k] && layoutMap[k].z > maxZ) {
                maxZ = layoutMap[k].z
            }
        }
        if (layoutMap[camId]) {
            layoutMap[camId].z = maxZ + 1
            saveLayout()
            applyLayoutToItems()
        }
    }

    function sendToBack(camId) {
        var minZ = 1
        for (var k in layoutMap) {
            if (layoutMap[k] && layoutMap[k].z < minZ) {
                minZ = layoutMap[k].z
            }
        }
        if (layoutMap[camId]) {
            layoutMap[camId].z = Math.max(0, minZ - 1)
            if (minZ <= 0) {
                for (var id in layoutMap) {
                    layoutMap[id].z += 1
                }
            }
            saveLayout()
            applyLayoutToItems()
        }
    }

    // Top control bar
    Rectangle {
        id: topBar
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height:        42
        color:         "#111827"
        border.color:  "#1f2937"
        border.width:  1
        z:             500

        RowLayout {
            anchors.fill:    parent
            anchors.margins: 6
            spacing:         8

            QGCLabel {
                text:           qsTr("🎥 Відео-стіна (WebRTC)")
                color:          "#f8fafc"
                font.bold:      true
                font.pointSize: ScreenTools.defaultFontPointSize
            }

            Item { Layout.fillWidth: true }

            QGCButton {
                text:    qsTr("⧉ PiP")
                checked: wallRoot.layoutMode === "pip"
                onClicked: wallRoot.pipLayout()
            }

            QGCButton {
                text:    qsTr("⊞ Сітка")
                checked: wallRoot.layoutMode === "grid"
                onClicked: wallRoot.gridLayout()
            }

            QGCButton {
                text: qsTr("⚙ Камери (%1)").arg(wallRoot.enabledCameras.length)
                onClicked: camDialog.visible = true
            }

            QGCButton {
                text:    qsTr("⛶ Екран")
                checked: QGroundControl.videoManager.fullScreen
                onClicked: QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen
            }

            QGCButton {
                text: qsTr("✕ Закрити")
                onClicked: {
                    if (wallRoot.wallMgr) {
                        wallRoot.wallMgr.wallOpen = false
                    }
                }
            }
        }
    }

    // Stage (.wstage)
    Item {
        id: stage
        anchors.top:    topBar.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        clip:           true

        onWidthChanged:  if (wallRoot.visible && layoutMode !== "free") Qt.callLater(layoutMode === "grid" ? gridLayout : pipLayout)
        onHeightChanged: if (wallRoot.visible && layoutMode !== "free") Qt.callLater(layoutMode === "grid" ? gridLayout : pipLayout)

        // Empty state
        Column {
            anchors.centerIn: parent
            spacing:          12
            visible:          wallRoot.enabledCameras.length === 0

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text:  qsTr("Немає доданих WebRTC камер")
                color: "#e2e8f0"
                font.bold: true
                font.pointSize: ScreenTools.largeFontPointSize
            }

            QGCButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text:    qsTr("+ Додати камери")
                primary: true
                onClicked: camDialog.visible = true
            }
        }

        Repeater {
            id: tileRepeater
            model: wallRoot.enabledCameras

            delegate: VideoWallTile {
                required property var modelData

                camId:     modelData.id
                camName:   modelData.name
                hdUrl:     modelData.hdUrl
                sdUrl:     modelData.sdUrl
                stageItem: stage
                isMain:    camId === wallRoot.mainCamId

                onSwapRequested: function(id) { wallRoot.swapWithMain(id) }
                onBringToFrontRequested: function(id) { wallRoot.bringToFront(id) }
                onSendToBackRequested: function(id) { wallRoot.sendToBack(id) }

                onGeometryCommitted: function(id, nx, ny, nw, nh) {
                    if (!wallRoot.layoutMap[id]) {
                        wallRoot.layoutMap[id] = { x: nx, y: ny, w: nw, h: nh, z: z, q: qualityMode, contain: containMode }
                    } else {
                        wallRoot.layoutMap[id].x = nx
                        wallRoot.layoutMap[id].y = ny
                        wallRoot.layoutMap[id].w = nw
                        wallRoot.layoutMap[id].h = nh
                    }
                    wallRoot.layoutMode = "free"
                    wallRoot.saveLayout()
                }

                onQualityChanged: function(id, q) {
                    if (wallRoot.layoutMap[id]) {
                        wallRoot.layoutMap[id].q = q
                        wallRoot.saveLayout()
                    }
                }

                onContainChanged: function(id, c) {
                    if (wallRoot.layoutMap[id]) {
                        wallRoot.layoutMap[id].contain = c
                        wallRoot.saveLayout()
                    }
                }
            }
        }
    }

    VideoWallCameraDialog {
        id: camDialog
    }
}
