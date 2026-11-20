#include "catalog.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QSet>

const Node *Diagram::node(const QString &id) const {
    for (const auto &node : nodes)
        if (node.id == id)
            return &node;
    return nullptr;
}

QList<Node> Diagram::drawOrder() const {
    QList<Node> ordered;
    for (const auto &node : nodes)
        if (node.shape == "group")
            ordered.append(node);
    for (const auto &node : nodes)
        if (node.shape != "group")
            ordered.append(node);
    return ordered;
}

static QRectF rectOf(const QJsonObject &o) {
    return QRectF(o.value("x").toDouble(), o.value("y").toDouble(), o.value("w").toDouble(), o.value("h").toDouble());
}

Diagram Catalog::parse(const QJsonObject &object, const QString &source, QStringList *problems) {
    Diagram diagram;
    diagram.source = source;
    diagram.id = object.value("id").toString();
    diagram.title = object.value("title").toString();
    diagram.category = object.value("category").toString();
    diagram.number = object.value("number").toString();
    for (const auto &note : object.value("notes").toArray())
        diagram.notes.append(note.toString());

    const QString where = source + (diagram.id.isEmpty() ? "" : " (" + diagram.id + ")");
    auto problem = [&](const QString &text) { if (problems) problems->append(where + ": " + text); };

    if (diagram.id.isEmpty()) problem("diagram has no id");
    if (diagram.title.isEmpty()) problem("diagram has no title");

    static const QSet<QString> shapes{"box", "cylinder", "circle", "hexagon", "queue", "actor", "group", "diamond"};
    QSet<QString> ids;
    for (const auto &value : object.value("nodes").toArray()) {
        const auto o = value.toObject();
        Node node;
        node.id = o.value("id").toString();
        node.label = o.value("label").toString();
        node.stereotype = o.value("stereotype").toString();
        node.detail = o.value("detail").toString();
        node.shape = o.value("shape").toString("box");
        node.rect = rectOf(o);
        node.fill = o.value("fill").toBool(false);
        node.labelAt = o.value("labelAt").toString("center");
        if (node.labelAt != "center" && node.labelAt != "top") problem("node " + node.id + " has unknown labelAt " + node.labelAt);
        if (node.id.isEmpty()) problem("node without id");
        else if (ids.contains(node.id)) problem("duplicate node id " + node.id);
        if (!shapes.contains(node.shape)) problem("node " + node.id + " has unknown shape " + node.shape);
        if (node.rect.width() <= 0 || node.rect.height() <= 0) problem("node " + node.id + " has no size");
        if (!QRectF(0, 0, Diagram::Width, Diagram::Height).contains(node.rect))
            problem("node " + node.id + " lies outside the 120 x 64 sheet");
        ids.insert(node.id);
        diagram.nodes.append(node);
    }

    auto known = [&](const QString &id, const QString &what) {
        if (!ids.contains(id)) problem(what + " refers to unknown node " + id);
    };
    static const QSet<QString> heads{"open", "triangle", "none", "both"};
    for (const auto &value : object.value("edges").toArray()) {
        const auto o = value.toObject();
        Edge edge;
        edge.from = o.value("from").toString();
        edge.to = o.value("to").toString();
        edge.label = o.value("label").toString();
        edge.style = o.value("style").toString("solid");
        edge.head = o.value("head").toString("open");
        for (const auto &p : o.value("points").toArray()) {
            const auto pair = p.toArray();
            edge.points.append(QPointF(pair.at(0).toDouble(), pair.at(1).toDouble()));
        }
        known(edge.from, "edge");
        known(edge.to, "edge");
        if (edge.style != "solid" && edge.style != "dashed") problem("edge has unknown style " + edge.style);
        if (!heads.contains(edge.head)) problem("edge has unknown head " + edge.head);
        diagram.edges.append(edge);
    }

    static const QSet<QString> sides{"top", "bottom", "left", "right"};
    for (const auto &value : object.value("dimensions").toArray()) {
        const auto o = value.toObject();
        Dimension dimension;
        dimension.from = o.value("from").toString();
        dimension.to = o.value("to").toString();
        dimension.side = o.value("side").toString("bottom");
        dimension.label = o.value("label").toString();
        dimension.offset = o.value("offset").toDouble(4);
        known(dimension.from, "dimension");
        known(dimension.to, "dimension");
        if (!sides.contains(dimension.side)) problem("dimension has unknown side " + dimension.side);
        diagram.dimensions.append(dimension);
    }

    for (const auto &value : object.value("callouts").toArray()) {
        const auto o = value.toObject();
        Callout callout;
        callout.node = o.value("node").toString();
        callout.n = o.value("n").toInt(1);
        callout.dx = o.value("dx").toDouble(3);
        callout.dy = o.value("dy").toDouble(-3);
        known(callout.node, "callout");
        if (callout.n < 1 || callout.n > diagram.notes.size())
            problem(QString("callout %1 has no matching note").arg(callout.n));
        diagram.callouts.append(callout);
    }

    return diagram;
}

void Catalog::loadJson(const QByteArray &json, const QString &source) {
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(json, &error);
    if (document.isNull()) {
        m_problems.append(source + ": " + error.errorString());
        return;
    }
    // A file holds either one diagram or a {"diagrams": [...]} collection.
    QJsonArray array;
    if (document.isArray()) array = document.array();
    else if (document.object().contains("diagrams")) array = document.object().value("diagrams").toArray();
    else array.append(document.object());

    for (const auto &value : array) {
        QStringList problems;
        Diagram diagram = parse(value.toObject(), source, &problems);
        if (!problems.isEmpty()) {
            m_problems.append(problems);
            continue;
        }
        if (indexOf(diagram.id) >= 0) {
            m_problems.append(source + ": duplicate diagram id " + diagram.id);
            continue;
        }
        m_diagrams.append(diagram);
    }
}

void Catalog::loadBundled() {
    QFile file(":/diagrams.json");
    if (file.open(QIODevice::ReadOnly))
        loadJson(file.readAll(), "bundled");
    else
        m_problems.append("bundled catalog is missing");
}

void Catalog::loadFile(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        m_problems.append(path + ": " + file.errorString());
        return;
    }
    loadJson(file.readAll(), path);
}

void Catalog::loadDirectory(const QString &directory) {
    QDir dir(directory);
    if (!dir.exists())
        return;
    for (const auto &entry : dir.entryList({"*.json"}, QDir::Files | QDir::Readable, QDir::Name))
        loadFile(dir.filePath(entry));
}

int Catalog::indexOf(const QString &id) const {
    for (int i = 0; i < m_diagrams.size(); ++i)
        if (m_diagrams.at(i).id == id)
            return i;
    return -1;
}
