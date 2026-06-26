#include "posixserialgpssource.h"

#include <QSocketNotifier>

#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>

static speed_t baudConstant(int baud)
{
    switch (baud) {
    case 4800:   return B4800;
    case 9600:   return B9600;
    case 19200:  return B19200;
    case 38400:  return B38400;
    case 57600:  return B57600;
    case 115200: return B115200;
    case 230400: return B230400;
    case 460800: return B460800;
    default:     return B9600;
    }
}

PosixSerialGpsSource::PosixSerialGpsSource(const QString &device, int baud, QObject *parent)
    : GpsSource(parent), m_device(device), m_baud(baud)
{
}

PosixSerialGpsSource::~PosixSerialGpsSource()
{
    stop();
}

void PosixSerialGpsSource::start()
{
    stop();
    m_got = false;

    const QByteArray path = m_device.toLocal8Bit();
    m_fd = ::open(path.constData(), O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (m_fd < 0) {
        emit status(QStringLiteral("open %1 failed: %2")
                        .arg(m_device, QString::fromLocal8Bit(strerror(errno))),
                    false);
        return;
    }

    struct termios tio;
    memset(&tio, 0, sizeof(tio));
    if (tcgetattr(m_fd, &tio) == 0) {
        cfmakeraw(&tio);
        const speed_t b = baudConstant(m_baud);
        cfsetispeed(&tio, b);
        cfsetospeed(&tio, b);
        tio.c_cflag |= (CLOCAL | CREAD);
        tio.c_cflag &= ~CRTSCTS;
        tio.c_cc[VMIN] = 0;
        tio.c_cc[VTIME] = 0;
        tcsetattr(m_fd, TCSANOW, &tio);
    }

    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &PosixSerialGpsSource::onActivated);
    emit status(QStringLiteral("Opened %1 @ %2").arg(m_device).arg(m_baud), false);
}

void PosixSerialGpsSource::stop()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_fd >= 0) {
        ::close(m_fd);
        m_fd = -1;
    }
    m_buf.clear();
}

QString PosixSerialGpsSource::description() const
{
    return QStringLiteral("%1 @ %2").arg(m_device).arg(m_baud);
}

void PosixSerialGpsSource::onActivated()
{
    if (m_fd < 0)
        return;

    char tmp[512];
    ssize_t n;
    while ((n = ::read(m_fd, tmp, sizeof(tmp))) > 0)
        m_buf.append(tmp, int(n));

    int idx;
    while ((idx = m_buf.indexOf('\n')) >= 0) {
        QByteArray line = m_buf.left(idx);
        m_buf.remove(0, idx + 1);
        const QString s = QString::fromLatin1(line).trimmed();
        if (s.isEmpty())
            continue;
        if (!m_got) {
            m_got = true;
            emit status(QStringLiteral("Receiving on %1").arg(m_device), true);
        }
        emit sentence(s);
    }

    // Cap buffer if we somehow never see a newline.
    if (m_buf.size() > 8192)
        m_buf.clear();
}
