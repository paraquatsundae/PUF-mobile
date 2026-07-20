#include "phoneplatform.h"

#ifdef Q_OS_ANDROID
#include <QtAndroid>
#include <QAndroidJniObject>
#include <QAndroidJniEnvironment>
#include <QMetaObject>
#include <QDebug>
#endif

namespace {
#ifdef Q_OS_ANDROID
void readSystemBarInsets(int *top, int *bottom)
{
    *top = 0;
    *bottom = 0;
    QAndroidJniObject activity = QtAndroid::androidActivity();
    if (!activity.isValid())
        return;
    QAndroidJniObject arr = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/PhoneUiHelper", "systemBarInsets",
        "(Landroid/app/Activity;)[I", activity.object<jobject>());
    if (!arr.isValid())
        return;
    QAndroidJniEnvironment env;
    jintArray jarr = arr.object<jintArray>();
    const jsize len = env->GetArrayLength(jarr);
    if (len < 2)
        return;
    jint *elems = env->GetIntArrayElements(jarr, nullptr);
    *top = elems[0];
    *bottom = elems[1];
    env->ReleaseIntArrayElements(jarr, elems, JNI_ABORT);
    // All View/Window reads must stay on the Android UI thread (see setInsetsFromAndroid).
    if (*top <= 0) {
        *top = QAndroidJniObject::callStaticMethod<jint>(
            "org/qtproject/example/PhoneUiHelper", "statusBarInset",
            "(Landroid/app/Activity;)I", activity.object<jobject>());
    }
}
#endif
} // namespace

PhonePlatform::PhonePlatform(QObject *parent) : QObject(parent) {}

void PhonePlatform::setKeepScreenOn(bool on)
{
#ifdef Q_OS_ANDROID
    // Window flags touch the Android view hierarchy, which may ONLY be done on
    // the UI thread. This is invoked from QML on Qt's qtMainLoopThread, so marshal
    // it across or Android throws CalledFromWrongThreadException (fatal under JNI
    // CheckJNI). Mirrors applySystemChrome() below.
    QtAndroid::runOnAndroidThread([on]() {
        QAndroidJniObject activity = QtAndroid::androidActivity();
        if (!activity.isValid())
            return;
        QAndroidJniObject window = activity.callObjectMethod(
            "getWindow", "()Landroid/view/Window;");
        if (!window.isValid())
            return;
        const int flag = 128; // WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (on)
            window.callMethod<void>("addFlags", "(I)V", flag);
        else
            window.callMethod<void>("clearFlags", "(I)V", flag);
    });
#else
    Q_UNUSED(on)
#endif
}

void PhonePlatform::setBackgroundRecording(bool on)
{
#ifdef Q_OS_ANDROID
    QtAndroid::runOnAndroidThread([on]() {
        QAndroidJniObject activity = QtAndroid::androidActivity();
        if (!activity.isValid())
            return;
        if (on) {
            QAndroidJniObject::callStaticMethod<void>(
                "org/qtproject/example/RecordingService", "start",
                "(Landroid/content/Context;)V", activity.object<jobject>());
        } else {
            QAndroidJniObject::callStaticMethod<void>(
                "org/qtproject/example/RecordingService", "stop",
                "(Landroid/content/Context;)V", activity.object<jobject>());
        }
    });
#else
    Q_UNUSED(on)
#endif
}

void PhonePlatform::applySystemChrome(bool dark)
{
#ifdef Q_OS_ANDROID
    QtAndroid::runOnAndroidThread([dark, this]() {
        QAndroidJniObject activity = QtAndroid::androidActivity();
        if (!activity.isValid())
            return;
        QAndroidJniObject::callStaticMethod<void>(
            "org/qtproject/example/PhoneUiHelper", "applySystemUi",
            "(Landroid/app/Activity;Z)V", activity.object<jobject>(),
            static_cast<jboolean>(dark));

        QAndroidJniObject window = activity.callObjectMethod(
            "getWindow", "()Landroid/view/Window;");
        if (!window.isValid())
            return;
        QAndroidJniObject decor = window.callObjectMethod(
            "getDecorView", "()Landroid/view/View;");
        if (decor.isValid()) {
            const jint bg = dark ? 0xFF0b1310 : 0xFFdfe8e2; // Theme.banner
            decor.callMethod<void>("setBackgroundColor", "(I)V", bg);
        }

        int nextTop = 0;
        int nextBottom = 0;
        readSystemBarInsets(&nextTop, &nextBottom);
        QMetaObject::invokeMethod(this, "setInsetsFromAndroid",
                                  Qt::QueuedConnection,
                                  Q_ARG(int, nextTop), Q_ARG(int, nextBottom));
    });
#else
    Q_UNUSED(dark)
#endif
}

void PhonePlatform::setInsetsFromAndroid(int top, int bottom)
{
#ifdef Q_OS_ANDROID
    // Never touch Activity/Window/View from qtMainLoopThread — that throws
    // CalledFromWrongThreadException under CheckJNI and aborts the process.
    // Inset fallback reads belong in readSystemBarInsets() on the Android thread.
    // Samsung and other OEMs occasionally report stableInset* far larger than the
    // real status/gesture bands (hundreds of px), which leaves tall voids in the
    // phone shell. Cap absurd values; gesture nav is typically ~48 px.
    static const int kMaxStatusInset = 40;
    static const int kMaxNavInset = 56;
    static const int kAbsurdNavInset = 120;
    if (top > kMaxStatusInset) {
        qWarning() << "PhonePlatform: capping statusBarInset"
                   << top << "->" << kMaxStatusInset;
        top = kMaxStatusInset;
    }
    if (bottom > kAbsurdNavInset) {
        qWarning() << "PhonePlatform: capping absurd navigationBarInset"
                   << bottom << "->" << kMaxNavInset;
        bottom = kMaxNavInset;
    } else if (bottom > kMaxNavInset) {
        bottom = kMaxNavInset;
    }
#endif
    if (top != m_statusInset) {
        m_statusInset = top;
        emit statusBarInsetChanged();
    }
    if (bottom != m_navInset) {
        m_navInset = bottom;
        emit navigationBarInsetChanged();
    }
}

void PhonePlatform::refreshCellularGeneration()
{
    QString next;
#ifdef Q_OS_ANDROID
    const QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/qtproject/example/RecordingService", "cellularGeneration",
        "()Ljava/lang/String;");
    if (res.isValid())
        next = res.toString();
#endif
    if (next != m_cellular) {
        m_cellular = next;
        emit cellularGenerationChanged();
    }
}

void PhonePlatform::refreshSystemInsets()
{
#ifdef Q_OS_ANDROID
    QtAndroid::runOnAndroidThread([this]() {
        int nextTop = 0;
        int nextBottom = 0;
        readSystemBarInsets(&nextTop, &nextBottom);
        QMetaObject::invokeMethod(this, "setInsetsFromAndroid",
                                  Qt::QueuedConnection,
                                  Q_ARG(int, nextTop), Q_ARG(int, nextBottom));
    });
#endif
}

void PhonePlatform::refreshNavigationBarInset()
{
    refreshSystemInsets();
}
