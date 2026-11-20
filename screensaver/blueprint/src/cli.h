#pragma once

#include <QStringList>

// Display-free commands: `blueprint list`, `blueprint check [files]` and
// `blueprint render <out.png>`. Each takes --json where it prints data, exits
// 0 or 1, and reports errors on stderr.
bool isCliCommand(const QStringList &arguments);
int runCli(const QStringList &arguments);
