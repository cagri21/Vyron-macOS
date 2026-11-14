import { actOnPage, clearPageSnapshot, consumeNavigationSnapshot, readPageSnapshot } from "./dom.js";
import { BridgeSession } from "./session.js";
import { isRequestID, sameOriginURL } from "./protocol.js";

let nativePort = null;
let heartbeat = null;
let lastError = null;
let browserConnection = null;
let openingTabs = false;

const session = new BridgeSession({ execute: executeRequest, respond, changed: publishState });

function respond(message) {
    try { nativePort?.postMessage(message); }
    catch { endConnection("The connection to Vyron ended. Reconnect this tab to continue."); }
}

function publishState() {
    const hasPending = session.pending.size > 0;
    chrome.action.setBadgeText({ text: hasPending ? "!" : (session.tabs.size ? String(session.tabs.size) : "") });
    chrome.action.setBadgeBackgroundColor({ color: hasPending ? "#FF8549" : "#339CFF" });
    chrome.action.setTitle({ title: hasPending ? "Vyron: review a browser action" : "Vyron for Chrome" });
}

function endConnection(reason) {
    const port = nativePort;
    nativePort = null;
    if (heartbeat !== null) clearInterval(heartbeat);
    heartbeat = null;
    lastError = reason;
    browserConnection = null;
    for (const tabID of session.tabs.keys()) discardSnapshot(tabID);
    session.disconnectAll(reason);
    try { port?.disconnect(); } catch { /* A closed Chrome port needs no further cleanup. */ }
}

function closeIfUnused() {
    if (nativePort && !browserConnection && !session.tabs.size) endConnection(null);
}

function discardSnapshot(tabID) {
    // No page content is read. Navigation/closed tabs can make this cleanup unavailable;
    // isolated-world references also expire after 30 seconds independently of the worker.
    void chrome.scripting.executeScript({
        target: { tabId: tabID, frameIds: [0] }, world: "ISOLATED", func: clearPageSnapshot
    }).catch(() => false);
}

function connectHost() {
    if (nativePort) return;
    lastError = null;
    const port = chrome.runtime.connectNative("ai.vyron.chrome");
    nativePort = port;
    port.onMessage.addListener(message => {
        if (port !== nativePort) return;
        if (message?.version === 1 && message.type === "cancel" && isRequestID(message.id)) {
            session.cancel(message.id);
        } else {
            void session.receive(message, Boolean(browserConnection));
        }
    });
    port.onDisconnect.addListener(() => {
        const reason = chrome.runtime.lastError?.message;
        if (port === nativePort) {
            endConnection(reason
                ? "Vyron could not connect: " + reason + " Install the Chrome connection in Vyron, then connect again."
                : "The connection to Vyron ended. Connect the tab again to continue.");
        }
    });
    port.postMessage({ version: 1, type: "hello" });
    heartbeat = setInterval(() => respond({ version: 1, type: "heartbeat" }), 2_000);
}

async function currentTab(connected) {
    const tab = await chrome.tabs.get(connected.id);
    if (tab.incognito || tab.pendingUrl) throw new Error("Wait for the page to finish loading, then connect it again.");
    sameOriginURL(tab.url, connected.origin);
    return tab;
}

function requireLiveRequest(request, connected, port = nativePort) {
    if (!nativePort || nativePort !== port || session.isCancelled(request.id) || Date.now() >= request.expiresAt
        || (connected && session.tabs.get(connected.id) !== connected)) {
        throw new Error("The request expired or was cancelled. No action was retried.");
    }
}

async function normalWindow(windowID) {
    if (!Number.isSafeInteger(windowID) || windowID < 0) throw new Error("Open the popup in a regular Chrome window.");
    const window = await chrome.windows.get(windowID);
    if (!window || window.id !== windowID || window.incognito || window.type !== "normal") {
        throw new Error("Open the popup in a regular Chrome window.");
    }
    return window;
}

async function openGroupedTabs(request, windowID) {
    if (openingTabs) throw new Error("Wait for the approved browser action to finish.");
    const port = nativePort;
    const connection = browserConnection;
    const { urls, groupTitle } = request.arguments;
    const tabIds = [];
    function requireLiveGroupRequest() {
        requireLiveRequest(request, null, port);
        if (!connection || browserConnection !== connection) throw new Error("Chrome was disconnected while opening the group.");
    }
    openingTabs = true;
    try {
        await normalWindow(windowID);
        for (const url of urls) {
            requireLiveGroupRequest();
            const tab = await chrome.tabs.create({ windowId: windowID, active: false, url });
            if (!Number.isSafeInteger(tab.id) || tab.id < 0) throw new Error("Chrome did not identify the new tab.");
            tabIds.push(tab.id);
        }
        requireLiveGroupRequest();
        const groupID = await chrome.tabs.group({ tabIds, createProperties: { windowId: windowID } });
        requireLiveGroupRequest();
        await chrome.tabGroups.update(groupID, { title: groupTitle });
        requireLiveGroupRequest();
        return { groupID, groupTitle, tabCount: tabIds.length };
    } catch (error) {
        const cleanup = await Promise.allSettled(tabIds.map(async tabID => chrome.tabs.remove(tabID)));
        if (cleanup.some(result => result.status === "rejected")) {
            throw new Error("Chrome could not finish the group or close every new tab. Check Chrome before trying again.");
        }
        throw error;
    } finally {
        openingTabs = false;
    }
}

async function executeRequest(request, connected, windowID) {
    const args = request.arguments;
    requireLiveRequest(request, connected);
    if (request.method === "openTabs") return openGroupedTabs(request, windowID);
    if (request.method === "tabs") {
        const tabs = [];
        for (const item of [...session.tabs.values()]) {
            try {
                const tab = await currentTab(item);
                requireLiveRequest(request, null);
                if (session.tabs.get(item.id) !== item) continue;
                tabs.push({ tabID: item.id, title: String(tab.title ?? "").slice(0, 300), url: tab.url });
            } catch {
                session.disconnect(item.id, "The tab is no longer available. Connect it again in Chrome.");
            }
        }
        return { tabs };
    }
    await currentTab(connected);
    requireLiveRequest(request, connected);
    const context = { ...args, method: request.method, expiresAt: request.expiresAt, origin: connected.origin };
    if (request.method === "snapshot" || request.method === "click" || request.method === "fill") {
        const results = await chrome.scripting.executeScript({
            target: { tabId: connected.id, frameIds: [0] },
            world: "ISOLATED",
            func: request.method === "snapshot" ? readPageSnapshot : actOnPage,
            args: [context]
        });
        const result = results.find(item => item.frameId === 0)?.result;
        if (!result) throw new Error("The page did not return a result. Reconnect the tab and try again.");
        return result;
    }
    const navigationCheck = await chrome.scripting.executeScript({
        target: { tabId: connected.id, frameIds: [0] }, world: "ISOLATED", func: consumeNavigationSnapshot, args: [context]
    });
    if (!navigationCheck.find(item => item.frameId === 0)?.result?.url) throw new Error("The page snapshot could not be verified.");
    await currentTab(connected);
    requireLiveRequest(request, connected);
    if (request.method === "navigate") {
        const url = sameOriginURL(args.url, connected.origin);
        requireLiveRequest(request, connected);
        await chrome.tabs.update(connected.id, { url: url.href });
    } else if (request.method === "reload") {
        requireLiveRequest(request, connected);
        await chrome.tabs.reload(connected.id);
    } else {
        throw new Error("This browser command is unavailable.");
    }
    return { tabID: connected.id, action: request.method, status: "sent", message: "Read a fresh snapshot to verify the result." };
}

async function popupMessage(message) {
    switch (message?.type) {
    case "status":
        return { ok: true, connected: Boolean(nativePort), browserConnected: Boolean(browserConnection), lastError, ...session.view() };
    case "connectBrowser":
        await normalWindow(message.windowID);
        if (!await chrome.permissions.contains({ permissions: ["tabGroups"] })) {
            throw new Error("Chrome needs permission to create named tab groups.");
        }
        browserConnection ??= Symbol("Open Chrome tab groups");
        try { connectHost(); }
        catch (error) { endConnection(error.message); throw error; }
        return { ok: true };
    case "disconnectBrowser":
        browserConnection = null;
        session.disconnectBrowser();
        closeIfUnused();
        return { ok: true };
    case "connect": {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!tab || tab.id !== message.tabID) throw new Error("The active tab changed. Open the extension on your chosen tab again.");
        session.connect(tab);
        try { connectHost(); }
        catch (error) { endConnection(error.message); throw error; }
        return { ok: true };
    }
    case "disconnect":
        if (session.tabs.has(message.tabID)) discardSnapshot(message.tabID);
        session.disconnect(message.tabID);
        closeIfUnused();
        return { ok: true };
    case "disconnectAll":
        for (const tabID of session.tabs.keys()) {
            discardSnapshot(tabID);
            session.disconnect(tabID);
        }
        closeIfUnused();
        return { ok: true };
    case "approve": {
        if (!isRequestID(message.id)) throw new Error("Invalid action review.");
        const request = session.pending.get(message.id)?.request;
        if (request?.method === "openTabs") {
            await normalWindow(message.windowID);
            if (!await chrome.permissions.contains({ permissions: ["tabGroups"] })) {
                throw new Error("Chrome needs permission to create a named tab group.");
            }
        }
        await session.approve(message.id, message.windowID);
        return { ok: true };
    }
    case "deny":
        session.deny(message.id);
        return { ok: true };
    default:
        throw new Error("This extension action is unavailable.");
    }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL("popup.html") || sender.tab) return false;
    popupMessage(message).then(sendResponse, error => sendResponse({ ok: false, error: String(error.message).slice(0, 400) }));
    return true;
});

chrome.tabs.onRemoved.addListener(tabID => {
    if (!session.tabs.has(tabID)) return;
    session.disconnect(tabID, "The connected tab was closed.");
    closeIfUnused();
});

chrome.tabs.onUpdated.addListener((tabID, change, tab) => {
    if (!session.tabs.has(tabID)) return;
    if (change.status === "loading" || change.url) session.invalidate(tabID);
    if (change.url || change.title || change.status === "complete") session.update(tab);
    closeIfUnused();
});

// An extension update or worker restart never restores a prior page connection.
publishState();
