#include "theme.h"

#include <QSettings>

Theme::Theme(QObject *parent) : QObject(parent)
{
    QSettings s;
    m_dark = s.value(QStringLiteral("ui/darkMode"), true).toBool();
    m_userGuideSeen = s.value(QStringLiteral("ui/userGuideSeen"), false).toBool();
}

void Theme::setUserGuideSeen(bool seen)
{
    if (m_userGuideSeen == seen)
        return;
    m_userGuideSeen = seen;
    QSettings s;
    s.setValue(QStringLiteral("ui/userGuideSeen"), seen);
    s.sync();
    emit userGuideSeenChanged();
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
