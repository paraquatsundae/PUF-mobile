#pragma once

#include "gpssource.h"
#include <QByteArray>

class QSerialPort;

// Desktop-only serial backend (QtSerialPort). Useful for testing a USB/UART
// receiver on a PC COM port. On Android this file is not compiled; wired USB
// receivers there require the Android USB Host API (added later).
class SerialGpsSource : public GpsSource
{
    Q_OBJECT
public:
    SerialGpsSource(const QString &portName, int baud, QObject *parent = nullptr);

    void start() override;
    void stop() override;
    QString description() const override;

private slots:
    void onReadyRead();

private:
    QString m_portName;
    int m_baud;
    QSerialPort *m_port = nullptr;
    QByteArray m_buffer;
    bool m_gotData = false;
};
