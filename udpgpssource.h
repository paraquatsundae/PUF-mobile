#pragma once

#include "gpssource.h"
#include <QHostAddress>

class QUdpSocket;

// Listens on a UDP port for NMEA/PANDA datagrams (one or many sentences per
// packet). Works on Android (QtNetwork) and is the primary path for both the
// PUFworks gps_bridge (JD CAN -> UDP) and a PC serial->UDP relay.
class UdpGpsSource : public GpsSource
{
    Q_OBJECT
public:
    explicit UdpGpsSource(quint16 port, QObject *parent = nullptr);

    void start() override;
    void stop() override;
    QString description() const override;

private slots:
    void onReadyRead();

private:
    quint16 m_port;
    QUdpSocket *m_socket = nullptr;
    bool m_gotData = false;
};
