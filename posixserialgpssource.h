#pragma once

#include "gpssource.h"
#include <QByteArray>

class QSocketNotifier;

// Reads NMEA from a Linux TTY device (e.g. the tablet's internal GNSS on
// /dev/ttyS0). Uses raw POSIX termios + QSocketNotifier on the fd, so it works
// on Android without the USB Host API or QtSerialPort. Compiled on android/linux.
class PosixSerialGpsSource : public GpsSource
{
    Q_OBJECT
public:
    PosixSerialGpsSource(const QString &device, int baud, QObject *parent = nullptr);
    ~PosixSerialGpsSource() override;

    void start() override;
    void stop() override;
    QString description() const override;

private slots:
    void onActivated();

private:
    QString m_device;
    int m_baud;
    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    QByteArray m_buf;
    bool m_got = false;
};
