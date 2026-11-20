// blueprint - draws software patterns and architectures as old blueprints,
// as a desktop viewer and as the Omarchy screensaver.

#include <QCommandLineParser>
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "catalog.h"
#include "cli.h"
#include "sheetview.h"
#include "show.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    QStringList arguments;
    for (int i = 0; i < argc; ++i)
        arguments.append(QString::fromLocal8Bit(argv[i]));

    // The display-free commands still need fonts, so they run a GUI app on the
    // offscreen platform and never open a window.
    if (isCliCommand(arguments)) {
        qputenv("QT_QPA_PLATFORM", "offscreen");
        QGuiApplication app(argc, argv);
        app.setApplicationName("blueprint");
        return runCli(arguments);
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("blueprint");
    app.setApplicationVersion("0.1.0");

    QCommandLineParser parser;
    parser.setApplicationDescription("Software patterns and architectures, drawn as blueprints.");
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption({"screensaver", "Run as a screensaver: fullscreen, no cursor, any input quits."});
    parser.addOption({"app-id", "Wayland app id to use with --screensaver.", "id", "org.omarchy.screensaver"});
    parser.addOption({"fullscreen", "Start fullscreen."});
    parser.addOption({"draw", "Seconds spent inking each sheet.", "seconds", "7"});
    parser.addOption({"hold", "Seconds a finished sheet stays up.", "seconds", "14"});
    parser.addOption({"fade", "Seconds to fade a sheet out.", "seconds", "1.2"});
    parser.addOption({"diagrams", "Extra directory of diagram JSON files.", "dir"});
    parser.addOption({"drawn", "Name for the DRAWN cell of the title block (default: your login).", "name"});
    parser.addOption({"only", "Show one diagram, by id, on repeat.", "id"});
    parser.addOption({"start", "Diagram id to open with.", "id"});
    parser.process(app);

    const bool screensaver = parser.isSet("screensaver");
    // Matches the window to blueprint.desktop so the launcher shows its icon;
    // as a screensaver it borrows Omarchy's class so the compositor rules and
    // the idle service treat it like the stock one.
    app.setDesktopFileName(screensaver ? parser.value("app-id") : "blueprint");
    app.setWindowIcon(QIcon::fromTheme("blueprint"));
    QQuickStyle::setStyle("Material");

    Translator translator;
    app.installTranslator(&translator);
    Theme theme;

    Catalog catalog;
    catalog.loadBundled();
    catalog.loadDirectory(QDir::homePath() + "/.config/blueprint/diagrams");
    if (parser.isSet("diagrams"))
        catalog.loadDirectory(parser.value("diagrams"));

    Show::Options options;
    options.screensaver = screensaver;
    options.drawSeconds = parser.value("draw").toDouble();
    options.holdSeconds = parser.value("hold").toDouble();
    options.fadeSeconds = parser.value("fade").toDouble();
    options.drawnBy = parser.isSet("drawn") ? parser.value("drawn") : qEnvironmentVariable("USER").toUpper();
    options.only = parser.value("only");
    options.start = parser.value("start");
    Show show(catalog, options);

    if (screensaver) {
        // Every monitor runs its own copy; ending one ends them all, the way
        // the terminal screensavers do, by the class they carry in argv.
        QObject::connect(&app, &QGuiApplication::aboutToQuit, [id = parser.value("app-id")] {
            QProcess::startDetached("pkill", {"-f", "[" + id.left(1) + "]" + id.mid(1)});
        });
    }

    qmlRegisterType<SheetView>("Blueprint", 1, 0, "SheetView");

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("slideshow", &show);
    engine.rootContext()->setContextProperty("startFullscreen", parser.isSet("fullscreen"));
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
