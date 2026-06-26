QT += quick network
CONFIG += c++17

# PUF-mobile: native lib name (libpufmobile_<abi>.so) and default APK base name.
TARGET = pufmobile

HEADERS += \
    gpsmodel.h \
    gpsfilter.h \
    gpssource.h \
    udpgpssource.h \
    appcontroller.h \
    layoutmanager.h \
    coverage.h \
    farmdata.h \
    taskdata.h \
    kmlimport.h \
    farmstore.h \
    jobstore.h \
    workcatalog.h \
    rxmap.h \
    cangpssource.h \
    btgpssource.h \
    tabletgpssource.h \
    phoneplatform.h \
    theme.h

SOURCES += \
    main.cpp \
    gpsmodel.cpp \
    gpsfilter.cpp \
    udpgpssource.cpp \
    appcontroller.cpp \
    layoutmanager.cpp \
    coverage.cpp \
    taskdata.cpp \
    kmlimport.cpp \
    farmstore.cpp \
    jobstore.cpp \
    workcatalog.cpp \
    rxmap.cpp \
    cangpssource.cpp \
    btgpssource.cpp \
    tabletgpssource.cpp \
    phoneplatform.cpp \
    theme.cpp

RESOURCES += qml.qrc

# Desktop QtSerialPort backend (PC COM-port testing).
!android {
    QT += serialport
    DEFINES += HAVE_SERIAL
    HEADERS += serialgpssource.h
    SOURCES += serialgpssource.cpp
}

# Raw POSIX/termios backend for Linux TTYs, incl. the tablet's internal GNSS
# on /dev/ttyS0. Works on Android without the USB Host API.
android|linux {
    DEFINES += HAVE_POSIX_SERIAL
    HEADERS += posixserialgpssource.h
    SOURCES += posixserialgpssource.cpp
}

# Android: QtAndroid (runtime storage permission for KML import) + custom
# manifest carrying READ_EXTERNAL_STORAGE.
android {
    QT += androidextras
    ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
}

ANDROID_MIN_SDK_VERSION = 23
# Pinned to 29 so android:requestLegacyExternalStorage is honored on Android 10/11
# (lets the app read non-media files like TASKDATA.XML in Download under scoped
# storage). Raising to >= 30 would re-enable scoped storage and break KML import.
ANDROID_TARGET_SDK_VERSION = 29
