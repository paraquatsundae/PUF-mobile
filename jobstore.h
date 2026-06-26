#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Local, upload-ready work-data store. Each job lives in its own self-describing
// folder so a future sync system can consume it without app-internal knowledge:
//
//   <AppData>/jobs/<fieldId>/<jobId>/
//       metadata.json    — schema/version, client/farm/field ids + names, job
//                          dates, worked area, implement width, antenna height,
//                          GPS source, and the local-frame origin (lat/lon).
//       coverage.geojson — worked swaths as WGS84 LineString features, each with
//                          a width_m property (FeatureCollection).
//
// A per-field "current.txt" names the active (resumable) job so a field can be
// re-entered and its coverage reloaded. Starting a new job just repoints it;
// old job folders are kept on disk.
class JobStore : public QObject
{
    Q_OBJECT
public:
    explicit JobStore(QObject *parent = nullptr);

    // True if the field has a resumable job with saved coverage.
    Q_INVOKABLE bool hasJob(const QString &fieldId) const;
    // Metadata of the field's current job (empty map if none).
    Q_INVOKABLE QVariantMap jobMeta(const QString &fieldId) const;
    // Coverage GeoJSON text for the field's current job (empty if none).
    Q_INVOKABLE QString loadCoverage(const QString &fieldId) const;
    // Persist a job: writes metadata.json + coverage.geojson and points the field
    // at it. `meta` must carry "fieldId"; "jobId" is derived (date) if absent.
    // Returns the job id used.
    Q_INVOKABLE QString saveJob(const QVariantMap &meta, const QString &coverageGeoJson);
    // Forget the current job for a field so the next session starts fresh. The
    // job folder is retained on disk (only the "current" pointer is cleared).
    Q_INVOKABLE void startNewJob(const QString &fieldId);
    // Root folder holding every job (for documentation / external sync tools).
    Q_INVOKABLE QString jobsRoot() const;
    // Every job folder's metadata for a field, newest first (paddock history).
    Q_INVOKABLE QVariantList listJobs(const QString &fieldId) const;

    // ---- Job lifecycle (active job + state machine, all persisted locally) ----
    // The "active job" is the last OPEN job across every field, remembered in
    // jobs/active.txt ("realFieldId<TAB>jobId") so the day-start Resume popup can
    // offer it after an app restart / unclean exit.
    // Metadata of the global active (last open) job, with fieldId/jobId/state
    // injected; empty map if there is none.
    Q_INVOKABLE QVariantMap activeJob() const;
    Q_INVOKABLE void setActiveJob(const QString &fieldId, const QString &jobId);
    Q_INVOKABLE void clearActiveJob();
    // Every saved job across all fields, newest first (capped to `limit`, 0 = all).
    // Each entry carries fieldId, jobId, displayName, state, timestamps, areaHa,
    // and the application — the chronological list for the Resume popup.
    Q_INVOKABLE QVariantList listAllJobs(int limit = 0) const;
    // Make `jobId` the field's current job + the global active job, state "open".
    // The UI then activates the field (FarmStore) to restore its coverage.
    Q_INVOKABLE void openJob(const QString &fieldId, const QString &jobId);
    // States: "open" | "paused" | "complete". Rewrites metadata.json in place.
    Q_INVOKABLE void setJobState(const QString &fieldId, const QString &jobId,
                                 const QString &state);
    Q_INVOKABLE QVariantMap jobMetaById(const QString &fieldId, const QString &jobId) const;
    Q_INVOKABLE QString loadCoverageById(const QString &fieldId, const QString &jobId) const;
    // Permanently remove a job: deletes its folder (metadata.json +
    // coverage.geojson), clears it from the field's "current" pointer and the
    // global active pointer if it was active. Returns true if the folder was
    // removed. Deleting the active/open job is safe — callers should refresh.
    Q_INVOKABLE bool deleteJob(const QString &fieldId, const QString &jobId);
    // Human-friendly name (application/mix name + created date-time). Stored on
    // save; recomputed as a fallback for older jobs that predate the field.
    Q_INVOKABLE static QString displayNameFor(const QVariantMap &meta);

    // UI hub: the Work page calls these; FieldView (which owns the live coverage
    // geometry) listens and performs the actual save / start-new.
    Q_INVOKABLE void requestSave() { emit saveRequested(); }
    Q_INVOKABLE void requestNew() { emit newRequested(); }
    // Emitted after saveJob()/startNewJob() so the UI can refresh hasJob() state.
    Q_INVOKABLE void notifyChanged() { emit changed(); }

    // Phone shell: last field the operator worked on (QSettings phone/lastFieldId).
    Q_INVOKABLE QString lastActiveFieldId() const;
    Q_INVOKABLE QString lastActiveJobId() const;
    Q_INVOKABLE void rememberLastActive(const QString &fieldId, const QString &jobId = QString());
    // True when any field has resumable coverage on disk.
    Q_INVOKABLE bool hasAnySavedJobs() const;

signals:
    void saveRequested();
    void newRequested();
    void changed();

private:
    static QString sanitize(const QString &id);
    QString fieldDir(const QString &fieldId) const;
    QString jobDir(const QString &fieldId, const QString &jobId) const;
    QString currentJobId(const QString &fieldId) const;
    void setCurrentJobId(const QString &fieldId, const QString &jobId) const;
    QString activeRefPath() const;
    QVariantMap readJobMeta(const QString &fieldId, const QString &jobId) const;
    void writeJobMeta(const QString &fieldId, const QString &jobId,
                      const QVariantMap &meta) const;
};
