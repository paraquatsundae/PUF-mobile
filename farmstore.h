#pragma once

#include "farmdata.h"

#include <QObject>
#include <QVariantList>
#include <QVector>

class GpsModel;

// In-memory Client/Farm/Field model with ISOXML persistence, on-device
// boundary + AB-line capture, and KML import. Exposed to QML as `farm`.
class FarmStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList clients READ clients NOTIFY clientsChanged)
    Q_PROPERTY(QVariantList farms READ farms NOTIFY farmsChanged)
    Q_PROPERTY(QVariantList fields READ fields NOTIFY fieldsChanged)
    Q_PROPERTY(QString browseClientId READ browseClientId WRITE setBrowseClient NOTIFY farmsChanged)
    Q_PROPERTY(QString browseFarmId READ browseFarmId WRITE setBrowseFarm NOTIFY fieldsChanged)

    Q_PROPERTY(bool hasActiveField READ hasActiveField NOTIFY activeChanged)
    Q_PROPERTY(QString activeClientId READ activeClientId NOTIFY activeChanged)
    Q_PROPERTY(QString activeFarmId READ activeFarmId NOTIFY activeChanged)
    Q_PROPERTY(QString activeFieldId READ activeFieldId NOTIFY activeChanged)
    Q_PROPERTY(QString activeFieldName READ activeFieldName NOTIFY activeChanged)
    Q_PROPERTY(QString activeFarmName READ activeFarmName NOTIFY activeChanged)
    Q_PROPERTY(QString activeClientName READ activeClientName NOTIFY activeChanged)
    Q_PROPERTY(double activeAreaHa READ activeAreaHa NOTIFY activeChanged)
    Q_PROPERTY(int boundaryCount READ boundaryCount NOTIFY geometryChanged)
    Q_PROPERTY(int abCount READ abCount NOTIFY geometryChanged)
    Q_PROPERTY(QString abLineName READ abLineName NOTIFY geometryChanged)

    Q_PROPERTY(bool hasDraftA READ hasDraftA NOTIFY draftChanged)
    Q_PROPERTY(bool hasDraftB READ hasDraftB NOTIFY draftChanged)

    Q_PROPERTY(QVariantList activeBoundary READ activeBoundary NOTIFY geometryChanged)
    Q_PROPERTY(QVariantList activeAbLines READ activeAbLines NOTIFY geometryChanged)

public:
    explicit FarmStore(QObject *parent = nullptr);

    // Wire the GPS model so that activating a field can deterministically pin the
    // local-frame origin to the boundary centroid when there is no live fix yet.
    void setGpsModel(GpsModel *gps) { m_gps = gps; }

    QVariantList clients() const;
    QVariantList farms() const;
    QVariantList fields() const;
    QString browseClientId() const { return m_browseClientId; }
    QString browseFarmId() const { return m_browseFarmId; }

    bool hasActiveField() const { return activeField() != nullptr; }
    QString activeClientId() const { return m_activeClientId; }
    QString activeFarmId() const { return m_activeFarmId; }
    QString activeFieldId() const { return m_activeFieldId; }
    QString activeFieldName() const;
    QString activeFarmName() const;
    QString activeClientName() const;
    double activeAreaHa() const;
    int boundaryCount() const;
    int abCount() const;
    QString abLineName() const;

    bool hasDraftA() const { return m_hasDraftA; }
    bool hasDraftB() const { return m_hasDraftB; }

    QVariantList activeBoundary() const;
    QVariantList activeAbLines() const;

public slots:
    // CRUD
    QString addClient(const QString &name);
    QString addFarm(const QString &clientId, const QString &name);
    QString addField(const QString &clientId, const QString &farmId, const QString &name);
    void renameClient(const QString &id, const QString &name);
    void renameFarm(const QString &id, const QString &name);
    void renameField(const QString &id, const QString &name);
    void deleteClient(const QString &id);
    void deleteFarm(const QString &id);
    void deleteField(const QString &id);

    void setBrowseClient(const QString &id);
    void setBrowseFarm(const QString &id);
    void setActiveField(const QString &clientId, const QString &farmId, const QString &fieldId);

    // AB line capture
    void markA(double lat, double lon);
    void markB(double lat, double lon);
    void commitAbLine(const QString &name);
    // Synthesise an AB line from a single point A and a heading (deg from true
    // north): B is placed a fixed distance out along that bearing, then stored
    // like a committed AB line. Used by the run-line popup's "A + heading" and
    // "lat/lon + heading" add methods.
    void addAbLineHeading(const QString &name, double latA, double lonA, double headingDeg);
    void clearAbDraft();
    void selectAbLine(int index);
    void renameAbLine(int index, const QString &name);
    void deleteAbLine(int index);

    // Import / persistence
    // Creates one field per KML polygon (auto-named) under the given farm,
    // assigns any KML lines as AB lines to the containing paddock, sets the
    // first new field active, and returns the number of fields created.
    int importKmlToFarm(const QString &clientId, const QString &farmId, const QString &path);
    // Merges an external ISOXML TASKDATA.XML (or a folder containing one) into
    // the store as new Clients/Farms/Fields, re-issuing local ids. Returns the
    // number of fields imported and sets the first one active.
    int importIsoxml(const QString &path);
    QStringList listImportFiles(const QString &folder);
    QString defaultImportFolder() const;
    void requestStoragePermission();
    void load();
    void save();
    // Copy bundled assets/farm/TASKDATA.XML into app storage when empty (phone P1).
    void seedBundledFarmIfEmpty();

signals:
    void clientsChanged();
    void farmsChanged();
    void fieldsChanged();
    void activeChanged();
    void geometryChanged();
    void draftChanged();

private:
    Field *activeField();
    const Field *activeField() const;
    Client *findClient(const QString &id);
    Farm *findFarm(const QString &id);
    Field *findField(const QString &id);
    QString storagePath() const;
    static double areaHaOf(const QVector<GeoPt> &ring);
    static bool pointInRing(double lat, double lon, const QVector<GeoPt> &ring);
    // If the GPS model has no valid origin (no live fix / 0,0 / out-of-range),
    // derive one from the active field's boundary centroid and pin it, so the
    // boundary maps to small local metres and renders without a GPS fix. A real
    // live-fix origin is never overridden.
    void healOriginFromActiveBoundary();

    GpsModel *m_gps = nullptr;
    QVector<Client> m_clients;
    QString m_browseClientId;
    QString m_browseFarmId;
    QString m_activeClientId;
    QString m_activeFarmId;
    QString m_activeFieldId;

    GeoPt m_draftA;
    GeoPt m_draftB;
    bool m_hasDraftA = false;
    bool m_hasDraftB = false;

    int m_ctrSeq = 0;
    int m_frmSeq = 0;
    int m_pfdSeq = 0;
    int m_gpnSeq = 0;
};
