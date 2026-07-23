#include "taskdata.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QtMath>
#include <QDebug>

namespace {

// Local-metre area (ha) via equirectangular projection around the first point.
double areaHaOf(const QVector<GeoPt> &ring)
{
    if (ring.size() < 3)
        return 0.0;
    const double k = 111320.0;
    const double lat0 = ring.first().lat;
    const double cosLat = qCos(qDegreesToRadians(lat0));
    double sum = 0.0;
    const int n = ring.size();
    for (int i = 0; i < n; ++i) {
        const GeoPt &p = ring.at(i);
        const GeoPt &q = ring.at((i + 1) % n);
        const double x1 = (p.lon - ring.first().lon) * k * cosLat;
        const double y1 = (p.lat - ring.first().lat) * k;
        const double x2 = (q.lon - ring.first().lon) * k * cosLat;
        const double y2 = (q.lat - ring.first().lat) * k;
        sum += (x1 * y2 - x2 * y1);
    }
    return qFabs(sum) / 2.0 / 10000.0;
}

} // namespace

bool TaskData::load(const QString &path, QVector<Client> &clients)
{
    clients.clear();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    // Flat parse, then assemble the hierarchy from the ref attributes.
    QVector<Client> tmpClients;                 // CTR
    QHash<QString, int> clientIdx;              // id -> index
    struct FarmRef { Farm farm; QString clientRef; };
    QVector<FarmRef> farms;                     // FRM
    struct FieldRef { Field field; QString clientRef; QString farmRef; };
    QVector<FieldRef> fields;                   // PFD

    enum PntMode { None, Boundary, Guidance };
    PntMode mode = None;
    int curLsgType = 0;
    FieldRef *curField = nullptr;
    AbLine curAb;
    bool inGpn = false;

    QXmlStreamReader xml(&file);
    while (!xml.atEnd()) {
        const auto tok = xml.readNext();
        if (tok == QXmlStreamReader::StartElement) {
            const QStringRef name = xml.name();
            const QXmlStreamAttributes a = xml.attributes();
            if (name == QLatin1String("CTR")) {
                Client c;
                c.id = a.value("A").toString();
                c.name = a.value("B").toString();
                tmpClients.append(c);
                clientIdx.insert(c.id, tmpClients.size() - 1);
            } else if (name == QLatin1String("FRM")) {
                FarmRef fr;
                fr.farm.id = a.value("A").toString();
                fr.farm.name = a.value("B").toString();
                fr.clientRef = a.value("I").toString();
                farms.append(fr);
            } else if (name == QLatin1String("PFD")) {
                FieldRef fr;
                fr.field.id = a.value("A").toString();
                fr.field.name = a.value("C").toString();
                fr.clientRef = a.value("E").toString();
                fr.farmRef = a.value("F").toString();
                fields.append(fr);
                curField = &fields.last();
            } else if (name == QLatin1String("PLN")) {
                if (a.value("A").toString() == QLatin1String("1"))
                    mode = Boundary;
            } else if (name == QLatin1String("GGP")) {
                // container only
            } else if (name == QLatin1String("GPN")) {
                inGpn = true;
                mode = Guidance;
                curAb = AbLine();
                curAb.id = a.value("A").toString();
                curAb.name = a.value("B").toString();
            } else if (name == QLatin1String("LSG")) {
                curLsgType = a.value("A").toString().toInt();
            } else if (name == QLatin1String("PNT")) {
                GeoPt p;
                p.lat = a.value("C").toString().toDouble();
                p.lon = a.value("D").toString().toDouble();
                if (mode == Boundary && curField && curLsgType == 1) {
                    curField->field.boundary.append(p);
                } else if (mode == Guidance && inGpn) {
                    if (curAb.a.lat == 0.0 && curAb.a.lon == 0.0)
                        curAb.a = p;
                    else
                        curAb.b = p;
                }
            }
        } else if (tok == QXmlStreamReader::EndElement) {
            const QStringRef name = xml.name();
            if (name == QLatin1String("PFD")) {
                curField = nullptr;
            } else if (name == QLatin1String("PLN")) {
                mode = None;
            } else if (name == QLatin1String("GPN")) {
                if (curField)
                    curField->field.abLines.append(curAb);
                inGpn = false;
                mode = None;
            }
        }
    }
    file.close();
    if (xml.hasError())
        return false;

    // Assemble hierarchy.
    for (const FarmRef &fr : farms) {
        const int ci = clientIdx.value(fr.clientRef, -1);
        if (ci >= 0)
            tmpClients[ci].farms.append(fr.farm);
    }
    for (FieldRef &fr : fields) {
        if (fr.field.boundary.size() >= 3)
            fr.field.areaHa = areaHaOf(fr.field.boundary);
        const int ci = clientIdx.value(fr.clientRef, -1);
        if (ci < 0)
            continue;
        Client &c = tmpClients[ci];
        for (Farm &fm : c.farms) {
            if (fm.id == fr.farmRef) {
                fm.fields.append(fr.field);
                break;
            }
        }
    }

    clients = tmpClients;
    return true;
}

bool TaskData::save(const QString &path, const QVector<Client> &clients)
{
    QFileInfo fi(path);
    QDir().mkpath(fi.absolutePath());

    if (QFile::exists(path) && !fi.isWritable()) {
        QFile::setPermissions(path,
                              QFileDevice::ReadOwner | QFileDevice::WriteOwner
                                  | QFileDevice::ReadUser | QFileDevice::WriteUser);
    }

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        qWarning("[taskdata] cannot write %s: %s",
                 qUtf8Printable(path), qUtf8Printable(file.errorString()));
        return false;
    }

    QXmlStreamWriter xml(&file);
    xml.setAutoFormatting(true);
    xml.writeStartDocument();

    xml.writeStartElement(QStringLiteral("ISO11783_TaskData"));
    xml.writeAttribute(QStringLiteral("VersionMajor"), QStringLiteral("4"));
    xml.writeAttribute(QStringLiteral("VersionMinor"), QStringLiteral("0"));
    xml.writeAttribute(QStringLiteral("ManagementSoftwareManufacturer"), QStringLiteral("PUFworks"));
    xml.writeAttribute(QStringLiteral("ManagementSoftwareVersion"), QStringLiteral("1.0"));
    xml.writeAttribute(QStringLiteral("DataTransferOrigin"), QStringLiteral("1"));

    // Customers
    for (const Client &c : clients) {
        xml.writeStartElement(QStringLiteral("CTR"));
        xml.writeAttribute(QStringLiteral("A"), c.id);
        xml.writeAttribute(QStringLiteral("B"), c.name);
        xml.writeEndElement();
    }
    // Farms
    for (const Client &c : clients) {
        for (const Farm &fm : c.farms) {
            xml.writeStartElement(QStringLiteral("FRM"));
            xml.writeAttribute(QStringLiteral("A"), fm.id);
            xml.writeAttribute(QStringLiteral("B"), fm.name);
            xml.writeAttribute(QStringLiteral("I"), c.id);
            xml.writeEndElement();
        }
    }
    // Partfields (fields)
    for (const Client &c : clients) {
        for (const Farm &fm : c.farms) {
            for (const Field &fd : fm.fields) {
                xml.writeStartElement(QStringLiteral("PFD"));
                xml.writeAttribute(QStringLiteral("A"), fd.id);
                xml.writeAttribute(QStringLiteral("C"), fd.name);
                xml.writeAttribute(QStringLiteral("D"),
                    QString::number(static_cast<qulonglong>(fd.areaHa * 10000.0 + 0.5)));
                xml.writeAttribute(QStringLiteral("E"), c.id);
                xml.writeAttribute(QStringLiteral("F"), fm.id);

                // Boundary
                if (fd.boundary.size() >= 3) {
                    xml.writeStartElement(QStringLiteral("PLN"));
                    xml.writeAttribute(QStringLiteral("A"), QStringLiteral("1")); // PartfieldBoundary
                    xml.writeAttribute(QStringLiteral("B"), QStringLiteral("Boundary"));
                    xml.writeStartElement(QStringLiteral("LSG"));
                    xml.writeAttribute(QStringLiteral("A"), QStringLiteral("1")); // PolygonExterior
                    for (const GeoPt &p : fd.boundary) {
                        xml.writeStartElement(QStringLiteral("PNT"));
                        xml.writeAttribute(QStringLiteral("A"), QStringLiteral("2")); // Other
                        xml.writeAttribute(QStringLiteral("C"), QString::number(p.lat, 'f', 9));
                        xml.writeAttribute(QStringLiteral("D"), QString::number(p.lon, 'f', 9));
                        xml.writeEndElement();
                    }
                    xml.writeEndElement(); // LSG
                    xml.writeEndElement(); // PLN
                }

                // AB lines
                if (!fd.abLines.isEmpty()) {
                    xml.writeStartElement(QStringLiteral("GGP"));
                    xml.writeAttribute(QStringLiteral("A"), fd.id + QStringLiteral("-GGP"));
                    xml.writeAttribute(QStringLiteral("B"), QStringLiteral("Guidance"));
                    for (const AbLine &ab : fd.abLines) {
                        xml.writeStartElement(QStringLiteral("GPN"));
                        xml.writeAttribute(QStringLiteral("A"), ab.id);
                        xml.writeAttribute(QStringLiteral("B"), ab.name);
                        xml.writeAttribute(QStringLiteral("C"), QStringLiteral("1")); // AB
                        xml.writeStartElement(QStringLiteral("LSG"));
                        xml.writeAttribute(QStringLiteral("A"), QStringLiteral("5")); // GuidancePattern
                        for (const GeoPt &p : { ab.a, ab.b }) {
                            xml.writeStartElement(QStringLiteral("PNT"));
                            xml.writeAttribute(QStringLiteral("A"), QStringLiteral("2"));
                            xml.writeAttribute(QStringLiteral("C"), QString::number(p.lat, 'f', 9));
                            xml.writeAttribute(QStringLiteral("D"), QString::number(p.lon, 'f', 9));
                            xml.writeEndElement();
                        }
                        xml.writeEndElement(); // LSG
                        xml.writeEndElement(); // GPN
                    }
                    xml.writeEndElement(); // GGP
                }

                xml.writeEndElement(); // PFD
            }
        }
    }

    xml.writeEndElement(); // ISO11783_TaskData
    xml.writeEndDocument();
    file.close();
    return true;
}
