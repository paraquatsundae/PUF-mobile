#pragma once

#include <QObject>
#include <QStringList>
#include <QHash>

// Configurable shell layout. Pages are referenced by string id. Column
// visibility is stored per run-page; the element lists are shared across
// whichever columns are shown. The active-pages list controls which run pages
// the top pager cycles through (and in what order).
class LayoutManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentPage READ currentPage WRITE setCurrentPage NOTIFY currentPageChanged)
    Q_PROPERTY(bool leftVisible READ leftVisible NOTIFY leftVisibleChanged)
    Q_PROPERTY(bool rightVisible READ rightVisible NOTIFY rightVisibleChanged)
    Q_PROPERTY(QStringList leftElements READ leftElements NOTIFY leftElementsChanged)
    Q_PROPERTY(QStringList rightElements READ rightElements NOTIFY rightElementsChanged)
    Q_PROPERTY(QStringList runCatalog READ runCatalog CONSTANT)
    Q_PROPERTY(QStringList activePages READ activePages NOTIFY activePagesChanged)

public:
    explicit LayoutManager(QObject *parent = nullptr);

    QString currentPage() const { return m_currentPage; }
    void setCurrentPage(const QString &id);

    // Visibility for the current page.
    bool leftVisible() const { return leftVisibleFor(m_currentPage); }
    bool rightVisible() const { return rightVisibleFor(m_currentPage); }

    QStringList leftElements() const { return m_leftEls; }
    QStringList rightElements() const { return m_rightEls; }

    QStringList runCatalog() const { return m_runCatalog; }
    QStringList activePages() const { return m_activePages; }

    // Per-page column config (only meaningful on run pages).
    Q_INVOKABLE bool isRunPage(const QString &id) const { return m_runCatalog.contains(id); }
    Q_INVOKABLE bool leftVisibleFor(const QString &id) const;
    Q_INVOKABLE bool rightVisibleFor(const QString &id) const;
    Q_INVOKABLE void setLeftVisibleFor(const QString &id, bool v);
    Q_INVOKABLE void setRightVisibleFor(const QString &id, bool v);

    // Active run pages (which pages the pager cycles, and ordering).
    Q_INVOKABLE bool pageActive(const QString &id) const { return m_activePages.contains(id); }
    Q_INVOKABLE void setPageActive(const QString &id, bool on);
    Q_INVOKABLE void movePage(const QString &id, int dir);   // -1 up, +1 down

    // Element selection (side = "left"|"right").
    Q_INVOKABLE bool contains(const QString &side, const QString &id) const;
    Q_INVOKABLE void toggle(const QString &side, const QString &id);

    // Layout persistence (QSettings). load() runs once at startup; save() is
    // called automatically whenever the layout changes.
    Q_INVOKABLE void load();
    Q_INVOKABLE void save() const;

signals:
    void currentPageChanged();
    void leftVisibleChanged();
    void rightVisibleChanged();
    void leftElementsChanged();
    void rightElementsChanged();
    void activePagesChanged();

private:
    QString m_currentPage = QStringLiteral("nav");
    QStringList m_runCatalog;
    QStringList m_activePages;
    QHash<QString, bool> m_leftVis;
    QHash<QString, bool> m_rightVis;
    QStringList m_leftEls;
    QStringList m_rightEls;
};
