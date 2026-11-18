import QGroundControl
import QGroundControl.Controls

ToolStripAction {
    text:       qsTr("Відео-стіна")
    iconSource: "/qmlimages/Gps.svg"
    checked:    QGroundControl.videoManager.videoWallManager.wallOpen
    onTriggered: {
        QGroundControl.videoManager.videoWallManager.wallOpen = !QGroundControl.videoManager.videoWallManager.wallOpen
    }
}
