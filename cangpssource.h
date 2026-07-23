#pragma once

#include "gpssource.h"

#include <QByteArray>
#include <QString>
#include <QList>

class QSocketNotifier;
class QUdpSocket;
class QTimer;

// Decodes John Deere StarFire / ATX ISOBUS frames (J1939 extended IDs, source
// address 0x1C) into a position + attitude fix and renders the SAME AgOpenGPS NMEA
// stream the Wi-Fi bridge emits. This is a faithful 1:1 port of
// PUFworks-isobus/scripts/gps_bridge_lib.py (the field-validated PGN map) so the
// direct-plug USB-CAN path feeds GpsModel byte-identically to the bridge:
//   PGN 0xFEF3  lat/lon   (uint32 LE * 1e-7; both axes offset -210 deg)
//   PGN 0xFEE8  heading / speed / pitch / altitude (u16 LE)
//   PGN 0xFEE6  roll      (bytes 2-3, u16 LE / 128 deg)
//   PGN 0xFFFF  JD proprietary GNSS-quality multiplex; sub-msg 0x51 (sig
//               0x51 0x03 0x02) byte 3 = satellites used (SA-gated to 0x1C)
//   PGN 0xFEF1  wheel speed fallback (any source address)
class JdCanDecoder
{
public:
    // Feed one CAN frame. Returns true if any field changed.
    bool update(quint32 canId, const QByteArray &data);
    bool valid() const { return m_haveLatLon; }
    // True for an ATX position frame (PGN 0xFEF3) — used to pace NMEA output.
    static bool isPositionFrame(quint32 canId);
    // Build the four AgOpenGPS sentences exactly as the bridge's nmea_bundle()
    // does (GGA, RMC, VTG, PANDA — $PANDA last so its attitude payload wins).
    // Empty list if no fix yet. Each string is a complete "$...*CS" sentence.
    QStringList bundle() const;
    // Build "$PANDA,...*CS" for the current fix (or empty if no fix yet).
    QString panda() const;

private:
    void applyFee8(const QByteArray &b, qint64 tsMs);

    double m_lat = 0.0, m_lon = 0.0;
    double m_speedKmh = 0.0, m_headingDeg = 0.0;
    double m_pitchDeg = 0.0, m_rollDeg = 0.0, m_yawRate = 0.0, m_altM = 0.0;
    int m_fixQuality = 1;
    int m_sats = 0;
    bool m_haveSats = false;
    bool m_haveLatLon = false;
    bool m_fef1Speed = false;
    double m_prevLat = 0.0, m_prevLon = 0.0;
    bool m_havePrevLL = false;
    double m_prevHeading = 0.0;
    qint64 m_prevHeadingTs = 0;
    bool m_havePrevHeading = false;
};

// slcan (LAWICEL) USB-CAN adapter -> JD GPS/TCM as $PANDA. Two transports,
// chosen by the device string:
//   "/dev/..."  raw POSIX TTY (rooted/permissive Linux/Android, CDC-ACM node)
//   anything else ("usb")  Android USB-host: a Java helper opens the CDC-ACM
//                          device and pipes raw bytes over localhost UDP here.
class CanGpsSource : public GpsSource
{
    Q_OBJECT
public:
    CanGpsSource(const QString &device, int ttyBaud, int canBitrate, QObject *parent = nullptr);
    ~CanGpsSource() override;

    void start() override;
    void stop() override;
    QString description() const override;

    // Parse a chunk of raw slcan bytes (shared by the TTY and USB-host feeds).
    void feedBytes(const QByteArray &chunk);

    // slcan bit-rate command char ('5'=250k, '6'=500k, ...) for a bps value.
    static char slcanCode(int bitrate);

private slots:
    void onActivated();   // TTY readable
    void onUdpReady();    // USB-host bytes arrived over localhost UDP
    void onDiag();        // 1 Hz RX summary to the status line

private:
    void startTty();
    void startUsbHost();
    void handleToken(const QByteArray &token);

    QString m_device;
    int m_ttyBaud;
    int m_canBitrate;
    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    QUdpSocket *m_udp = nullptr;
    QTimer *m_diag = nullptr;
    QByteArray m_buf;
    bool m_got = false;
    JdCanDecoder m_decoder;

    // RX diagnostics (surfaced on the status line; visible without adb).
    qint64 m_rxBytes = 0;
    qint64 m_rxFrames = 0;
    QList<quint32> m_seen;   // distinct (PGN<<8 | SA) keys, capped
};
