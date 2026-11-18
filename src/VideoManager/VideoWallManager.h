#pragma once

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QSize>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

class QQuickItem;
class VideoReceiver;

/// Manages multiple concurrent WebRTC/RTSP/UDP video streams and persistent layout
/// for the FlyView Video Wall overlay.
class VideoWallManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(QVariantList cameras     READ cameras     NOTIFY camerasChanged)
    Q_PROPERTY(QString      layoutJson  READ layoutJson  WRITE setLayoutJson NOTIFY layoutJsonChanged)
    Q_PROPERTY(bool         wallOpen    READ wallOpen    WRITE setWallOpen   NOTIFY wallOpenChanged)

public:
    explicit VideoWallManager(QObject *parent = nullptr);
    ~VideoWallManager() override;

    QVariantList cameras() const { return _cameras; }
    QString layoutJson() const { return _layoutJson; }
    bool wallOpen() const { return _wallOpen; }

    void setLayoutJson(const QString &json);
    void setWallOpen(bool open);

    /// Camera CRUD (persisted in QSettings under group "VideoWall")
    Q_INVOKABLE QString addCamera(const QString &name, const QString &hdUrl, const QString &sdUrl = QString());
    Q_INVOKABLE void addMediaMtxCameras(const QString &host, int port, const QString &namesCsv);
    Q_INVOKABLE void updateCamera(const QString &camId, const QString &name, const QString &hdUrl, const QString &sdUrl);
    Q_INVOKABLE void removeCamera(const QString &camId);
    Q_INVOKABLE void setCameraEnabled(const QString &camId, bool enabled);

    /// Stream lifecycle bound to a QML VideoOutput item per tile
    Q_INVOKABLE void attachTile(const QString &camId, QQuickItem *widget, const QString &uri);
    Q_INVOKABLE void setTileUri(const QString &camId, const QString &uri);
    Q_INVOKABLE void detachTile(const QString &camId);
    Q_INVOKABLE void stopAllStreams();

    /// Per-tile live state queries for QML
    Q_INVOKABLE bool isDecoding(const QString &camId) const;
    Q_INVOKABLE bool isStreaming(const QString &camId) const;
    Q_INVOKABLE QSize videoSize(const QString &camId) const;

signals:
    void camerasChanged();
    void layoutJsonChanged();
    void wallOpenChanged();
    void tileStateChanged(const QString &camId);

private:
    struct TileStream {
        VideoReceiver *receiver = nullptr;
        QQuickItem *widget = nullptr;
        QString uri;
        bool decoding = false;
        bool streaming = false;
        bool wantRunning = false;
        int retryCount = 0;
        QSize videoSize;
    };

    void _loadSettings();
    void _saveCameras() const;
    void _startReceiver(const QString &camId, TileStream &stream);
    void _stopAndDestroyStream(const QString &camId);

    QVariantList _cameras;
    QString _layoutJson;
    bool _wallOpen = false;
    QHash<QString, TileStream> _streams;
};
