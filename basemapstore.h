#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QNetworkAccessManager>
#include <QVector>

class QNetworkReply;

// Offline Esri World Imagery packs for cab use. Tiles live under AppData/basemap/
// and are drawn by FieldView/PhoneMapView from disk (no live network while spraying).
//
// Two-tier strategy for large paddocks:
//   overview — whole boundary at z14–16 (cheap, always sharp enough to navigate)
//   detail   — ~cab patch at z17–19 around GPS / a chosen point
class BasemapStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadChanged)
    Q_PROPERTY(double progress READ progress NOTIFY downloadChanged)
    Q_PROPERTY(int downloadDone READ downloadDone NOTIFY downloadChanged)
    Q_PROPERTY(int downloadTotal READ downloadTotal NOTIFY downloadChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY downloadChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY downloadChanged)
    Q_PROPERTY(QVariantList packs READ packs NOTIFY packsChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchChanged)
    Q_PROPERTY(QVariantMap pendingPrompt READ pendingPrompt NOTIFY pendingPromptChanged)
    Q_PROPERTY(bool hasPendingPrompt READ hasPendingPrompt NOTIFY pendingPromptChanged)
    Q_PROPERTY(bool sslAvailable READ sslAvailable NOTIFY sslChanged)
    Q_PROPERTY(int packRevision READ packRevision NOTIFY packsChanged)

public:
    explicit BasemapStore(QObject *parent = nullptr);

    bool downloading() const { return m_downloading; }
    bool sslAvailable() const { return m_sslAvailable; }
    int packRevision() const { return m_packRevision; }
    double progress() const;
    int downloadDone() const { return m_dlDone; }
    int downloadTotal() const { return m_dlTotal; }
    QString statusText() const { return m_status; }
    QString errorText() const { return m_error; }
    QVariantList packs() const;
    QVariantList searchResults() const { return m_searchResults; }
    bool searching() const { return m_searching; }
    QVariantMap pendingPrompt() const { return m_pendingPrompt; }
    bool hasPendingPrompt() const { return !m_pendingPrompt.isEmpty(); }

    // Overview plan (z14–16) for a ring of {lat,lon} points, buffered in metres.
    Q_INVOKABLE QVariantMap planForPoints(const QVariantList &points,
                                          double bufferM = 250.0) const;
    Q_INVOKABLE QVariantMap planForBbox(double south, double west,
                                        double north, double east) const;
    // Cab-detail plan (z17–19) around a lat/lon. Default radius ≈ 180 m.
    Q_INVOKABLE QVariantMap planDetailAround(double lat, double lon,
                                             double radiusM = 220.0) const;

    // True if any on-device pack fully covers this bbox (no overview download needed).
    Q_INVOKABLE bool coversBbox(double south, double west,
                                double north, double east) const;

    // After boundary create/import: queue a confirm dialog if imagery is missing.
    Q_INVOKABLE void suggestForPoints(const QString &packId,
                                      const QString &label,
                                      const QVariantList &points,
                                      double bufferM = 250.0);
    Q_INVOKABLE void clearPendingPrompt();
    Q_INVOKABLE void acceptPendingPrompt();

    // Overview download for a bbox (z14–16). Clears only overview tiles in that bbox.
    Q_INVOKABLE void startDownload(const QString &packId, const QString &label,
                                   double south, double west,
                                   double north, double east);
    // Detail download around a point (z17–19). Clears only detail tiles in that patch.
    Q_INVOKABLE void startDetailDownload(const QString &packId, const QString &label,
                                         double lat, double lon,
                                         double radiusM = 220.0);
    Q_INVOKABLE void cancelDownload();
    // Removes pack metadata + deletes on-disk tiles for that pack's zoom range.
    Q_INVOKABLE void deletePack(const QString &packId);
    // Wipe every pack listing and all cached tile files.
    Q_INVOKABLE void clearAllMaps();

    Q_INVOKABLE void searchLocation(const QString &query);
    Q_INVOKABLE void clearSearch();

    // Visible on-disk tiles for the viewport (world render). Caps count for Mali.
    // Skips sparse high zooms so cab zoom falls back to overview instead of blanking.
    Q_INVOKABLE QVariantList visibleTiles(double south, double west,
                                          double north, double east,
                                          double metresPerPixel,
                                          int maxTiles = 48) const;

    Q_INVOKABLE QString attribution() const;

signals:
    void downloadChanged();
    void packsChanged();
    void searchChanged();
    void pendingPromptChanged();
    void downloadFinished(bool ok);
    void sslChanged();

private:
    struct BBox {
        double south = 0, west = 0, north = 0, east = 0;
        bool valid() const { return north > south && east > west; }
    };
    struct TileCoord {
        int z = 0, x = 0, y = 0;
    };
    struct Pack {
        QString id;
        QString label;
        QString kind; // "overview" | "detail"
        BBox bbox;
        int minZoom = 14;
        int maxZoom = 16;
        int tileCount = 0;
        qint64 bytes = 0;
        QString createdAt;
    };

    static BBox bufferBBox(BBox b, double bufferM);
    static BBox bboxFromPoints(const QVariantList &points);
    static int lonToTileX(double lon, int z);
    static int latToTileY(double lat, int z);
    static void tileLatLonBounds(int z, int x, int y,
                                 double *south, double *west,
                                 double *north, double *east);
    static QVector<TileCoord> enumerateTiles(const BBox &b, int minZ, int maxZ);
    static QVariantMap planPack(const BBox &b, int minZ, int maxZ,
                                int minAllowedMaxZ, const QString &kind);

    QString rootDir() const;
    QString packsPath() const;
    QString tileFile(int z, int x, int y) const;
    QString tileUrl(int z, int x, int y) const;
    int clearTilesInBBox(const BBox &b, int minZ, int maxZ);
    int purgePlaceholderTiles() const;
    void startDownloadRange(const QString &packId, const QString &label,
                            const BBox &b, int minZ, int maxZ,
                            const QString &kind);
    void loadPacks();
    void savePacks() const;
    void pumpDownload();
    void finishDownload(bool ok, const QString &err);
    Pack *findPack(const QString &id);
    const Pack *findPack(const QString &id) const;

    QNetworkAccessManager m_nam;
    QVector<Pack> m_packs;
    QVariantList m_searchResults;
    QVariantMap m_pendingPrompt;

    bool m_downloading = false;
    bool m_searching = false;
    bool m_cancel = false;
    int m_dlDone = 0;
    int m_dlTotal = 0;
    int m_dlOk = 0;
    int m_dlFail = 0;
    int m_dlSkip = 0;
    qint64 m_dlBytes = 0;
    int m_packRevision = 0;
    bool m_sslAvailable = false;
    QString m_status;
    QString m_error;
    QString m_dlPackId;
    QString m_dlLabel;
    QString m_dlKind;
    BBox m_dlBBox;
    int m_dlMinZ = 14;
    int m_dlMaxZ = 16;
    QVector<TileCoord> m_dlQueue;
    QNetworkReply *m_reply = nullptr;
    int m_inFlight = 0;
    static constexpr int kMaxInFlight = 4;
};
