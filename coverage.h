#pragma once

#include <QObject>
#include <QSet>
#include <QVariantList>
#include <QVector>

// True (non-overlapping) coverage via a raster grid of fixed-size cells. Cells
// are stored once regardless of how many passes touch them, so area is exact.
// Also answers isCovered() for section control.
class Coverage : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double areaHa READ areaHa NOTIFY changed)
    Q_PROPERTY(int cellCount READ cellCount NOTIFY changed)
    Q_PROPERTY(int chunkCount READ chunkCount NOTIFY changed)

public:
    explicit Coverage(QObject *parent = nullptr) : QObject(parent) {}

    double areaHa() const { return m_cells.size() * m_cell * m_cell / 10000.0; }
    int cellCount() const { return m_cells.size(); }

    // Mark all cells across `width` metres, centred at world point (x,y) east/north,
    // perpendicular to headingDeg (clockwise from north).
    Q_INVOKABLE void mark(double x, double y, double headingDeg, double width);
    // Interpolate marks from (x0,y0) → (x1,y1) so sparse GPS does not leave
    // along-track holes between accepted samples.
    Q_INVOKABLE void markAlong(double x0, double y0, double x1, double y1,
                               double headingDeg, double width);
    Q_INVOKABLE bool isCovered(double x, double y) const;
    Q_INVOKABLE void reset();

    // ---- Frozen-chunk spatial index (for viewport-culled coverage rendering) ----
    // QML registers each frozen swath chunk's world-space bbox (east / -north, the
    // same coords the swath points use) as it is frozen, in lockstep with the
    // doneStrokes array. The render layer then asks for only the chunks whose bbox
    // intersects the current view rect, so a fully-worked field renders O(visible)
    // chunks instead of all tens of thousands.
    Q_INVOKABLE void addChunkBox(double minx, double miny, double maxx, double maxy);
    Q_INVOKABLE void clearChunks();
    int chunkCount() const { return m_chunks.size(); }
    // Indices (into the registration order == doneStrokes order) of frozen chunks
    // whose bbox intersects [minx,maxx]x[miny,maxy]. When more than maxN intersect
    // (e.g. a whole field framed in fit mode) the result is evenly strided down to
    // maxN so the rendered count stays bounded at every zoom level.
    Q_INVOKABLE QVariantList visibleChunks(double minx, double miny,
                                           double maxx, double maxy, int maxN) const;
    // Covered cells whose centre falls in [minx,maxx]x[miny,maxy] (east / -north,
    // same coords as frozen swath chunks). Returns maps {x, y, s} with y = -north.
    Q_INVOKABLE QVariantList visibleCells(double minx, double miny,
                                          double maxx, double maxy, int maxN) const;
    // Merged cell tiles for paint — grows tile size until count <= maxN (no striding).
    Q_INVOKABLE QVariantList visibleCellTiles(double minx, double miny,
                                              double maxx, double maxy, int maxN,
                                              int minTileCells) const;
    // Row-band RLE: contiguous ix runs only (never fill gaps between passes).
    Q_INVOKABLE QVariantList visibleCellSpans(double minx, double miny,
                                              double maxx, double maxy, int maxN,
                                              int rowMergeCells) const;

signals:
    void changed();
    void cleared();

private:
    qint64 key(int ix, int iy) const
    { return static_cast<qint64>(ix + 2000000) * 4000001LL + (iy + 2000000); }
    void stampCross(double x, double y, double headingDeg, double width);

    struct ChunkBox { double minx; double miny; double maxx; double maxy; };

    QSet<qint64> m_cells;
    double m_cell = 0.5; // metres
    QVector<ChunkBox> m_chunks;
};
