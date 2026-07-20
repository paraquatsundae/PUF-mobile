#include "appcontroller.h"

#include "gpsmodel.h"
#include "gpssource.h"
#include "udpgpssource.h"

#include <QNetworkInterface>
#include <QSettings>

#ifdef HAVE_SERIAL
#include "serialgpssource.h"
#include <QSerialPortInfo>
#endif

#ifdef HAVE_POSIX_SERIAL
#include "posixserialgpssource.h"
#endif

#include "cangpssource.h"
#include "btgpssource.h"
#include "tabletgpssource.h"

#ifdef Q_OS_ANDROID
#include <QAndroidJniObject>
#endif

AppController::AppController(GpsModel *model, QObject *parent)
    : QObject(parent), m_model(model)
{
    m_ageTimer.setInterval(500);
    connect(&m_ageTimer, &QTimer::timeout, m_model, &GpsModel::tick);
    m_ageTimer.start();
    m_sectionCount = qBound(1, qRound(m_implementWidth / 2.0), 16);
    distributeEvenly();
    // Keep the GPS smoothing filter's heading damping in step with the boom
    // width (wider boom -> steadier heading). Pushed now and on every change.
    if (m_model)
        m_model->setImplementWidth(m_implementWidth);
    connect(this, &AppController::implementWidthChanged, this, [this] {
        if (m_model)
            m_model->setImplementWidth(m_implementWidth);
    });
}

QString AppController::activeSource() const
{
    return m_source ? m_source->description() : QString();
}

QString AppController::localAddresses() const
{
    QStringList out;
    const auto ifaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &ni : ifaces) {
        if (!(ni.flags() & QNetworkInterface::IsUp))
            continue;
        if (ni.flags() & QNetworkInterface::IsLoopBack)
            continue;
        for (const QNetworkAddressEntry &e : ni.addressEntries()) {
            const QHostAddress a = e.ip();
            if (a.protocol() == QAbstractSocket::IPv4Protocol)
                out << a.toString();
        }
    }
    return out.isEmpty() ? QStringLiteral("(no network)") : out.join(QStringLiteral(", "));
}

bool AppController::serialSupported() const
{
#ifdef HAVE_SERIAL
    return true;
#else
    return false;
#endif
}

bool AppController::internalSerialSupported() const
{
#ifdef HAVE_POSIX_SERIAL
    return true;
#else
    return false;
#endif
}

bool AppController::canSupported() const
{
#ifdef HAVE_POSIX_SERIAL
    return true;
#else
    return false;
#endif
}

bool AppController::btSupported() const
{
#ifdef Q_OS_ANDROID
    return true;
#else
    return false;
#endif
}

bool AppController::tabletGpsSupported() const
{
#ifdef Q_OS_ANDROID
    return true;
#else
    return false;
#endif
}

QString AppController::btMacAt(int index) const
{
    if (index < 0 || index >= m_btMacs.size())
        return QString();
    return m_btMacs.at(index);
}

void AppController::refreshBtDevices()
{
    m_btLabels.clear();
    m_btMacs.clear();
#ifdef Q_OS_ANDROID
    const QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/BtGps", "pairedDevices", "()Ljava/lang/String;");
    if (res.isValid()) {
        const QString all = res.toString();
        const QStringList lines = all.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            const QStringList parts = line.split(QLatin1Char('\t'));
            if (parts.size() < 2)
                continue;
            const QString name = parts.at(0);
            const QString mac = parts.at(1);
            m_btLabels << QStringLiteral("%1  —  %2").arg(name, mac);
            m_btMacs << mac;
        }
    }
#endif
    emit btDevicesChanged();
}

void AppController::startBt(const QString &mac)
{
    m_lastSource = QStringLiteral("bt");
    m_lastBtMac = mac;
    emit settingsChanged();
    setSource(new BtGpsSource(mac, 1, this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
}

void AppController::startTabletGps()
{
    m_lastSource = QStringLiteral("tablet");
    emit settingsChanged();
    setSource(new TabletGpsSource(this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
}

void AppController::setInternalDevice(const QString &d)
{
    if (d != m_internalDevice) {
        m_internalDevice = d;
        emit internalDeviceChanged();
    }
}

void AppController::setCanDevice(const QString &d)
{
    if (d != m_canDevice) {
        m_canDevice = d;
        emit canDeviceChanged();
    }
}

void AppController::startCan(const QString &device, int canBitrate, int ttyBaud)
{
    m_canDevice = device;
    m_lastSource = QStringLiteral("can");
    m_canBitrate = canBitrate;
    m_ttyBaud = ttyBaud;
    emit canDeviceChanged();
    emit settingsChanged();
    // canBitrate = the CAN bus speed (must match the JD bus: 250k X119 / 500k proprietary).
    // ttyBaud = USB-serial line coding; usually ignored by native-USB CDC adapters but
    // exposed so it can match a known-good slcan config.
    setSource(new CanGpsSource(device, ttyBaud, canBitrate, this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
}

QStringList AppController::serialPorts() const
{
    QStringList list;
#ifdef HAVE_SERIAL
    const auto ports = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &pi : ports)
        list << pi.portName();
#endif
    return list;
}

void AppController::refreshSerialPorts()
{
    emit serialPortsChanged();
}

void AppController::setUdpPort(int p)
{
    if (p > 0 && p <= 65535 && p != m_udpPort) {
        m_udpPort = p;
        emit udpPortChanged();
    }
}

void AppController::setHubHost(const QString &h)
{
    if (h != m_hubHost) {
        m_hubHost = h;
        emit hubHostChanged();
    }
}

void AppController::setHubWebPort(int p)
{
    if (p > 0 && p <= 65535 && p != m_hubWebPort) {
        m_hubWebPort = p;
        emit hubWebPortChanged();
    }
}

void AppController::setSource(GpsSource *src)
{
    if (m_source) {
        m_source->stop();
        m_source->deleteLater();
        m_source = nullptr;
    }
    m_source = src;
    if (m_source) {
        connect(m_source, &GpsSource::sentence, m_model, &GpsModel::feed);
        connect(m_source, &GpsSource::status, this,
                [this](const QString &text, bool connected) {
                    m_status = text;
                    m_connected = connected;
                    emit statusChanged();
                });
    }
}

void AppController::startUdp()
{
    m_lastSource = QStringLiteral("udp");
    emit settingsChanged();
    setSource(new UdpGpsSource(static_cast<quint16>(m_udpPort), this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
}

void AppController::startSerial(const QString &portName, int baud)
{
#ifdef HAVE_SERIAL
    m_lastSource = QStringLiteral("serial");
    m_serialPort = portName;
    m_serialBaud = baud;
    emit settingsChanged();
    setSource(new SerialGpsSource(portName, baud, this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
#else
    Q_UNUSED(portName)
    Q_UNUSED(baud)
    m_status = QStringLiteral("Serial not supported on this build");
    emit statusChanged();
#endif
}

void AppController::setImplementWidth(double w)
{
    if (w < 0.5) w = 0.5;
    if (w > 60.0) w = 60.0;
    if (!qFuzzyCompare(w, m_implementWidth)) {
        m_implementWidth = w;
        // The working-width control sets the total boom width; spread it evenly
        // across the current sections (custom widths are set per-section instead).
        distributeEvenly();
        emit implementWidthChanged();
        // While track spacing is unset it follows the boom width, so its
        // effective value just changed too.
        if (m_trackSpacing <= 0.0)
            emit trackSpacingChanged();
    }
}

QVariantList AppController::sectionWidths() const
{
    QVariantList l;
    for (double w : m_sectionWidths)
        l.append(w);
    return l;
}

void AppController::setSectionCount(int n)
{
    if (n < 1) n = 1;
    if (n > 16) n = 16;
    if (n == m_sectionCount && m_sectionWidths.size() == n)
        return;
    m_sectionCount = n;
    distributeEvenly();   // re-init widths evenly; total (implementWidth) preserved
    emit sectionCountChanged();
}

void AppController::distributeEvenly()
{
    double total = m_implementWidth;
    if (total < 0.5) total = 0.5;
    const int n = qBound(1, m_sectionCount, 16);
    const double each = total / n;
    m_sectionWidths.clear();
    for (int i = 0; i < n; ++i)
        m_sectionWidths.append(each);
    m_sectionCount = n;
    m_implementWidth = each * n;   // == total, but keep them exactly consistent
    emit sectionWidthsChanged();
}

void AppController::setSectionWidth(int index, double metres)
{
    if (index < 0 || index >= m_sectionWidths.size())
        return;
    if (metres < 0.1) metres = 0.1;
    if (metres > 60.0) metres = 60.0;
    if (qFuzzyCompare(metres, m_sectionWidths[index]))
        return;
    m_sectionWidths[index] = metres;
    double sum = 0.0;
    for (double w : m_sectionWidths)
        sum += w;
    m_implementWidth = sum;
    emit sectionWidthsChanged();
    emit implementWidthChanged();
    if (m_trackSpacing <= 0.0)
        emit trackSpacingChanged();
}

void AppController::setTrackSpacing(double s)
{
    if (s < 0.5) s = 0.5;
    if (s > 60.0) s = 60.0;
    if (!qFuzzyCompare(s, m_trackSpacing)) {
        m_trackSpacing = s;
        emit trackSpacingChanged();
    }
}

void AppController::setRecording(bool on)
{
    if (on != m_recording) {
        m_recording = on;
        // Capture the raw GPS track for the duration of the recording so the
        // user can drive one pass and tune the filter offline (tools/gps_replay).
        if (m_model)
            m_model->setRawLogging(on);
        emit recordingChanged();
    }
}

void AppController::toggleRecording()
{
    setRecording(!m_recording);
}

void AppController::setImplementOffset(double d)
{
    if (d < 0.0) d = 0.0;
    if (d > 20.0) d = 20.0;
    if (!qFuzzyCompare(d + 1.0, m_implementOffset + 1.0)) {
        m_implementOffset = d;
        emit implementOffsetChanged();
        emit recordOffsetChanged();
    }
}

void AppController::setRecordAttachment(int t)
{
    if (t < 0) t = 0;
    if (t > 2) t = 2;
    if (m_recordAttachment != t) {
        m_recordAttachment = t;
        emit recordAttachmentChanged();
        emit recordOffsetChanged();
    }
}

void AppController::setHitchOffsetM(double d)
{
    if (d < 0.0) d = 0.0;
    if (d > 20.0) d = 20.0;
    if (!qFuzzyCompare(d + 1.0, m_hitchOffsetM + 1.0)) {
        m_hitchOffsetM = d;
        emit hitchOffsetChanged();
        emit recordOffsetChanged();
    }
}

double AppController::recordOffsetM() const
{
    switch (m_recordAttachment) {
    case 0: return 0.0;
    case 2: return m_hitchOffsetM;
    case 1:
    default: return m_implementOffset;
    }
}

void AppController::setAntennaHeight(double h)
{
    if (h < 0.0) h = 0.0;
    if (h > 10.0) h = 10.0;
    if (!qFuzzyCompare(h + 1.0, m_antennaHeight + 1.0)) {
        m_antennaHeight = h;
        emit antennaHeightChanged();
    }
}

void AppController::setTankSizeL(double l)
{
    if (l < 0.0) l = 0.0;
    if (l > 100000.0) l = 100000.0;
    if (!qFuzzyCompare(l + 1.0, m_tankSizeL + 1.0)) {
        m_tankSizeL = l;
        emit tankSizeChanged();
    }
}

void AppController::setApplication(const QVariantMap &a)
{
    m_application = a;
    emit applicationChanged();
}

void AppController::clearApplication()
{
    if (!m_application.isEmpty()) {
        m_application.clear();
        emit applicationChanged();
    }
}

void AppController::setSectionControl(bool on)
{
    if (on != m_sectionControl) {
        m_sectionControl = on;
        emit sectionControlChanged();
    }
}

void AppController::toggleSectionControl()
{
    setSectionControl(!m_sectionControl);
}

void AppController::setTrackName(const QString &t)
{
    if (t != m_trackName) {
        m_trackName = t;
        emit trackNameChanged();
    }
}

void AppController::startInternalSerial(const QString &device, int baud)
{
#ifdef HAVE_POSIX_SERIAL
    m_internalDevice = device;
    m_lastSource = QStringLiteral("internal");
    m_internalBaud = baud;
    emit internalDeviceChanged();
    emit settingsChanged();
    setSource(new PosixSerialGpsSource(device, baud, this));
    m_source->start();
    m_running = true;
    emit runningChanged();
    emit statusChanged();
#else
    Q_UNUSED(device)
    Q_UNUSED(baud)
    m_status = QStringLiteral("Internal serial not supported on this build");
    emit statusChanged();
#endif
}

void AppController::stop()
{
    if (m_source) {
        m_source->stop();
        m_source->deleteLater();
        m_source = nullptr;
    }
    m_running = false;
    m_connected = false;
    m_status = QStringLiteral("Stopped");
    emit runningChanged();
    emit statusChanged();
}

void AppController::saveSettings()
{
    QSettings s;
    s.beginGroup(QStringLiteral("machine"));
    s.setValue(QStringLiteral("implementWidth"), m_implementWidth);
    QStringList sw;
    for (double w : m_sectionWidths)
        sw << QString::number(w, 'f', 3);
    s.setValue(QStringLiteral("sectionWidths"), sw.join(QLatin1Char(',')));
    s.setValue(QStringLiteral("trackSpacing"), m_trackSpacing);
    s.setValue(QStringLiteral("implementOffset"), m_implementOffset);
    s.setValue(QStringLiteral("recordAttachment"), m_recordAttachment);
    s.setValue(QStringLiteral("hitchOffsetM"), m_hitchOffsetM);
    s.setValue(QStringLiteral("antennaHeight"), m_antennaHeight);
    s.setValue(QStringLiteral("tankSizeL"), m_tankSizeL);
    s.setValue(QStringLiteral("sectionControl"), m_sectionControl);
    s.setValue(QStringLiteral("trackName"), m_trackName);
    s.endGroup();

    s.beginGroup(QStringLiteral("source"));
    s.setValue(QStringLiteral("lastSource"), m_lastSource);
    s.setValue(QStringLiteral("udpPort"), m_udpPort);
    s.setValue(QStringLiteral("internalDevice"), m_internalDevice);
    s.setValue(QStringLiteral("internalBaud"), m_internalBaud);
    s.setValue(QStringLiteral("canDevice"), m_canDevice);
    s.setValue(QStringLiteral("canBitrate"), m_canBitrate);
    s.setValue(QStringLiteral("ttyBaud"), m_ttyBaud);
    s.setValue(QStringLiteral("serialPort"), m_serialPort);
    s.setValue(QStringLiteral("serialBaud"), m_serialBaud);
    s.setValue(QStringLiteral("btMac"), m_lastBtMac);
    s.endGroup();

    s.beginGroup(QStringLiteral("hub"));
    s.setValue(QStringLiteral("host"), m_hubHost);
    s.setValue(QStringLiteral("webPort"), m_hubWebPort);
    s.endGroup();
    s.sync();

    m_status = QStringLiteral("Settings saved");
    emit statusChanged();
}

void AppController::loadSettings()
{
    QSettings s;
    s.beginGroup(QStringLiteral("machine"));
    setImplementWidth(s.value(QStringLiteral("implementWidth"), m_implementWidth).toDouble());
    // Restore custom per-section widths if present; this overrides the even split
    // applied by setImplementWidth above and re-derives implementWidth = sum.
    const QString swStr = s.value(QStringLiteral("sectionWidths")).toString();
    if (!swStr.isEmpty()) {
        const QStringList parts = swStr.split(QLatin1Char(','), Qt::SkipEmptyParts);
        QVector<double> v;
        for (const QString &p : parts) {
            bool ok = false;
            const double d = p.toDouble(&ok);
            if (ok && d > 0.0 && d < 100.0)
                v.append(d);
        }
        if (!v.isEmpty() && v.size() <= 16) {
            m_sectionWidths = v;
            m_sectionCount = v.size();
            double sum = 0.0;
            for (double w : v)
                sum += w;
            m_implementWidth = sum;
        }
    }
    // 0 = unset → trackSpacing() falls back to the implement width; a real stored
    // value is clamped and kept independent of the boom width.
    const double ts = s.value(QStringLiteral("trackSpacing"), 0.0).toDouble();
    m_trackSpacing = (ts > 0.0) ? qBound(0.5, ts, 60.0) : 0.0;
    // An older build could persist a 0 m offset, which would record coverage at
    // the antenna instead of behind the machine. Treat a stored ~0 as "unset"
    // and fall back to the default so the boom/record point stay sensible. The
    // antenna is at the FRONT of the 6 m machine, so the default sets the boom
    // back behind the machine tail (see AppController::m_implementOffset).
    double off = s.value(QStringLiteral("implementOffset"), m_implementOffset).toDouble();
    if (off < 0.05) off = m_implementOffset;
    setImplementOffset(off);
    setRecordAttachment(s.value(QStringLiteral("recordAttachment"), m_recordAttachment).toInt());
    double hitch = s.value(QStringLiteral("hitchOffsetM"), m_hitchOffsetM).toDouble();
    if (hitch < 0.05) hitch = m_hitchOffsetM;
    setHitchOffsetM(hitch);
    setAntennaHeight(s.value(QStringLiteral("antennaHeight"), m_antennaHeight).toDouble());
    setTankSizeL(s.value(QStringLiteral("tankSizeL"), m_tankSizeL).toDouble());
    setSectionControl(s.value(QStringLiteral("sectionControl"), m_sectionControl).toBool());
    setTrackName(s.value(QStringLiteral("trackName"), m_trackName).toString());
    s.endGroup();

    s.beginGroup(QStringLiteral("source"));
    m_lastSource = s.value(QStringLiteral("lastSource"),
                          tabletGpsSupported() ? QStringLiteral("tablet")
                                               : QStringLiteral("udp"))
                     .toString();
    setUdpPort(s.value(QStringLiteral("udpPort"), m_udpPort).toInt());
    m_internalDevice = s.value(QStringLiteral("internalDevice"), m_internalDevice).toString();
    m_internalBaud = s.value(QStringLiteral("internalBaud"), m_internalBaud).toInt();
    m_canDevice = s.value(QStringLiteral("canDevice"), m_canDevice).toString();
    m_canBitrate = s.value(QStringLiteral("canBitrate"), m_canBitrate).toInt();
    m_ttyBaud = s.value(QStringLiteral("ttyBaud"), m_ttyBaud).toInt();
    m_serialPort = s.value(QStringLiteral("serialPort"), m_serialPort).toString();
    m_serialBaud = s.value(QStringLiteral("serialBaud"), m_serialBaud).toInt();
    m_lastBtMac = s.value(QStringLiteral("btMac"), m_lastBtMac).toString();
    s.endGroup();

    s.beginGroup(QStringLiteral("hub"));
    m_hubHost = s.value(QStringLiteral("host"), m_hubHost).toString();
    setHubWebPort(s.value(QStringLiteral("webPort"), m_hubWebPort).toInt());
    s.endGroup();

    emit internalDeviceChanged();
    emit hubHostChanged();
    emit canDeviceChanged();
    emit sectionCountChanged();
    emit sectionWidthsChanged();
    emit implementWidthChanged();
    emit trackSpacingChanged();
    emit settingsChanged();
}
