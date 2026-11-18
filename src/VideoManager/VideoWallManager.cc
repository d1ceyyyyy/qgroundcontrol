#include "VideoWallManager.h"

#include "QGCCorePlugin.h"
#include "QGCLoggingCategory.h"
#include "SettingsManager.h"
#include "VideoBackend.h"
#include "VideoReceiver.h"
#include "VideoSettings.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSettings>
#include <QtCore/QTimer>
#include <QtCore/QUuid>
#include <QtQuick/QQuickItem>

#include <algorithm>
#include <climits>

QGC_LOGGING_CATEGORY(VideoWallManagerLog, "Video.VideoWallManager")

namespace {
constexpr const char *kSettingsGroup = "VideoWall";
constexpr const char *kCamerasKey    = "cameras";
constexpr const char *kLayoutKey     = "layout";
constexpr uint32_t    kStreamTimeoutSec = 8;
constexpr int         kRetryDelaysMs[] = { 150, 400, 800, 1500, 2000 };
}

VideoWallManager::VideoWallManager(QObject *parent)
    : QObject(parent)
{
    _loadSettings();
}

VideoWallManager::~VideoWallManager()
{
    stopAllStreams();
}

void VideoWallManager::_loadSettings()
{
    QSettings settings;
    settings.beginGroup(QLatin1String(kSettingsGroup));
    const QString camerasRaw = settings.value(QLatin1String(kCamerasKey)).toString();
    _layoutJson = settings.value(QLatin1String(kLayoutKey)).toString();
    settings.endGroup();

    _cameras.clear();
    if (!camerasRaw.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(camerasRaw.toUtf8());
        if (doc.isArray()) {
            const QJsonArray arr = doc.array();
            for (const QJsonValue &val : arr) {
                if (val.isObject()) {
                    _cameras.append(val.toObject().toVariantMap());
                }
            }
        }
    }
}

void VideoWallManager::_saveCameras() const
{
    QJsonArray arr;
    for (const QVariant &v : _cameras) {
        arr.append(QJsonObject::fromVariantMap(v.toMap()));
    }

    QSettings settings;
    settings.beginGroup(QLatin1String(kSettingsGroup));
    settings.setValue(QLatin1String(kCamerasKey), QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact)));
    settings.endGroup();
}

void VideoWallManager::setLayoutJson(const QString &json)
{
    if (_layoutJson == json) {
        return;
    }
    _layoutJson = json;

    QSettings settings;
    settings.beginGroup(QLatin1String(kSettingsGroup));
    settings.setValue(QLatin1String(kLayoutKey), _layoutJson);
    settings.endGroup();

    emit layoutJsonChanged();
}

void VideoWallManager::setWallOpen(bool open)
{
    if (_wallOpen == open) {
        return;
    }
    _wallOpen = open;
    if (!_wallOpen) {
        stopAllStreams();
    }
    emit wallOpenChanged();
}

QString VideoWallManager::addCamera(const QString &name, const QString &hdUrl, const QString &sdUrl)
{
    const QString camId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QVariantMap cam;
    cam.insert(QStringLiteral("id"), camId);
    cam.insert(QStringLiteral("name"), name.trimmed().isEmpty() ? QStringLiteral("Camera") : name.trimmed());
    cam.insert(QStringLiteral("hdUrl"), hdUrl.trimmed());
    cam.insert(QStringLiteral("sdUrl"), sdUrl.trimmed());
    cam.insert(QStringLiteral("enabled"), true);

    _cameras.append(cam);
    _saveCameras();
    emit camerasChanged();
    return camId;
}

void VideoWallManager::addMediaMtxCameras(const QString &host, int port, const QString &namesCsv)
{
    const QString cleanHost = host.trimmed();
    if (cleanHost.isEmpty() || port <= 0 || port > 65535) {
        return;
    }

    const QStringList parts = namesCsv.split(QLatin1Char(','), Qt::SkipEmptyParts);
    bool addedAny = false;
    for (const QString &rawName : parts) {
        const QString name = rawName.trimmed();
        if (name.isEmpty()) {
            continue;
        }
        const QString camId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        QVariantMap cam;
        cam.insert(QStringLiteral("id"), camId);
        cam.insert(QStringLiteral("name"), name);
        cam.insert(QStringLiteral("hdUrl"), QStringLiteral("http://%1:%2/%3HD/whep").arg(cleanHost).arg(port).arg(name));
        cam.insert(QStringLiteral("sdUrl"), QStringLiteral("http://%1:%2/%3SD/whep").arg(cleanHost).arg(port).arg(name));
        cam.insert(QStringLiteral("enabled"), true);
        _cameras.append(cam);
        addedAny = true;
    }

    if (addedAny) {
        _saveCameras();
        emit camerasChanged();
    }
}

void VideoWallManager::updateCamera(const QString &camId, const QString &name, const QString &hdUrl, const QString &sdUrl)
{
    for (int i = 0; i < _cameras.size(); ++i) {
        QVariantMap cam = _cameras[i].toMap();
        if (cam.value(QStringLiteral("id")).toString() == camId) {
            cam.insert(QStringLiteral("name"), name.trimmed().isEmpty() ? QStringLiteral("Camera") : name.trimmed());
            cam.insert(QStringLiteral("hdUrl"), hdUrl.trimmed());
            cam.insert(QStringLiteral("sdUrl"), sdUrl.trimmed());
            _cameras[i] = cam;
            _saveCameras();
            emit camerasChanged();
            return;
        }
    }
}

void VideoWallManager::removeCamera(const QString &camId)
{
    detachTile(camId);
    for (int i = 0; i < _cameras.size(); ++i) {
        if (_cameras[i].toMap().value(QStringLiteral("id")).toString() == camId) {
            _cameras.removeAt(i);
            _saveCameras();
            emit camerasChanged();
            return;
        }
    }
}

void VideoWallManager::setCameraEnabled(const QString &camId, bool enabled)
{
    for (int i = 0; i < _cameras.size(); ++i) {
        QVariantMap cam = _cameras[i].toMap();
        if (cam.value(QStringLiteral("id")).toString() == camId) {
            if (cam.value(QStringLiteral("enabled")).toBool() == enabled) {
                return;
            }
            cam.insert(QStringLiteral("enabled"), enabled);
            _cameras[i] = cam;
            _saveCameras();
            if (!enabled) {
                detachTile(camId);
            }
            emit camerasChanged();
            return;
        }
    }
}

void VideoWallManager::attachTile(const QString &camId, QQuickItem *widget, const QString &uri)
{
    if (camId.isEmpty() || !widget) {
        return;
    }

    if (_streams.contains(camId)) {
        if (_streams[camId].widget == widget) {
            setTileUri(camId, uri);
            return;
        }
        _stopAndDestroyStream(camId);
    }

    VideoReceiver *receiver = QGCCorePlugin::instance()->createVideoReceiver(this);
    if (!receiver) {
        qCWarning(VideoWallManagerLog) << "createVideoReceiver failed for wall tile" << camId;
        return;
    }

    receiver->setName(QStringLiteral("wall_%1").arg(camId));
    receiver->setWidget(widget);

    void *sink = QGCCorePlugin::instance()->createVideoSink(widget, receiver);
    if (!sink) {
        qCWarning(VideoWallManagerLog) << "createVideoSink failed for wall tile" << camId;
        receiver->deleteLater();
        return;
    }
    receiver->setSink(sink);
    VideoBackend::attachSink(receiver, sink, widget);

    if (VideoSettings *vs = SettingsManager::instance()->videoSettings()) {
        receiver->setLowLatency(vs->lowLatencyMode()->rawValue().toBool());
        const int rtpLatencyMs = static_cast<int>(std::min(vs->rtpJitterLatencyMs()->rawValue().toUInt(), static_cast<uint>(INT_MAX)));
        receiver->setRtpJitterLatencyMs(rtpLatencyMs);
        receiver->setAutoReconnect(true);
    }

    TileStream stream;
    stream.receiver = receiver;
    stream.widget = widget;
    stream.uri = uri.trimmed();
    stream.wantRunning = !stream.uri.isEmpty();
    _streams.insert(camId, stream);

    (void) connect(receiver, &VideoReceiver::onStartComplete, this, [this, camId](VideoReceiver::STATUS status) {
        if (!_streams.contains(camId)) {
            return;
        }
        TileStream &s = _streams[camId];
        switch (status) {
        case VideoReceiver::STATUS_OK:
            s.receiver->setStarted(true);
            if (s.receiver->sink()) {
                s.receiver->startDecoding(s.receiver->sink());
            }
            break;
        case VideoReceiver::STATUS_INVALID_URL:
        case VideoReceiver::STATUS_INVALID_STATE:
            break;
        default:
            if (s.wantRunning) {
                const int idx = std::min(s.retryCount, static_cast<int>(std::size(kRetryDelaysMs)) - 1);
                const int delayMs = kRetryDelaysMs[idx];
                ++s.retryCount;
                QTimer::singleShot(delayMs, s.receiver, [this, camId]() {
                    if (_streams.contains(camId) && _streams[camId].wantRunning) {
                        _startReceiver(camId, _streams[camId]);
                    }
                });
            }
            break;
        }
    });

    (void) connect(receiver, &VideoReceiver::onStopComplete, this, [this, camId](VideoReceiver::STATUS status) {
        if (!_streams.contains(camId)) {
            return;
        }
        TileStream &s = _streams[camId];
        s.receiver->setStarted(false);
        if (s.wantRunning && status != VideoReceiver::STATUS_INVALID_URL && !s.uri.isEmpty()) {
            QTimer::singleShot(250, s.receiver, [this, camId]() {
                if (_streams.contains(camId) && _streams[camId].wantRunning) {
                    _startReceiver(camId, _streams[camId]);
                }
            });
        }
    });

    (void) connect(receiver, &VideoReceiver::streamingChanged, this, [this, camId](bool active) {
        if (_streams.contains(camId)) {
            _streams[camId].streaming = active;
            emit tileStateChanged(camId);
        }
    });

    (void) connect(receiver, &VideoReceiver::decodingChanged, this, [this, camId](bool active) {
        if (_streams.contains(camId)) {
            _streams[camId].decoding = active;
            if (active) {
                _streams[camId].retryCount = 0;
            }
            emit tileStateChanged(camId);
        }
    });

    (void) connect(receiver, &VideoReceiver::videoSizeChanged, this, [this, camId](QSize size) {
        if (_streams.contains(camId)) {
            _streams[camId].videoSize = size;
            emit tileStateChanged(camId);
        }
    });

    if (stream.wantRunning) {
        _startReceiver(camId, _streams[camId]);
    }
}

void VideoWallManager::setTileUri(const QString &camId, const QString &uri)
{
    if (!_streams.contains(camId)) {
        return;
    }
    TileStream &s = _streams[camId];
    const QString trimmed = uri.trimmed();
    if (s.uri == trimmed && s.wantRunning == !trimmed.isEmpty()) {
        return;
    }

    s.uri = trimmed;
    s.wantRunning = !trimmed.isEmpty();

    if (s.receiver->started()) {
        s.receiver->stop();
    } else if (s.wantRunning) {
        _startReceiver(camId, s);
    }
}

void VideoWallManager::detachTile(const QString &camId)
{
    _stopAndDestroyStream(camId);
}

void VideoWallManager::stopAllStreams()
{
    const QStringList ids = _streams.keys();
    for (const QString &camId : ids) {
        _stopAndDestroyStream(camId);
    }
}

bool VideoWallManager::isDecoding(const QString &camId) const
{
    return _streams.contains(camId) && _streams[camId].decoding;
}

bool VideoWallManager::isStreaming(const QString &camId) const
{
    return _streams.contains(camId) && _streams[camId].streaming;
}

QSize VideoWallManager::videoSize(const QString &camId) const
{
    return _streams.contains(camId) ? _streams[camId].videoSize : QSize();
}

void VideoWallManager::_startReceiver(const QString &camId, TileStream &stream)
{
    if (!stream.receiver || stream.uri.isEmpty() || stream.receiver->started()) {
        return;
    }
    qCDebug(VideoWallManagerLog) << "Starting wall stream" << camId << "URI:" << stream.uri;
    stream.receiver->setUri(stream.uri);
    stream.receiver->start(kStreamTimeoutSec);
}

void VideoWallManager::_stopAndDestroyStream(const QString &camId)
{
    if (!_streams.contains(camId)) {
        return;
    }
    TileStream s = _streams.take(camId);
    s.wantRunning = false;
    if (s.receiver) {
        if (s.receiver->started()) {
            s.receiver->stop();
        }
        if (s.receiver->sink()) {
            QGCCorePlugin::instance()->releaseVideoSink(s.receiver->sink());
        }
        s.receiver->deleteLater();
    }
    emit tileStateChanged(camId);
}
