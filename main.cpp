#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "gpsmodel.h"
#include "appcontroller.h"
#include "layoutmanager.h"
#include "coverage.h"
#include "farmstore.h"
#include "jobstore.h"
#include "workcatalog.h"
#include "rxmap.h"
#include "phoneplatform.h"
#include "theme.h"
#include "basemapstore.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    // Android: load bundled libssl_1_1 / libcrypto_1_1 (see android_openssl).
    // Must be set before any QNetworkAccessManager / QSslSocket use.
#ifdef Q_OS_ANDROID
    qputenv("ANDROID_OPENSSL_SUFFIX", "_1_1");
#endif
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("PUFworks"));
    app.setApplicationName(QStringLiteral("PUF-mobile"));

    GpsModel gps;
    AppController controller(&gps);
    LayoutManager layout;
    Coverage coverage;
    FarmStore farm;
    JobStore jobs;
    WorkCatalog catalog;
    RxMap rx;
    PhonePlatform platform;
    Theme theme;
    BasemapStore basemap;
    // Restore persisted machine setup + layout before the UI binds to them.
    controller.loadSettings();
    layout.load();
    farm.setGpsModel(&gps);
    farm.seedBundledFarmIfEmpty();
    farm.load();
    catalog.load();

    // Save-on-exit / save-on-background: persist the active job + its coverage when
    // the app is backgrounded or quits, closing the "unclean exit loses the job"
    // gap (PLAN §2). requestSave() drives FieldView (which owns the live coverage
    // geometry) to write metadata.json + coverage.geojson via JobStore.
    QObject::connect(&app, &QGuiApplication::applicationStateChanged,
                     [&jobs](Qt::ApplicationState st) {
                         if (st == Qt::ApplicationInactive || st == Qt::ApplicationSuspended)
                             jobs.requestSave();
                     });
    QObject::connect(&app, &QGuiApplication::aboutToQuit, [&jobs]() { jobs.requestSave(); });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("gps"), &gps);
    engine.rootContext()->setContextProperty(QStringLiteral("app"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("layout"), &layout);
    engine.rootContext()->setContextProperty(QStringLiteral("coverage"), &coverage);
    engine.rootContext()->setContextProperty(QStringLiteral("farm"), &farm);
    engine.rootContext()->setContextProperty(QStringLiteral("jobs"), &jobs);
    engine.rootContext()->setContextProperty(QStringLiteral("catalog"), &catalog);
    engine.rootContext()->setContextProperty(QStringLiteral("rx"), &rx);
    engine.rootContext()->setContextProperty(QStringLiteral("platform"), &platform);
    engine.rootContext()->setContextProperty(QStringLiteral("theme"), &theme);
    engine.rootContext()->setContextProperty(QStringLiteral("basemap"), &basemap);

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
