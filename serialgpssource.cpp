#include "serialgpssource.h"

#include <QSerialPort>

SerialGpsSource::SerialGpsSource(const QString &portName, int baud, QObject *parent)
    : GpsSource(parent), m_portName(portName), m_baud(baud)
{
}

void SerialGpsSource::start()
{
    stop();
    m_port = new QSerialPort(this);
    m_port->setPortName(m_portName);
    m_port->setBaudRate(m_baud);
    m_port->setDataBits(QSerialPort::Data8);
    m_port->setParity(QSerialPort::NoParity);
    m_port->setStopBits(QSerialPort::OneStop);
    m_port->setFlowControl(QSerialPort::NoFlowControl);
    m_gotData = false;

    if (m_port->open(QIODevice::ReadOnly)) {
        connect(m_port, &QSerialPort::readyRead, this, &SerialGpsSource::onReadyRead);
        emit status(QStringLiteral("Opened %1 @ %2").arg(m_portName).arg(m_baud), false);
    } else {
        emit status(QStringLiteral("Open failed %1: %2")
                        .arg(m_portName, m_port->errorString()),
                    false);
    }
}

void SerialGpsSource::stop()
{
    if (m_port) {
        m_port->close();
        m_port->deleteLater();
        m_port = nullptr;
    }
    m_buffer.clear();
}

QString SerialGpsSource::description() const
{
    return QStringLiteral("%1 @ %2").arg(m_portName).arg(m_baud);
}

void SerialGpsSource::onReadyRead()
{
    if (!m_port)
        return;
    m_buffer.append(m_port->readAll());

    int idx;
    while ((idx = m_buffer.indexOf('\n')) >= 0) {
        QByteArray line = m_buffer.left(idx);
        m_buffer.remove(0, idx + 1);
        const QString s = QString::fromLatin1(line).trimmed();
        if (s.isEmpty())
            continue;
        if (!m_gotData) {
            m_gotData = true;
            emit status(QStringLiteral("Receiving on %1").arg(m_portName), true);
        }
        emit sentence(s);
    }
}
