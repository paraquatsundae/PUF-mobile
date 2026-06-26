#include "udpgpssource.h"

#include <QUdpSocket>

UdpGpsSource::UdpGpsSource(quint16 port, QObject *parent)
    : GpsSource(parent), m_port(port)
{
}

void UdpGpsSource::start()
{
    stop();
    m_socket = new QUdpSocket(this);
    m_gotData = false;
    if (m_socket->bind(QHostAddress::AnyIPv4, m_port,
                       QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        connect(m_socket, &QUdpSocket::readyRead, this, &UdpGpsSource::onReadyRead);
        emit status(QStringLiteral("Listening on UDP %1").arg(m_port), false);
    } else {
        emit status(QStringLiteral("Bind failed on UDP %1: %2")
                        .arg(m_port).arg(m_socket->errorString()),
                    false);
    }
}

void UdpGpsSource::stop()
{
    if (m_socket) {
        m_socket->close();
        m_socket->deleteLater();
        m_socket = nullptr;
    }
}

QString UdpGpsSource::description() const
{
    return QStringLiteral("UDP :%1").arg(m_port);
}

void UdpGpsSource::onReadyRead()
{
    while (m_socket && m_socket->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(int(m_socket->pendingDatagramSize()));
        m_socket->readDatagram(buf.data(), buf.size());

        if (!m_gotData) {
            m_gotData = true;
            emit status(QStringLiteral("Receiving on UDP %1").arg(m_port), true);
        }

        const QString text = QString::fromLatin1(buf);
        const QStringList lines = text.split(QRegExp("[\r\n]"), QString::SkipEmptyParts);
        for (const QString &line : lines)
            emit sentence(line.trimmed());
    }
}
