#pragma once

#include <QJsonObject>
#include <QList>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QStringList>
#include <QVector>

// One diagram as a draftsman would lay it out: nodes and connections on a
// 120 x 64 unit sheet, with notes, dimensions and numbered callouts.
struct Node {
    QString id, label, stereotype, detail, shape = "box";
    QRectF rect;
    bool fill = false;         // paper-filled, so it hides whatever it sits on
    QString labelAt = "center"; // "top" letters along the upper edge, for nested rings
    QPointF center() const { return rect.center(); }
};

struct Edge {
    QString from, to, label, style = "solid", head = "open";
    QVector<QPointF> points;
};

struct Dimension {
    QString from, to, side = "bottom", label;
    double offset = 4;
};

struct Callout {
    QString node;
    int n = 1;
    double dx = 3, dy = -3;
};

struct Diagram {
    QString id, title, category, number, source;
    QStringList notes;
    QList<Node> nodes;
    QList<Edge> edges;
    QList<Dimension> dimensions;
    QList<Callout> callouts;

    static constexpr double Width = 120, Height = 64;

    const Node *node(const QString &id) const;
    // Diagrams are drawn groups first, so the frame goes under what it holds.
    QList<Node> drawOrder() const;
};

// The bundled catalog plus any diagrams the user drops into
// ~/.config/blueprint/diagrams/*.json. Problems are collected, not thrown, so
// one broken file never takes the screensaver down.
class Catalog {
public:
    static Diagram parse(const QJsonObject &object, const QString &source, QStringList *problems);

    void loadBundled();
    void loadFile(const QString &path);
    void loadDirectory(const QString &directory);

    const QList<Diagram> &diagrams() const { return m_diagrams; }
    const QStringList &problems() const { return m_problems; }
    int indexOf(const QString &id) const;

private:
    void loadJson(const QByteArray &json, const QString &source);

    QList<Diagram> m_diagrams;
    QStringList m_problems;
};
