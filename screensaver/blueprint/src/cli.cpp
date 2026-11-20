#include "cli.h"

#include <QCommandLineParser>
#include <QDate>
#include <QDir>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

#include "catalog.h"
#include "sheetpainter.h"

static QString userDiagramDirectory() {
    return QDir::homePath() + "/.config/blueprint/diagrams";
}

bool isCliCommand(const QStringList &arguments) {
    for (int i = 1; i < arguments.size(); ++i) {
        const QString &a = arguments[i];
        if (a.startsWith('-')) continue;
        return a == "list" || a == "check" || a == "render";
    }
    return false;
}

static int list(QCommandLineParser &parser, const Catalog &catalog) {
    QTextStream out(stdout);
    if (parser.isSet("json")) {
        QJsonArray array;
        for (const auto &d : catalog.diagrams())
            array.append(QJsonObject{{"id", d.id}, {"title", d.title}, {"category", d.category}, {"number", d.number},
                                     {"source", d.source}, {"nodes", d.nodes.size()}, {"edges", d.edges.size()}});
        out << QJsonDocument(array).toJson();
    } else {
        for (const auto &d : catalog.diagrams())
            out << QString("%1  %2  %3\n").arg(d.number, -12).arg(d.id, -18).arg(d.title);
    }
    return 0;
}

static int check(QCommandLineParser &parser, Catalog &catalog) {
    const QStringList positional = parser.positionalArguments().mid(1);
    for (const auto &path : positional)
        catalog.loadFile(path);
    QTextStream out(stdout), err(stderr);
    if (parser.isSet("json")) {
        QJsonArray problems;
        for (const auto &p : catalog.problems()) problems.append(p);
        out << QJsonDocument(QJsonObject{{"diagrams", catalog.diagrams().size()}, {"problems", problems}}).toJson();
    } else {
        for (const auto &p : catalog.problems()) err << p << '\n';
        out << catalog.diagrams().size() << " diagrams, " << catalog.problems().size() << " problems\n";
    }
    return catalog.problems().isEmpty() ? 0 : 1;
}

static int render(QCommandLineParser &parser, const Catalog &catalog) {
    QTextStream err(stderr);
    const QStringList positional = parser.positionalArguments();
    if (positional.size() < 2) {
        err << "usage: blueprint render <out.png> [--sheet <id|n>] [--at <0..1>] [--size <WxH>] [--drawn <name>]\n";
        return 1;
    }
    if (catalog.diagrams().isEmpty()) {
        err << "no diagrams to render\n";
        return 1;
    }
    int index = 0;
    const QString sheet = parser.value("sheet");
    if (!sheet.isEmpty()) {
        bool number = false;
        const int n = sheet.toInt(&number);
        index = number ? n - 1 : catalog.indexOf(sheet);
        if (index < 0 || index >= catalog.diagrams().size()) {
            err << "unknown sheet " << sheet << '\n';
            return 1;
        }
    }
    QSize size(1920, 1200);
    const QStringList dims = parser.value("size").split('x');
    if (dims.size() == 2) size = QSize(dims[0].toInt(), dims[1].toInt());
    if (size.width() < 200 || size.height() < 120) {
        err << "size must be at least 200x120\n";
        return 1;
    }
    const double at = parser.isSet("at") ? qBound(0.0, parser.value("at").toDouble(), 1.0) : 1.0;

    SheetInfo info;
    info.sheetNumber = index + 1;
    info.sheetCount = catalog.diagrams().size();
    info.drawnBy = parser.value("drawn");
    info.date = QDate::currentDate();

    SheetPainter painter;
    const QImage image = painter.render(catalog.diagrams().at(index), info, size, at);
    if (!image.save(positional[1])) {
        err << "could not write " << positional[1] << '\n';
        return 1;
    }
    if (parser.isSet("json"))
        QTextStream(stdout) << QJsonDocument(QJsonObject{{"file", positional[1]}, {"sheet", catalog.diagrams().at(index).id},
                                                         {"width", size.width()}, {"height", size.height()}}).toJson();
    return 0;
}

int runCli(const QStringList &arguments) {
    QCommandLineParser parser;
    parser.addPositionalArgument("command", "list | check [files...] | render <out.png>");
    parser.addOption({"json", "Print machine-readable JSON."});
    parser.addOption({"sheet", "Diagram id or 1-based number to render.", "id"});
    parser.addOption({"at", "Drawing progress to render, 0 to 1.", "fraction", "1"});
    parser.addOption({"size", "Image size, e.g. 1920x1200.", "WxH", "1920x1200"});
    parser.addOption({"drawn", "Name for the DRAWN cell of the title block.", "name"});
    parser.addOption({"diagrams", "Extra directory of diagram JSON files.", "dir"});
    parser.addOption({"no-user", "Skip ~/.config/blueprint/diagrams."});
    parser.addHelpOption();
    parser.process(arguments);

    Catalog catalog;
    catalog.loadBundled();
    if (!parser.isSet("no-user"))
        catalog.loadDirectory(userDiagramDirectory());
    if (parser.isSet("diagrams"))
        catalog.loadDirectory(parser.value("diagrams"));

    const QString command = parser.positionalArguments().value(0);
    if (command == "list") return list(parser, catalog);
    if (command == "check") return check(parser, catalog);
    if (command == "render") return render(parser, catalog);
    QTextStream(stderr) << parser.helpText();
    return 1;
}
