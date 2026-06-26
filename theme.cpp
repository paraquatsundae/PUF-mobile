#include "theme.h"

#include <QSettings>

Theme::Theme(QObject *parent) : QObject(parent)
{
    QSettings s;
    m_dark = s.value(QStringLiteral("ui/darkMode"), true).toBool();
}

void Theme::setDark(bool on)
{
    if (on == m_dark)
        return;
    m_dark = on;
    QSettings s;
    s.setValue(QStringLiteral("ui/darkMode"), m_dark);
    s.sync();
    emit darkChanged();
}
