# Host-only replay/tuning harness for the shared GPS smoothing filter.
# Qt-free console app: it compiles the SAME gpsfilter.cpp the phone/tablet use.
#
#   qmake && make            (or nmake / jom on MSVC)
#   ./gps_replay <input.csv> [width_m] [output.csv]

TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
QT -= core gui

TARGET = gps_replay

INCLUDEPATH += $$PWD/../..
SOURCES += \
    replay.cpp \
    $$PWD/../../gpsfilter.cpp
