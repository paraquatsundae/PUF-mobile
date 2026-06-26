#pragma once

#include <QObject>
#include <QString>

// Android phone helpers: keep-screen-on, background recording service, cellular tier.
class PhonePlatform : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString cellularGeneration READ cellularGeneration NOTIFY cellularGenerationChanged)
    Q_PROPERTY(int statusBarInset READ statusBarInset NOTIFY statusBarInsetChanged)
    Q_PROPERTY(int navigationBarInset READ navigationBarInset NOTIFY navigationBarInsetChanged)

public:
    explicit PhonePlatform(QObject *parent = nullptr);

    QString cellularGeneration() const { return m_cellular; }
    int statusBarInset() const { return m_statusInset; }
    int navigationBarInset() const { return m_navInset; }

    Q_INVOKABLE void setKeepScreenOn(bool on);
    Q_INVOKABLE void setBackgroundRecording(bool on);
    Q_INVOKABLE void refreshCellularGeneration();
    // Match Theme.banner / Theme.bg on the Android system bars and window backdrop.
    // dark = true keeps the original dark chrome; false applies the light palette
    // (light bars with dark status/nav icons).
    Q_INVOKABLE void applySystemChrome(bool dark);
    Q_INVOKABLE void refreshSystemInsets();
    Q_INVOKABLE void refreshNavigationBarInset();

signals:
    void cellularGenerationChanged();
    void statusBarInsetChanged();
    void navigationBarInsetChanged();

private slots:
    void setInsetsFromAndroid(int top, int bottom);

private:
    QString m_cellular;
    int m_statusInset = 0;
    int m_navInset = 0;
};
