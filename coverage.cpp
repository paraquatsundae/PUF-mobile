#include "coverage.h"

#include <QHash>
#include <QSet>
#include <QVector>
#include <QtMath>
#include <algorithm>
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

static int floorCellDiv(int a, int b)
{
    if (b <= 0)
        return 0;
    if (a >= 0)
        return a / b;
    return (a - b + 1) / b;
}

// Stamp cells across `width` at (x,y), perpendicular to heading. Always includes
// the exact ±width/2 endpoints so boom edges are not undersampled.
void Coverage::stampCross(double x, double y, double headingDeg, double width)
{
    const double hd = qDegreesToRadians(headingDeg);
    const double rx = qCos(hd);   // right (east)
    const double ry = -qSin(hd);  // right (north)
    const double half = width * 0.5;
    for (double t = -half;;) {
        const double px = x + t * rx;
        const double py = y + t * ry;
        m_cells.insert(key(cellIndex(px, m_cell), cellIndex(py, m_cell)));
        if (t >= half - 1e-9)
            break;
        const double next = t + m_cell;
        t = (next > half) ? half : next;
    }
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
    const double fx = qSin(hd);
    const double fy = qCos(hd);

    const int before = m_cells.size();
    // Short forward ribbon for a lone sample (markAlong covers long GPS steps).
    for (double s = 0.0; s <= m_cell + 1e-6; s += m_cell * 0.5)
        stampCross(x + s * fx, y + s * fy, headingDeg, width);
    if (m_cells.size() != before)
        emit changed();
}

void Coverage::markAlong(double x0, double y0, double x1, double y1,
                         double headingDeg, double width)
{
    if (!std::isfinite(x0) || !std::isfinite(y0)
        || !std::isfinite(x1) || !std::isfinite(y1)
        || !std::isfinite(headingDeg)
        || !std::isfinite(width) || width <= 0.0)
        return;
    if (width > 200.0)
        width = 200.0;

    const double dx = x1 - x0;
    const double dy = y1 - y0;
    const double dist = std::hypot(dx, dy);
    if (dist < 1e-6) {
        mark(x1, y1, headingDeg, width);
        return;
    }

    // Path bearing (clockwise from north) keeps the boom square to travel.
    double hdg = qRadiansToDegrees(std::atan2(dx, dy));
    if (hdg < 0.0)
        hdg += 360.0;
    if (!std::isfinite(hdg))
        hdg = headingDeg;

    const double step = m_cell * 0.5;
    const int nSteps = qMax(1, int(std::ceil(dist / step)));
    const int before = m_cells.size();
    for (int i = 0; i <= nSteps; ++i) {
        const double u = double(i) / double(nSteps);
        stampCross(x0 + u * dx, y0 + u * dy, hdg, width);
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

QVariantList Coverage::visibleCellTiles(double minx, double miny,
                                        double maxx, double maxy, int maxN,
                                        int minTileCells) const
{
    QVariantList out;
    if (m_cells.isEmpty() || maxN < 1)
        return out;
    if (!std::isfinite(minx) || !std::isfinite(miny)
        || !std::isfinite(maxx) || !std::isfinite(maxy))
        return out;
    if (minTileCells < 1)
        minTileCells = 1;

    auto blockKey = [](int tx, int ty) -> qint64 {
        return static_cast<qint64>(tx + 2000000) * 4000001LL + (ty + 2000000);
    };

    int tileCells = minTileCells;
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

QVariantList Coverage::visibleCellSpans(double minx, double miny,
                                        double maxx, double maxy, int maxN,
                                        int rowMergeCells) const
{
    QVariantList out;
    if (m_cells.isEmpty() || maxN < 1)
        return out;
    if (!std::isfinite(minx) || !std::isfinite(miny)
        || !std::isfinite(maxx) || !std::isfinite(maxy))
        return out;
    if (rowMergeCells < 1)
        rowMergeCells = 1;

    // Contiguous ix runs per north-band. Old min→max fill painted solid bars
    // across empty gaps between parallel passes ("coverage everywhere").
    QVector<QVariantMap> runs;
    int merge = rowMergeCells;
    for (int attempt = 0; attempt < 8; ++attempt) {
        QHash<int, QSet<int>> bands;
        for (qint64 k : m_cells) {
            const int iy = int(k % 4000001LL) - 2000000;
            const int ix = int(k / 4000001LL) - 2000000;
            const double cx = ix * m_cell + m_cell * 0.5;
            const double cy = -(iy * m_cell + m_cell * 0.5);
            if (cx < minx || cx > maxx || cy < miny || cy > maxy)
                continue;
            bands[floorCellDiv(iy, merge)].insert(ix);
        }

        runs.clear();
        runs.reserve(qMin(bands.size() * 2, maxN));
        QList<int> bandKeys = bands.keys();
        std::sort(bandKeys.begin(), bandKeys.end());
        for (int band : bandKeys) {
            QList<int> ixs = bands.value(band).values();
            if (ixs.isEmpty())
                continue;
            std::sort(ixs.begin(), ixs.end());
            int run0 = ixs.at(0);
            int prev = ixs.at(0);
            const int iy0 = band * merge;
            auto emitRun = [&](int ix0, int ix1) {
                QVariantMap m;
                m.insert(QStringLiteral("x"), ix0 * m_cell);
                m.insert(QStringLiteral("y"), -(iy0 + merge) * m_cell);
                m.insert(QStringLiteral("w"), (ix1 - ix0 + 1) * m_cell);
                m.insert(QStringLiteral("h"), merge * m_cell);
                runs.append(m);
            };
            for (int i = 1; i < ixs.size(); ++i) {
                const int ix = ixs.at(i);
                if (ix == prev + 1) {
                    prev = ix;
                    continue;
                }
                emitRun(run0, prev);
                run0 = ix;
                prev = ix;
            }
            emitRun(run0, prev);
        }

        if (runs.size() <= maxN || merge >= 64)
            break;
        merge *= 2;
    }

    const int rn = runs.size();
    if (rn <= maxN) {
        out.reserve(rn);
        for (int i = 0; i < rn; ++i)
            out.append(runs.at(i));
        return out;
    }
    // Even stride — never truncate from a QHash walk (flicker / missing bands).
    const int stride = (rn + maxN - 1) / maxN;
    out.reserve(maxN);
    for (int i = 0; i < rn; i += stride)
        out.append(runs.at(i));
    return out;
}
