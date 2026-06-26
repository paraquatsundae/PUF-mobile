#pragma once

#include <QColor>
#include <QObject>

// Runtime-switchable phone palette. Style.js stays the static dark source for the
// tablet UI; the phone QML binds to these reactive colours so the whole shell can
// flip between the dark palette (default) and a sunlight-readable light palette
// without a restart. The choice is persisted via QSettings (same store as
// AppController), following the saveSettings/loadSettings pattern.
class Theme : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(QColor bg READ bg NOTIFY darkChanged)
    Q_PROPERTY(QColor banner READ banner NOTIFY darkChanged)
    Q_PROPERTY(QColor bannerHi READ bannerHi NOTIFY darkChanged)
    Q_PROPERTY(QColor panel READ panel NOTIFY darkChanged)
    Q_PROPERTY(QColor panelEdge READ panelEdge NOTIFY darkChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY darkChanged)
    // Text/glyph colour to use on top of an accent-filled button.
    Q_PROPERTY(QColor accentText READ accentText NOTIFY darkChanged)
    Q_PROPERTY(QColor textDim READ textDim NOTIFY darkChanged)
    Q_PROPERTY(QColor text READ text NOTIFY darkChanged)
    Q_PROPERTY(QColor gridMinor READ gridMinor NOTIFY darkChanged)
    // Map "ground" fill behind the coverage swaths.
    Q_PROPERTY(QColor mapField READ mapField NOTIFY darkChanged)

public:
    explicit Theme(QObject *parent = nullptr);

    bool dark() const { return m_dark; }
    void setDark(bool on);
    Q_INVOKABLE void toggle() { setDark(!m_dark); }

    QColor bg() const         { return m_dark ? QColor("#0e1714") : QColor("#f4f7f4"); }
    QColor banner() const     { return m_dark ? QColor("#0b1310") : QColor("#dfe8e2"); }
    QColor bannerHi() const   { return m_dark ? QColor("#13201b") : QColor("#cdd9d0"); }
    QColor panel() const      { return m_dark ? QColor("#16241f") : QColor("#ffffff"); }
    QColor panelEdge() const  { return m_dark ? QColor("#23362f") : QColor("#c2cfc7"); }
    QColor accent() const     { return m_dark ? QColor("#3ddc84") : QColor("#1f9d57"); }
    QColor accentText() const { return m_dark ? QColor("#0b1310") : QColor("#ffffff"); }
    QColor textDim() const    { return m_dark ? QColor("#9fb4ac") : QColor("#4f5e57"); }
    QColor text() const       { return m_dark ? QColor("#ffffff") : QColor("#10201a"); }
    QColor gridMinor() const  { return m_dark ? QColor("#a6ada7") : QColor("#b8c2bb"); }
    QColor mapField() const   { return m_dark ? QColor("#142018") : QColor("#e3ebe4"); }

signals:
    void darkChanged();

private:
    bool m_dark = true; // default: dark
};
