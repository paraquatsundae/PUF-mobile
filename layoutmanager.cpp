#include "layoutmanager.h"

#include <QSettings>

LayoutManager::LayoutManager(QObject *parent) : QObject(parent)
{
    m_leftEls  = QStringList() << QStringLiteral("area") << QStringLiteral("speed") << QStringLiteral("location");
    m_rightEls = QStringList() << QStringLiteral("satellites") << QStringLiteral("hdop");

    // Run pages available to the pager, and the default cycle.
    m_runCatalog  = QStringList() << QStringLiteral("nav") << QStringLiteral("data") << QStringLiteral("work");
    m_activePages = QStringList() << QStringLiteral("nav") << QStringLiteral("data") << QStringLiteral("work");

    // Default column visibility per run page.
    m_leftVis[QStringLiteral("nav")]  = true;  m_rightVis[QStringLiteral("nav")]  = true;
    m_leftVis[QStringLiteral("data")] = true;  m_rightVis[QStringLiteral("data")] = false;
    m_leftVis[QStringLiteral("work")] = false; m_rightVis[QStringLiteral("work")] = false;
}

void LayoutManager::setCurrentPage(const QString &id)
{
    if (id != m_currentPage) {
        m_currentPage = id;
        emit currentPageChanged();
        emit leftVisibleChanged();
        emit rightVisibleChanged();
    }
}

bool LayoutManager::leftVisibleFor(const QString &id) const
{
    if (!isRunPage(id))
        return false;
    return m_leftVis.value(id, false);
}

bool LayoutManager::rightVisibleFor(const QString &id) const
{
    if (!isRunPage(id))
        return false;
    return m_rightVis.value(id, false);
}

void LayoutManager::setLeftVisibleFor(const QString &id, bool v)
{
    if (m_leftVis.value(id, false) != v) {
        m_leftVis[id] = v;
        if (id == m_currentPage)
            emit leftVisibleChanged();
        save();
    }
}

void LayoutManager::setRightVisibleFor(const QString &id, bool v)
{
    if (m_rightVis.value(id, false) != v) {
        m_rightVis[id] = v;
        if (id == m_currentPage)
            emit rightVisibleChanged();
        save();
    }
}

void LayoutManager::setPageActive(const QString &id, bool on)
{
    if (!isRunPage(id))
        return;
    const bool has = m_activePages.contains(id);
    if (on && !has) {
        // Keep catalog order when re-inserting.
        QStringList next;
        for (const QString &c : m_runCatalog)
            if (c == id || m_activePages.contains(c))
                next << c;
        m_activePages = next;
        emit activePagesChanged();
        save();
    } else if (!on && has) {
        if (m_activePages.size() <= 1)
            return;                 // always keep at least one run page
        m_activePages.removeAll(id);
        emit activePagesChanged();
        save();
    }
}

void LayoutManager::movePage(const QString &id, int dir)
{
    const int i = m_activePages.indexOf(id);
    if (i < 0) return;
    const int j = i + (dir < 0 ? -1 : 1);
    if (j < 0 || j >= m_activePages.size()) return;
    m_activePages.move(i, j);
    emit activePagesChanged();
    save();
}

bool LayoutManager::contains(const QString &side, const QString &id) const
{
    return (side == QLatin1String("left") ? m_leftEls : m_rightEls).contains(id);
}

void LayoutManager::toggle(const QString &side, const QString &id)
{
    const bool left = (side == QLatin1String("left"));
    QStringList &list = left ? m_leftEls : m_rightEls;
    if (list.contains(id))
        list.removeAll(id);
    else
        list.append(id);
    if (left) emit leftElementsChanged(); else emit rightElementsChanged();
    save();
}

void LayoutManager::save() const
{
    QSettings s;
    s.beginGroup(QStringLiteral("layout"));
    s.setValue(QStringLiteral("leftElements"), m_leftEls);
    s.setValue(QStringLiteral("rightElements"), m_rightEls);
    s.setValue(QStringLiteral("activePages"), m_activePages);
    // Per-page column visibility, flattened to "<page>" keys under sub-groups.
    s.beginWriteArray(QStringLiteral("pageVis"));
    int i = 0;
    for (const QString &id : m_runCatalog) {
        s.setArrayIndex(i++);
        s.setValue(QStringLiteral("id"), id);
        s.setValue(QStringLiteral("left"), m_leftVis.value(id, false));
        s.setValue(QStringLiteral("right"), m_rightVis.value(id, false));
    }
    s.endArray();
    s.endGroup();
}

void LayoutManager::load()
{
    QSettings s;
    s.beginGroup(QStringLiteral("layout"));
    if (!s.contains(QStringLiteral("leftElements"))) { // nothing saved yet
        s.endGroup();
        return;
    }
    m_leftEls = s.value(QStringLiteral("leftElements"), m_leftEls).toStringList();
    m_rightEls = s.value(QStringLiteral("rightElements"), m_rightEls).toStringList();
    const QStringList ap = s.value(QStringLiteral("activePages"), m_activePages).toStringList();
    // Keep only known run pages and never end up with an empty cycle.
    QStringList valid;
    for (const QString &id : ap)
        if (m_runCatalog.contains(id) && !valid.contains(id))
            valid << id;
    if (!valid.isEmpty())
        m_activePages = valid;

    const int n = s.beginReadArray(QStringLiteral("pageVis"));
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        const QString id = s.value(QStringLiteral("id")).toString();
        if (!m_runCatalog.contains(id))
            continue;
        m_leftVis[id] = s.value(QStringLiteral("left"), m_leftVis.value(id, false)).toBool();
        m_rightVis[id] = s.value(QStringLiteral("right"), m_rightVis.value(id, false)).toBool();
    }
    s.endArray();
    s.endGroup();

    emit leftElementsChanged();
    emit rightElementsChanged();
    emit activePagesChanged();
    emit leftVisibleChanged();
    emit rightVisibleChanged();
}
