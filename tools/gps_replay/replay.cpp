// Offline replay + tuning harness for PUF-mobile's automatic GPS smoothing.
//
// Feeds a captured raw-track CSV (produced on-device by the raw-track logger,
// see GpsModel::setRawLogging) through the SHARED gpsfilter code and emits a
// filtered CSV plus simple wobble metrics, so filter constants can be A/B
// compared on the dev host (Windows) without re-driving.
//
// This is a host-only tool — Qt-free, builds with any C++17 compiler.
//
//   Build (qmake):   qmake && make            (in this folder)
//   Build (g++):     g++ -std=c++17 -O2 -I../.. replay.cpp ../../gpsfilter.cpp -o gps_replay
//   Build (MSVC):    cl /std:c++17 /EHsc /I..\.. replay.cpp ..\..\gpsfilter.cpp /Fe:gps_replay.exe
//
//   Run:             gps_replay <input.csv> [width_m] [output.csv]
//
// Input columns:  timestamp,raw_lat,raw_lon,raw_heading,raw_speed,fix_quality,hdop
//                 (header row optional; timestamp is epoch milliseconds)

#include "gpsfilter.h"

#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Row {
    double tsMs = 0.0;
    double lat = 0.0;
    double lon = 0.0;
    double heading = 0.0;
    double speed = 0.0;
    int fixQuality = 0;
    double hdop = 0.0;
    bool hdopValid = false;
};

bool parseDouble(const std::string &s, double &out)
{
    if (s.empty())
        return false;
    try {
        size_t idx = 0;
        out = std::stod(s, &idx);
        return idx > 0;
    } catch (...) {
        return false;
    }
}

std::vector<std::string> splitCsv(const std::string &line)
{
    std::vector<std::string> out;
    std::string cur;
    std::istringstream ss(line);
    while (std::getline(ss, cur, ','))
        out.push_back(cur);
    return out;
}

// Smallest signed angular difference a-b, in degrees, wrapped to [-180,180].
double angDiff(double a, double b)
{
    double d = std::fmod(a - b + 540.0, 360.0) - 180.0;
    return d;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::fprintf(stderr,
                     "usage: %s <input.csv> [width_m] [output.csv]\n", argv[0]);
        return 2;
    }
    const std::string inPath = argv[1];
    const double widthM = (argc >= 3) ? std::atof(argv[2]) : 24.0;
    std::string outPath = (argc >= 4) ? argv[3] : std::string();
    if (outPath.empty()) {
        const size_t dot = inPath.find_last_of('.');
        outPath = (dot == std::string::npos ? inPath : inPath.substr(0, dot))
                  + "_filtered.csv";
    }

    std::ifstream in(inPath);
    if (!in) {
        std::fprintf(stderr, "error: cannot open %s\n", inPath.c_str());
        return 1;
    }

    std::vector<Row> rows;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty())
            continue;
        // Strip a trailing CR (CSV captured on Android / edited on Windows).
        if (line.back() == '\r')
            line.pop_back();
        const std::vector<std::string> f = splitCsv(line);
        if (f.size() < 6)
            continue;
        Row r;
        // A non-numeric first field = header row -> skip.
        if (!parseDouble(f[0], r.tsMs))
            continue;
        parseDouble(f[1], r.lat);
        parseDouble(f[2], r.lon);
        parseDouble(f[3], r.heading);
        parseDouble(f[4], r.speed);
        double fq = 0.0;
        if (parseDouble(f[5], fq))
            r.fixQuality = static_cast<int>(fq);
        if (f.size() >= 7)
            r.hdopValid = parseDouble(f[6], r.hdop);
        rows.push_back(r);
    }
    if (rows.size() < 2) {
        std::fprintf(stderr, "error: need >= 2 fixes, got %zu\n", rows.size());
        return 1;
    }

    // Equirectangular ENU around the first fix — identical constants/order to
    // GpsModel::updateLocal so the replay matches on-device behaviour.
    const double k = 111320.0;
    const double cosLat0 = std::cos(rows[0].lat * 3.14159265358979323846 / 180.0);

    gpsfilter::GpsFilter filter;

    std::ofstream out(outPath);
    if (!out) {
        std::fprintf(stderr, "error: cannot write %s\n", outPath.c_str());
        return 1;
    }
    out << "timestamp,raw_lat,raw_lon,filt_lat,filt_lon,raw_heading,filt_heading,"
           "raw_x,raw_y,filt_x,filt_y,speed,tier\n";

    std::vector<double> rawX, rawY, filtX, filtY, rawHdg, filtHdg;
    rawX.reserve(rows.size());

    double prevTs = rows[0].tsMs;
    for (size_t i = 0; i < rows.size(); ++i) {
        const Row &r = rows[i];
        const double dt = (i == 0) ? 0.0 : (r.tsMs - prevTs) / 1000.0;
        prevTs = r.tsMs;

        const double rx = (r.lon - rows[0].lon) * k * cosLat0;
        const double ry = (r.lat - rows[0].lat) * k;
        const gpsfilter::Tier tier =
            gpsfilter::tierFor(r.fixQuality, r.hdop, r.hdopValid);
        const gpsfilter::GpsFilter::Output o =
            filter.update(rx, ry, r.speed, dt, tier, widthM);

        const double fLat = rows[0].lat + o.y / k;
        const double fLon = rows[0].lon + (cosLat0 != 0.0 ? o.x / (k * cosLat0) : 0.0);

        const char *tierName = tier == gpsfilter::Tier::Rtk ? "RTK"
                             : tier == gpsfilter::Tier::Sbas ? "SBAS" : "GNSS";

        char buf[512];
        std::snprintf(buf, sizeof(buf),
                      "%.0f,%.8f,%.8f,%.8f,%.8f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.3f,%s\n",
                      r.tsMs, r.lat, r.lon, fLat, fLon, r.heading, o.headingDeg,
                      rx, ry, o.x, o.y, r.speed, tierName);
        out << buf;

        rawX.push_back(rx);
        rawY.push_back(ry);
        filtX.push_back(o.x);
        filtY.push_back(o.y);
        rawHdg.push_back(r.heading);
        filtHdg.push_back(o.headingDeg);
    }
    out.close();

    // ---- Wobble metrics ---------------------------------------------------
    // Position jerk proxy: mean magnitude of the 2nd difference of position (m).
    // A smoother track has smaller frame-to-frame curvature/jitter.
    auto posJerk = [](const std::vector<double> &xs,
                      const std::vector<double> &ys) {
        if (xs.size() < 3)
            return 0.0;
        double sum = 0.0;
        size_t n = 0;
        for (size_t i = 2; i < xs.size(); ++i) {
            const double ax = xs[i] - 2.0 * xs[i - 1] + xs[i - 2];
            const double ay = ys[i] - 2.0 * ys[i - 1] + ys[i - 2];
            sum += std::sqrt(ax * ax + ay * ay);
            ++n;
        }
        return n ? sum / double(n) : 0.0;
    };
    // Heading wobble: RMS of successive heading changes (deg/sample).
    auto hdgWobble = [](const std::vector<double> &h) {
        if (h.size() < 2)
            return 0.0;
        double sum = 0.0;
        size_t n = 0;
        for (size_t i = 1; i < h.size(); ++i) {
            const double d = angDiff(h[i], h[i - 1]);
            sum += d * d;
            ++n;
        }
        return n ? std::sqrt(sum / double(n)) : 0.0;
    };

    const double rawJerk = posJerk(rawX, rawY);
    const double filtJerk = posJerk(filtX, filtY);
    const double rawHw = hdgWobble(rawHdg);
    const double filtHw = hdgWobble(filtHdg);

    auto pct = [](double from, double to) {
        return from > 0.0 ? (1.0 - to / from) * 100.0 : 0.0;
    };

    std::printf("\nGPS replay: %zu fixes, width=%.1f m\n", rows.size(), widthM);
    std::printf("  input : %s\n", inPath.c_str());
    std::printf("  output: %s\n\n", outPath.c_str());
    std::printf("  position jitter (mean 2nd-diff, m):  raw %.4f -> filt %.4f  (%.1f%% smoother)\n",
                rawJerk, filtJerk, pct(rawJerk, filtJerk));
    std::printf("  heading wobble  (RMS step, deg):      raw %.3f -> filt %.3f  (%.1f%% smoother)\n",
                rawHw, filtHw, pct(rawHw, filtHw));
    std::printf("\nTune constants in gpsfilter.cpp, rebuild, and re-run to A/B.\n\n");
    return 0;
}
