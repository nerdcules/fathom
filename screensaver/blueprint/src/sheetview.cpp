#include "sheetview.h"

#include <QPainter>
#include <QQuickWindow>

SheetView::SheetView(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setOpaquePainting(true);
}

void SheetView::setShow(Show *show) {
    if (m_show == show)
        return;
    if (m_show)
        disconnect(m_show, nullptr, this, nullptr);
    m_show = show;
    if (m_show) {
        connect(m_show, &Show::frame, this, [this] { update(); });
        connect(m_show, &Show::sheetChanged, this, [this] { invalidateStrokes(); update(); });
    }
    emit showChanged();
    update();
}

void SheetView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();
}

void SheetView::invalidateStrokes() {
    m_strokesSheet = -1;
}

void SheetView::paint(QPainter *painter) {
    // Lay out in device pixels so the lettering and hairlines stay crisp on a
    // scaled display, then paint back down to item coordinates.
    const double dpr = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    const QSize size(int(width() * dpr), int(height() * dpr));
    if (size.isEmpty())
        return;

    if (size != m_paperSize) {
        m_layout = m_painter.layout(size);
        m_paper = m_painter.paper(m_layout);
        m_paperSize = size;
        m_strokesSheet = -1;
    }

    painter->save();
    painter->scale(1 / dpr, 1 / dpr);
    painter->drawImage(0, 0, m_paper);

    const Diagram *diagram = m_show ? m_show->diagram() : nullptr;
    if (diagram) {
        if (m_strokesSheet != m_show->sheet() || m_strokesSize != size) {
            m_strokes = m_painter.strokes(*diagram, m_show->info(), m_layout);
            m_strokesSheet = m_show->sheet();
            m_strokesSize = size;
        }
        m_painter.paintStrokes(*painter, m_strokes, m_show->progress(), m_show->alpha(), m_show->drawing(), &m_paper);
    }
    painter->restore();
}
