/****************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Petri M. Gerdt <petri.gerdt@jollamobile.com>
**
****************************************************************************/

#include "declarativehistorymodel.h"

#include "dbmanager.h"

DeclarativeHistoryModel::DeclarativeHistoryModel(QObject *parent) :
    QAbstractListModel(parent), m_tabId(-1)
{
    connect(DBManager::instance(), SIGNAL(tabChanged(Tab)),
            this, SLOT(tabChanged(Tab)));
    connect(DBManager::instance(), SIGNAL(historyAvailable(QList<Link>)),
            this, SLOT(historyAvailable(QList<Link>)));
    connect(DBManager::instance(), SIGNAL(tabHistoryAvailable(int,QList<Link>)),
            this, SLOT(tabHistoryAvailable(int, QList<Link>)));
    connect(DBManager::instance(), SIGNAL(thumbPathChanged(QString,QString)),
            this, SLOT(updateThumbPath(QString,QString)));
    connect(DBManager::instance(), SIGNAL(titleChanged(QString,QString)),
            this, SLOT(updateTitle(QString,QString)));
}

QHash<int, QByteArray> DeclarativeHistoryModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[ThumbPathRole] = "thumbnailPath";
    roles[UrlRole] = "url";
    roles[TitleRole] = "title";
    return roles;
}

void DeclarativeHistoryModel::clear()
{
    if (m_links.count() == 0)
        return;

    beginRemoveRows(QModelIndex(), 0, m_links.count() - 1);
    m_links.clear();
    endRemoveRows();
    if (m_tabId <= 0) {
        DBManager::instance()->clearHistory();
    } else {
        DBManager::instance()->clearTabHistory(m_tabId);
    }
    emit countChanged();
}

int DeclarativeHistoryModel::tabId() const
{
    return m_tabId;
}

void DeclarativeHistoryModel::setTabId(int tabId)
{
    if (m_tabId != tabId) {
        m_tabId = tabId;
        emit tabIdChanged();
        load();
    }
}

int DeclarativeHistoryModel::rowCount(const QModelIndex & parent) const {
    Q_UNUSED(parent);
    return m_links.count();
}

QVariant DeclarativeHistoryModel::data(const QModelIndex & index, int role) const {
    if (index.row() < 0 || index.row() > m_links.count())
        return QVariant();

    const Link url = m_links[index.row()];
    if (role == ThumbPathRole) {
        return url.thumbPath();
    } else if (role == UrlRole) {
        return url.url();
    } else if (role == TitleRole) {
        return url.title();
    }
    return QVariant();
}

void DeclarativeHistoryModel::componentComplete()
{
    load();
}

void DeclarativeHistoryModel::classBegin()
{
}

void DeclarativeHistoryModel::load()
{
    if (m_tabId > 0) {
        DBManager::instance()->getTabHistory(m_tabId);
    } else {
        DBManager::instance()->getHistory();
    }
}

void DeclarativeHistoryModel::tabHistoryAvailable(int tabId, QList<Link> linkList)
{
    if (tabId == m_tabId) {
        beginResetModel();
        m_links = linkList;
        endResetModel();
        emit countChanged();
    }
}

void DeclarativeHistoryModel::historyAvailable(QList<Link> linkList)
{
    if (m_tabId <= 0) {
        beginResetModel();
        m_links = linkList;
        endResetModel();
        emit countChanged();
    }
}

void DeclarativeHistoryModel::tabChanged(Tab tab)
{
    if (m_tabId == tab.tabId()) {
        load();
    }
}

void DeclarativeHistoryModel::updateThumbPath(QString url, QString path)
{
    QVector<int> roles;
    roles << ThumbPathRole;
    for (int i = 0; i < m_links.count(); i++) {
        if (m_links.at(i).url() == url && m_links.at(i).thumbPath() != path) {
            m_links[i].setThumbPath(path);
            QModelIndex start = index(i, 0);
            QModelIndex end = index(i, 0);
            emit dataChanged(start, end, roles);
        }
    }
}

void DeclarativeHistoryModel::updateTitle(QString url, QString title)
{
    QVector<int> roles;
    roles << TitleRole;
    for (int i = 0; i < m_links.count(); i++) {
        if (m_links.at(i).url() == url && m_links.at(i).title() != title) {
            m_links[i].setTitle(title);
            QModelIndex start = index(i, 0);
            QModelIndex end = index(i, 0);
            emit dataChanged(start, end, roles);
        }
    }
}