QT += core gui quick quickcontrols2 testlib dbus
CONFIG += c++17 testcase
TARGET = blueprint_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/catalog.h ../src/sheetpainter.h ../src/show.h ../src/theme.h ../src/translator.h
SOURCES += blueprint_tests.cpp ../src/catalog.cpp ../src/sheetpainter.cpp ../src/show.cpp ../src/theme.cpp ../src/translator.cpp
RESOURCES += ../src/resources.qrc
