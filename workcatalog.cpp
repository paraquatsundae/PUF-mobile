#include "workcatalog.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

WorkCatalog::WorkCatalog(QObject *parent) : QObject(parent) {}

QString WorkCatalog::catalogPath() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return base + QStringLiteral("/catalog.json");
}

bool WorkCatalog::listHasCI(const QStringList &list, const QString &value)
{
    for (const QString &s : list)
        if (s.compare(value, Qt::CaseInsensitive) == 0)
            return true;
    return false;
}

void WorkCatalog::seedDefaults()
{
    if (m_productTypes.isEmpty())
        m_productTypes = QStringList{
            QStringLiteral("Fertiliser"), QStringLiteral("Herbicide"),
            QStringLiteral("Insecticide"), QStringLiteral("Fungicide"),
            QStringLiteral("Other") };
    if (m_crops.isEmpty())
        m_crops = QStringList{
            QStringLiteral("Fallow"), QStringLiteral("Pasture"), QStringLiteral("Wheat"),
            QStringLiteral("Barley"), QStringLiteral("Canola"), QStringLiteral("Oats"),
            QStringLiteral("Sorghum"), QStringLiteral("Cotton"), QStringLiteral("Lucerne"),
            QStringLiteral("Chickpea"), QStringLiteral("Faba bean"), QStringLiteral("Maize"),
            QStringLiteral("Triticale") };
}

void WorkCatalog::load()
{
    QFile f(catalogPath());
    if (f.exists() && f.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        f.close();
        if (doc.isObject()) {
            const QJsonObject o = doc.object();
            m_productTypes = QVariant(o.value(QStringLiteral("productTypes")).toArray().toVariantList()).toStringList();
            m_products = o.value(QStringLiteral("products")).toArray().toVariantList();
            m_tankMixes = o.value(QStringLiteral("tankMixes")).toArray().toVariantList();
            m_crops = QVariant(o.value(QStringLiteral("crops")).toArray().toVariantList()).toStringList();
        }
    }
    const bool freshFile = m_productTypes.isEmpty() && m_crops.isEmpty()
                           && m_products.isEmpty() && m_tankMixes.isEmpty();
    seedDefaults();
    if (freshFile)
        save();
    emit productTypesChanged();
    emit productsChanged();
    emit tankMixesChanged();
    emit cropsChanged();
}

void WorkCatalog::save() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(base);

    QJsonObject o;
    o[QStringLiteral("schema")] = QStringLiteral("puf-mobile.catalog");
    o[QStringLiteral("schemaVersion")] = 1;
    o[QStringLiteral("productTypes")] = QJsonArray::fromStringList(m_productTypes);
    o[QStringLiteral("products")] = QJsonArray::fromVariantList(m_products);
    o[QStringLiteral("tankMixes")] = QJsonArray::fromVariantList(m_tankMixes);
    o[QStringLiteral("crops")] = QJsonArray::fromStringList(m_crops);

    QFile f(catalogPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        f.close();
    }
}

QStringList WorkCatalog::productsForType(const QString &type) const
{
    QStringList out;
    for (const QVariant &v : m_products) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("type")).toString().compare(type, Qt::CaseInsensitive) == 0)
            out.append(m.value(QStringLiteral("name")).toString());
    }
    return out;
}

void WorkCatalog::addProductType(const QString &type)
{
    const QString t = type.trimmed();
    if (t.isEmpty() || listHasCI(m_productTypes, t))
        return;
    m_productTypes.append(t);
    save();
    emit productTypesChanged();
}

void WorkCatalog::addProduct(const QString &name, const QString &type)
{
    const QString n = name.trimmed();
    const QString t = type.trimmed();
    if (n.isEmpty() || t.isEmpty())
        return;
    for (const QVariant &v : m_products) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString().compare(n, Qt::CaseInsensitive) == 0
            && m.value(QStringLiteral("type")).toString().compare(t, Qt::CaseInsensitive) == 0)
            return;
    }
    if (!listHasCI(m_productTypes, t)) {
        m_productTypes.append(t);
        emit productTypesChanged();
    }
    QVariantMap p;
    p[QStringLiteral("name")] = n;
    p[QStringLiteral("type")] = t;
    m_products.append(p);
    save();
    emit productsChanged();
}

void WorkCatalog::addTankMix(const QVariantMap &mix)
{
    const QString name = mix.value(QStringLiteral("name")).toString().trimmed();
    if (name.isEmpty())
        return;
    QVariantMap m = mix;
    m[QStringLiteral("name")] = name;
    for (int i = 0; i < m_tankMixes.size(); ++i) {
        if (m_tankMixes.at(i).toMap().value(QStringLiteral("name")).toString()
                .compare(name, Qt::CaseInsensitive) == 0) {
            m_tankMixes[i] = m;
            save();
            emit tankMixesChanged();
            return;
        }
    }
    m_tankMixes.append(m);
    save();
    emit tankMixesChanged();
}

void WorkCatalog::addCrop(const QString &crop)
{
    const QString c = crop.trimmed();
    if (c.isEmpty() || listHasCI(m_crops, c))
        return;
    m_crops.append(c);
    save();
    emit cropsChanged();
}

void WorkCatalog::deleteProduct(const QString &name, const QString &type)
{
    bool removed = false;
    for (int i = 0; i < m_products.size(); ++i) {
        const QVariantMap m = m_products.at(i).toMap();
        if (m.value(QStringLiteral("name")).toString().compare(name, Qt::CaseInsensitive) == 0
            && m.value(QStringLiteral("type")).toString().compare(type, Qt::CaseInsensitive) == 0) {
            m_products.removeAt(i);
            removed = true;
            break;
        }
    }
    if (removed) {
        save();
        emit productsChanged();
    }
}

void WorkCatalog::updateProduct(const QString &oldName, const QString &oldType,
                                const QString &newName, const QString &newType)
{
    const QString n = newName.trimmed();
    const QString t = newType.trimmed();
    if (n.isEmpty() || t.isEmpty())
        return;
    for (int i = 0; i < m_products.size(); ++i) {
        QVariantMap m = m_products.at(i).toMap();
        if (m.value(QStringLiteral("name")).toString().compare(oldName, Qt::CaseInsensitive) == 0
            && m.value(QStringLiteral("type")).toString().compare(oldType, Qt::CaseInsensitive) == 0) {
            m[QStringLiteral("name")] = n;
            m[QStringLiteral("type")] = t;
            m_products[i] = m;
            if (!listHasCI(m_productTypes, t)) {
                m_productTypes.append(t);
                emit productTypesChanged();
            }
            save();
            emit productsChanged();
            return;
        }
    }
}

void WorkCatalog::deleteProductType(const QString &type)
{
    for (int i = 0; i < m_productTypes.size(); ++i) {
        if (m_productTypes.at(i).compare(type, Qt::CaseInsensitive) == 0) {
            m_productTypes.removeAt(i);
            save();
            emit productTypesChanged();
            return;
        }
    }
}

void WorkCatalog::deleteTankMix(const QString &name)
{
    for (int i = 0; i < m_tankMixes.size(); ++i) {
        if (m_tankMixes.at(i).toMap().value(QStringLiteral("name")).toString()
                .compare(name, Qt::CaseInsensitive) == 0) {
            m_tankMixes.removeAt(i);
            save();
            emit tankMixesChanged();
            return;
        }
    }
}

QVariantMap WorkCatalog::tankMixByName(const QString &name) const
{
    for (const QVariant &v : m_tankMixes) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString().compare(name, Qt::CaseInsensitive) == 0)
            return m;
    }
    return QVariantMap();
}

void WorkCatalog::deleteCrop(const QString &crop)
{
    for (int i = 0; i < m_crops.size(); ++i) {
        if (m_crops.at(i).compare(crop, Qt::CaseInsensitive) == 0) {
            m_crops.removeAt(i);
            save();
            emit cropsChanged();
            return;
        }
    }
}

void WorkCatalog::renameCrop(const QString &oldCrop, const QString &newCrop)
{
    const QString n = newCrop.trimmed();
    if (n.isEmpty() || listHasCI(m_crops, n))
        return;
    for (int i = 0; i < m_crops.size(); ++i) {
        if (m_crops.at(i).compare(oldCrop, Qt::CaseInsensitive) == 0) {
            m_crops[i] = n;
            save();
            emit cropsChanged();
            return;
        }
    }
}
