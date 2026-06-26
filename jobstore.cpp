#include "jobstore.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QSettings>

#include <algorithm>

namespace {
constexpr auto kPhoneLastFieldKey = "phone/lastFieldId";
constexpr auto kPhoneLastJobKey = "phone/lastJobId";
} // namespace

JobStore::JobStore(QObject *parent) : QObject(parent) {}

QString JobStore::sanitize(const QString &id)
{
    QString out;
    out.reserve(id.size());
    for (const QChar c : id) {
        if (c.isLetterOrNumber() || c == QLatin1Char('-') || c == QLatin1Char('_'))
            out.append(c);
        else
            out.append(QLatin1Char('_'));
    }
    return out.isEmpty() ? QStringLiteral("field") : out;
}

QString JobStore::jobsRoot() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return base + QStringLiteral("/jobs");
}

QString JobStore::fieldDir(const QString &fieldId) const
{
    return jobsRoot() + QLatin1Char('/') + sanitize(fieldId);
}

QString JobStore::jobDir(const QString &fieldId, const QString &jobId) const
{
    return fieldDir(fieldId) + QLatin1Char('/') + jobId;
}

QString JobStore::activeRefPath() const
{
    return jobsRoot() + QStringLiteral("/active.txt");
}

QString JobStore::currentJobId(const QString &fieldId) const
{
    QFile f(fieldDir(fieldId) + QStringLiteral("/current.txt"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    const QString id = QString::fromUtf8(f.readAll()).trimmed();
    return id;
}

void JobStore::setCurrentJobId(const QString &fieldId, const QString &jobId) const
{
    const QString dir = fieldDir(fieldId);
    QDir().mkpath(dir);
    QFile f(dir + QStringLiteral("/current.txt"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        f.write(jobId.toUtf8());
}

bool JobStore::hasJob(const QString &fieldId) const
{
    if (fieldId.isEmpty())
        return false;
    const QString jobId = currentJobId(fieldId);
    if (jobId.isEmpty())
        return false;
    return QFile::exists(fieldDir(fieldId) + QLatin1Char('/') + jobId
                         + QStringLiteral("/coverage.geojson"));
}

QVariantMap JobStore::jobMeta(const QString &fieldId) const
{
    QVariantMap out;
    const QString jobId = currentJobId(fieldId);
    if (jobId.isEmpty())
        return out;
    QFile f(fieldDir(fieldId) + QLatin1Char('/') + jobId + QStringLiteral("/metadata.json"));
    if (!f.open(QIODevice::ReadOnly))
        return out;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (doc.isObject())
        out = doc.object().toVariantMap();
    return out;
}

QString JobStore::loadCoverage(const QString &fieldId) const
{
    const QString jobId = currentJobId(fieldId);
    if (jobId.isEmpty())
        return QString();
    QFile f(fieldDir(fieldId) + QLatin1Char('/') + jobId + QStringLiteral("/coverage.geojson"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(f.readAll());
}

QString JobStore::saveJob(const QVariantMap &meta, const QString &coverageGeoJson)
{
    const QString fieldId = meta.value(QStringLiteral("fieldId")).toString();
    if (fieldId.isEmpty())
        return QString();

    QString jobId = meta.value(QStringLiteral("jobId")).toString();
    if (jobId.isEmpty())
        jobId = currentJobId(fieldId);
    const bool isNew = jobId.isEmpty();
    if (isNew)
        jobId = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));

    const QString dir = fieldDir(fieldId) + QLatin1Char('/') + jobId;
    QDir().mkpath(dir);

    // metadata.json — self-describing job header.
    QVariantMap m = meta;
    m[QStringLiteral("schema")] = QStringLiteral("puf-mobile.job");
    m[QStringLiteral("schemaVersion")] = 2;
    m[QStringLiteral("jobId")] = jobId;
    const QString now = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    if (isNew || !m.contains(QStringLiteral("createdUtc")))
        m[QStringLiteral("createdUtc")] = now;
    m[QStringLiteral("modifiedUtc")] = now;
    m[QStringLiteral("coverageFile")] = QStringLiteral("coverage.geojson");
    // Lifecycle: default to "open" (the freshly recorded / resumed job). A caller
    // can pass an explicit state (e.g. "complete") in `meta` to override.
    if (!m.contains(QStringLiteral("state")) || m.value(QStringLiteral("state")).toString().isEmpty())
        m[QStringLiteral("state")] = QStringLiteral("open");
    m[QStringLiteral("displayName")] = displayNameFor(m);

    QFile mf(dir + QStringLiteral("/metadata.json"));
    if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        mf.write(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Indented));
        mf.close();
    }

    QFile cf(dir + QStringLiteral("/coverage.geojson"));
    if (cf.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        cf.write(coverageGeoJson.toUtf8());
        cf.close();
    }

    setCurrentJobId(fieldId, jobId);
    // An open job becomes the global "last open job" for the Resume popup; a
    // completed one releases the active pointer if it pointed here.
    if (m.value(QStringLiteral("state")).toString() == QLatin1String("open"))
        setActiveJob(fieldId, jobId);
    else
        clearActiveJob();
    rememberLastActive(fieldId, jobId);
    emit changed();
    return jobId;
}

QString JobStore::displayNameFor(const QVariantMap &meta)
{
    const QVariantMap app = meta.value(QStringLiteral("application")).toMap();
    QString name = app.value(QStringLiteral("name")).toString();
    if (name.isEmpty())
        name = meta.value(QStringLiteral("trackName")).toString();
    if (name.isEmpty())
        name = QStringLiteral("Job");
    QString when = meta.value(QStringLiteral("createdUtc")).toString();
    const QDateTime dt = QDateTime::fromString(when, Qt::ISODate);
    if (dt.isValid())
        when = dt.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"));
    return when.isEmpty() ? name : (name + QStringLiteral(" \u2014 ") + when);
}

QVariantMap JobStore::readJobMeta(const QString &fieldId, const QString &jobId) const
{
    QVariantMap out;
    if (fieldId.isEmpty() || jobId.isEmpty())
        return out;
    QFile f(jobDir(fieldId, jobId) + QStringLiteral("/metadata.json"));
    if (!f.open(QIODevice::ReadOnly))
        return out;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (doc.isObject())
        out = doc.object().toVariantMap();
    return out;
}

void JobStore::writeJobMeta(const QString &fieldId, const QString &jobId,
                            const QVariantMap &meta) const
{
    const QString dir = jobDir(fieldId, jobId);
    QDir().mkpath(dir);
    QFile mf(dir + QStringLiteral("/metadata.json"));
    if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate))
        mf.write(QJsonDocument(QJsonObject::fromVariantMap(meta)).toJson(QJsonDocument::Indented));
}

QVariantMap JobStore::jobMetaById(const QString &fieldId, const QString &jobId) const
{
    return readJobMeta(fieldId, jobId);
}

QString JobStore::loadCoverageById(const QString &fieldId, const QString &jobId) const
{
    if (fieldId.isEmpty() || jobId.isEmpty())
        return QString();
    QFile f(jobDir(fieldId, jobId) + QStringLiteral("/coverage.geojson"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(f.readAll());
}

void JobStore::setActiveJob(const QString &fieldId, const QString &jobId)
{
    if (fieldId.isEmpty() || jobId.isEmpty())
        return;
    QDir().mkpath(jobsRoot());
    QFile f(activeRefPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        f.write((fieldId + QLatin1Char('\t') + jobId).toUtf8());
}

void JobStore::clearActiveJob()
{
    QFile::remove(activeRefPath());
}

QVariantMap JobStore::activeJob() const
{
    QVariantMap out;
    QFile f(activeRefPath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return out;
    const QString ref = QString::fromUtf8(f.readAll()).trimmed();
    const int tab = ref.indexOf(QLatin1Char('\t'));
    if (tab <= 0)
        return out;
    const QString fieldId = ref.left(tab);
    const QString jobId = ref.mid(tab + 1).trimmed();
    out = readJobMeta(fieldId, jobId);
    if (out.isEmpty())
        return out;
    out[QStringLiteral("fieldId")] = fieldId;
    out[QStringLiteral("jobId")] = jobId;
    if (!out.contains(QStringLiteral("displayName")))
        out[QStringLiteral("displayName")] = displayNameFor(out);
    return out;
}

void JobStore::openJob(const QString &fieldId, const QString &jobId)
{
    if (fieldId.isEmpty() || jobId.isEmpty())
        return;
    setCurrentJobId(fieldId, jobId);
    setJobState(fieldId, jobId, QStringLiteral("open"));
    setActiveJob(fieldId, jobId);
    emit changed();
}

void JobStore::setJobState(const QString &fieldId, const QString &jobId,
                           const QString &state)
{
    QVariantMap m = readJobMeta(fieldId, jobId);
    if (m.isEmpty())
        return;
    m[QStringLiteral("state")] = state;
    m[QStringLiteral("modifiedUtc")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    writeJobMeta(fieldId, jobId, m);
    if (state == QLatin1String("complete")) {
        // A completed job releases the active pointer if it was the active one.
        const QVariantMap act = activeJob();
        if (act.value(QStringLiteral("jobId")).toString() == jobId
            && act.value(QStringLiteral("fieldId")).toString() == fieldId)
            clearActiveJob();
    }
    emit changed();
}

QVariantList JobStore::listAllJobs(int limit) const
{
    QVariantList out;
    QDir root(jobsRoot());
    if (!root.exists())
        return out;
    const QStringList fieldDirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &fd : fieldDirs) {
        QDir d(jobsRoot() + QLatin1Char('/') + fd);
        const QStringList subs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &sub : subs) {
            QFile f(d.absolutePath() + QLatin1Char('/') + sub + QStringLiteral("/metadata.json"));
            if (!f.open(QIODevice::ReadOnly))
                continue;
            const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
            f.close();
            if (!doc.isObject())
                continue;
            QVariantMap m = doc.object().toVariantMap();
            // The real (unsanitised) fieldId lives in the metadata; fall back to
            // the directory name only if an older job lacks it.
            if (!m.contains(QStringLiteral("fieldId")) || m.value(QStringLiteral("fieldId")).toString().isEmpty())
                m[QStringLiteral("fieldId")] = fd;
            m[QStringLiteral("jobId")] = sub;
            if (!m.contains(QStringLiteral("displayName")))
                m[QStringLiteral("displayName")] = displayNameFor(m);
            if (!m.contains(QStringLiteral("state")))
                m[QStringLiteral("state")] = QStringLiteral("open");
            out.append(m);
        }
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        const QString ka = a.toMap().value(QStringLiteral("modifiedUtc")).toString();
        const QString kb = b.toMap().value(QStringLiteral("modifiedUtc")).toString();
        return ka > kb;
    });
    if (limit > 0 && out.size() > limit)
        out = out.mid(0, limit);
    return out;
}

QVariantList JobStore::listJobs(const QString &fieldId) const
{
    QVariantList out;
    if (fieldId.isEmpty())
        return out;
    QDir d(fieldDir(fieldId));
    if (!d.exists())
        return out;
    const QStringList subs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &sub : subs) {
        QFile f(fieldDir(fieldId) + QLatin1Char('/') + sub + QStringLiteral("/metadata.json"));
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        f.close();
        if (doc.isObject())
            out.append(doc.object().toVariantMap());
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        const QString ka = a.toMap().value(QStringLiteral("modifiedUtc")).toString();
        const QString kb = b.toMap().value(QStringLiteral("modifiedUtc")).toString();
        return ka > kb;
    });
    return out;
}

bool JobStore::deleteJob(const QString &fieldId, const QString &jobId)
{
    if (fieldId.isEmpty() || jobId.isEmpty())
        return false;
    // Guard the path: jobId is a folder name we created (date stamp); reject any
    // separators so a crafted id can't escape the field directory.
    if (jobId.contains(QLatin1Char('/')) || jobId.contains(QLatin1Char('\\'))
        || jobId.contains(QStringLiteral("..")))
        return false;

    // If this job is the global active job, release the pointer first.
    const QVariantMap act = activeJob();
    if (act.value(QStringLiteral("jobId")).toString() == jobId
        && act.value(QStringLiteral("fieldId")).toString() == fieldId)
        clearActiveJob();

    // If this job is the field's current/resumable job, forget the pointer so a
    // re-entry of the field starts fresh instead of trying to reload a gone job.
    if (currentJobId(fieldId) == jobId)
        QFile::remove(fieldDir(fieldId) + QStringLiteral("/current.txt"));

    QDir dir(jobDir(fieldId, jobId));
    const bool removed = dir.exists() ? dir.removeRecursively() : false;
    emit changed();
    return removed;
}

void JobStore::startNewJob(const QString &fieldId)
{
    if (fieldId.isEmpty())
        return;
    QFile::remove(fieldDir(fieldId) + QStringLiteral("/current.txt"));
    emit changed();
}

QString JobStore::lastActiveFieldId() const
{
    QSettings s;
    return s.value(QLatin1String(kPhoneLastFieldKey)).toString();
}

QString JobStore::lastActiveJobId() const
{
    QSettings s;
    return s.value(QLatin1String(kPhoneLastJobKey)).toString();
}

void JobStore::rememberLastActive(const QString &fieldId, const QString &jobId)
{
    if (fieldId.isEmpty())
        return;
    QSettings s;
    s.setValue(QLatin1String(kPhoneLastFieldKey), fieldId);
    if (!jobId.isEmpty())
        s.setValue(QLatin1String(kPhoneLastJobKey), jobId);
    s.sync();
}

bool JobStore::hasAnySavedJobs() const
{
    QDir root(jobsRoot());
    if (!root.exists())
        return false;
    const QStringList fieldDirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &fd : fieldDirs) {
        if (hasJob(fd))
            return true;
        // Real field ids may differ from sanitized dir names — scan job folders.
        QDir d(jobsRoot() + QLatin1Char('/') + fd);
        const QStringList subs = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &sub : subs) {
            if (QFile::exists(d.absolutePath() + QLatin1Char('/') + sub
                              + QStringLiteral("/coverage.geojson")))
                return true;
        }
    }
    return false;
}
