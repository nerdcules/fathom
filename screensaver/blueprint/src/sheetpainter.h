#pragma once

#include <QColor>
#include <QDate>
#include <QFont>
#include <QImage>
#include <QPainter>
#include <QPolygonF>
#include <QRectF>
#include <QSize>
#include <QVector>

#include "catalog.h"

struct SheetInfo {
    int sheetNumber = 1, sheetCount = 1;
    QString drawnBy, revision = "A";
    QDate date;
};

// One pen movement on the sheet, in pixels: a polyline or a run of lettering.
// The sheet is drawn by replaying these in order up to a progress fraction.
struct Stroke {
    enum Kind { Line, Text };
    Kind kind = Line;
    QPolygonF points;
    double width = 1;          // multiplier on the ink pen
    bool dashed = false, fill = false, paper = false;
    QString text;
    QPointF anchor;            // baseline start of the lettering
    double rotation = 0, size = 12, advance = 0, ascent = 0, descent = 0;
    bool background = false;
    QColor backgroundColor;
    double length = 0;         // pen travel, so lettering and lines share one clock
};

// Where everything sits on a sheet of a given pixel size.
struct SheetLayout {
    QSize size;
    QRectF outer, inner, band, notes, title, diagram;
    QRectF cells[8];           // title, dwg no, category, sheet, scale, drawn, date, rev
    double zone = 0, scale = 1;
    QPointF origin;            // diagram unit (0,0) in pixels
    QPointF px(const QPointF &u) const { return origin + u * scale; }
    QPointF px(double x, double y) const { return px(QPointF(x, y)); }
    double px(double units) const { return units * scale; }
};

// Paints diagrams as cyanotype blueprints: blue paper with a drafting frame,
// white ink lettered in capitals, and a title block in the corner.
class SheetPainter {
public:
    SheetPainter();

    static QFont letteringFont();

    SheetLayout layout(const QSize &size) const;
    QImage paper(const SheetLayout &layout) const;
    QColor paperColorAt(const SheetLayout &layout, const QPointF &p) const;
    QVector<Stroke> strokes(const Diagram &diagram, const SheetInfo &info, const SheetLayout &layout) const;
    static double totalLength(const QVector<Stroke> &strokes);

    // Replays the strokes up to progress (0..1 of the total pen travel) at the
    // given opacity, with the pen tip glowing where the ink is still wet.
    void paintStrokes(QPainter &painter, const QVector<Stroke> &strokes, double progress, double alpha,
                      bool showTip, const QImage *paper = nullptr) const;

    // Everything at once: paper, strokes, done. For snapshots and tests.
    QImage render(const Diagram &diagram, const SheetInfo &info, const QSize &size, double progress = 1) const;

    QColor ink() const { return m_ink; }

private:
    struct Builder;
    QColor m_ink, m_paperCenter, m_paperEdge;
    QFont m_font;
};
