#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>

#include "catalog.h"
#include "sheetpainter.h"

// Runs the slideshow: each sheet is inked in over a few seconds, held, then
// faded before the next one, dealt from a shuffled deck so every diagram
// appears before any repeats.
class Show : public QObject {
    Q_OBJECT
    Q_PROPERTY(int sheet READ sheet NOTIFY sheetChanged)
    Q_PROPERTY(int sheetCount READ sheetCount CONSTANT)
    Q_PROPERTY(QString title READ title NOTIFY sheetChanged)
    Q_PROPERTY(double progress READ progress NOTIFY frame)
    Q_PROPERTY(double alpha READ alpha NOTIFY frame)
    Q_PROPERTY(bool drawing READ drawing NOTIFY frame)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool screensaver READ screensaver CONSTANT)
    Q_PROPERTY(QString problems READ problems CONSTANT)

public:
    struct Options {
        double drawSeconds = 7, holdSeconds = 14, fadeSeconds = 1.2;
        bool screensaver = false;
        QString drawnBy, only, start;
    };
    enum Phase { Drawing, Holding, Fading };

    explicit Show(const Catalog &catalog, const Options &options, QObject *parent = nullptr);

    int sheet() const { return m_index; }
    int sheetCount() const { return m_catalog.diagrams().size(); }
    QString title() const;
    double progress() const { return m_progress; }
    double alpha() const { return m_alpha; }
    bool drawing() const { return m_phase == Drawing; }
    bool paused() const { return !m_timer.isActive(); }
    bool screensaver() const { return m_options.screensaver; }
    QString problems() const { return m_catalog.problems().join('\n'); }
    Phase phase() const { return m_phase; }

    const Diagram *diagram() const;
    SheetInfo info() const;

    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void finishDrawing();
    Q_INVOKABLE void togglePause();

    // Moves the show's clock by hand, for tests and the snapshot command.
    void advance(double seconds);

signals:
    void frame();
    void sheetChanged();
    void pausedChanged();

private:
    void tick();
    void beginSheet(int index);
    int dealNext();
    void reshuffle();

    Catalog m_catalog;
    Options m_options;
    QTimer m_timer;
    QElapsedTimer m_clock;
    Phase m_phase = Drawing;
    double m_elapsed = 0, m_progress = 0, m_alpha = 1;
    int m_index = -1;
    QList<int> m_deck, m_history;
    int m_cursor = -1;
};
