#pragma once

#include <QImage>
#include <QQuickPaintedItem>

#include "sheetpainter.h"
#include "show.h"

// The sheet on screen: paper cached per size, strokes cached per sheet, and
// the ink replayed to the show's progress on every frame.
class SheetView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(Show *show READ show WRITE setShow NOTIFY showChanged)

public:
    explicit SheetView(QQuickItem *parent = nullptr);

    Show *show() const { return m_show; }
    void setShow(Show *show);

    void paint(QPainter *painter) override;

signals:
    void showChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void invalidateStrokes();

    Show *m_show = nullptr;
    SheetPainter m_painter;
    SheetLayout m_layout;
    QImage m_paper;
    QSize m_paperSize;
    QVector<Stroke> m_strokes;
    int m_strokesSheet = -1;
    QSize m_strokesSize;
};
