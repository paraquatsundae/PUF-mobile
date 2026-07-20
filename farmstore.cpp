#include "farmstore.h"
#include "taskdata.h"
#include "kmlimport.h"
#include "gpsmodel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QUuid>
#include <QDateTime>
#include <QSet>
#include <QVariantMap>
#include <QtMath>
#include <cmath>

#ifdef Q_OS_ANDROID
#include <QtAndroid>
#endif

FarmStore::FarmStore(QObject *parent) : QObject(parent) {}

// Locate a TASKDATA.XML inside dir, a "TASKDATA" subfolder, or any immediate
// subfolder (JD often nests as <Export>/TASKDATA/TASKDATA.XML).
static QString findTaskDataXml(const QString &dir)
{
    const QStringList names = QStringList()
        << QStringLiteral("TASKDATA.XML") << QStringLiteral("Taskdata.xml")
        << QStringLiteral("taskdata.xml") << QStringLiteral("TaskData.xml");
    QDir d(dir);
    for (const QString &n : names)
        if (d.exists(n)) return d.absoluteFilePath(n);
    const auto subs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &sub : subs) {
        QDir s(d.absoluteFilePath(sub));
        for (const QString &n : names)
            if (s.exists(n)) return s.absoluteFilePath(n);
    }
    return QString();
}

static QString normPath(const QString &path)
{
    return QDir::cleanPath(path);
}

static bool isAllowedBrowsePath(const QString &path)
{
#ifdef Q_OS_ANDROID
    const QString norm = normPath(path);
    return norm.startsWith(QStringLiteral("/storage/emulated/0"))
        || norm.startsWith(QStringLiteral("/storage/emulated/legacy"));
#else
    Q_UNUSED(path);
    return true;
#endif
}

static QString importKindForPath(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.exists())
        return QString();
    if (fi.isDir())
        return findTaskDataXml(path).isEmpty() ? QStringLiteral("dir")
                                               : QStringLiteral("isoxml_folder");
    const QString low = fi.suffix().toLower();
    if (low == QStringLiteral("xml"))
        return QStringLiteral("isoxml_xml");
    if (low == QStringLiteral("kml"))
        return QStringLiteral("kml");
    return QString();
}

static QString stagingDestFor(const QString &farmData, const QString &sourcePath, const QString &kind)
{
    const QFileInfo fi(sourcePath);
    if (kind == QStringLiteral("isoxml_folder"))
        return normPath(farmData + QLatin1Char('/') + fi.fileName());
    if (kind == QStringLiteral("isoxml_xml") || kind == QStringLiteral("kml"))
        return normPath(farmData + QLatin1Char('/') + fi.fileName());
    return QString();
}

static bool copyPathRecursive(const QString &src, const QString &dest, bool overwrite)
{
    const QFileInfo sfi(src);
    if (!sfi.exists())
        return false;
    if (sfi.isFile()) {
        if (QFileInfo::exists(dest)) {
            if (!overwrite)
                return false;
            QFile::remove(dest);
        }
        return QFile::copy(src, dest);
    }
    QDir destDir(dest);
    if (destDir.exists()) {
        if (!overwrite)
            return false;
        destDir.removeRecursively();
    }
    if (!QDir().mkpath(dest))
        return false;
    const QDir srcDir(src);
    const auto entries = srcDir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot);
    for (const QString &e : entries) {
        if (!copyPathRecursive(srcDir.absoluteFilePath(e), destDir.absoluteFilePath(e), true))
            return false;
    }
    return true;
}

static bool movePathTo(const QString &src, const QString &dest, bool overwrite)
{
    if (QFileInfo(src).isFile()) {
        if (QFile::rename(src, dest))
            return true;
    } else if (QDir().rename(src, dest))
        return true;
    if (!copyPathRecursive(src, dest, overwrite))
        return false;
    if (QFileInfo(src).isFile())
        return QFile::remove(src);
    return QDir(src).removeRecursively();
}

static QVariantList paddockConflicts(const QVector<Client> &existing, const QVector<Client> &imported)
{
    auto key = [](const QString &c, const QString &f, const QString &fd) {
        return c.trimmed().toLower() + QLatin1Char('|') + f.trimmed().toLower() + QLatin1Char('|')
               + fd.trimmed().toLower();
    };
    QSet<QString> existingKeys;
    for (const Client &c : existing) {
        for (const Farm &f : c.farms) {
            for (const Field &fd : f.fields)
                existingKeys.insert(key(c.name, f.name, fd.name));
        }
    }
    QVariantList conflicts;
    for (const Client &c : imported) {
        for (const Farm &f : c.farms) {
            for (const Field &fd : f.fields) {
                if (!existingKeys.contains(key(c.name, f.name, fd.name)))
                    continue;
                QVariantMap m;
                m.insert(QStringLiteral("client"), c.name);
                m.insert(QStringLiteral("farm"), f.name);
                m.insert(QStringLiteral("field"), fd.name);
                conflicts.append(m);
            }
        }
    }
    return conflicts;
}

// ---- lookups ----
Client *FarmStore::findClient(const QString &id)
{
    for (Client &c : m_clients)
        if (c.id == id) return &c;
    return nullptr;
}

Farm *FarmStore::findFarm(const QString &id)
{
    for (Client &c : m_clients)
        for (Farm &f : c.farms)
            if (f.id == id) return &f;
    return nullptr;
}

Field *FarmStore::findField(const QString &id)
{
    for (Client &c : m_clients)
        for (Farm &f : c.farms)
            for (Field &fd : f.fields)
                if (fd.id == id) return &fd;
    return nullptr;
}

Field *FarmStore::activeField()
{
    if (m_activeFieldId.isEmpty()) return nullptr;
    return findField(m_activeFieldId);
}

const Field *FarmStore::activeField() const
{
    return const_cast<FarmStore *>(this)->activeField();
}

double FarmStore::areaHaOf(const QVector<GeoPt> &ring)
{
    if (ring.size() < 3) return 0.0;
    const double k = 111320.0;
    const double cosLat = qCos(qDegreesToRadians(ring.first().lat));
    double sum = 0.0;
    const int n = ring.size();
    for (int i = 0; i < n; ++i) {
        const GeoPt &p = ring.at(i);
        const GeoPt &q = ring.at((i + 1) % n);
        const double x1 = (p.lon - ring.first().lon) * k * cosLat;
        const double y1 = (p.lat - ring.first().lat) * k;
        const double x2 = (q.lon - ring.first().lon) * k * cosLat;
        const double y2 = (q.lat - ring.first().lat) * k;
        sum += (x1 * y2 - x2 * y1);
    }
    return qFabs(sum) / 2.0 / 10000.0;
}

double FarmStore::pointDistM(double lat1, double lon1, double lat2, double lon2)
{
    const double k = 111320.0;
    const double dLat = (lat2 - lat1) * k;
    const double cosLat = qCos(qDegreesToRadians(lat1));
    const double dLon = (lon2 - lon1) * k * (cosLat != 0.0 ? cosLat : 1e-9);
    return qSqrt(dLat * dLat + dLon * dLon);
}

double FarmStore::boundaryDraftAreaHa() const
{
    return areaHaOf(m_boundaryDraft);
}

QVariantList FarmStore::boundaryDraftPoints() const
{
    QVariantList out;
    out.reserve(m_boundaryDraft.size());
    for (const GeoPt &p : m_boundaryDraft) {
        QVariantMap m;
        m[QStringLiteral("lat")] = p.lat;
        m[QStringLiteral("lon")] = p.lon;
        out.append(m);
    }
    return out;
}

QVariantList FarmStore::archivedBoundaries() const
{
    QVariantList out;
    const Field *f = activeField();
    if (!f)
        return out;
    const auto it = m_boundaryArchives.constFind(f->id);
    if (it == m_boundaryArchives.constEnd())
        return out;
    for (const ArchivedBoundary &ab : *it) {
        QVariantMap m;
        m[QStringLiteral("id")] = ab.id;
        m[QStringLiteral("archivedUtc")] = ab.archivedUtc;
        m[QStringLiteral("areaHa")] = ab.areaHa;
        m[QStringLiteral("pointCount")] = ab.ring.size();
        out.append(m);
    }
    return out;
}

QString FarmStore::archivesPath() const
{
    return QFileInfo(storagePath()).absolutePath() + QStringLiteral("/boundary_archives.json");
}

void FarmStore::loadArchives()
{
    m_boundaryArchives.clear();
    QFile f(archivesPath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;
    const QJsonObject root = doc.object();
    const QJsonObject fields = root.value(QStringLiteral("fields")).toObject();
    for (auto it = fields.begin(); it != fields.end(); ++it) {
        if (!it.value().isArray())
            continue;
        QVector<ArchivedBoundary> list;
        const QJsonArray arr = it.value().toArray();
        for (const QJsonValue &v : arr) {
            if (!v.isObject())
                continue;
            const QJsonObject o = v.toObject();
            ArchivedBoundary ab;
            ab.id = o.value(QStringLiteral("id")).toString();
            ab.archivedUtc = o.value(QStringLiteral("archivedUtc")).toString();
            ab.areaHa = o.value(QStringLiteral("areaHa")).toDouble();
            const QJsonArray ring = o.value(QStringLiteral("ring")).toArray();
            for (const QJsonValue &pv : ring) {
                if (!pv.isObject())
                    continue;
                const QJsonObject po = pv.toObject();
                GeoPt p;
                p.lat = po.value(QStringLiteral("lat")).toDouble();
                p.lon = po.value(QStringLiteral("lon")).toDouble();
                ab.ring.append(p);
            }
            if (!ab.id.isEmpty() && ab.ring.size() >= 3)
                list.append(ab);
        }
        if (!list.isEmpty())
            m_boundaryArchives.insert(it.key(), list);
    }
}

void FarmStore::saveArchives()
{
    QJsonObject root;
    QJsonObject fields;
    for (auto it = m_boundaryArchives.constBegin(); it != m_boundaryArchives.constEnd(); ++it) {
        QJsonArray arr;
        for (const ArchivedBoundary &ab : it.value()) {
            QJsonObject o;
            o[QStringLiteral("id")] = ab.id;
            o[QStringLiteral("archivedUtc")] = ab.archivedUtc;
            o[QStringLiteral("areaHa")] = ab.areaHa;
            QJsonArray ring;
            for (const GeoPt &p : ab.ring) {
                QJsonObject po;
                po[QStringLiteral("lat")] = p.lat;
                po[QStringLiteral("lon")] = p.lon;
                ring.append(po);
            }
            o[QStringLiteral("ring")] = ring;
            arr.append(o);
        }
        fields[it.key()] = arr;
    }
    root[QStringLiteral("fields")] = fields;
    const QString path = archivesPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

void FarmStore::appendLinePoints(QVector<GeoPt> &draft, double lat1, double lon1,
                                 double lat2, double lon2, double stepM)
{
    const double total = pointDistM(lat1, lon1, lat2, lon2);
    if (total < 0.01)
        return;
    const int steps = qMax(1, static_cast<int>(total / stepM));
    for (int i = 1; i <= steps; ++i) {
        const double t = static_cast<double>(i) / steps;
        GeoPt p;
        p.lat = lat1 + t * (lat2 - lat1);
        p.lon = lon1 + t * (lon2 - lon1);
        if (!draft.isEmpty()) {
            const GeoPt &last = draft.last();
            if (pointDistM(last.lat, last.lon, p.lat, p.lon) < stepM * 0.5)
                continue;
        }
        draft.append(p);
    }
}

// ---- list models for QML ----
QVariantList FarmStore::clients() const
{
    QVariantList out;
    for (const Client &c : m_clients) {
        QVariantMap m;
        m["id"] = c.id;
        m["name"] = c.name;
        m["farmCount"] = c.farms.size();
        m["active"] = (c.id == m_activeClientId);
        out.append(m);
    }
    return out;
}

QVariantList FarmStore::farms() const
{
    QVariantList out;
    for (const Client &c : m_clients) {
        if (c.id != m_browseClientId) continue;
        for (const Farm &f : c.farms) {
            QVariantMap m;
            m["id"] = f.id;
            m["name"] = f.name;
            m["fieldCount"] = f.fields.size();
            m["active"] = (f.id == m_activeFarmId);
            out.append(m);
        }
    }
    return out;
}

QVariantList FarmStore::fields() const
{
    QVariantList out;
    for (const Client &c : m_clients) {
        if (c.id != m_browseClientId) continue;
        for (const Farm &f : c.farms) {
            if (f.id != m_browseFarmId) continue;
            for (const Field &fd : f.fields) {
                QVariantMap m;
                m["id"] = fd.id;
                m["name"] = fd.name;
                m["areaHa"] = fd.areaHa;
                m["boundaryCount"] = fd.boundary.size();
                m["abCount"] = fd.abLines.size();
                m["active"] = (fd.id == m_activeFieldId);
                out.append(m);
            }
        }
    }
    return out;
}

QString FarmStore::activeFieldName() const
{
    const Field *f = activeField();
    return f ? f->name : QString();
}

QString FarmStore::activeFarmName() const
{
    for (const Client &c : m_clients)
        for (const Farm &f : c.farms)
            if (f.id == m_activeFarmId) return f.name;
    return QString();
}

QString FarmStore::activeClientName() const
{
    for (const Client &c : m_clients)
        if (c.id == m_activeClientId) return c.name;
    return QString();
}

double FarmStore::activeAreaHa() const
{
    const Field *f = activeField();
    return f ? f->areaHa : 0.0;
}

int FarmStore::boundaryCount() const
{
    const Field *f = activeField();
    return f ? f->boundary.size() : 0;
}

int FarmStore::abCount() const
{
    const Field *f = activeField();
    return f ? f->abLines.size() : 0;
}

QString FarmStore::abLineName() const
{
    const Field *f = activeField();
    if (!f || f->selectedAb < 0 || f->selectedAb >= f->abLines.size())
        return QString();
    return f->abLines.at(f->selectedAb).name;
}

QVariantList FarmStore::activeBoundary() const
{
    QVariantList out;
    const Field *f = activeField();
    if (!f) return out;
    for (const GeoPt &p : f->boundary) {
        QVariantMap m;
        m["lat"] = p.lat;
        m["lon"] = p.lon;
        out.append(m);
    }
    return out;
}

QVariantList FarmStore::activeAbLines() const
{
    QVariantList out;
    const Field *f = activeField();
    if (!f) return out;
    for (int i = 0; i < f->abLines.size(); ++i) {
        const AbLine &ab = f->abLines.at(i);
        QVariantMap m;
        m["index"] = i;
        m["id"] = ab.id;
        m["name"] = ab.name;
        m["aLat"] = ab.a.lat; m["aLon"] = ab.a.lon;
        m["bLat"] = ab.b.lat; m["bLon"] = ab.b.lon;
        m["selected"] = (i == f->selectedAb);
        // Bearing (deg from true north, A->B) + length (m), equirectangular at
        // field scale — for the run-line management page details.
        const double k = 111320.0;
        const double cosLat = qCos(qDegreesToRadians(ab.a.lat));
        const double de = (ab.b.lon - ab.a.lon) * k * cosLat; // east
        const double dn = (ab.b.lat - ab.a.lat) * k;          // north
        double brg = qRadiansToDegrees(qAtan2(de, dn));
        if (brg < 0.0) brg += 360.0;
        m["bearingDeg"] = brg;
        m["lengthM"] = qSqrt(de * de + dn * dn);
        out.append(m);
    }
    return out;
}

// ---- CRUD ----
QString FarmStore::addClient(const QString &name)
{
    Client c;
    c.id = QStringLiteral("CTR%1").arg(++m_ctrSeq);
    c.name = name.trimmed().isEmpty() ? QStringLiteral("Client %1").arg(m_ctrSeq) : name.trimmed();
    m_clients.append(c);
    m_browseClientId = c.id;
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();
    save();
    return c.id;
}

QString FarmStore::addFarm(const QString &clientId, const QString &name)
{
    Client *c = findClient(clientId);
    if (!c) return QString();
    Farm f;
    f.id = QStringLiteral("FRM%1").arg(++m_frmSeq);
    f.name = name.trimmed().isEmpty() ? QStringLiteral("Farm %1").arg(m_frmSeq) : name.trimmed();
    c->farms.append(f);
    m_browseClientId = clientId;
    m_browseFarmId = f.id;
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();
    save();
    return f.id;
}

QString FarmStore::addField(const QString &clientId, const QString &farmId, const QString &name)
{
    Client *c = findClient(clientId);
    if (!c) return QString();
    Farm *fm = nullptr;
    for (Farm &f : c->farms)
        if (f.id == farmId) { fm = &f; break; }
    if (!fm) return QString();
    Field fd;
    fd.id = QStringLiteral("PFD%1").arg(++m_pfdSeq);
    fd.name = name.trimmed().isEmpty() ? QStringLiteral("Field %1").arg(m_pfdSeq) : name.trimmed();
    fm->fields.append(fd);
    m_browseClientId = clientId;
    m_browseFarmId = farmId;
    emit farmsChanged();
    emit fieldsChanged();
    save();
    return fd.id;
}

void FarmStore::renameClient(const QString &id, const QString &name)
{
    if (Client *c = findClient(id)) { c->name = name; emit clientsChanged(); emit activeChanged(); save(); }
}

void FarmStore::renameFarm(const QString &id, const QString &name)
{
    if (Farm *f = findFarm(id)) { f->name = name; emit farmsChanged(); emit activeChanged(); save(); }
}

void FarmStore::renameField(const QString &id, const QString &name)
{
    if (Field *f = findField(id)) { f->name = name; emit fieldsChanged(); emit activeChanged(); save(); }
}

void FarmStore::deleteClient(const QString &id)
{
    for (int i = 0; i < m_clients.size(); ++i) {
        if (m_clients.at(i).id == id) {
            m_clients.removeAt(i);
            if (m_browseClientId == id) m_browseClientId.clear();
            if (m_activeClientId == id) { m_activeClientId.clear(); m_activeFarmId.clear(); m_activeFieldId.clear(); }
            emit clientsChanged(); emit farmsChanged(); emit fieldsChanged(); emit activeChanged(); emit geometryChanged();
            save();
            return;
        }
    }
}

void FarmStore::deleteFarm(const QString &id)
{
    for (Client &c : m_clients) {
        for (int i = 0; i < c.farms.size(); ++i) {
            if (c.farms.at(i).id == id) {
                c.farms.removeAt(i);
                if (m_browseFarmId == id) m_browseFarmId.clear();
                if (m_activeFarmId == id) { m_activeFarmId.clear(); m_activeFieldId.clear(); }
                emit farmsChanged(); emit fieldsChanged(); emit activeChanged(); emit geometryChanged();
                save();
                return;
            }
        }
    }
}

void FarmStore::deleteField(const QString &id)
{
    for (Client &c : m_clients) {
        for (Farm &f : c.farms) {
            for (int i = 0; i < f.fields.size(); ++i) {
                if (f.fields.at(i).id == id) {
                    f.fields.removeAt(i);
                    if (m_activeFieldId == id) m_activeFieldId.clear();
                    emit fieldsChanged(); emit activeChanged(); emit geometryChanged();
                    save();
                    return;
                }
            }
        }
    }
}

void FarmStore::setBrowseClient(const QString &id)
{
    if (id == m_browseClientId) return;
    m_browseClientId = id;
    m_browseFarmId.clear();
    emit farmsChanged();
    emit fieldsChanged();
}

void FarmStore::setBrowseFarm(const QString &id)
{
    if (id == m_browseFarmId) return;
    m_browseFarmId = id;
    emit fieldsChanged();
}

void FarmStore::healOriginFromActiveBoundary()
{
    if (!m_gps)
        return;

    // A live GPS fix owns the origin: never override a real fix, and never
    // touch an already-valid origin while a fix is present.
    const double ola = m_gps->originLat();
    const double olo = m_gps->originLon();
    const bool originValid = m_gps->hasOrigin()
        && std::isfinite(ola) && std::isfinite(olo)
        && ola >= -90.0 && ola <= 90.0 && olo >= -180.0 && olo <= 180.0
        && !(std::abs(ola) < 1e-7 && std::abs(olo) < 1e-7);
    if (m_gps->hasFix() && originValid) {
        qWarning("[bndy] healOrigin skip: live fix origin %.6f,%.6f", ola, olo);
        return;
    }

    const Field *f = activeField();
    const int ringN = f ? f->boundary.size() : 0;
    if (ringN < 3) {
        qWarning("[bndy] healOrigin: active field has no usable ring (count=%d)", ringN);
        return;
    }

    double sLat = 0.0, sLon = 0.0;
    int n = 0;
    for (const GeoPt &p : f->boundary) {
        if (!std::isfinite(p.lat) || !std::isfinite(p.lon))
            continue;
        if (p.lat < -90.0 || p.lat > 90.0 || p.lon < -180.0 || p.lon > 180.0)
            continue;
        if (std::abs(p.lat) < 1e-7 && std::abs(p.lon) < 1e-7)
            continue;
        sLat += p.lat;
        sLon += p.lon;
        ++n;
    }
    if (n < 1) {
        qWarning("[bndy] healOrigin: ring has no in-range lat/lon (count=%d)", ringN);
        return;
    }

    const double cLat = sLat / n;
    const double cLon = sLon / n;
    qWarning("[bndy] healOrigin activate: ring=%d valid=%d centroid=%.6f,%.6f "
             "origin(before)=%.6f,%.6f hasOrigin=%d hasFix=%d",
             ringN, n, cLat, cLon, ola, olo, int(m_gps->hasOrigin()), int(m_gps->hasFix()));
    m_gps->setOrigin(cLat, cLon);
    qWarning("[bndy] healOrigin done: origin(after)=%.6f,%.6f hasOrigin=%d",
             m_gps->originLat(), m_gps->originLon(), int(m_gps->hasOrigin()));
}

void FarmStore::setActiveField(const QString &clientId, const QString &farmId, const QString &fieldId)
{
    m_activeClientId = clientId;
    m_activeFarmId = farmId;
    m_activeFieldId = fieldId;
    // Stop any in-progress capture when switching fields.
    cancelBoundaryRecording();
    clearAbDraft();
    // Deterministically pin the local-frame origin from the (now-active) field's
    // ring before QML maps it. Runs ahead of the signals below so the QML
    // re-entry path (restoreActiveJob) can still override with a saved-job origin
    // when one exists; with no job and no live fix the centroid origin stands.
    healOriginFromActiveBoundary();
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();
    emit activeChanged();
    emit geometryChanged();
}

// ---- AB line capture ----
void FarmStore::markA(double lat, double lon)
{
    m_draftA.lat = lat; m_draftA.lon = lon; m_hasDraftA = true;
    emit draftChanged();
}

void FarmStore::markB(double lat, double lon)
{
    m_draftB.lat = lat; m_draftB.lon = lon; m_hasDraftB = true;
    emit draftChanged();
}

void FarmStore::commitAbLine(const QString &name)
{
    Field *f = activeField();
    if (!f || !m_hasDraftA || !m_hasDraftB) return;
    AbLine ab;
    ab.id = QStringLiteral("GPN%1").arg(++m_gpnSeq);
    ab.name = name.trimmed().isEmpty() ? QStringLiteral("AB %1").arg(m_gpnSeq) : name.trimmed();
    ab.a = m_draftA;
    ab.b = m_draftB;
    f->abLines.append(ab);
    f->selectedAb = f->abLines.size() - 1;
    clearAbDraft();
    emit geometryChanged();
    save();
}

void FarmStore::addAbLineHeading(const QString &name, double latA, double lonA, double headingDeg)
{
    Field *f = activeField();
    if (!f)
        return;
    // Reject non-finite / out-of-range inputs so a bad entry can't poison the
    // local frame or the saved ISOXML.
    if (!std::isfinite(latA) || !std::isfinite(lonA) || !std::isfinite(headingDeg)
        || latA < -90.0 || latA > 90.0 || lonA < -180.0 || lonA > 180.0)
        return;
    const double k = 111320.0;
    const double D = 100.0;                       // baseline length for B (m)
    const double hr = qDegreesToRadians(headingDeg);
    const double cosLat = qCos(qDegreesToRadians(latA));
    const double latB = latA + (D * qCos(hr)) / k;
    const double lonB = lonA + (D * qSin(hr)) / (k * (cosLat != 0.0 ? cosLat : 1e-9));
    AbLine ab;
    ab.id = QStringLiteral("GPN%1").arg(++m_gpnSeq);
    ab.name = name.trimmed().isEmpty() ? QStringLiteral("AB %1").arg(m_gpnSeq) : name.trimmed();
    ab.a.lat = latA; ab.a.lon = lonA;
    ab.b.lat = latB; ab.b.lon = lonB;
    f->abLines.append(ab);
    f->selectedAb = f->abLines.size() - 1;
    emit geometryChanged();
    save();
}

void FarmStore::clearAbDraft()
{
    m_hasDraftA = false;
    m_hasDraftB = false;
    emit draftChanged();
}

void FarmStore::selectAbLine(int index)
{
    Field *f = activeField();
    if (!f) return;
    if (index < -1 || index >= f->abLines.size()) return;
    f->selectedAb = index;
    emit geometryChanged();
    save();
}

void FarmStore::renameAbLine(int index, const QString &name)
{
    Field *f = activeField();
    if (!f || index < 0 || index >= f->abLines.size()) return;
    const QString n = name.trimmed();
    if (n.isEmpty()) return;                 // keep the existing name on a blank
    f->abLines[index].name = n;
    emit geometryChanged();
    save();
}

void FarmStore::deleteAbLine(int index)
{
    Field *f = activeField();
    if (!f || index < 0 || index >= f->abLines.size()) return;
    f->abLines.removeAt(index);
    // Keep the selection valid: clear if the list is now empty, shift down if a
    // line before the selected one was removed, or re-clamp the selected index.
    if (f->abLines.isEmpty())
        f->selectedAb = -1;
    else if (f->selectedAb == index)
        f->selectedAb = qMin(index, f->abLines.size() - 1);
    else if (f->selectedAb > index)
        f->selectedAb -= 1;
    emit geometryChanged();
    save();
}

// ---- boundary capture (ISOXML PLN type 1 / LSG type 1 / PNT) ----
void FarmStore::startBoundaryRecording()
{
    if (!activeField())
        return;
    m_boundaryDraft.clear();
    m_boundaryRecording = true;
    m_boundaryPaused = false;
    m_boundaryResumePending = false;
    m_hasPausePoint = false;
    emit boundaryDraftChanged();
}

void FarmStore::stopBoundaryRecording()
{
    if (!m_boundaryRecording)
        return;
    m_boundaryRecording = false;
    m_boundaryPaused = false;
    m_boundaryResumePending = false;
    emit boundaryDraftChanged();
}

void FarmStore::pauseBoundaryRecording()
{
    if (!m_boundaryRecording || m_boundaryPaused)
        return;
    m_boundaryPaused = true;
    m_boundaryResumePending = false;
    if (!m_boundaryDraft.isEmpty()) {
        m_pausePoint = m_boundaryDraft.last();
        m_hasPausePoint = true;
    } else {
        m_hasPausePoint = false;
    }
    emit boundaryDraftChanged();
}

void FarmStore::resumeBoundaryRecording()
{
    if (!m_boundaryRecording || !m_boundaryPaused)
        return;
    m_boundaryPaused = false;
    m_boundaryResumePending = true;
    emit boundaryDraftChanged();
}

void FarmStore::appendBoundaryPoint(double lat, double lon)
{
    if (!m_boundaryRecording || m_boundaryPaused || !activeField())
        return;
    if (!std::isfinite(lat) || !std::isfinite(lon)
        || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0)
        return;
    if (std::abs(lat) < 1e-7 && std::abs(lon) < 1e-7)
        return;

    static constexpr double kMinStepM = 3.0;
    static constexpr double kAutoCloseM = 1.0;
    static constexpr int kMaxPts = 4000;

    if (m_boundaryResumePending && m_hasPausePoint) {
        appendLinePoints(m_boundaryDraft, m_pausePoint.lat, m_pausePoint.lon,
                         lat, lon, kMinStepM);
        m_boundaryResumePending = false;
    } else if (m_boundaryResumePending) {
        m_boundaryResumePending = false;
    }

    if (m_boundaryDraft.size() >= 3) {
        const GeoPt &first = m_boundaryDraft.first();
        if (pointDistM(first.lat, first.lon, lat, lon) <= kAutoCloseM) {
            const GeoPt &last = m_boundaryDraft.last();
            if (pointDistM(last.lat, last.lon, first.lat, first.lon) >= kMinStepM * 0.5)
                m_boundaryDraft.append(first);
            m_boundaryRecording = false;
            m_boundaryPaused = false;
            m_boundaryResumePending = false;
            emit boundaryAutoClosed();
            emit boundaryDraftChanged();
            return;
        }
    }

    if (!m_boundaryDraft.isEmpty()) {
        const GeoPt &last = m_boundaryDraft.last();
        if (pointDistM(last.lat, last.lon, lat, lon) < kMinStepM)
            return;
    }
    if (m_boundaryDraft.size() >= kMaxPts)
        return;

    GeoPt p;
    p.lat = lat;
    p.lon = lon;
    m_boundaryDraft.append(p);
    emit boundaryDraftChanged();
}

bool FarmStore::commitBoundary()
{
    Field *f = activeField();
    if (!f || m_boundaryDraft.size() < 3)
        return false;
    m_boundaryRecording = false;
    f->boundary = m_boundaryDraft;
    f->areaHa = areaHaOf(f->boundary);
    m_boundaryDraft.clear();
    healOriginFromActiveBoundary();
    emit boundaryDraftChanged();
    emit geometryChanged();
    save();
    return true;
}

void FarmStore::cancelBoundaryRecording()
{
    const bool had = m_boundaryRecording || !m_boundaryDraft.isEmpty();
    m_boundaryRecording = false;
    m_boundaryPaused = false;
    m_boundaryResumePending = false;
    m_hasPausePoint = false;
    m_boundaryDraft.clear();
    if (had)
        emit boundaryDraftChanged();
}

bool FarmStore::archiveActiveBoundary()
{
    Field *f = activeField();
    if (!f || f->boundary.size() < 3)
        return false;

    ArchivedBoundary ab;
    ab.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    ab.archivedUtc = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    ab.areaHa = f->areaHa > 0.0 ? f->areaHa : areaHaOf(f->boundary);
    ab.ring = f->boundary;

    m_boundaryArchives[f->id].append(ab);
    f->boundary.clear();
    f->areaHa = 0.0;
    saveArchives();
    emit archivesChanged();
    emit geometryChanged();
    save();
    return true;
}

void FarmStore::deleteArchivedBoundary(const QString &archiveId)
{
    Field *f = activeField();
    if (!f || archiveId.isEmpty())
        return;
    auto it = m_boundaryArchives.find(f->id);
    if (it == m_boundaryArchives.end())
        return;
    QVector<ArchivedBoundary> &list = it.value();
    for (int i = 0; i < list.size(); ++i) {
        if (list[i].id == archiveId) {
            list.removeAt(i);
            if (list.isEmpty())
                m_boundaryArchives.erase(it);
            saveArchives();
            emit archivesChanged();
            return;
        }
    }
}

// ---- import / persistence ----
bool FarmStore::pointInRing(double lat, double lon, const QVector<GeoPt> &ring)
{
    // Ray casting in lat/lon space (adequate at field scale).
    bool inside = false;
    const int n = ring.size();
    for (int i = 0, j = n - 1; i < n; j = i++) {
        const double xi = ring.at(i).lon, yi = ring.at(i).lat;
        const double xj = ring.at(j).lon, yj = ring.at(j).lat;
        const bool intersect = ((yi > lat) != (yj > lat))
            && (lon < (xj - xi) * (lat - yi) / ((yj - yi) != 0 ? (yj - yi) : 1e-12) + xi);
        if (intersect) inside = !inside;
    }
    return inside;
}

int FarmStore::importKmlToFarm(const QString &clientId, const QString &farmId, const QString &path)
{
    Client *c = findClient(clientId);
    if (!c) return 0;
    Farm *fm = nullptr;
    for (Farm &f : c->farms)
        if (f.id == farmId) { fm = &f; break; }
    if (!fm) return 0;

    qWarning("[bndy] importKml start path=%s", qUtf8Printable(path));
    KmlImport::Result r;
    if (!KmlImport::parse(path, r)) return 0;
    qWarning("[bndy] importKml parsed: polygons=%d lines=%d", int(r.polygons.size()), int(r.lines.size()));

    QString firstNewId;
    for (const KmlImport::Poly &poly : r.polygons) {
        Field fd;
        fd.id = QStringLiteral("PFD%1").arg(++m_pfdSeq);
        fd.name = poly.name;
        fd.boundary = poly.ring;
        fd.areaHa = areaHaOf(fd.boundary);
        fm->fields.append(fd);
        if (firstNewId.isEmpty()) firstNewId = fd.id;
    }

    // Assign each KML line to the paddock whose boundary contains its midpoint.
    for (AbLine ab : r.lines) {
        ab.id = QStringLiteral("GPN%1").arg(++m_gpnSeq);
        const double midLat = (ab.a.lat + ab.b.lat) / 2.0;
        const double midLon = (ab.a.lon + ab.b.lon) / 2.0;
        Field *target = nullptr;
        for (Field &fd : fm->fields)
            if (fd.boundary.size() >= 3 && pointInRing(midLat, midLon, fd.boundary)) { target = &fd; break; }
        if (!target && !fm->fields.isEmpty())
            target = &fm->fields.last();
        if (target) {
            target->abLines.append(ab);
            if (target->selectedAb < 0) target->selectedAb = target->abLines.size() - 1;
        }
    }

    qWarning("[bndy] importKml saving (fields built)");
    save();
    m_browseClientId = clientId;
    m_browseFarmId = farmId;
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();

    qWarning("[bndy] importKml activating first=%s", qUtf8Printable(firstNewId));
    if (!firstNewId.isEmpty())
        setActiveField(clientId, farmId, firstNewId);   // emits geometry/active + refreshes map
    else {
        emit geometryChanged();
        emit activeChanged();
    }
    return r.polygons.size();
}

int FarmStore::importIsoxml(const QString &path, bool replacePaddocks)
{
    qWarning("[bndy] importIso start path=%s replace=%d", qUtf8Printable(path), int(replacePaddocks));
    QString xmlPath = path;
    const QFileInfo fi(path);
    if (fi.isDir()) {
        const QString found = findTaskDataXml(path);
        if (!found.isEmpty()) xmlPath = found;
    }

    QVector<Client> imported;
    if (!TaskData::load(xmlPath, imported) || imported.isEmpty())
        return 0;
    qWarning("[bndy] importIso parsed: clients=%d xml=%s", int(imported.size()), qUtf8Printable(xmlPath));

    if (replacePaddocks)
        removeMatchingImportedFields(imported);

    int count = 0;
    QString firstClientId, firstFarmId, firstFieldId;
    for (Client &c : imported) {
        c.id = QStringLiteral("CTR%1").arg(++m_ctrSeq);
        for (Farm &f : c.farms) {
            f.id = QStringLiteral("FRM%1").arg(++m_frmSeq);
            for (Field &fd : f.fields) {
                fd.id = QStringLiteral("PFD%1").arg(++m_pfdSeq);
                for (AbLine &ab : fd.abLines)
                    ab.id = QStringLiteral("GPN%1").arg(++m_gpnSeq);
                if (fd.areaHa <= 0.0 && fd.boundary.size() >= 3)
                    fd.areaHa = areaHaOf(fd.boundary);
                if (fd.selectedAb < 0 && !fd.abLines.isEmpty())
                    fd.selectedAb = 0;
                ++count;
                if (firstFieldId.isEmpty()) {
                    firstClientId = c.id; firstFarmId = f.id; firstFieldId = fd.id;
                }
            }
        }
        m_clients.append(c);
    }

    qWarning("[bndy] importIso saving: fields=%d", count);
    save();
    if (!firstClientId.isEmpty()) m_browseClientId = firstClientId;
    if (!firstFarmId.isEmpty())   m_browseFarmId = firstFarmId;
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();
    qWarning("[bndy] importIso activating first=%s", qUtf8Printable(firstFieldId));
    if (!firstFieldId.isEmpty())
        setActiveField(firstClientId, firstFarmId, firstFieldId);
    else {
        emit geometryChanged();
        emit activeChanged();
    }
    return count;
}

QStringList FarmStore::listImportFiles(const QString &folder)
{
    QStringList dirs;
    if (!folder.isEmpty()) {
        dirs << folder;
    } else {
        dirs = importScanFolders();
    }

    QStringList out;
    auto appendDir = [&](const QString &dirPath) {
        qWarning("[bndy] listImportFiles scan dir=%s", qUtf8Printable(dirPath));
        QDir d(dirPath);
        if (!d.exists())
            QDir().mkpath(dirPath);
        const auto files = d.entryList(QStringList()
                                           << QStringLiteral("*.kml") << QStringLiteral("*.KML")
                                           << QStringLiteral("*.xml") << QStringLiteral("*.XML"),
                                       QDir::Files, QDir::Name);
        for (const QString &e : files) {
            const QString abs = d.absoluteFilePath(e);
            if (!out.contains(abs))
                out << abs;
        }
        const auto subdirs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString subPath = d.absoluteFilePath(sub);
            if (!findTaskDataXml(subPath).isEmpty() && !out.contains(subPath))
                out << subPath;
        }
    };

    for (const QString &dir : dirs)
        appendDir(dir);

    qWarning("[bndy] listImportFiles done: %d entries", int(out.size()));
    return out;
}

QStringList FarmStore::browseRoots()
{
    QStringList roots;
#ifdef Q_OS_ANDROID
    const QString storage = QStringLiteral("/storage/emulated/0");
    const QString download = QStringLiteral("/storage/emulated/0/Download");
    const QString documents = QStringLiteral("/storage/emulated/0/Documents");
    if (QDir(download).exists())
        roots << download;
    if (QDir(documents).exists() && !roots.contains(documents))
        roots << documents;
    const QString farmData = defaultImportFolder();
    if (QDir(farmData).exists() && !roots.contains(farmData))
        roots << farmData;
    if (QDir(storage).exists() && !roots.contains(storage))
        roots << storage;
#else
    const QString dl = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!dl.isEmpty())
        roots << dl;
    roots << defaultImportFolder();
#endif
    return roots;
}

QVariantList FarmStore::listBrowseEntries(const QString &folder)
{
    QVariantList out;
    const QString path = normPath(folder);
    if (!isAllowedBrowsePath(path))
        return out;
    QDir d(path);
    if (!d.exists())
        return out;

    const auto dirs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &name : dirs) {
        const QString abs = d.absoluteFilePath(name);
        QVariantMap e;
        e.insert(QStringLiteral("name"), name);
        e.insert(QStringLiteral("path"), abs);
        e.insert(QStringLiteral("isDir"), true);
        e.insert(QStringLiteral("kind"), importKindForPath(abs));
        out.append(e);
    }
    const auto files = d.entryList(QStringList()
                                       << QStringLiteral("*.xml") << QStringLiteral("*.XML")
                                       << QStringLiteral("*.kml") << QStringLiteral("*.KML"),
                                   QDir::Files, QDir::Name);
    for (const QString &name : files) {
        const QString abs = d.absoluteFilePath(name);
        QVariantMap e;
        e.insert(QStringLiteral("name"), name);
        e.insert(QStringLiteral("path"), abs);
        e.insert(QStringLiteral("isDir"), false);
        e.insert(QStringLiteral("kind"), importKindForPath(abs));
        out.append(e);
    }
    return out;
}

QVariantMap FarmStore::checkImportSelection(const QString &sourcePath)
{
    QVariantMap r;
    r.insert(QStringLiteral("ok"), false);
    const QString path = normPath(sourcePath);
    const QString kind = importKindForPath(path);
    if (kind.isEmpty() || kind == QStringLiteral("dir")) {
        r.insert(QStringLiteral("error"), QStringLiteral("Not an ISOXML or KML import file."));
        return r;
    }

    const QFileInfo fi(path);
    const QString farmData = defaultImportFolder();
    const QString dest = stagingDestFor(farmData, path, kind);
    const bool alreadyStaged = path.startsWith(normPath(farmData) + QLatin1Char('/'))
                               || path == normPath(farmData + QLatin1Char('/') + fi.fileName());

    r.insert(QStringLiteral("ok"), true);
    r.insert(QStringLiteral("kind"), kind);
    r.insert(QStringLiteral("sourcePath"), path);
    r.insert(QStringLiteral("sourceName"), fi.fileName());
    r.insert(QStringLiteral("destPath"), dest);
    r.insert(QStringLiteral("alreadyStaged"), alreadyStaged);
    r.insert(QStringLiteral("fileConflict"),
             !alreadyStaged && QFileInfo::exists(dest) && normPath(dest) != path);

    QVariantList padConflicts;
    if (kind.startsWith(QStringLiteral("isoxml"))) {
        QString xmlPath = path;
        if (fi.isDir())
            xmlPath = findTaskDataXml(path);
        QVector<Client> imported;
        if (TaskData::load(xmlPath, imported))
            padConflicts = paddockConflicts(m_clients, imported);
    }
    r.insert(QStringLiteral("paddockConflicts"), padConflicts);
    return r;
}

QString FarmStore::stageImportFile(const QString &sourcePath, bool moveNotCopy, bool overwriteFile)
{
    const QVariantMap check = checkImportSelection(sourcePath);
    if (!check.value(QStringLiteral("ok")).toBool())
        return check.value(QStringLiteral("error")).toString();

    const QString path = check.value(QStringLiteral("sourcePath")).toString();
    const QString kind = check.value(QStringLiteral("kind")).toString();
    const bool alreadyStaged = check.value(QStringLiteral("alreadyStaged")).toBool();
    if (alreadyStaged)
        return QString();

    const QString dest = check.value(QStringLiteral("destPath")).toString();
    if (dest.isEmpty())
        return QStringLiteral("Could not determine destination path.");

    QDir().mkpath(defaultImportFolder());

    if (QFileInfo::exists(dest) && normPath(dest) != path) {
        if (!overwriteFile)
            return QStringLiteral("A file or folder with that name already exists in Farm_data.");
        if (QFileInfo(dest).isDir())
            QDir(dest).removeRecursively();
        else
            QFile::remove(dest);
    }

    const bool ok = moveNotCopy ? movePathTo(path, dest, overwriteFile)
                                : copyPathRecursive(path, dest, overwriteFile);
    if (!ok)
        return moveNotCopy ? QStringLiteral("Move failed — try Copy instead.")
                           : QStringLiteral("Copy failed — check storage permission.");
    return QString();
}

Client *FarmStore::findClientByName(const QString &name)
{
    for (Client &c : m_clients) {
        if (c.name.compare(name, Qt::CaseInsensitive) == 0)
            return &c;
    }
    return nullptr;
}

Farm *FarmStore::findFarmByName(Client &client, const QString &name)
{
    for (Farm &f : client.farms) {
        if (f.name.compare(name, Qt::CaseInsensitive) == 0)
            return &f;
    }
    return nullptr;
}

void FarmStore::removeMatchingImportedFields(const QVector<Client> &imported)
{
    for (const Client &ic : imported) {
        Client *ec = findClientByName(ic.name);
        if (!ec)
            continue;
        for (const Farm &ifarm : ic.farms) {
            Farm *ef = findFarmByName(*ec, ifarm.name);
            if (!ef)
                continue;
            for (const Field &ifd : ifarm.fields) {
                for (int i = ef->fields.size() - 1; i >= 0; --i) {
                    if (ef->fields[i].name.compare(ifd.name, Qt::CaseInsensitive) == 0)
                        ef->fields.removeAt(i);
                }
            }
        }
    }
    for (int ci = m_clients.size() - 1; ci >= 0; --ci) {
        Client &c = m_clients[ci];
        for (int fi = c.farms.size() - 1; fi >= 0; --fi) {
            if (c.farms[fi].fields.isEmpty())
                c.farms.removeAt(fi);
        }
        if (c.farms.isEmpty())
            m_clients.removeAt(ci);
    }
}

QString FarmStore::defaultImportFolder() const
{
#ifdef Q_OS_ANDROID
    return QStringLiteral("/storage/emulated/0/Download/Farm_data");
#else
    const QString d = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    return (d.isEmpty() ? QDir::homePath() : d) + QStringLiteral("/Farm_data");
#endif
}

QStringList FarmStore::importScanFolders() const
{
    QStringList dirs;
    dirs << defaultImportFolder();
#ifdef Q_OS_ANDROID
    const QString dlRoot = QStringLiteral("/storage/emulated/0/Download");
    if (!dirs.contains(dlRoot))
        dirs << dlRoot;
#endif
    const QString dl = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!dl.isEmpty() && !dirs.contains(dl))
        dirs << dl;
    return dirs;
}

void FarmStore::requestStoragePermission()
{
#ifdef Q_OS_ANDROID
    QStringList perms;
    const QString read = QStringLiteral("android.permission.READ_EXTERNAL_STORAGE");
    const QString write = QStringLiteral("android.permission.WRITE_EXTERNAL_STORAGE");
    if (QtAndroid::checkPermission(read) != QtAndroid::PermissionResult::Granted)
        perms << read;
    if (QtAndroid::checkPermission(write) != QtAndroid::PermissionResult::Granted)
        perms << write;
    if (!perms.isEmpty())
        QtAndroid::requestPermissions(perms, [](const QtAndroid::PermissionResultMap &) {});
#endif
}

QString FarmStore::storagePath() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return base + QStringLiteral("/TASKDATA/TASKDATA.XML");
}

static int seqFromIds(const QVector<Client> &clients, const QString &prefix)
{
    int maxN = 0;
    auto take = [&](const QString &id) {
        if (id.startsWith(prefix)) {
            bool ok = false;
            const int n = id.mid(prefix.size()).toInt(&ok);
            if (ok && n > maxN) maxN = n;
        }
    };
    for (const Client &c : clients) {
        if (prefix == QLatin1String("CTR")) take(c.id);
        for (const Farm &f : c.farms) {
            if (prefix == QLatin1String("FRM")) take(f.id);
            for (const Field &fd : f.fields) {
                if (prefix == QLatin1String("PFD")) take(fd.id);
                if (prefix == QLatin1String("GPN"))
                    for (const AbLine &ab : fd.abLines) take(ab.id);
            }
        }
    }
    return maxN;
}

void FarmStore::load()
{
    TaskData::load(storagePath(), m_clients);
    loadArchives();
    m_ctrSeq = seqFromIds(m_clients, QStringLiteral("CTR"));
    m_frmSeq = seqFromIds(m_clients, QStringLiteral("FRM"));
    m_pfdSeq = seqFromIds(m_clients, QStringLiteral("PFD"));
    m_gpnSeq = seqFromIds(m_clients, QStringLiteral("GPN"));
    if (!m_clients.isEmpty()) {
        m_browseClientId = m_clients.first().id;
        if (!m_clients.first().farms.isEmpty())
            m_browseFarmId = m_clients.first().farms.first().id;
    }
    emit clientsChanged();
    emit farmsChanged();
    emit fieldsChanged();
    emit activeChanged();
    emit geometryChanged();
}

void FarmStore::save()
{
    TaskData::save(storagePath(), m_clients);
}

void FarmStore::seedBundledFarmIfEmpty()
{
    if (QFileInfo::exists(storagePath()))
        return;
    // Tester builds ship an empty ISOXML seed (no Clare Downs / workshop data).
    const QString bundled = QStringLiteral(":/assets/farm/TASKDATA.EMPTY.xml");
    if (!QFileInfo::exists(bundled))
        return;
    const QString destDir = QFileInfo(storagePath()).absolutePath();
    QDir().mkpath(destDir);
    const QString dest = storagePath();
    if (QFile::exists(dest))
        return;
    if (!QFile::copy(bundled, dest))
        return;
}
