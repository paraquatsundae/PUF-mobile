#include "basemapstore.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslSocket>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QtMath>
#include <QDateTime>
#include <QDebug>

namespace {
// Two-tier offline packs for large paddocks:
//   overview z14–17 — whole boundary (rural WA Maxar often ends at z17)
//   detail   z17–18 — cab patch; z19 usually Esri placeholders out here
constexpr int kOverviewMinZoom = 14;
constexpr int kOverviewMaxZoom = 17;
constexpr int kDetailMinZoom = 17;
constexpr int kDetailMaxZoom = 18;
constexpr int kDisplayMinZoom = 13;
constexpr int kDisplayMaxZoom = 19;
constexpr int kMaxPackTiles = 16000;
constexpr qint64 kAvgTileBytes = 25000;
constexpr double kDefaultDetailRadiusM = 220.0;
// Esri "Map data not yet available" JPEGs are ~2521 bytes; real imagery is larger.
constexpr qint64 kMinRealTileBytes = 4000;
// Accept a zoom only when most viewport tiles exist (else fall back coarser).
constexpr double kMinCoverage = 0.65;
// Partial downloads must land most tiles before the pack is marked complete.
constexpr double kMinSuccessRatio = 0.75;
const char *kEsriUrl =
    "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%1/%2/%3";
const char *kAttrib =
    "Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community";
}

BasemapStore::BasemapStore(QObject *parent)
    : QObject(parent)
{
    m_sslAvailable = QSslSocket::supportsSsl();
    qWarning("[basemap] SSL supports=%d build=%s lib=%s root=%s",
             int(m_sslAvailable),
             qUtf8Printable(QSslSocket::sslLibraryBuildVersionString()),
             qUtf8Printable(QSslSocket::sslLibraryVersionString()),
             qUtf8Printable(rootDir()));
    QDir().mkpath(rootDir() + QStringLiteral("/tiles"));
    const int purged = purgePlaceholderTiles();
    if (purged > 0)
        qWarning("[basemap] purged %d Esri placeholder tiles (< %lld B)",
                 purged, static_cast<long long>(kMinRealTileBytes));
    loadPacks();
    m_packRevision = m_packs.size();
}

double BasemapStore::progress() const
{
    if (m_dlTotal <= 0)
        return 0.0;
    return qBound(0.0, 1.0, double(m_dlDone) / double(m_dlTotal));
}

QVariantList BasemapStore::packs() const
{
    QVariantList out;
    for (const Pack &p : m_packs) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), p.id);
        m.insert(QStringLiteral("label"), p.label);
        m.insert(QStringLiteral("kind"), p.kind.isEmpty()
                 ? QStringLiteral("overview") : p.kind);
        m.insert(QStringLiteral("south"), p.bbox.south);
        m.insert(QStringLiteral("west"), p.bbox.west);
        m.insert(QStringLiteral("north"), p.bbox.north);
        m.insert(QStringLiteral("east"), p.bbox.east);
        m.insert(QStringLiteral("minZoom"), p.minZoom);
        m.insert(QStringLiteral("maxZoom"), p.maxZoom);
        m.insert(QStringLiteral("tileCount"), p.tileCount);
        m.insert(QStringLiteral("bytes"), double(p.bytes));
        m.insert(QStringLiteral("mbLabel"),
                 p.bytes < 1024 * 1024
                     ? QStringLiteral("%1 KB").arg(qMax(1, int(p.bytes / 1024)))
                     : QStringLiteral("%1 MB").arg(p.bytes / (1024.0 * 1024.0), 0, 'f', 1));
        m.insert(QStringLiteral("createdAt"), p.createdAt);
        out.append(m);
    }
    return out;
}

QString BasemapStore::attribution() const
{
    return QString::fromUtf8(kAttrib);
}

QString BasemapStore::rootDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
           + QStringLiteral("/basemap");
}

QString BasemapStore::packsPath() const
{
    return rootDir() + QStringLiteral("/packs.json");
}

QString BasemapStore::tileFile(int z, int x, int y) const
{
    return rootDir() + QStringLiteral("/tiles/%1/%2/%3.jpg").arg(z).arg(x).arg(y);
}

QString BasemapStore::tileUrl(int z, int x, int y) const
{
    // Esri path order: z / y / x
    return QString::fromLatin1(kEsriUrl).arg(z).arg(y).arg(x);
}

BasemapStore::BBox BasemapStore::bboxFromPoints(const QVariantList &points)
{
    BBox b;
    bool any = false;
    for (const QVariant &v : points) {
        const QVariantMap m = v.toMap();
        const double lat = m.value(QStringLiteral("lat")).toDouble();
        const double lon = m.value(QStringLiteral("lon")).toDouble();
        if (!qIsFinite(lat) || !qIsFinite(lon))
            continue;
        if (!any) {
            b.south = b.north = lat;
            b.west = b.east = lon;
            any = true;
        } else {
            b.south = qMin(b.south, lat);
            b.north = qMax(b.north, lat);
            b.west = qMin(b.west, lon);
            b.east = qMax(b.east, lon);
        }
    }
    if (!any)
        return {};
    return b;
}

BasemapStore::BBox BasemapStore::bufferBBox(BBox b, double bufferM)
{
    if (!b.valid() || bufferM <= 0)
        return b;
    const double midLat = (b.south + b.north) * 0.5;
    const double latRad = midLat * M_PI / 180.0;
    const double dLat = bufferM / 111320.0;
    const double cosLat = qMax(0.2, qCos(latRad));
    const double dLng = bufferM / (111320.0 * cosLat);
    b.south -= dLat;
    b.north += dLat;
    b.west -= dLng;
    b.east += dLng;
    return b;
}

int BasemapStore::lonToTileX(double lon, int z)
{
    const double n = qPow(2.0, z);
    int x = int(qFloor(((lon + 180.0) / 360.0) * n));
    return qBound(0, int(n) - 1, x);
}

int BasemapStore::latToTileY(double lat, int z)
{
    const double latRad = lat * M_PI / 180.0;
    const double n = qPow(2.0, z);
    const double y = (1.0 - qLn(qTan(latRad) + 1.0 / qCos(latRad)) / M_PI) / 2.0 * n;
    return qBound(0, int(n) - 1, int(qFloor(y)));
}

void BasemapStore::tileLatLonBounds(int z, int x, int y,
                                    double *south, double *west,
                                    double *north, double *east)
{
    const double n = qPow(2.0, z);
    *west = x / n * 360.0 - 180.0;
    *east = (x + 1) / n * 360.0 - 180.0;
    const auto latOfY = [n](int ty) {
        const double t = M_PI - 2.0 * M_PI * ty / n;
        return 180.0 / M_PI * qAtan(0.5 * (qExp(t) - qExp(-t)));
    };
    *north = latOfY(y);
    *south = latOfY(y + 1);
}

QVector<BasemapStore::TileCoord> BasemapStore::enumerateTiles(const BBox &b, int minZ, int maxZ)
{
    QVector<TileCoord> tiles;
    for (int z = minZ; z <= maxZ; ++z) {
        const int n = 1 << z;
        int xMin = lonToTileX(b.west, z);
        int xMax = lonToTileX(b.east, z);
        int yMin = latToTileY(b.north, z);
        int yMax = latToTileY(b.south, z);
        if (xMin > xMax)
            qSwap(xMin, xMax);
        if (yMin > yMax)
            qSwap(yMin, yMax);
        xMin = qBound(0, n - 1, xMin);
        xMax = qBound(0, n - 1, xMax);
        yMin = qBound(0, n - 1, yMin);
        yMax = qBound(0, n - 1, yMax);
        for (int x = xMin; x <= xMax; ++x) {
            for (int y = yMin; y <= yMax; ++y)
                tiles.append({z, x, y});
        }
    }
    return tiles;
}

QVariantMap BasemapStore::planPack(const BBox &raw, int minZ, int maxZ,
                                   int minAllowedMaxZ, const QString &kind)
{
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("kind"), kind);
    if (!raw.valid() || minZ > maxZ) {
        out.insert(QStringLiteral("error"), QStringLiteral("Invalid area"));
        return out;
    }
    bool zoomReduced = false;
    bool overBudget = false;
    QVector<TileCoord> tiles;
    int useMax = maxZ;
    for (useMax = maxZ; useMax >= minAllowedMaxZ; --useMax) {
        tiles = enumerateTiles(raw, minZ, useMax);
        if (tiles.size() <= kMaxPackTiles) {
            zoomReduced = (useMax < maxZ);
            break;
        }
        overBudget = true;
    }
    if (tiles.size() > kMaxPackTiles) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Area too large for offline pack — shrink the boundary or download detail around the machine only."));
        out.insert(QStringLiteral("overBudget"), true);
        out.insert(QStringLiteral("tileCount"), tiles.size());
        return out;
    }
    const qint64 bytes = qint64(tiles.size()) * kAvgTileBytes;
    out.insert(QStringLiteral("ok"), true);
    out.insert(QStringLiteral("south"), raw.south);
    out.insert(QStringLiteral("west"), raw.west);
    out.insert(QStringLiteral("north"), raw.north);
    out.insert(QStringLiteral("east"), raw.east);
    out.insert(QStringLiteral("minZoom"), minZ);
    out.insert(QStringLiteral("maxZoom"), useMax);
    out.insert(QStringLiteral("tileCount"), tiles.size());
    out.insert(QStringLiteral("bytes"), double(bytes));
    out.insert(QStringLiteral("mbLabel"),
               bytes < 1024 * 1024
                   ? QStringLiteral("%1 KB").arg(qMax(1, int(bytes / 1024)))
                   : QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1));
    out.insert(QStringLiteral("zoomReduced"), zoomReduced);
    out.insert(QStringLiteral("overBudget"), overBudget && zoomReduced);
    return out;
}

QVariantMap BasemapStore::planForPoints(const QVariantList &points, double bufferM) const
{
    return planPack(bufferBBox(bboxFromPoints(points), bufferM),
                    kOverviewMinZoom, kOverviewMaxZoom, kOverviewMinZoom,
                    QStringLiteral("overview"));
}

QVariantMap BasemapStore::planForBbox(double south, double west, double north, double east) const
{
    return planPack({south, west, north, east},
                    kOverviewMinZoom, kOverviewMaxZoom, kOverviewMinZoom,
                    QStringLiteral("overview"));
}

QVariantMap BasemapStore::planDetailAround(double lat, double lon, double radiusM) const
{
    if (!qIsFinite(lat) || !qIsFinite(lon)) {
        QVariantMap out;
        out.insert(QStringLiteral("ok"), false);
        out.insert(QStringLiteral("error"), QStringLiteral("Need a GPS fix for cab detail."));
        return out;
    }
    const double r = radiusM > 0 ? radiusM : kDefaultDetailRadiusM;
    return planPack(bufferBBox({lat, lon, lat, lon}, r),
                    kDetailMinZoom, kDetailMaxZoom, kDetailMinZoom,
                    QStringLiteral("detail"));
}

bool BasemapStore::coversBbox(double south, double west, double north, double east) const
{
    for (const Pack &p : m_packs) {
        // Detail patches must not suppress the overview download prompt.
        if (p.kind == QLatin1String("detail"))
            continue;
        if (p.bbox.south <= south && p.bbox.west <= west
            && p.bbox.north >= north && p.bbox.east >= east)
            return true;
    }
    return false;
}

void BasemapStore::suggestForPoints(const QString &packId, const QString &label,
                                    const QVariantList &points, double bufferM)
{
    QVariantMap plan = planForPoints(points, bufferM);
    if (!plan.value(QStringLiteral("ok")).toBool()) {
        m_pendingPrompt.clear();
        emit pendingPromptChanged();
        return;
    }
    if (coversBbox(plan.value(QStringLiteral("south")).toDouble(),
                   plan.value(QStringLiteral("west")).toDouble(),
                   plan.value(QStringLiteral("north")).toDouble(),
                   plan.value(QStringLiteral("east")).toDouble())) {
        m_pendingPrompt.clear();
        emit pendingPromptChanged();
        return;
    }
    plan.insert(QStringLiteral("packId"),
                packId.isEmpty()
                    ? QStringLiteral("field-%1").arg(QDateTime::currentMSecsSinceEpoch())
                    : packId);
    plan.insert(QStringLiteral("label"),
                label.isEmpty() ? QStringLiteral("Field imagery") : label);
    m_pendingPrompt = plan;
    emit pendingPromptChanged();
}

void BasemapStore::clearPendingPrompt()
{
    if (m_pendingPrompt.isEmpty())
        return;
    m_pendingPrompt.clear();
    emit pendingPromptChanged();
}

void BasemapStore::acceptPendingPrompt()
{
    if (m_pendingPrompt.isEmpty())
        return;
    const QVariantMap p = m_pendingPrompt;
    m_pendingPrompt.clear();
    emit pendingPromptChanged();
    startDownload(p.value(QStringLiteral("packId")).toString(),
                  p.value(QStringLiteral("label")).toString(),
                  p.value(QStringLiteral("south")).toDouble(),
                  p.value(QStringLiteral("west")).toDouble(),
                  p.value(QStringLiteral("north")).toDouble(),
                  p.value(QStringLiteral("east")).toDouble());
}

void BasemapStore::startDownload(const QString &packId, const QString &label,
                                 double south, double west, double north, double east)
{
    BBox b{south, west, north, east};
    QVariantMap plan = planPack(b, kOverviewMinZoom, kOverviewMaxZoom, kOverviewMinZoom,
                                QStringLiteral("overview"));
    if (!plan.value(QStringLiteral("ok")).toBool()) {
        if (m_downloading)
            return;
        m_error = plan.value(QStringLiteral("error")).toString();
        emit downloadChanged();
        emit downloadFinished(false);
        return;
    }
    startDownloadRange(packId, label, b,
                       plan.value(QStringLiteral("minZoom")).toInt(),
                       plan.value(QStringLiteral("maxZoom")).toInt(),
                       QStringLiteral("overview"));
}

void BasemapStore::startDetailDownload(const QString &packId, const QString &label,
                                       double lat, double lon, double radiusM)
{
    QVariantMap plan = planDetailAround(lat, lon, radiusM);
    if (!plan.value(QStringLiteral("ok")).toBool()) {
        if (m_downloading)
            return;
        m_error = plan.value(QStringLiteral("error")).toString();
        emit downloadChanged();
        emit downloadFinished(false);
        return;
    }
    const BBox b{plan.value(QStringLiteral("south")).toDouble(),
                 plan.value(QStringLiteral("west")).toDouble(),
                 plan.value(QStringLiteral("north")).toDouble(),
                 plan.value(QStringLiteral("east")).toDouble()};
    const QString id = packId.isEmpty()
                           ? QStringLiteral("detail-%1").arg(QDateTime::currentMSecsSinceEpoch())
                           : (packId.endsWith(QLatin1String("-detail"))
                                  ? packId
                                  : packId + QStringLiteral("-detail"));
    const QString lbl = label.isEmpty()
                            ? QStringLiteral("Cab detail")
                            : (label.contains(QStringLiteral("detail"), Qt::CaseInsensitive)
                                   ? label
                                   : label + QStringLiteral(" (detail)"));
    startDownloadRange(id, lbl, b,
                       plan.value(QStringLiteral("minZoom")).toInt(),
                       plan.value(QStringLiteral("maxZoom")).toInt(),
                       QStringLiteral("detail"));
}

void BasemapStore::startDownloadRange(const QString &packId, const QString &label,
                                      const BBox &b, int minZ, int maxZ,
                                      const QString &kind)
{
    if (m_downloading)
        return;
    if (!b.valid() || minZ > maxZ) {
        m_error = QStringLiteral("Invalid download area");
        emit downloadChanged();
        emit downloadFinished(false);
        return;
    }
    m_dlMinZ = minZ;
    m_dlMaxZ = maxZ;
    m_dlBBox = b;
    m_dlKind = kind;
    m_dlPackId = packId.isEmpty()
                     ? QStringLiteral("pack-%1").arg(QDateTime::currentMSecsSinceEpoch())
                     : packId;
    m_dlLabel = label.isEmpty() ? m_dlPackId : label;
    // Only clear the zoom band this pack owns — keep the other tier intact.
    const int cleared = clearTilesInBBox(b, minZ, maxZ);
    if (cleared > 0)
        qWarning("[basemap] cleared %d old tiles (z%d–%d, %s) before download",
                 cleared, minZ, maxZ, qUtf8Printable(kind));
    m_dlQueue = enumerateTiles(b, m_dlMinZ, m_dlMaxZ);
    m_dlDone = 0;
    m_dlOk = 0;
    m_dlFail = 0;
    m_dlSkip = 0;
    m_dlTotal = m_dlQueue.size();
    m_dlBytes = 0;
    m_cancel = false;
    m_error.clear();
    m_downloading = true;
    if (!m_sslAvailable && m_dlTotal > 0) {
        m_error = QStringLiteral("HTTPS unavailable on this build (OpenSSL missing). Redeploy required.");
        m_status = m_error;
        emit downloadChanged();
        finishDownload(false, m_error);
        return;
    }
    m_status = QStringLiteral("Downloading %1 %2 tiles (z%3–%4)…")
                   .arg(m_dlTotal)
                   .arg(kind)
                   .arg(m_dlMinZ)
                   .arg(m_dlMaxZ);
    emit downloadChanged();
    ++m_packRevision;
    emit packsChanged();
    pumpDownload();
}

void BasemapStore::cancelDownload()
{
    if (!m_downloading)
        return;
    m_cancel = true;
    if (m_reply) {
        m_reply->abort();
    }
}

void BasemapStore::finishDownload(bool ok, const QString &err)
{
    m_downloading = false;
    m_inFlight = 0;
    m_reply = nullptr;
    m_dlQueue.clear();
    if (ok) {
        m_status = QStringLiteral("Download complete");
        m_error.clear();
    } else {
        m_status = QStringLiteral("Download failed");
        m_error = err;
    }
    emit downloadChanged();
    emit downloadFinished(ok);
}

void BasemapStore::pumpDownload()
{
    if (m_cancel) {
        finishDownload(false, QStringLiteral("Cancelled"));
        return;
    }
    while (m_inFlight < kMaxInFlight && !m_dlQueue.isEmpty()) {
        const TileCoord t = m_dlQueue.takeFirst();
        const QString path = tileFile(t.z, t.x, t.y);
        QDir().mkpath(QFileInfo(path).absolutePath());

        QNetworkRequest req{QUrl(tileUrl(t.z, t.x, t.y))};
        req.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("PUF-mobile/1.0 (offline basemap; cab guidance)"));
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

        QNetworkReply *reply = m_nam.get(req);
        ++m_inFlight;
        m_reply = reply;
        connect(reply, &QNetworkReply::finished, this, [this, reply, t, path]() {
            --m_inFlight;
            if (m_reply == reply)
                m_reply = nullptr;
            const bool aborted = reply->error() == QNetworkReply::OperationCanceledError;
            bool wrote = false;
            bool placeholder = false;
            if (!aborted && reply->error() == QNetworkReply::NoError) {
                const QByteArray data = reply->readAll();
                // Esri JPEG starts FF D8; reject empty / HTML error bodies.
                const bool looksJpeg = data.size() > 128
                        && uchar(data.at(0)) == 0xFF && uchar(data.at(1)) == 0xD8;
                if (looksJpeg && data.size() < kMinRealTileBytes) {
                    // Rural WA often has no Maxar at z18+ — Esri still returns a
                    // tiny JPEG that paints "Map data not yet available".
                    placeholder = true;
                    if (QFile::exists(path))
                        QFile::remove(path);
                } else if (looksJpeg) {
                    QFile f(path);
                    if (f.open(QIODevice::WriteOnly)) {
                        f.write(data);
                        f.close();
                        m_dlBytes += data.size();
                        wrote = true;
                    }
                }
            } else if (!aborted && m_dlFail < 3) {
                qWarning("[basemap] tile z=%d x=%d y=%d err=%s",
                         t.z, t.x, t.y, qUtf8Printable(reply->errorString()));
            }
            if (wrote)
                ++m_dlOk;
            else if (placeholder)
                ++m_dlSkip;
            else if (!aborted)
                ++m_dlFail;
            reply->deleteLater();
            ++m_dlDone;
            if ((m_dlDone % 8) == 0 || m_dlDone >= m_dlTotal) {
                m_status = QStringLiteral("%1 / %2 tiles (%3 ok%4)")
                               .arg(m_dlDone)
                               .arg(m_dlTotal)
                               .arg(m_dlOk)
                               .arg(m_dlSkip > 0
                                        ? QStringLiteral(", %1 no imagery").arg(m_dlSkip)
                                        : QString());
                emit downloadChanged();
            }
            if (m_cancel) {
                if (m_inFlight == 0)
                    finishDownload(false, QStringLiteral("Cancelled"));
                return;
            }
            if (m_dlDone >= m_dlTotal && m_inFlight == 0) {
                // Placeholders don't count against the success ratio.
                const int judged = m_dlOk + m_dlFail;
                const int needOk = qMax(1, int(qCeil(qMax(1, judged) * kMinSuccessRatio)));
                if (m_dlOk < needOk) {
                    finishDownload(false,
                        QStringLiteral("Download incomplete — %1 of %2 tiles saved. Keep Wi‑Fi and retry.")
                            .arg(m_dlOk).arg(m_dlTotal));
                    return;
                }
                Pack p;
                p.id = m_dlPackId;
                p.label = m_dlLabel;
                p.kind = m_dlKind.isEmpty() ? QStringLiteral("overview") : m_dlKind;
                p.bbox = m_dlBBox;
                p.minZoom = m_dlMinZ;
                p.maxZoom = m_dlMaxZ;
                p.tileCount = m_dlOk;
                p.bytes = m_dlBytes;
                p.createdAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
                if (Pack *existing = findPack(p.id))
                    *existing = p;
                else
                    m_packs.append(p);
                ++m_packRevision;
                savePacks();
                emit packsChanged();
                finishDownload(true, {});
                return;
            }
            pumpDownload();
        });
    }
}

int BasemapStore::clearTilesInBBox(const BBox &b, int minZ, int maxZ)
{
    if (!b.valid() || minZ > maxZ)
        return 0;
    int removed = 0;
    const QVector<TileCoord> tiles = enumerateTiles(b, minZ, maxZ);
    for (const TileCoord &t : tiles) {
        const QString path = tileFile(t.z, t.x, t.y);
        if (QFile::exists(path) && QFile::remove(path))
            ++removed;
    }
    return removed;
}

int BasemapStore::purgePlaceholderTiles() const
{
    int removed = 0;
    QDirIterator it(rootDir() + QStringLiteral("/tiles"),
                    QStringList() << QStringLiteral("*.jpg"),
                    QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        if (QFileInfo(path).size() < kMinRealTileBytes && QFile::remove(path))
            ++removed;
    }
    return removed;
}

void BasemapStore::deletePack(const QString &packId)
{
    for (int i = 0; i < m_packs.size(); ++i) {
        if (m_packs[i].id != packId)
            continue;
        const Pack p = m_packs.takeAt(i);
        // Only remove this pack's zoom band so the other tier survives.
        clearTilesInBBox(p.bbox, p.minZoom, p.maxZoom);
        ++m_packRevision;
        savePacks();
        emit packsChanged();
        m_status = QStringLiteral("Cleared map pack");
        emit downloadChanged();
        return;
    }
}

void BasemapStore::clearAllMaps()
{
    if (m_downloading)
        cancelDownload();
    for (const Pack &p : m_packs)
        clearTilesInBBox(p.bbox, p.minZoom, p.maxZoom);
    // Also wipe any orphan tiles left from failed / renamed packs.
    const QString tilesRoot = rootDir() + QStringLiteral("/tiles");
    QDir(tilesRoot).removeRecursively();
    QDir().mkpath(tilesRoot);
    m_packs.clear();
    ++m_packRevision;
    savePacks();
    m_status = QStringLiteral("All offline maps cleared");
    m_error.clear();
    emit packsChanged();
    emit downloadChanged();
}

void BasemapStore::searchLocation(const QString &query)
{
    const QString q = query.trimmed();
    if (q.isEmpty()) {
        m_searchResults.clear();
        emit searchChanged();
        return;
    }
    if (m_searching)
        return;
    m_searching = true;
    m_searchResults.clear();
    emit searchChanged();

    QUrl url(QStringLiteral("https://nominatim.openstreetmap.org/search"));
    QUrlQuery qq;
    qq.addQueryItem(QStringLiteral("format"), QStringLiteral("json"));
    qq.addQueryItem(QStringLiteral("limit"), QStringLiteral("6"));
    qq.addQueryItem(QStringLiteral("q"), q);
    url.setQuery(qq);

    QNetworkRequest req{url};
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("PUF-mobile/1.0 (offline basemap; workshop)"));
    req.setRawHeader("Accept", "application/json");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        m_searching = false;
        m_searchResults.clear();
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            const QJsonArray arr = doc.array();
            for (const QJsonValue &v : arr) {
                const QJsonObject o = v.toObject();
                QVariantMap m;
                m.insert(QStringLiteral("label"), o.value(QStringLiteral("display_name")).toString());
                m.insert(QStringLiteral("lat"), o.value(QStringLiteral("lat")).toString().toDouble());
                m.insert(QStringLiteral("lon"), o.value(QStringLiteral("lon")).toString().toDouble());
                const QJsonArray bb = o.value(QStringLiteral("boundingbox")).toArray();
                if (bb.size() == 4) {
                    // Nominatim: south, north, west, east
                    const double south = bb.at(0).toString().toDouble();
                    const double north = bb.at(1).toString().toDouble();
                    const double west = bb.at(2).toString().toDouble();
                    const double east = bb.at(3).toString().toDouble();
                    const BBox buffered = bufferBBox({south, west, north, east}, 3000.0);
                    m.insert(QStringLiteral("south"), buffered.south);
                    m.insert(QStringLiteral("west"), buffered.west);
                    m.insert(QStringLiteral("north"), buffered.north);
                    m.insert(QStringLiteral("east"), buffered.east);
                } else {
                    const double lat = m.value(QStringLiteral("lat")).toDouble();
                    const double lon = m.value(QStringLiteral("lon")).toDouble();
                    const BBox sq = bufferBBox({lat, lon, lat, lon}, 4000.0);
                    m.insert(QStringLiteral("south"), sq.south);
                    m.insert(QStringLiteral("west"), sq.west);
                    m.insert(QStringLiteral("north"), sq.north);
                    m.insert(QStringLiteral("east"), sq.east);
                }
                m_searchResults.append(m);
            }
        } else {
            m_error = reply->errorString();
            emit downloadChanged();
        }
        reply->deleteLater();
        emit searchChanged();
    });
}

void BasemapStore::clearSearch()
{
    m_searchResults.clear();
    emit searchChanged();
}

QVariantList BasemapStore::visibleTiles(double south, double west,
                                        double north, double east,
                                        double metresPerPixel,
                                        int maxTiles) const
{
    QVariantList out;
    if (!(north > south && east > west) || metresPerPixel <= 0)
        return out;

    // Ground resolution at zoom z (equator) ≈ 156543.03 / 2^z metres per
    // *tile pixel*. Match that to screen metres-per-pixel so one tile pixel ≈
    // one screen pixel. (An earlier /256 here picked zooms ~8 levels too soft.)
    const double zf = qLn(156543.03392 / metresPerPixel) / qLn(2.0);
    // Prefer three levels sharper than ideal (tablet DPR / cab clarity).
    const int ideal = qBound(kDisplayMinZoom, kDisplayMaxZoom, int(qRound(zf)) + 3);

    auto collectAtZoom = [&](int tryZ, int *neededOut) -> QVariantList {
        QVariantList found;
        const auto coords = enumerateTiles({south, west, north, east}, tryZ, tryZ);
        if (neededOut)
            *neededOut = coords.size();
        for (const TileCoord &t : coords) {
            const QString path = tileFile(t.z, t.x, t.y);
            const QFileInfo fi(path);
            // Skip Esri placeholders so display falls back to real coarser tiles.
            if (!fi.exists() || fi.size() < kMinRealTileBytes)
                continue;
            double ts, tw, tn, te;
            tileLatLonBounds(t.z, t.x, t.y, &ts, &tw, &tn, &te);
            QVariantMap m;
            m.insert(QStringLiteral("z"), t.z);
            m.insert(QStringLiteral("x"), t.x);
            m.insert(QStringLiteral("y"), t.y);
            m.insert(QStringLiteral("south"), ts);
            m.insert(QStringLiteral("west"), tw);
            m.insert(QStringLiteral("north"), tn);
            m.insert(QStringLiteral("east"), te);
            m.insert(QStringLiteral("path"), QUrl::fromLocalFile(path).toString());
            found.append(m);
            if (found.size() >= maxTiles)
                break;
        }
        return found;
    };

    auto coverageOk = [](int found, int needed) -> bool {
        if (needed <= 0 || found <= 0)
            return false;
        // Cap truncates found — treat "hit the cap" as full enough.
        if (found >= needed)
            return true;
        return double(found) / double(needed) >= kMinCoverage;
    };

    // Prefer ideal (sharp) when coverage is good; else fall back to coarser
    // overview so cab zoom never blanks on a sparse high-z strip.
    for (int tryZ = ideal; tryZ >= kDisplayMinZoom; --tryZ) {
        int needed = 0;
        const QVariantList found = collectAtZoom(tryZ, &needed);
        if (coverageOk(found.size(), needed))
            return found;
    }
    for (int tryZ = ideal + 1; tryZ <= kDisplayMaxZoom; ++tryZ) {
        int needed = 0;
        const QVariantList found = collectAtZoom(tryZ, &needed);
        if (coverageOk(found.size(), needed))
            return found;
    }
    // Last resort: anything on disk (better than blank ground).
    for (int tryZ = ideal; tryZ >= kDisplayMinZoom; --tryZ) {
        int needed = 0;
        const QVariantList found = collectAtZoom(tryZ, &needed);
        if (!found.isEmpty())
            return found;
    }
    return out;
}

void BasemapStore::loadPacks()
{
    m_packs.clear();
    QFile f(packsPath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    const QJsonArray arr = doc.object().value(QStringLiteral("packs")).toArray();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Pack p;
        p.id = o.value(QStringLiteral("id")).toString();
        p.label = o.value(QStringLiteral("label")).toString();
        p.kind = o.value(QStringLiteral("kind")).toString();
        p.bbox.south = o.value(QStringLiteral("south")).toDouble();
        p.bbox.west = o.value(QStringLiteral("west")).toDouble();
        p.bbox.north = o.value(QStringLiteral("north")).toDouble();
        p.bbox.east = o.value(QStringLiteral("east")).toDouble();
        p.minZoom = o.value(QStringLiteral("minZoom")).toInt(kOverviewMinZoom);
        p.maxZoom = o.value(QStringLiteral("maxZoom")).toInt(kOverviewMaxZoom);
        p.tileCount = o.value(QStringLiteral("tileCount")).toInt();
        p.bytes = qint64(o.value(QStringLiteral("bytes")).toDouble());
        p.createdAt = o.value(QStringLiteral("createdAt")).toString();
        if (p.kind.isEmpty()) {
            // Legacy packs that reached z17+ were "all-in-one"; treat as overview
            // for listing, but keep their zoom range so delete clears the right band.
            p.kind = (p.maxZoom >= kDetailMinZoom && p.minZoom >= kDetailMinZoom)
                         ? QStringLiteral("detail")
                         : QStringLiteral("overview");
        }
        if (!p.id.isEmpty() && p.bbox.valid())
            m_packs.append(p);
    }
}

void BasemapStore::savePacks() const
{
    QDir().mkpath(rootDir());
    QJsonArray arr;
    for (const Pack &p : m_packs) {
        QJsonObject o;
        o.insert(QStringLiteral("id"), p.id);
        o.insert(QStringLiteral("label"), p.label);
        o.insert(QStringLiteral("kind"), p.kind);
        o.insert(QStringLiteral("south"), p.bbox.south);
        o.insert(QStringLiteral("west"), p.bbox.west);
        o.insert(QStringLiteral("north"), p.bbox.north);
        o.insert(QStringLiteral("east"), p.bbox.east);
        o.insert(QStringLiteral("minZoom"), p.minZoom);
        o.insert(QStringLiteral("maxZoom"), p.maxZoom);
        o.insert(QStringLiteral("tileCount"), p.tileCount);
        o.insert(QStringLiteral("bytes"), double(p.bytes));
        o.insert(QStringLiteral("createdAt"), p.createdAt);
        arr.append(o);
    }
    QJsonObject root;
    root.insert(QStringLiteral("packs"), arr);
    root.insert(QStringLiteral("source"), QStringLiteral("esri-world-imagery"));
    QFile f(packsPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

BasemapStore::Pack *BasemapStore::findPack(const QString &id)
{
    for (Pack &p : m_packs) {
        if (p.id == id)
            return &p;
    }
    return nullptr;
}

const BasemapStore::Pack *BasemapStore::findPack(const QString &id) const
{
    for (const Pack &p : m_packs) {
        if (p.id == id)
            return &p;
    }
    return nullptr;
}
