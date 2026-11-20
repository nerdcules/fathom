#include "sheetpainter.h"

#include <QCoreApplication>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QLineF>
#include <QPainterPath>
#include <QRandomGenerator>
#include <QtMath>
#include <cmath>

namespace {
const double kUnitsW = Diagram::Width, kUnitsH = Diagram::Height;

QColor mix(const QColor &a, const QColor &b, double t) {
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t);
}

QColor withAlpha(QColor c, int alpha) { c.setAlpha(alpha); return c; }

QString tr(const char *text) { return QCoreApplication::translate("Sheet", text); }

double polylineLength(const QPolygonF &points) {
    double length = 0;
    for (int i = 1; i < points.size(); ++i)
        length += QLineF(points[i - 1], points[i]).length();
    return length;
}

// The first `length` pixels of a polyline.
QPolygonF partial(const QPolygonF &points, double length) {
    QPolygonF out;
    if (points.isEmpty()) return out;
    out.append(points.first());
    for (int i = 1; i < points.size(); ++i) {
        QLineF segment(points[i - 1], points[i]);
        if (segment.length() <= length) {
            out.append(points[i]);
            length -= segment.length();
        } else {
            out.append(segment.pointAt(length / segment.length()));
            break;
        }
    }
    return out;
}

QPolygonF ellipsePoints(const QRectF &r, double startDeg, double spanDeg, int steps) {
    QPolygonF points;
    for (int i = 0; i <= steps; ++i) {
        const double a = qDegreesToRadians(startDeg + spanDeg * i / steps);
        points.append(QPointF(r.center().x() + r.width() / 2 * std::cos(a), r.center().y() - r.height() / 2 * std::sin(a)));
    }
    return points;
}
} // namespace

// Drafting lettering is monospaced capitals; the first of these present wins.
QFont SheetPainter::letteringFont() {
    const QStringList families = QFontDatabase::families();
    for (const char *wanted : {"iA Writer Mono S", "JetBrainsMono Nerd Font", "JetBrains Mono", "Noto Sans Mono"})
        if (families.contains(QString::fromLatin1(wanted)))
            return QFont(QString::fromLatin1(wanted));
    return QFontDatabase::systemFont(QFontDatabase::FixedFont);
}

SheetPainter::SheetPainter()
    : m_ink(236, 244, 255), m_paperCenter(30, 78, 142), m_paperEdge(19, 54, 104), m_font(letteringFont()) {
    m_font.setLetterSpacing(QFont::PercentageSpacing, 106);
}

SheetLayout SheetPainter::layout(const QSize &size) const {
    SheetLayout l;
    l.size = size;
    const double w = size.width(), h = size.height(), m = std::min(w, h);
    const double margin = m * 0.022;
    l.zone = m * 0.026;
    l.outer = QRectF(margin, margin, w - 2 * margin, h - 2 * margin);
    l.inner = l.outer.adjusted(l.zone, l.zone, -l.zone, -l.zone);

    const double bandHeight = l.inner.height() * 0.17;
    l.band = QRectF(l.inner.left(), l.inner.bottom() - bandHeight, l.inner.width(), bandHeight);
    const double titleWidth = l.inner.width() * 0.38;
    l.title = QRectF(l.band.right() - titleWidth, l.band.top(), titleWidth, bandHeight);
    l.notes = QRectF(l.band.left(), l.band.top(), l.band.width() - titleWidth, bandHeight);

    const double r1 = bandHeight * 0.40, r2 = bandHeight * 0.25, r3 = bandHeight - r1 - r2;
    const double split = titleWidth * 0.68;
    l.cells[0] = QRectF(l.title.left(), l.title.top(), split, r1);
    l.cells[1] = QRectF(l.title.left() + split, l.title.top(), titleWidth - split, r1);
    l.cells[2] = QRectF(l.title.left(), l.title.top() + r1, split, r2);
    l.cells[3] = QRectF(l.title.left() + split, l.title.top() + r1, titleWidth - split, r2);
    for (int i = 0; i < 4; ++i)
        l.cells[4 + i] = QRectF(l.title.left() + titleWidth * i / 4, l.title.top() + r1 + r2, titleWidth / 4, r3);

    const double pad = m * 0.03;
    const QRectF area(l.inner.left() + pad, l.inner.top() + pad, l.inner.width() - 2 * pad, l.band.top() - l.inner.top() - 2 * pad);
    l.scale = std::min(area.width() / kUnitsW, area.height() / kUnitsH);
    l.diagram = QRectF(0, 0, kUnitsW * l.scale, kUnitsH * l.scale);
    l.diagram.moveCenter(area.center());
    l.origin = l.diagram.topLeft();
    return l;
}

QColor SheetPainter::paperColorAt(const SheetLayout &layout, const QPointF &p) const {
    const QPointF c(layout.size.width() / 2.0, layout.size.height() / 2.0);
    const double r = QLineF(c, p).length() / QLineF(QPointF(0, 0), c).length();
    return mix(m_paperCenter, m_paperEdge, std::pow(std::min(1.0, r), 1.4));
}

QImage SheetPainter::paper(const SheetLayout &l) const {
    QImage image(l.size, QImage::Format_RGB32);
    const int w = l.size.width(), h = l.size.height();
    const QPointF c(w / 2.0, h / 2.0);
    const double radius = QLineF(QPointF(0, 0), c).length();
    QRandomGenerator noise(7);
    for (int y = 0; y < h; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < w; ++x) {
            const double r = std::hypot(x - c.x(), y - c.y()) / radius;
            const QColor base = mix(m_paperCenter, m_paperEdge, std::pow(std::min(1.0, r), 1.4));
            // Cyanotype paper is never flat: a grain of a few levels per channel.
            const int grain = int(noise.bounded(13)) - 6;
            line[x] = qRgb(qBound(0, base.red() + grain, 255), qBound(0, base.green() + grain, 255),
                           qBound(0, base.blue() + grain, 255));
        }
    }

    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);

    // Grid: two diagram units, heavier every ten, clipped to the frame.
    p.setClipRect(l.inner);
    const double g = l.px(2.0);
    const QPointF o = l.origin;
    for (int i = int(std::floor((l.inner.left() - o.x()) / g)); o.x() + i * g <= l.inner.right(); ++i) {
        const double x = o.x() + i * g;
        p.setPen(QPen(withAlpha(m_ink, i % 5 == 0 ? 40 : 20), 1));
        p.drawLine(QPointF(x, l.inner.top()), QPointF(x, l.inner.bottom()));
    }
    for (int j = int(std::floor((l.inner.top() - o.y()) / g)); o.y() + j * g <= l.inner.bottom(); ++j) {
        const double y = o.y() + j * g;
        p.setPen(QPen(withAlpha(m_ink, j % 5 == 0 ? 40 : 20), 1));
        p.drawLine(QPointF(l.inner.left(), y), QPointF(l.inner.right(), y));
    }
    p.setClipping(false);

    // Fold creases, where the print was kept folded in a drawer.
    p.setPen(QPen(withAlpha(QColor(255, 255, 255), 22), 2));
    p.drawLine(QPointF(w / 2.0, 0), QPointF(w / 2.0, h));
    p.drawLine(QPointF(0, h / 2.0), QPointF(w, h / 2.0));
    p.setPen(QPen(withAlpha(QColor(255, 255, 255), 11), 1.5));
    p.drawLine(QPointF(w / 4.0, 0), QPointF(w / 4.0, h));
    p.drawLine(QPointF(3 * w / 4.0, 0), QPointF(3 * w / 4.0, h));

    // Frame and zone band with its grid references.
    p.setPen(QPen(withAlpha(m_ink, 235), 2.2));
    p.drawRect(l.outer);
    p.setPen(QPen(withAlpha(m_ink, 235), 1.2));
    p.drawRect(l.inner);

    QFont zoneFont = m_font;
    zoneFont.setPixelSize(std::max(8.0, l.zone * 0.55));
    p.setFont(zoneFont);
    p.setPen(QPen(withAlpha(m_ink, 200), 1));
    const int columns = 8, rows = 6;
    for (int i = 0; i <= columns; ++i) {
        const double x = l.outer.left() + l.outer.width() * i / columns;
        if (i > 0 && i < columns) {
            p.drawLine(QPointF(x, l.outer.top()), QPointF(x, l.inner.top()));
            p.drawLine(QPointF(x, l.inner.bottom()), QPointF(x, l.outer.bottom()));
        }
        if (i < columns) {
            const QRectF top(x, l.outer.top(), l.outer.width() / columns, l.zone);
            const QRectF bottom(x, l.inner.bottom(), l.outer.width() / columns, l.zone);
            p.drawText(top, Qt::AlignCenter, QString::number(columns - i));
            p.drawText(bottom, Qt::AlignCenter, QString::number(columns - i));
        }
    }
    for (int j = 0; j <= rows; ++j) {
        const double y = l.outer.top() + l.outer.height() * j / rows;
        if (j > 0 && j < rows) {
            p.drawLine(QPointF(l.outer.left(), y), QPointF(l.inner.left(), y));
            p.drawLine(QPointF(l.inner.right(), y), QPointF(l.outer.right(), y));
        }
        if (j < rows) {
            const QRectF left(l.outer.left(), y, l.zone, l.outer.height() / rows);
            const QRectF right(l.inner.right(), y, l.zone, l.outer.height() / rows);
            const QString letter = QString(QChar('A' + j));
            p.drawText(left, Qt::AlignCenter, letter);
            p.drawText(right, Qt::AlignCenter, letter);
        }
    }

    // Bottom band: notes on the left, the title block on the right.
    p.setPen(QPen(withAlpha(m_ink, 235), 1.6));
    p.drawLine(l.band.topLeft(), l.band.topRight());
    p.setPen(QPen(withAlpha(m_ink, 235), 1.2));
    for (const auto &cell : l.cells)
        p.drawRect(cell);
    p.setPen(QPen(withAlpha(m_ink, 235), 2));
    p.drawRect(l.title);
    return image;
}

// Builds the stroke list for one sheet. Everything here is in pixels.
struct SheetPainter::Builder {
    const SheetPainter &sp;
    const SheetLayout &l;
    QVector<Stroke> out;

    Builder(const SheetPainter &painter, const SheetLayout &layout) : sp(painter), l(layout) {}

    QFont fontAt(double px) const {
        QFont f = sp.m_font;
        f.setPixelSize(std::max(1, int(std::lround(px))));
        return f;
    }

    void line(const QPolygonF &points, double width = 1, bool dashed = false, bool fill = false) {
        Stroke s;
        s.points = points;
        s.width = width;
        s.dashed = dashed;
        s.fill = fill;
        s.length = polylineLength(points);
        out.append(s);
    }

    // Letters a run of text centered on `center`, shrunk to `maxWidth` if set.
    void text(const QString &raw, const QPointF &center, double px, double rotation = 0, bool background = false,
              double maxWidth = 0) {
        const QString t = raw.toUpper();
        if (t.isEmpty()) return;
        QFontMetricsF fm(fontAt(px));
        if (maxWidth > 0 && fm.horizontalAdvance(t) > maxWidth) {
            px = std::max(6.0, px * maxWidth / fm.horizontalAdvance(t));
            fm = QFontMetricsF(fontAt(px));
        }
        Stroke s;
        s.kind = Stroke::Text;
        s.text = t;
        s.size = px;
        s.rotation = rotation;
        s.advance = fm.horizontalAdvance(t);
        s.ascent = fm.capHeight();
        s.descent = fm.descent() * 0.4;
        // The text frame has its baseline at the origin; place its centre on `center`.
        const QPointF local(s.advance / 2, (s.descent - s.ascent) / 2);
        const double a = qDegreesToRadians(rotation);
        const QPointF rotated(local.x() * std::cos(a) - local.y() * std::sin(a), local.x() * std::sin(a) + local.y() * std::cos(a));
        s.anchor = center - rotated;
        s.background = background;
        s.backgroundColor = sp.paperColorAt(l, center);
        s.length = s.advance * 1.6;
        out.append(s);
    }

    void textLeft(const QString &raw, const QPointF &baselineStart, double px, double maxWidth = 0) {
        QFontMetricsF fm(fontAt(px));
        const QString t = raw.toUpper();
        double advance = fm.horizontalAdvance(t);
        if (maxWidth > 0 && advance > maxWidth) {
            px = std::max(6.0, px * maxWidth / advance);
            advance = QFontMetricsF(fontAt(px)).horizontalAdvance(t);
        }
        const QFontMetricsF m(fontAt(px));
        text(t, baselineStart + QPointF(advance / 2, (m.descent() * 0.4 - m.capHeight()) / 2), px);
    }

    // Where a connection leaves a node: a waypoint square on to one side
    // meets that side at a right angle, anything else aims at the centre.
    QPointF boundary(const Node &node, const QPointF &towards, bool viaPoint = false) const {
        const QRectF r(l.px(node.rect.topLeft()), QSizeF(l.px(node.rect.width()), l.px(node.rect.height())));
        const QPointF c = r.center();
        QPointF d = towards - c;
        if (qFuzzyIsNull(d.x()) && qFuzzyIsNull(d.y())) return c;
        if (viaPoint && node.shape != "circle" && node.shape != "actor") {
            if (towards.x() >= r.left() && towards.x() <= r.right())
                return QPointF(towards.x(), towards.y() < c.y() ? r.top() : r.bottom());
            if (towards.y() >= r.top() && towards.y() <= r.bottom())
                return QPointF(towards.x() < c.x() ? r.left() : r.right(), towards.y());
        }
        if (node.shape == "circle") {
            const double a = std::atan2(d.y() / (r.height() / 2), d.x() / (r.width() / 2));
            return c + QPointF(r.width() / 2 * std::cos(a), r.height() / 2 * std::sin(a));
        }
        if (node.shape == "actor") {
            // The figure is narrower than its box; aim at the body.
            const QRectF body(c.x() - r.width() * 0.25, r.top(), r.width() * 0.5, r.height() * 0.85);
            return boundaryOfRect(body, towards);
        }
        return boundaryOfRect(r, towards);
    }

    static QPointF boundaryOfRect(const QRectF &r, const QPointF &towards) {
        const QPointF c = r.center();
        const QPointF d = towards - c;
        double t = 1e9;
        if (!qFuzzyIsNull(d.x())) t = std::min(t, std::abs(r.width() / 2 / d.x()));
        if (!qFuzzyIsNull(d.y())) t = std::min(t, std::abs(r.height() / 2 / d.y()));
        return c + d * t;
    }

    void arrowHead(const QPointF &tip, const QPointF &from, const QString &head, QPointF *shaftEnd) {
        QLineF dir(from, tip);
        if (shaftEnd) *shaftEnd = tip;
        if (dir.length() < 0.01 || head == "none") return;
        dir.setLength(1);
        const QPointF d = dir.p2() - dir.p1();
        const QPointF n(-d.y(), d.x());
        if (head == "triangle") {
            const double len = l.px(2.6), half = l.px(1.4);
            const QPointF base = tip - d * len;
            line({tip, base + n * half, base - n * half, tip}, 1);
            if (shaftEnd) *shaftEnd = base;
        } else {
            const double len = l.px(1.9), half = l.px(0.9);
            const QPointF base = tip - d * len;
            line({base + n * half, tip, base - n * half}, 1);
        }
    }

    void dimensionTip(const QPointF &tip, const QPointF &from) {
        QLineF dir(from, tip);
        if (dir.length() < 0.01) return;
        dir.setLength(1);
        const QPointF d = dir.p2() - dir.p1(), n(-d.y(), d.x());
        const QPointF base = tip - d * l.px(1.6);
        line({tip, base + n * l.px(0.4), base - n * l.px(0.4), tip}, 0.6, false, true);
    }

    void node(const Node &node) {
        const QRectF r(l.px(node.rect.topLeft()), QSizeF(l.px(node.rect.width()), l.px(node.rect.height())));
        const double u = l.scale;
        const QString &shape = node.shape;
        QRectF textArea = r;

        if (shape == "group") {
            line({r.topLeft(), r.topRight(), r.bottomRight(), r.bottomLeft(), r.topLeft()}, 0.8, true);
            textLeft(node.label, QPointF(r.left() + 1.5 * u, r.top() + 2.4 * u), 1.3 * u, r.width() - 3 * u);
            return;
        }
        if (node.fill) {
            Stroke s;
            s.points = {r.topLeft(), r.topRight(), r.bottomRight(), r.bottomLeft(), r.topLeft()};
            s.paper = true;
            s.backgroundColor = sp.paperColorAt(l, r.center());
            out.append(s);
        }
        if (shape == "box") {
            line({r.topLeft(), r.topRight(), r.bottomRight(), r.bottomLeft(), r.topLeft()});
        } else if (shape == "cylinder") {
            const double cap = std::min(0.22 * r.height(), 3.2 * u);
            const QRectF top(r.left(), r.top(), r.width(), cap);
            line(ellipsePoints(top, 0, 360, 48));
            line({QPointF(r.left(), r.top() + cap / 2), QPointF(r.left(), r.bottom() - cap / 2)});
            line({QPointF(r.right(), r.top() + cap / 2), QPointF(r.right(), r.bottom() - cap / 2)});
            line(ellipsePoints(QRectF(r.left(), r.bottom() - cap, r.width(), cap), 180, 180, 24));
            textArea = QRectF(r.left(), r.top() + cap, r.width(), r.height() - 1.5 * cap);
        } else if (shape == "circle") {
            line(ellipsePoints(r, 90, 360, 64));
            textArea = r.adjusted(r.width() * 0.12, r.height() * 0.12, -r.width() * 0.12, -r.height() * 0.12);
            if (node.labelAt == "top") {
                text(node.label, QPointF(r.center().x(), r.top() + 2.6 * u), 1.5 * u, 0, false, r.width() * 0.6);
                return;
            }
        } else if (shape == "hexagon") {
            const double q = r.width() * 0.25;
            line({QPointF(r.left(), r.center().y()), QPointF(r.left() + q, r.top()), QPointF(r.right() - q, r.top()),
                  QPointF(r.right(), r.center().y()), QPointF(r.right() - q, r.bottom()), QPointF(r.left() + q, r.bottom()),
                  QPointF(r.left(), r.center().y())});
            textArea = r.adjusted(q, 0, -q, 0);
        } else if (shape == "diamond") {
            line({QPointF(r.center().x(), r.top()), QPointF(r.right(), r.center().y()), QPointF(r.center().x(), r.bottom()),
                  QPointF(r.left(), r.center().y()), QPointF(r.center().x(), r.top())});
            textArea = r.adjusted(r.width() * 0.2, r.height() * 0.2, -r.width() * 0.2, -r.height() * 0.2);
        } else if (shape == "queue") {
            line({r.topLeft(), r.topRight(), r.bottomRight(), r.bottomLeft(), r.topLeft()});
            for (int i = 0; i < 3; ++i) {
                const double x = r.left() + (1.4 + 1.1 * i) * u;
                line({QPointF(x, r.top()), QPointF(x, r.bottom())}, 0.7);
            }
            textArea = QRectF(r.left() + 4.8 * u, r.top(), r.width() - 5.4 * u, r.height());
        } else if (shape == "actor") {
            const double hr = r.height() * 0.13;
            const QPointF cx(r.center().x(), 0);
            line(ellipsePoints(QRectF(r.center().x() - hr, r.top(), 2 * hr, 2 * hr), 90, 360, 32));
            line({QPointF(r.center().x(), r.top() + 2 * hr), QPointF(r.center().x(), r.top() + r.height() * 0.58)});
            line({QPointF(r.center().x() - r.width() * 0.3, r.top() + r.height() * 0.34),
                  QPointF(r.center().x() + r.width() * 0.3, r.top() + r.height() * 0.34)});
            line({QPointF(r.center().x() - r.width() * 0.28, r.top() + r.height() * 0.84),
                  QPointF(r.center().x(), r.top() + r.height() * 0.58),
                  QPointF(r.center().x() + r.width() * 0.28, r.top() + r.height() * 0.84)});
            text(node.label, QPointF(r.center().x(), r.bottom() - 0.6 * u), 1.3 * u, 0, false, r.width() * 1.6);
            Q_UNUSED(cx);
            return;
        }

        // Lettering: stereotype over the name, then a rule and the detail lines.
        const QStringList details = node.detail.isEmpty() ? QStringList() : node.detail.split('\n');
        const double labelPx = 1.7 * u, smallPx = 1.15 * u, pad = 0.9 * u;
        const double headerH = (node.stereotype.isEmpty() ? 0 : 1.5 * u) + 2.4 * u;
        const double maxWidth = textArea.width() - 2 * pad;

        if (details.isEmpty()) {
            const double block = node.stereotype.isEmpty() ? labelPx : labelPx + 1.6 * u;
            double y = textArea.center().y() - block / 2;
            if (!node.stereotype.isEmpty()) {
                text(node.stereotype, QPointF(textArea.center().x(), y + 0.6 * u), smallPx, 0, false, maxWidth);
                y += 1.6 * u;
            }
            text(node.label, QPointF(textArea.center().x(), y + labelPx / 2), labelPx, 0, false, maxWidth);
            return;
        }

        double y = textArea.top() + pad;
        if (!node.stereotype.isEmpty()) {
            text(node.stereotype, QPointF(textArea.center().x(), y + 0.6 * u), smallPx, 0, false, maxWidth);
            y += 1.5 * u;
        }
        text(node.label, QPointF(textArea.center().x(), y + 1.1 * u), labelPx, 0, false, maxWidth);
        const double ruleY = textArea.top() + pad + headerH;
        if (shape == "box")
            line({QPointF(r.left(), ruleY), QPointF(r.right(), ruleY)}, 0.7);
        y = ruleY + pad * 0.8;
        for (const auto &detail : details) {
            text(detail, QPointF(textArea.center().x(), y + 0.65 * u), smallPx, 0, false, maxWidth);
            y += 1.6 * u;
        }
    }

    void edge(const Diagram &diagram, const Edge &edge) {
        const Node *a = diagram.node(edge.from), *b = diagram.node(edge.to);
        if (!a || !b) return;
        QPolygonF points;
        QVector<QPointF> via;
        for (const auto &p : edge.points) via.append(l.px(p));
        const QPointF start = boundary(*a, via.isEmpty() ? l.px(b->center()) : via.first(), !via.isEmpty());
        const QPointF end = boundary(*b, via.isEmpty() ? l.px(a->center()) : via.last(), !via.isEmpty());
        points.append(start);
        for (const auto &p : via) points.append(p);
        points.append(end);

        QPointF shaftEnd = end, shaftStart = start;
        // Heads first so the shaft can stop at a hollow triangle's base.
        QVector<Stroke> heads;
        {
            std::swap(out, heads);
            arrowHead(end, points[points.size() - 2], edge.head == "both" ? "open" : edge.head, &shaftEnd);
            if (edge.head == "both") arrowHead(start, points[1], "open", &shaftStart);
            std::swap(out, heads);
        }
        points.first() = shaftStart;
        points.last() = shaftEnd;
        line(points, 1, edge.style == "dashed");
        out.append(heads);

        if (!edge.label.isEmpty()) {
            const double half = polylineLength(points) / 2;
            const QPolygonF toMid = partial(points, half);
            text(edge.label, toMid.last(), 1.25 * l.scale, 0, true);
        }
    }

    void dimension(const Diagram &diagram, const Dimension &d) {
        const Node *a = diagram.node(d.from), *b = diagram.node(d.to);
        if (!a || !b) return;
        const QRectF ra(l.px(a->rect.topLeft()), QSizeF(l.px(a->rect.width()), l.px(a->rect.height())));
        const QRectF rb(l.px(b->rect.topLeft()), QSizeF(l.px(b->rect.width()), l.px(b->rect.height())));
        const double u = l.scale, off = l.px(d.offset), gap = 0.6 * u, over = 1.2 * u;
        const double labelPx = 1.2 * u;

        if (d.side == "bottom" || d.side == "top") {
            const bool bottom = d.side == "bottom";
            const double y = bottom ? std::max(ra.bottom(), rb.bottom()) + off : std::min(ra.top(), rb.top()) - off;
            const double x1 = std::min(ra.left(), rb.left()), x2 = std::max(ra.right(), rb.right());
            const double ya = bottom ? ra.bottom() + gap : ra.top() - gap, yb = bottom ? rb.bottom() + gap : rb.top() - gap;
            const double yEnd = bottom ? y + over : y - over;
            line({QPointF(x1, ya), QPointF(x1, yEnd)}, 0.6);
            line({QPointF(x2, yb), QPointF(x2, yEnd)}, 0.6);
            line({QPointF(x1, y), QPointF(x2, y)}, 0.6);
            dimensionTip(QPointF(x1, y), QPointF(x2, y));
            dimensionTip(QPointF(x2, y), QPointF(x1, y));
            const double ty = bottom ? y + 1.4 * u : y - 1.4 * u;
            text(d.label, QPointF((x1 + x2) / 2, ty), labelPx, 0, false, x2 - x1 + 8 * u);
        } else {
            const bool right = d.side == "right";
            const double x = right ? std::max(ra.right(), rb.right()) + off : std::min(ra.left(), rb.left()) - off;
            const double y1 = std::min(ra.top(), rb.top()), y2 = std::max(ra.bottom(), rb.bottom());
            const double xa = right ? ra.right() + gap : ra.left() - gap, xb = right ? rb.right() + gap : rb.left() - gap;
            const double xEnd = right ? x + over : x - over;
            line({QPointF(xa, y1), QPointF(xEnd, y1)}, 0.6);
            line({QPointF(xb, y2), QPointF(xEnd, y2)}, 0.6);
            line({QPointF(x, y1), QPointF(x, y2)}, 0.6);
            dimensionTip(QPointF(x, y1), QPointF(x, y2));
            dimensionTip(QPointF(x, y2), QPointF(x, y1));
            const double tx = right ? x + 1.4 * u : x - 1.4 * u;
            text(d.label, QPointF(tx, (y1 + y2) / 2), labelPx, right ? 90 : -90, false, y2 - y1 + 8 * u);
        }
    }

    void callout(const Diagram &diagram, const Callout &c) {
        const Node *n = diagram.node(c.node);
        if (!n) return;
        const double u = l.scale, r = 1.5 * u;
        const QPointF center = l.px(n->rect.topRight()) + QPointF(l.px(c.dx), l.px(c.dy));
        // The leader runs to whichever corner of the node is closest, or
        // straight to the rim of a round node.
        QPointF corner = l.px(n->rect.topRight());
        for (const QPointF &candidate : {n->rect.topLeft(), n->rect.bottomLeft(), n->rect.bottomRight()})
            if (QLineF(center, l.px(candidate)).length() < QLineF(center, corner).length())
                corner = l.px(candidate);
        if (n->shape == "circle")
            corner = boundary(*n, center);
        QLineF leader(center, corner);
        if (leader.length() > r) {
            leader.setP1(leader.pointAt(r / leader.length()));
            line({leader.p1(), leader.p2()}, 0.6);
        }
        line(ellipsePoints(QRectF(center.x() - r, center.y() - r, 2 * r, 2 * r), 90, 360, 32), 0.9);
        text(QString::number(c.n), center, 1.5 * u);
    }

    void notes(const Diagram &diagram) {
        const QRectF area = l.notes.adjusted(l.zone * 0.8, l.zone * 0.5, -l.zone * 0.8, -l.zone * 0.4);
        const double px = qBound(9.0, area.height() * 0.082, 30.0);
        const QFontMetricsF fm(fontAt(px));
        const double lineH = px * 1.5;
        double y = area.top() + px;
        textLeft(tr("NOTES"), QPointF(area.left(), y), px * 1.05);
        y += lineH * 1.15;
        const double indent = fm.horizontalAdvance("0. ");
        for (int i = 0; i < diagram.notes.size(); ++i) {
            // Word-wrap each note under its number, stopping at the block's floor.
            const QStringList words = diagram.notes[i].toUpper().split(' ', Qt::SkipEmptyParts);
            QString current;
            QStringList lines;
            for (const auto &word : words) {
                const QString candidate = current.isEmpty() ? word : current + ' ' + word;
                if (fm.horizontalAdvance(candidate) > area.width() - indent && !current.isEmpty()) {
                    lines.append(current);
                    current = word;
                } else {
                    current = candidate;
                }
            }
            if (!current.isEmpty()) lines.append(current);
            for (int k = 0; k < lines.size(); ++k) {
                if (y > area.bottom()) return;
                if (k == 0) textLeft(QString::number(i + 1) + ".", QPointF(area.left(), y), px);
                textLeft(lines[k], QPointF(area.left() + indent, y), px);
                y += lineH;
            }
        }
    }

    void cell(int index, const QString &caption, const QString &value, double valueScale = 0.42) {
        const QRectF c = l.cells[index];
        const double cap = qBound(7.0, c.height() * 0.2, 18.0);
        textLeft(caption, QPointF(c.left() + cap * 0.6, c.top() + cap * 1.4), cap, c.width() - cap);
        const double vpx = c.height() * valueScale;
        text(value, QPointF(c.center().x(), c.center().y() + cap * 0.55), vpx, 0, false, c.width() - cap * 1.4);
    }

    void titleBlock(const Diagram &diagram, const SheetInfo &info) {
        cell(0, tr("TITLE"), diagram.title, 0.4);
        cell(1, tr("DWG NO."), diagram.number.isEmpty() ? QString("SW-%1").arg(info.sheetNumber, 3, 10, QChar('0')) : diagram.number, 0.32);
        cell(2, tr("SUBJECT"), diagram.category, 0.38);
        cell(3, tr("SHEET"), tr("%1 OF %2").arg(info.sheetNumber).arg(info.sheetCount), 0.42);
        cell(4, tr("SCALE"), tr("N.T.S."), 0.4);
        cell(5, tr("DRAWN"), info.drawnBy.isEmpty() ? tr("DRAFTING") : info.drawnBy, 0.4);
        cell(6, tr("DATE"), info.date.isValid() ? info.date.toString("yyyy-MM-dd") : QString("—"), 0.36);
        cell(7, tr("REV"), info.revision, 0.42);
    }
};

QVector<Stroke> SheetPainter::strokes(const Diagram &diagram, const SheetInfo &info, const SheetLayout &layout) const {
    Builder b(*this, layout);
    b.titleBlock(diagram, info);
    for (const auto &node : diagram.drawOrder())
        b.node(node);
    for (const auto &edge : diagram.edges)
        b.edge(diagram, edge);
    for (const auto &dimension : diagram.dimensions)
        b.dimension(diagram, dimension);
    for (const auto &callout : diagram.callouts)
        b.callout(diagram, callout);
    b.notes(diagram);
    return b.out;
}

double SheetPainter::totalLength(const QVector<Stroke> &strokes) {
    double total = 0;
    for (const auto &s : strokes)
        total += s.length;
    return total;
}

void SheetPainter::paintStrokes(QPainter &p, const QVector<Stroke> &strokes, double progress, double alpha,
                                bool showTip, const QImage *paper) const {
    p.save();
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::TextAntialiasing);
    p.setOpacity(qBound(0.0, alpha, 1.0));

    const double total = totalLength(strokes);
    double budget = qBound(0.0, progress, 1.0) * total;
    const double base = std::max(1.2, std::min(p.device()->width(), p.device()->height()) / 900.0);
    QPointF tip;
    bool haveTip = false;

    for (const auto &s : strokes) {
        if (budget <= 0) break;
        const double fraction = s.length <= 0 ? 1 : std::min(1.0, budget / s.length);
        budget -= s.length;

        if (s.paper) {
            // Filled with the paper itself where we have it, grid and grain
            // included, so the patch is invisible until its outline is inked.
            QPainterPath path;
            path.addPolygon(s.points);
            p.fillPath(path, paper ? QBrush(*paper) : QBrush(s.backgroundColor));
            continue;
        }
        if (s.kind == Stroke::Line) {
            const QPolygonF pts = fraction >= 1 ? s.points : partial(s.points, fraction * s.length);
            QPen pen(withAlpha(m_ink, 60), base * s.width * 3.2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            // A soft halo under the line, the way the print bleeds into the paper.
            if (!s.dashed) {
                p.setPen(pen);
                p.setBrush(Qt::NoBrush);
                p.drawPolyline(pts);
            }
            pen = QPen(m_ink, base * s.width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            if (s.dashed) {
                pen.setStyle(Qt::CustomDashLine);
                pen.setDashPattern({5, 3.5});
            }
            p.setPen(pen);
            if (s.fill && fraction >= 1) {
                QPainterPath path;
                path.addPolygon(pts);
                p.fillPath(path, m_ink);
            }
            p.drawPolyline(pts);
            if (fraction < 1 && !pts.isEmpty()) { tip = pts.last(); haveTip = true; }
        } else {
            QFont f = m_font;
            f.setPixelSize(std::max(1, int(std::lround(s.size))));
            p.setFont(f);
            p.save();
            p.translate(s.anchor);
            p.rotate(s.rotation);
            if (s.background) {
                const double pad = s.size * 0.35;
                p.fillRect(QRectF(-pad, -s.ascent - pad * 0.6, s.advance + 2 * pad, s.ascent + s.descent + pad * 1.2), s.backgroundColor);
            }
            const int chars = fraction >= 1 ? s.text.size() : int(std::ceil(fraction * s.text.size()));
            const QString shown = s.text.left(chars);
            p.setPen(withAlpha(m_ink, 70));
            p.drawText(QPointF(0.6, 0.4), shown);
            p.setPen(m_ink);
            p.drawText(QPointF(0, 0), shown);
            if (fraction < 1) {
                const double x = QFontMetricsF(f).horizontalAdvance(shown);
                const double a = qDegreesToRadians(s.rotation);
                tip = s.anchor + QPointF(x * std::cos(a), x * std::sin(a));
                haveTip = true;
            }
            p.restore();
        }
    }

    if (showTip && haveTip && progress < 1) {
        p.setPen(Qt::NoPen);
        p.setBrush(withAlpha(QColor(255, 255, 255), 50));
        p.drawEllipse(tip, base * 4.5, base * 4.5);
        p.setBrush(QColor(255, 255, 255));
        p.drawEllipse(tip, base * 1.6, base * 1.6);
    }
    p.restore();
}

QImage SheetPainter::render(const Diagram &diagram, const SheetInfo &info, const QSize &size, double progress) const {
    const SheetLayout l = layout(size);
    // The brush must read the untouched paper, not the sheet being inked.
    const QImage blank = paper(l);
    QImage image = blank;
    QPainter p(&image);
    paintStrokes(p, strokes(diagram, info, l), progress, 1, progress < 1, &blank);
    return image;
}
