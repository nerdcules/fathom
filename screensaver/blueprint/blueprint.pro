QT += core gui qml quick quickcontrols2 dbus

CONFIG += c++17 release
TARGET = blueprint
TEMPLATE = app

HEADERS += \
    src/catalog.h \
    src/cli.h \
    src/sheetpainter.h \
    src/sheetview.h \
    src/show.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/catalog.cpp \
    src/cli.cpp \
    src/sheetpainter.cpp \
    src/sheetview.cpp \
    src/show.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
