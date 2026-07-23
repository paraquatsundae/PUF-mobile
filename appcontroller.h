#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class GpsModel;
class GpsSource;

// Owns the active GPS source and wires it to the GpsModel. Exposes connection
// config + control to QML.
class AppController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY statusChanged)
    Q_PROPERTY(QString sourceStatus READ sourceStatus NOTIFY statusChanged)
    Q_PROPERTY(QString activeSource READ activeSource NOTIFY runningChanged)
    Q_PROPERTY(QString localAddresses READ localAddresses CONSTANT)
    Q_PROPERTY(bool serialSupported READ serialSupported CONSTANT)
    Q_PROPERTY(bool internalSerialSupported READ internalSerialSupported CONSTANT)
    Q_PROPERTY(bool canSupported READ canSupported CONSTANT)
    Q_PROPERTY(bool btSupported READ btSupported CONSTANT)
    Q_PROPERTY(bool tabletGpsSupported READ tabletGpsSupported CONSTANT)
    Q_PROPERTY(QStringList btDevices READ btDevices NOTIFY btDevicesChanged)
    Q_PROPERTY(QStringList serialPorts READ serialPorts NOTIFY serialPortsChanged)
    Q_PROPERTY(int udpPort READ udpPort WRITE setUdpPort NOTIFY udpPortChanged)
    Q_PROPERTY(QString internalDevice READ internalDevice WRITE setInternalDevice NOTIFY internalDeviceChanged)
    Q_PROPERTY(QString canDevice READ canDevice WRITE setCanDevice NOTIFY canDeviceChanged)
    Q_PROPERTY(double implementWidth READ implementWidth WRITE setImplementWidth NOTIFY implementWidthChanged)
    Q_PROPERTY(int sectionCount READ sectionCount WRITE setSectionCount NOTIFY sectionCountChanged)
    Q_PROPERTY(QVariantList sectionWidths READ sectionWidths NOTIFY sectionWidthsChanged)
    Q_PROPERTY(double trackSpacing READ trackSpacing WRITE setTrackSpacing NOTIFY trackSpacingChanged)
    Q_PROPERTY(double implementOffset READ implementOffset WRITE setImplementOffset NOTIFY implementOffsetChanged)
    // Recording-point attachment: 0 = antenna only (ute), 1 = 3PL rigid, 2 = drawbar pivot.
    Q_PROPERTY(int recordAttachment READ recordAttachment WRITE setRecordAttachment NOTIFY recordAttachmentChanged)
    Q_PROPERTY(double hitchOffsetM READ hitchOffsetM WRITE setHitchOffsetM NOTIFY hitchOffsetChanged)
    // Effective metres behind the GPS antenna for coverage/boundary recording.
    Q_PROPERTY(double recordOffsetM READ recordOffsetM NOTIFY recordOffsetChanged)
    Q_PROPERTY(double antennaHeight READ antennaHeight WRITE setAntennaHeight NOTIFY antennaHeightChanged)
    Q_PROPERTY(double tankSizeL READ tankSizeL WRITE setTankSizeL NOTIFY tankSizeChanged)
    // Application currently set up on the Work page (single product or tank mix).
    // Merged into the saved job metadata by FieldView; cleared/loaded per field.
    Q_PROPERTY(QVariantMap application READ application NOTIFY applicationChanged)
    Q_PROPERTY(bool recordingCoverage READ recordingCoverage NOTIFY recordingChanged)
    Q_PROPERTY(bool sectionControl READ sectionControl NOTIFY sectionControlChanged)
    Q_PROPERTY(QString trackName READ trackName WRITE setTrackName NOTIFY trackNameChanged)
    // Last-used connection settings (for restoring the connection screen).
    Q_PROPERTY(QString lastSource READ lastSource NOTIFY settingsChanged)
    Q_PROPERTY(int canBitrate READ canBitrate NOTIFY settingsChanged)
    Q_PROPERTY(int ttyBaud READ ttyBaud NOTIFY settingsChanged)
    Q_PROPERTY(int internalBaud READ internalBaud NOTIFY settingsChanged)
    Q_PROPERTY(int serialBaud READ serialBaud NOTIFY settingsChanged)
    Q_PROPERTY(QString serialPort READ serialPort NOTIFY settingsChanged)
    Q_PROPERTY(QString lastBtMac READ lastBtMac NOTIFY settingsChanged)
    // ISOBUS WiFi hub dashboard hint (phone listens UDP; hub sends NMEA to phone IP).
    Q_PROPERTY(QString hubHost READ hubHost WRITE setHubHost NOTIFY hubHostChanged)
    Q_PROPERTY(int hubWebPort READ hubWebPort WRITE setHubWebPort NOTIFY hubWebPortChanged)

public:
    explicit AppController(GpsModel *model, QObject *parent = nullptr);

    bool running() const { return m_running; }
    bool connected() const { return m_connected; }
    QString sourceStatus() const { return m_status; }
    QString activeSource() const;
    QString localAddresses() const;
    bool serialSupported() const;
    bool internalSerialSupported() const;
    bool canSupported() const;
    bool btSupported() const;
    bool tabletGpsSupported() const;
    QStringList btDevices() const { return m_btLabels; }
    Q_INVOKABLE QString btMacAt(int index) const;
    QStringList serialPorts() const;
    int udpPort() const { return m_udpPort; }
    void setUdpPort(int p);
    QString internalDevice() const { return m_internalDevice; }
    void setInternalDevice(const QString &d);
    QString canDevice() const { return m_canDevice; }
    void setCanDevice(const QString &d);
    double implementWidth() const { return m_implementWidth; }
    void setImplementWidth(double w);
    // Per-section width model. implementWidth is kept == sum(sectionWidths) so
    // coverage + the section bar stay correct; sectionCount is independently
    // editable and re-inits the widths evenly when it changes.
    int sectionCount() const { return m_sectionCount; }
    void setSectionCount(int n);
    QVariantList sectionWidths() const;
    // Run-line (controlled-traffic tram) spacing, independent of boom width. A
    // stored 0 means "unset" so it tracks implementWidth until explicitly set.
    double trackSpacing() const { return m_trackSpacing > 0.0 ? m_trackSpacing : m_implementWidth; }
    void setTrackSpacing(double s);
    double implementOffset() const { return m_implementOffset; }
    void setImplementOffset(double d);
    int recordAttachment() const { return m_recordAttachment; }
    void setRecordAttachment(int t);
    double hitchOffsetM() const { return m_hitchOffsetM; }
    void setHitchOffsetM(double d);
    double antennaHeight() const { return m_antennaHeight; }
    void setAntennaHeight(double h);
    double recordOffsetM() const;
    double tankSizeL() const { return m_tankSizeL; }
    void setTankSizeL(double l);
    QVariantMap application() const { return m_application; }
    bool recordingCoverage() const { return m_recording; }
    bool sectionControl() const { return m_sectionControl; }
    QString trackName() const { return m_trackName; }
    void setTrackName(const QString &t);
    QString lastSource() const { return m_lastSource; }
    int canBitrate() const { return m_canBitrate; }
    int ttyBaud() const { return m_ttyBaud; }
    int internalBaud() const { return m_internalBaud; }
    int serialBaud() const { return m_serialBaud; }
    QString serialPort() const { return m_serialPort; }
    QString lastBtMac() const { return m_lastBtMac; }
    QString hubHost() const { return m_hubHost; }
    void setHubHost(const QString &h);
    int hubWebPort() const { return m_hubWebPort; }
    void setHubWebPort(int p);

    // Machine/app configuration persistence (QSettings in the app data dir).
    // saveSettings() is bound to the "Save Settings" button; loadSettings() runs
    // once at startup (from main) so the last setup is restored automatically.
    Q_INVOKABLE void saveSettings();
    Q_INVOKABLE void loadSettings();

public slots:
    void distributeEvenly();
    void setSectionWidth(int index, double metres);
    void setApplication(const QVariantMap &a);
    void clearApplication();
    void toggleRecording();
    void setRecording(bool on);
    void toggleSectionControl();
    void setSectionControl(bool on);
    void startUdp();
    void startSerial(const QString &portName, int baud);
    void startInternalSerial(const QString &device, int baud);
    void startCan(const QString &device, int canBitrate, int ttyBaud);
    void startBt(const QString &mac);
    void startTabletGps();
    void refreshBtDevices();
    void stop();
    void refreshSerialPorts();

signals:
    void runningChanged();
    void statusChanged();
    void btDevicesChanged();
    void serialPortsChanged();
    void udpPortChanged();
    void internalDeviceChanged();
    void canDeviceChanged();
    void implementWidthChanged();
    void sectionCountChanged();
    void sectionWidthsChanged();
    void trackSpacingChanged();
    void implementOffsetChanged();
    void recordAttachmentChanged();
    void hitchOffsetChanged();
    void recordOffsetChanged();
    void antennaHeightChanged();
    void tankSizeChanged();
    void applicationChanged();
    void recordingChanged();
    void sectionControlChanged();
    void trackNameChanged();
    void settingsChanged();
    void hubHostChanged();
    void hubWebPortChanged();

private:
    void setSource(GpsSource *src);

    GpsModel *m_model = nullptr;
    GpsSource *m_source = nullptr;
    QTimer m_ageTimer;
    bool m_running = false;
    bool m_connected = false;
    QString m_status = QStringLiteral("Idle");
    int m_udpPort = 9999;
    QString m_internalDevice = QStringLiteral("/dev/ttyS0");
    QString m_canDevice = QStringLiteral("usb"); // "usb" = USB-host; or "/dev/ttyACM0"
    // Last-used source kind + transport params, remembered so the connection
    // screen reopens on the right backend after a restart.
    QString m_lastSource = QStringLiteral("udp"); // udp|serial|internal|can|bt|tablet
    int m_canBitrate = 250000;
    int m_ttyBaud = 115200;
    int m_internalBaud = 38400;
    int m_serialBaud = 38400;
    QString m_serialPort;
    QString m_lastBtMac;
    QString m_hubHost;
    int m_hubWebPort = 8080;
    QStringList m_btLabels;  // "Name — MAC" for the connection UI
    QStringList m_btMacs;    // parallel to m_btLabels
    double m_implementWidth = 6.0;  // metres (== sum of m_sectionWidths)
    int m_sectionCount = 3;
    QVector<double> m_sectionWidths;  // per-section widths, left -> right
    double m_trackSpacing = 0.0;    // 0 = follow implement width until set explicitly
    // Metres from the GPS receiver back to the implement/boom (recording point).
    // The antenna sits at the FRONT of the 6 m machine sprite, so the boom must
    // be set back past the 6 m rear to sit clearly behind the machine; 7 m puts
    // the section bar ~1 m behind the tail.
    double m_implementOffset = 7.0;
    int m_recordAttachment = 1;     // default 3PL rigid → implementOffset
    double m_hitchOffsetM = 5.0;  // drawbar pivot: metres from antenna to record point
    double m_antennaHeight = 3.0;   // metres above ground (for TCM tilt correction)
    double m_tankSizeL = 3000.0;    // sprayer/spreader tank capacity, litres
    QVariantMap m_application;      // current Work-page application (not persisted in QSettings)
    bool m_recording = false;
    bool m_sectionControl = true;
    QString m_trackName;
};
