#pragma once

#include "farmdata.h"
#include <QString>
#include <QVector>

// ISO 11783-10 TASKDATA.XML reader/writer. Maps:
//   CTR -> Client, FRM -> Farm, PFD -> Field,
//   PLN(type 1)/LSG(type 1)/PNT -> boundary,
//   GGP/GPN(type 1 AB)/LSG/PNT  -> AB run lines.
namespace TaskData {
bool load(const QString &path, QVector<Client> &clients);
bool save(const QString &path, const QVector<Client> &clients);
}
