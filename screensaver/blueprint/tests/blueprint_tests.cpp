#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTemporaryDir>
#include <QtTest>

#include "catalog.h"
#include "sheetpainter.h"
#include "show.h"
#include "theme.h"
#include "translator.h"

class BlueprintTests : public QObject {
    Q_OBJECT

    static int brightPixels(const QImage &image) {
        int count = 0;
        for (int y = 0; y < image.height(); ++y) {
            const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
            for (int x = 0; x < image.width(); ++x)
                if (qRed(line[x]) > 200 && qGreen(line[x]) > 200) ++count;
        }
        return count;
    }

private slots:
    void bundledCatalogIsClean()
    {
        Catalog catalog;
        catalog.loadBundled();
        QVERIFY2(catalog.problems().isEmpty(), qPrintable(catalog.problems().join("\n")));
        QVERIFY(catalog.diagrams().size() >= 15);
        for (const auto &d : catalog.diagrams()) {
            QVERIFY2(!d.notes.isEmpty(), qPrintable(d.id + " has no notes"));
            QVERIFY2(!d.number.isEmpty(), qPrintable(d.id + " has no drawing number"));
        }
    }

    void parseReportsBrokenReferences()
    {
        const auto object = QJsonDocument::fromJson(R"({
            "id": "broken", "title": "BROKEN",
            "nodes": [{"id": "a", "label": "A", "x": 0, "y": 0, "w": 10, "h": 5}],
            "edges": [{"from": "a", "to": "ghost"}],
            "callouts": [{"node": "a", "n": 2}]
        })").object();
        QStringList problems;
        Catalog::parse(object, "test", &problems);
        QCOMPARE(problems.size(), 2);
        QVERIFY(problems[0].contains("ghost"));
        QVERIFY(problems[1].contains("note"));
    }

    void userDirectoryAddsDiagramsAndRejectsDuplicates()
    {
        QTemporaryDir dir;
        write(dir.filePath("mine.json"), R"({"id": "mine", "title": "MINE", "notes": ["X."],
            "nodes": [{"id": "a", "label": "A", "x": 10, "y": 10, "w": 20, "h": 10}]})");
        write(dir.filePath("dupe.json"), R"({"id": "observer", "title": "AGAIN",
            "nodes": [{"id": "a", "label": "A", "x": 10, "y": 10, "w": 20, "h": 10}]})");
        write(dir.filePath("bad.json"), "{ not json");

        Catalog catalog;
        catalog.loadBundled();
        const int bundled = catalog.diagrams().size();
        catalog.loadDirectory(dir.path());
        QCOMPARE(catalog.diagrams().size(), bundled + 1);
        QVERIFY(catalog.indexOf("mine") == bundled);
        QCOMPARE(catalog.problems().size(), 2);
    }

    void inkGrowsWithProgress()
    {
        Catalog catalog;
        catalog.loadBundled();
        SheetPainter painter;
        SheetInfo info;
        info.sheetCount = catalog.diagrams().size();
        const Diagram &d = catalog.diagrams().first();
        const QSize size(900, 520);
        const int blank = brightPixels(painter.render(d, info, size, 0));
        const int half = brightPixels(painter.render(d, info, size, 0.5));
        const int full = brightPixels(painter.render(d, info, size, 1));
        QVERIFY(blank < half);
        QVERIFY(half < full);
        QVERIFY(full > 2000);
    }

    void everyDiagramRendersWithinTheSheet()
    {
        Catalog catalog;
        catalog.loadBundled();
        SheetPainter painter;
        const SheetLayout layout = painter.layout(QSize(1600, 1000));
        for (const auto &d : catalog.diagrams()) {
            SheetInfo info;
            for (const auto &s : painter.strokes(d, info, layout)) {
                for (const auto &p : s.points)
                    QVERIFY2(layout.inner.adjusted(-2, -2, 2, 2).contains(p),
                             qPrintable(QString("%1 draws outside the frame at %2,%3 (%4)").arg(d.id).arg(p.x()).arg(p.y()).arg(s.text)));
                if (s.kind == Stroke::Text)
                    QVERIFY2(layout.inner.contains(s.anchor), qPrintable(d.id + " letters outside the frame: " + s.text));
            }
        }
    }

    void showWalksThroughPhasesAndDeals()
    {
        Catalog catalog;
        catalog.loadBundled();
        Show::Options options;
        options.drawSeconds = 2;
        options.holdSeconds = 1;
        options.fadeSeconds = 1;
        Show show(catalog, options);
        show.togglePause();
        QVERIFY(show.paused());
        const int first = show.sheet();

        show.advance(1);
        QCOMPARE(show.progress(), 0.5);
        QCOMPARE(show.phase(), Show::Drawing);
        show.advance(1.1);
        QCOMPARE(show.progress(), 1.0);
        QCOMPARE(show.phase(), Show::Holding);
        show.advance(1.1);
        QCOMPARE(show.phase(), Show::Fading);
        show.advance(0.5);
        QVERIFY(show.alpha() < 0.6 && show.alpha() > 0.4);
        show.advance(0.6);
        QCOMPARE(show.phase(), Show::Drawing);
        QVERIFY(show.sheet() != first);
        QCOMPARE(show.progress(), 0.0);

        show.previous();
        QCOMPARE(show.sheet(), first);
        show.next();
        QVERIFY(show.sheet() != first);
    }

    void deckShowsEverySheetBeforeRepeating()
    {
        Catalog catalog;
        catalog.loadBundled();
        Show show(catalog, Show::Options{});
        show.togglePause();
        QSet<int> seen{show.sheet()};
        for (int i = 1; i < catalog.diagrams().size(); ++i) {
            show.next();
            QVERIFY2(!seen.contains(show.sheet()), "a sheet repeated before the deck ran out");
            seen.insert(show.sheet());
        }
        QCOMPARE(seen.size(), catalog.diagrams().size());
        const int last = show.sheet();
        show.next();
        QVERIFY(show.sheet() != last);
    }

    void onlyPinsOneDiagram()
    {
        Catalog catalog;
        catalog.loadBundled();
        Show::Options options;
        options.only = "cqrs";
        Show show(catalog, options);
        show.togglePause();
        QCOMPARE(show.title(), QString("CQRS"));
        show.next();
        QCOMPARE(show.title(), QString("CQRS"));
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "accent = \"#112233\"\n");
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "da\n");
        write(dir.path() + "/da.json", R"({"SHEET": "ARK"})");
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("da"));
        QCOMPARE(translator.translate("Sheet", "SHEET"), QString("ARK"));
        QVERIFY(translator.translate("Sheet", "SCALE").isNull());
    }

    void bundledDanishCoversTheSheetLabels()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "da\n");
        Translator translator(dir.path() + "/language", ":/i18n");
        for (const char *label : {"NOTES", "SHEET", "SCALE", "DRAWN", "DATE", "TITLE", "DWG NO."})
            QVERIFY2(!translator.translate("Sheet", label).isEmpty(), label);
    }

private:
    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
};

QTEST_MAIN(BlueprintTests)
#include "blueprint_tests.moc"
