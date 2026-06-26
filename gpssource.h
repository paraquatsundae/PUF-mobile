#pragma once

#include <QObject>
#include <QString>

// Abstract input for an NMEA stream. Concrete backends (UDP, serial, Bluetooth,
// Android USB host) emit one signal per received NMEA/PANDA sentence so the rest
// of the app is transport-agnostic.
class GpsSource : public QObject
{
    Q_OBJECT
public:
    explicit GpsSource(QObject *parent = nullptr) : QObject(parent) {}
    ~GpsSource() override = default;

    virtual void start() = 0;
    virtual void stop() = 0;
    virtual QString description() const = 0;

signals:
    // A single, trimmed sentence beginning with '$' (checksum still attached).
    void sentence(const QString &line);
    // Human-readable connection status; connected=true once data is flowing.
    void status(const QString &text, bool connected);
};
