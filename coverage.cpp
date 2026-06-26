#include "coverage.h"

#include <QtMath>
#include <cmath>

// Largest cell index the key() packing can represent without collision. A bad
// coordinate (NaN/Inf, or a point flung far off the local frame by a corrupt
// attitude/heading decode) must never index outside this band — clamp instead.
static constexpr int kCellLimit = 1999999;

static inline int cellIndex(double v, double cell)
{
    if (!std::isfinite(v))
        return 0;
    const double f = std::floor(v / cell);
    if (f <= double(-kCellLimit)) return -kCellLimit;
    if (f >= double(kCellLimit))  return kCellLimit;
    return int(f);
}

void Coverage::mark(double x, double y, double headingDeg, double width)
{
    // Reject anything non-finite or degenerate before it can corrupt the grid
    // (a NaN here used to flow straight into qFloor -> int and an out-of-band
    // cell key). Section sampling calls this while driving over worked ground.
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(headingDeg)
        || !std::isfinite(width) || width <= 0.0)
        return;
    if (width > 200.0)   // sane upper bound; caps the inner loop iteration count
        width = 200.0;

    const double hd = qDegreesToRadians(headingDeg);
    const double rx = qCos(hd);   // right (east) component
    const double ry = -qSin(hd);  // right (north) component

    const int before = m_cells.size();
    for (double t = -width / 2.0; t <= width / 2.0 + 1e-6; t += m_cell) {
        const double px = x + t * rx;
        const double py = y + t * ry;
        m_cells.insert(key(cellIndex(px, m_cell), cellIndex(py, m_cell)));
    }
    if (m_cells.size() != before)
        emit changed();
}

bool Coverage::isCovered(double x, double y) const
{
    if (!std::isfinite(x) || !std::isfinite(y))
        return false;
    return m_cells.contains(key(cellIndex(x, m_cell), cellIndex(y, m_cell)));
}

void Coverage::reset()
{
    m_cells.clear();
    m_chunks.clear();
    emit changed();
    emit cleared();
}

void Coverage::addChunkBox(double minx, double miny, double maxx, double maxy)
{
    if (!std::isfinite(minx) || !std::isfinite(miny)
        || !std::isfinite(maxx) || !std::isfinite(maxy))
        return;
    m_chunks.append({ minx, miny, maxx, maxy });
    emit changed();
}

void Coverage::clearChunks()
{
    if (m_chunks.isEmpty())
        return;
    m_chunks.clear();
    emit changed();
}

QVariantList Coverage::visibleChunks(double minx, double miny,
                                     double maxx, double maxy, int maxN) const
{
    QVariantList out;
    const int n = m_chunks.size();
    if (n == 0)
        return out;
    // Linear AABB scan: each test is a few float compares, so even 30-50k chunks
    // cost well under a millisecond, and this only runs when the (quantised) view
    // rect or the chunk set actually changes — not per fix.
    QVector<int> hits;
    hits.reserve(qMin(n, 4096));
    for (int i = 0; i < n; ++i) {
        const ChunkBox &b = m_chunks.at(i);
        if (b.maxx < minx || b.minx > maxx || b.maxy < miny || b.miny > maxy)
            continue;
        hits.append(i);
    }
    if (maxN < 1)
        maxN = 1;
    const int hn = hits.size();
    if (hn <= maxN) {
        out.reserve(hn);
        for (int i = 0; i < hn; ++i)
            out.append(hits.at(i));
        return out;
    }
    // Too many in view (zoomed-out / whole-field): evenly stride down to maxN so
    // the rendered chunk count stays bounded. Coverage reads as a filled block at
    // that zoom, so dropping interleaved chunks is not noticeable.
    const int stride = (hn + maxN - 1) / maxN;
    out.reserve(maxN);
    for (int i = 0; i < hn; i += stride)
        out.append(hits.at(i));
    return out;
}

QVariantList Coverage::visibleCells(double minx, double miny,
                                    double maxx, double maxy, int maxN) const
{
    QVariantList out;
    if (m_cells.isEmpty() || maxN < 1)
        return out;
    if (!std::isfinite(minx) || !std::isfinite(miny)
        || !std::isfinite(maxx) || !std::isfinite(maxy))
        return out;

    QVector<QVariantMap> hits;
    hits.reserve(qMin(m_cells.size(), maxN));
    for (qint64 k : m_cells) {
        const int iy = int(k % 4000001LL) - 2000000;
        const int ix = int(k / 4000001LL) - 2000000;
        const double cx = ix * m_cell + m_cell * 0.5;
        const double cy = -(iy * m_cell + m_cell * 0.5);
        if (cx < minx || cx > maxx || cy < miny || cy > maxy)
            continue;
        QVariantMap m;
        m.insert(QStringLiteral("x"), cx);
        m.insert(QStringLiteral("y"), cy);
        m.insert(QStringLiteral("s"), m_cell);
        hits.append(m);
    }
    const int hn = hits.size();
    if (hn <= maxN) {
        out.reserve(hn);
        for (int i = 0; i < hn; ++i)
            out.append(hits.at(i));
        return out;
    }
    const int stride = (hn + maxN - 1) / maxN;
    out.reserve(maxN);
    for (int i = 0; i < hn; i += stride)
        out.append(hits.at(i));
    return out;
}

static int floorCellDiv(int a, int b)
{
    if (b <= 0)
        return 0;
    if (a >= 0)
        return a / b;
    return (a - b + 1) / b;
}

QVariantList Coverage::visibleCellTiles(double minx, double miny,
                                        double maxx, double maxy, int maxN) const
{
    QVariantList out;
    if (m_cells.isEmpty() || maxN < 1)
        return out;
    if (!std::isfinite(minx) || !std::isfinite(miny)
        || !std::isfinite(maxx) || !std::isfinite(maxy))
        return out;

    auto blockKey = [](int tx, int ty) -> qint64 {
        return static_cast<qint64>(tx + 2000000) * 4000001LL + (ty + 2000000);
    };

    int tileCells = 1;
    QSet<qint64> keys;
    for (int attempt = 0; attempt < 8; ++attempt) {
        keys.clear();
        for (qint64 k : m_cells) {
            const int iy = int(k % 4000001LL) - 2000000;
            const int ix = int(k / 4000001LL) - 2000000;
            const double cx = ix * m_cell + m_cell * 0.5;
            const double cy = -(iy * m_cell + m_cell * 0.5);
            if (cx < minx || cx > maxx || cy < miny || cy > maxy)
                continue;
            keys.insert(blockKey(floorCellDiv(ix, tileCells),
                                 floorCellDiv(iy, tileCells)));
        }
        if (keys.size() <= maxN || tileCells >= 64)
            break;
        tileCells *= 2;
    }

    const double tileM = m_cell * tileCells;
    out.reserve(keys.size());
    for (qint64 bk : keys) {
        const int ty = int(bk % 4000001LL) - 2000000;
        const int tx = int(bk / 4000001LL) - 2000000;
        QVariantMap m;
        m.insert(QStringLiteral("x"), tx * tileM);
        m.insert(QStringLiteral("y"), -(ty + 1) * tileM);
        m.insert(QStringLiteral("w"), tileM);
        m.insert(QStringLiteral("h"), tileM);
        m.insert(QStringLiteral("tileCells"), tileCells);
        out.append(m);
    }
    return out;
}
