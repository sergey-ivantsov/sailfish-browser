/****************************************************************************
**
** Copyright (c) 2014 - 2021 Jolla Ltd.
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.2
import QtQuick.Window 2.2 as QuickWindow
import Sailfish.Silica 1.0
import Sailfish.Browser 1.0
import Sailfish.WebView.Pickers 1.0 as Pickers
import Sailfish.WebView.Popups 1.0 as Popups
import Sailfish.WebView.Controls 1.0
import Qt5Mozilla 1.0
import Sailfish.Policy 1.0
import Sailfish.TextLinking 1.0
import "." as Browser

WebContainer {
    id: webView

    readonly property bool moving: contentItem ? contentItem.moving : false
    property bool findInPageHasResult
    property bool canShowSelectionMarkers: true

    property var resourceController: ResourceController {
        webPage: contentItem
        background: !webView.visible
    }

    property Timer auxTimer: Timer {
        interval: 1000
    }

    property var _webPageCreator: WebPageCreator {
        activeWebPage: contentItem
        // onNewWindowRequested is always handled as synchronous operation (not through newTab).
        onNewWindowRequested: tabModel.newTab("", parentId)
    }

    property Component textSelectionControllerComponent: Component {
        TextSelectionController {
            opacity: canShowSelectionMarkers ? 1.0 : 0.0
            contentWidth: webView.rotationHandler ? webView.rotationHandler.width : 0
            contentHeight: Math.max(0, webView.fullscreenHeight - webView.toolbarHeight)
            // Push below the overlay
            z: -1
            anchors {
                fill: parent
                bottomMargin: webView.toolbarHeight
            }

            Behavior on opacity { FadeAnimator {} }
        }
    }

    property var linkHandler: LinkHandler {}

    function stop() {
        if (contentItem) {
            contentItem.stop()
        }
    }

    function clearSelection() {
        if (contentItem) {
            contentItem.clearSelection()
        }
    }

    function sendAsyncMessage(name, data) {
        if (!contentItem) {
            return
        }

        contentItem.sendAsyncMessage(name, data)
    }

    function thumbnailCaptureSize() {
        var ratio = browserPage.width / browserPage.thumbnailSize.width
        var height = browserPage.thumbnailSize.height * ratio

        return Qt.size(browserPage.width, height)
    }

    function grabActivePage() {
        if (webView.contentItem && webView.activeTabRendered) {
            if (webView.privateMode) {
                webView.contentItem.grabThumbnail(thumbnailCaptureSize())
            } else {
                webView.contentItem.grabToFile(thumbnailCaptureSize())
            }
        }
    }

    foreground: visibility >= QuickWindow.Window.Maximized && Qt.application.state === Qt.ApplicationActive
    readyToPaint: resourceController.videoActive ? webView.visible && !resourceController.displayOff : webView.visible && webView.contentItem && webView.contentItem.domContentLoaded
    allowHiding: !resourceController.videoActive && !resourceController.audioActive
    fullscreenMode: (contentItem && !contentItem.chrome) ||
                    (contentItem && contentItem.fullscreen)

    touchBlocked: contentItem && contentItem.popupOpener && contentItem.popupOpener.active ||
                  webView.contentItem && webView.contentItem.textSelectionActive || !AccessPolicy.browserEnabled || false
    favicon: contentItem ? contentItem.favicon : ""

    webPageComponent: Component {
        WebPage {
            id: webPage

            property bool acceptedTouchIcon
            property int frameCounter
            property bool rendered
            readonly property bool textSelectionActive: textSelectionController && textSelectionController.active
            property Item textSelectionController: null
            readonly property bool activeWebPage: container.tabId == tabId

            property QtObject pickerOpener: Pickers.PickerOpener {
                pageStack: window.pageStack
                contentItem: webPage
            }

            property QtObject popupOpener: Popups.PopupOpener {
                pageStack: window.pageStack
                parentItem: browserPage
                contentItem: webPage
                // ContextMenu needs a reference to correct TabModel so that
                // private and public tabs are created to correct model. While context
                // menu is open, tab model cannot change (at least at the moment).
                tabModel: webView.tabModel

                onAboutToOpenContextMenu: {
                    if (Qt.inputMethod.visible) {
                        browserPage.focus = true
                        Qt.inputMethod.hide()
                    }

                    // Possible path that leads to a new tab. Thus, capturing current
                    // view before opening context menu.
                    webView.grabActivePage()
                    contextMenuRequested(data)
                }

                onLoginSaved: {
                    FaviconManager.grabIcon("logins", webPage,
                                            Qt.size(Theme.iconSizeMedium,
                                                    Theme.iconSizeMedium));
                }
            }

            signal selectionCopied(var data)
            signal contextMenuRequested(var data)

            function grabItem() {
                if (rendered && activeWebPage && active) {
                    if (webView.privateMode) {
                        grabThumbnail(thumbnailCaptureSize())
                    } else {
                        grabToFile(thumbnailCaptureSize())
                    }
                }
            }

            function clearSelection() {
                if (textSelectionActive) {
                    textSelectionController.clearSelection()
                }
            }

            fullscreenHeight: container.fullscreenHeight
            toolbarHeight: container.toolbarHeight
            throttlePainting: !foreground && !resourceController.videoActive && webView.visible || !webView.visible
            enabled: webView.enabled
            chromeGestureThreshold: toolbarHeight / 2
            chromeGestureEnabled: !forcedChrome && enabled && !webView.imOpened

            onGrabResult: tabModel.updateThumbnailPath(tabId, fileName)

            // Image data is base64 encoded which can be directly used as source in Image element
            onThumbnailResult: tabModel.updateThumbnailPath(tabId, data)

            onAtYBeginningChanged: {
                if (atYBeginning && activeWebPage && domContentLoaded) {
                    chrome = true
                }
            }

            onAtYEndChanged: {
                // Don't hide chrome if content lenght is short e.i. forcedChrome is enabled.
                if (!atYBeginning && atYEnd && !forcedChrome && chrome && activeWebPage && domContentLoaded) {
                    chrome = false
                }
            }

            onUrlChanged: {
                if (url == "about:blank") return

                webView.findInPageHasResult = false
                var modelUrl = tabModel.url(tabId)

                rendered = false
                frameCounter = 0

                // If url has changed or url doesn't exists in the model,
                // clear the thumbnail. Preserve the thumbnails in the model
                // if it has the same url (restarting browser / resurrecting a tab).
                if (!modelUrl || modelUrl != url) {
                    tabModel.updateThumbnailPath(tabId, "")
                }
            }

            onBackgroundColorChanged: {
                // Update only webPage
                if (container.contentItem === webPage) {
                    sendAsyncMessage("Browser:SelectionColorUpdate",
                                     {
                                         "color": Theme.secondaryHighlightColor
                                     })
                }
            }

            onDraggingChanged: {
                if (dragging && loading) {
                    userHasDraggedWhileLoading = true
                }
            }

            onLoadedChanged: {
                if (loaded) {
                    if (!userHasDraggedWhileLoading && resurrectedContentRect) {
                        sendAsyncMessage("embedui:zoomToRect",
                                         {
                                             "x": resurrectedContentRect.x, "y": resurrectedContentRect.y,
                                             "width": resurrectedContentRect.width, "height": resurrectedContentRect.height
                                         })
                        resurrectedContentRect = null
                    }
                    grabItem()

                    if (!webView.privateMode) {
                        // Update the favicon for history items.
                        FaviconManager.grabIcon("history", webPage,
                                                Qt.size(Theme.iconSizeMedium,
                                                        Theme.iconSizeMedium))
                    }
                }

                // Refresh timers (if any) keep working even for suspended views. Hence
                // suspend the view again explicitly if browser content window is in not visible (background).
                if (loaded && !webView.visible) {
                    suspendView();
                }
            }

            onLoadingChanged: {
                if (loading) {
                    userHasDraggedWhileLoading = false
                    webPage.chrome = true
                    favicon = ""
                    acceptedTouchIcon = false
                }
            }

            onAfterRendering: {
                // Try to capture something else than glClear color.
                if (frameCounter < 3) {
                    ++frameCounter
                } else if (!rendered) {
                    rendered = true
                    grabItem()
                }
            }

            onRecvAsyncMessage: {
                if (pickerOpener.message(message, data) || popupOpener.message(message, data)) {
                    return
                }

                switch (message) {
                case "Link:SetIcon": {
                    if (acceptedTouchIcon)
                        return

                    acceptedTouchIcon = data.isRichIcon
                    favicon = data.url
                    break
                }
                case "Content:SelectionRange": {
                    if (textSelectionController === null) {
                        textSelectionController = textSelectionControllerComponent.createObject(browserPage,
                                                                                                {"contentItem" : webPage}
                                                                                                )
                    }
                    textSelectionController.selectionRangeUpdated(data)
                    break
                }
                case "Content:SelectionSwap": {
                    if (textSelectionController) {
                        textSelectionController.swap()
                    }

                    break
                }
                case "embed:find": {
                    // Found, or found wrapped
                    if( data.r == 0 || data.r == 2) {
                        webView.findInPageHasResult = true
                    } else {
                        webView.findInPageHasResult = false
                    }
                    break
                }
                // embed:OpenLink listener is registered only in the captive portal mode
                case "embed:OpenLink": {
                    linkHandler.handleLink(data.uri)
                    break
                }
                case "Link:AddSearch": {
                    if (!webView.privateMode) {
                        // This adds this search as available if not already there
                        SearchEngineModel.add(data.engine.title, data.engine.href)
                    }
                    break
                }
                }
            }
            onRecvSyncMessage: {
                // sender expects that this handler will update `response` argument
                switch (message) {
                case "Content:SelectionCopied": {
                    if (data.succeeded && textSelectionController) {
                        textSelectionController.showNotification()
                        response.message = {"": ""}
                    }
                    break
                }
                }
            }

            onContextMenuRequested: {
                if (data.types.indexOf("content-text") !== -1) {
                    // we want to select some content text
                    webPage.sendAsyncMessage("Browser:SelectionStart", {"xPos": data.xPos, "yPos": data.yPos})
                }
            }

            Component.onCompleted: {
                addMessageListener("Content:SelectionRange")
                addMessageListener("Content:SelectionCopied")
                addMessageListener("Content:SelectionSwap")

                PermissionManager.instance()
            }
        }
    }
}
