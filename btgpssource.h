#pragma once

#include "gpssource.h"

#include <QByteArray>
#include <QString>

class QUdpSocket;
class QTimer;

// Bluetooth (SPP / RFCOMM) NMEA source. A small Java helper (BtGps.java) connects
// to a paired Bluetooth device that streams NMEA -- the bt_gps_host.py bridge on a
// laptop/Pi, or any off-the-shelf Bluetooth GPS receiver -- and forwards the bytes
// to this object over localhost UDP. We split them into '$' sentences and emit them,
// reusing the same Java->UDP->parser pattern as the USB-CAN source.
class BtGpsSource : public GpsSource
{
    Q_OBJECT
public:
    BtGpsSource(const QString &mac, int channel = 1, QObject *parent = nullptr);
    ~BtGpsSource() override;

    void start() override;
    void stop() override;
    QString description() const override;

private slots:
    void onUdpReady();
    void onDiag();

private:
    void feedBytes(const QByteArray &chunk);

    QString m_mac;
    int m_channel;
    QUdpSocket *m_udp = nullptr;
    QTimer *m_diag = nullptr;
    QByteArray m_buf;
    bool m_got = false;
    qint64 m_rxBytes = 0;
    qint64 m_rxLines = 0;
};
