#include "show.h"

#include <QDate>
#include <QRandomGenerator>
#include <algorithm>

Show::Show(const Catalog &catalog, const Options &options, QObject *parent)
    : QObject(parent), m_catalog(catalog), m_options(options) {
    m_timer.setInterval(16);
    connect(&m_timer, &QTimer::timeout, this, &Show::tick);

    if (sheetCount() == 0)
        return;
    int first = m_catalog.indexOf(m_options.start);
    if (first < 0 && !m_options.only.isEmpty())
        first = m_catalog.indexOf(m_options.only);
    if (first < 0) {
        reshuffle();
        first = m_deck.takeFirst();
    } else {
        reshuffle();
        m_deck.removeAll(first);
    }
    beginSheet(first);
    m_clock.start();
    m_timer.start();
}

QString Show::title() const {
    const Diagram *d = diagram();
    return d ? d->title : QString();
}

const Diagram *Show::diagram() const {
    return m_index >= 0 && m_index < sheetCount() ? &m_catalog.diagrams().at(m_index) : nullptr;
}

SheetInfo Show::info() const {
    SheetInfo info;
    info.sheetNumber = m_index + 1;
    info.sheetCount = sheetCount();
    info.drawnBy = m_options.drawnBy;
    info.date = QDate::currentDate();
    return info;
}

void Show::reshuffle() {
    m_deck.clear();
    if (!m_options.only.isEmpty()) {
        const int only = m_catalog.indexOf(m_options.only);
        if (only >= 0) m_deck.append(only);
        return;
    }
    for (int i = 0; i < sheetCount(); ++i)
        m_deck.append(i);
    auto *rng = QRandomGenerator::global();
    for (int i = m_deck.size() - 1; i > 0; --i)
        m_deck.swapItemsAt(i, int(rng->bounded(i + 1)));
    // A fresh deck must not open with the sheet that just closed.
    if (m_deck.size() > 1 && m_deck.first() == m_index)
        m_deck.swapItemsAt(0, m_deck.size() - 1);
}

int Show::dealNext() {
    if (m_deck.isEmpty())
        reshuffle();
    return m_deck.isEmpty() ? m_index : m_deck.takeFirst();
}

void Show::beginSheet(int index) {
    if (index < 0 || index >= sheetCount())
        return;
    m_index = index;
    if (m_cursor < 0 || m_history.value(m_cursor) != index) {
        // Branching off the past forgets the sheets that were ahead.
        while (m_history.size() > m_cursor + 1)
            m_history.removeLast();
        m_history.append(index);
        m_cursor = m_history.size() - 1;
        if (m_history.size() > 64) { m_history.removeFirst(); --m_cursor; }
    }
    m_phase = Drawing;
    m_elapsed = 0;
    m_progress = 0;
    m_alpha = 1;
    emit sheetChanged();
    emit frame();
}

void Show::advance(double seconds) {
    if (m_index < 0)
        return;
    m_elapsed += seconds;
    switch (m_phase) {
    case Drawing:
        m_progress = m_options.drawSeconds <= 0 ? 1 : std::min(1.0, m_elapsed / m_options.drawSeconds);
        emit frame();
        if (m_progress >= 1) { m_phase = Holding; m_elapsed = 0; }
        break;
    case Holding:
        if (m_elapsed >= m_options.holdSeconds) { m_phase = Fading; m_elapsed = 0; }
        break;
    case Fading:
        m_alpha = m_options.fadeSeconds <= 0 ? 0 : std::max(0.0, 1 - m_elapsed / m_options.fadeSeconds);
        emit frame();
        if (m_alpha <= 0) {
            if (m_cursor < m_history.size() - 1) beginSheet(m_history.at(++m_cursor));
            else beginSheet(dealNext());
        }
        break;
    }
}

void Show::tick() {
    const double dt = m_clock.restart() / 1000.0;
    // A laptop waking from sleep hands us one giant step; treat it as a frame.
    advance(std::min(dt, 0.1));
}

void Show::next() {
    if (m_cursor < m_history.size() - 1) beginSheet(m_history.at(++m_cursor));
    else beginSheet(dealNext());
}

void Show::previous() {
    if (m_cursor > 0) beginSheet(m_history.at(--m_cursor));
    else beginSheet(m_index);
}

void Show::finishDrawing() {
    if (m_phase == Drawing) {
        m_progress = 1;
        m_phase = Holding;
        m_elapsed = 0;
        emit frame();
    }
}

void Show::togglePause() {
    if (m_timer.isActive()) m_timer.stop();
    else { m_clock.restart(); m_timer.start(); }
    emit pausedChanged();
}
