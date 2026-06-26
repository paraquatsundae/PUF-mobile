#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// Master catalogs (product types, products, tank mixes, crops) shared across
// paddocks and sessions. Persisted as a single self-describing JSON file in the
// app data dir (same storage style as JobStore), saved on every change so QML
// lists stay live. All lists are user-extendable.
class WorkCatalog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList productTypes READ productTypes NOTIFY productTypesChanged)
    Q_PROPERTY(QVariantList products READ products NOTIFY productsChanged)
    Q_PROPERTY(QVariantList tankMixes READ tankMixes NOTIFY tankMixesChanged)
    Q_PROPERTY(QStringList crops READ crops NOTIFY cropsChanged)

public:
    explicit WorkCatalog(QObject *parent = nullptr);

    QStringList productTypes() const { return m_productTypes; }
    QVariantList products() const { return m_products; }     // [{name, type}]
    QVariantList tankMixes() const { return m_tankMixes; }   // [{name, rateHa, unit, carrier, products:[{name,rate,unit}]}]
    QStringList crops() const { return m_crops; }

    Q_INVOKABLE void load();
    Q_INVOKABLE QStringList productsForType(const QString &type) const;
    Q_INVOKABLE void addProductType(const QString &type);
    Q_INVOKABLE void addProduct(const QString &name, const QString &type);
    Q_INVOKABLE void addTankMix(const QVariantMap &mix);
    Q_INVOKABLE void addCrop(const QString &crop);
    Q_INVOKABLE QString catalogPath() const;

    // ---- Catalog management (Catalog Manager page): edit + delete -----------
    // Remove a single product identified by name+type.
    Q_INVOKABLE void deleteProduct(const QString &name, const QString &type);
    // Rename / retype a product (oldName+oldType -> newName+newType).
    Q_INVOKABLE void updateProduct(const QString &oldName, const QString &oldType,
                                   const QString &newName, const QString &newType);
    // Remove a product type (products of that type are left untouched).
    Q_INVOKABLE void deleteProductType(const QString &type);
    // Remove a tank mix by name.
    Q_INVOKABLE void deleteTankMix(const QString &name);
    // Tank-mix lookup by name (returns {} if absent) for the editor.
    Q_INVOKABLE QVariantMap tankMixByName(const QString &name) const;
    // Remove / rename a crop.
    Q_INVOKABLE void deleteCrop(const QString &crop);
    Q_INVOKABLE void renameCrop(const QString &oldCrop, const QString &newCrop);

signals:
    void productTypesChanged();
    void productsChanged();
    void tankMixesChanged();
    void cropsChanged();

private:
    void save() const;
    void seedDefaults();
    static bool listHasCI(const QStringList &list, const QString &value);

    QStringList m_productTypes;
    QVariantList m_products;
    QVariantList m_tankMixes;
    QStringList m_crops;
};
