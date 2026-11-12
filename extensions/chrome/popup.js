import { normalPageURL } from "./protocol.js";

const elements = Object.fromEntries(["page-title", "page-origin", "connect", "error", "reviews", "review-list", "connections",
    "connection-list", "disconnect-all", "status"].map(id => [id, document.getElementById(id)]));
let activeTab = null;
let lastView = "";
let busy = false;

function showError(message) {
    elements.error.textContent = message ?? "";
    elements.error.hidden = !message;
}

async function send(message) {
    const result = await chrome.runtime.sendMessage(message);
    if (!result?.ok) throw new Error(result?.error ?? "The extension did not respond. Close and reopen this popup.");
    return result;
}

async function perform(message) {
    if (busy) return;
    busy = true;
    showError(null);
    try { await send(message); }
    catch (error) { showError(error.message); }
    finally { busy = false; await refresh(); }
}

function node(tag, className, text) {
    const value = document.createElement(tag);
    if (className) value.className = className;
    if (text !== undefined) value.textContent = text;
    return value;
}

function actionTitle(method) {
    return { click: "Click a page control", fill: "Enter text in a field", navigate: "Open a page on this website", reload: "Reload this page" }[method]
        ?? "Browser action";
}

function render(view) {
    const connected = view.tabs.some(tab => tab.id === activeTab?.id);
    elements.connect.textContent = connected ? "This tab is connected" : "Connect this tab";
    elements.connect.disabled = !activeTab || connected || busy;
    elements.connections.hidden = !view.tabs.length;
    elements.reviews.hidden = !view.pending.length;
    elements.status.textContent = view.connected && view.tabs.length
        ? `${view.tabs.length} ${view.tabs.length === 1 ? "tab connected" : "tabs connected"} · Vyron can request page snapshots`
        : "Disconnected";
    if (view.lastError) showError(view.lastError);
    const identity = JSON.stringify([view.tabs, view.pending]);
    if (identity === lastView) return;
    lastView = identity;
    elements["connection-list"].replaceChildren(...view.tabs.map(tab => {
        const row = node("div", "connected-tab");
        const labels = node("div");
        labels.append(node("p", "", tab.title || "Untitled page"), node("p", "muted", tab.origin));
        const button = node("button", "secondary", "Disconnect");
        button.setAttribute("aria-label", "Disconnect " + (tab.title || tab.origin));
        button.addEventListener("click", () => void perform({ type: "disconnect", tabID: tab.id }));
        row.append(labels, button);
        return row;
    }));
    elements["review-list"].replaceChildren(...view.pending.map(item => {
        const card = node("article", "review");
        const tab = view.tabs.find(value => value.id === item.arguments.tabID);
        card.append(node("h3", "", actionTitle(item.method)), node("p", "muted", tab?.title || "Connected tab"));
        if (item.arguments.elementID) {
            card.append(node("p", "", item.targetLabel || "Page control #" + item.arguments.elementID));
            card.append(node("p", "muted", (item.targetRole || "Control") + " · #" + item.arguments.elementID));
        }
        if (item.arguments.text !== undefined) card.append(node("pre", "", item.arguments.text));
        if (item.targetURL) card.append(node("pre", "", item.targetURL));
        if (item.arguments.url) card.append(node("pre", "", item.arguments.url));
        const timing = node("p", "muted", "This request expires in at most 30 seconds.");
        const buttons = node("div", "review-actions");
        const decline = node("button", "secondary", "Decline");
        const approve = node("button", "primary", "Approve once");
        decline.addEventListener("click", () => void perform({ type: "deny", id: item.id }));
        approve.addEventListener("click", () => void perform({ type: "approve", id: item.id }));
        buttons.append(decline, approve);
        card.append(timing, buttons);
        return card;
    }));
}

async function refresh() {
    try { render(await send({ type: "status" })); }
    catch (error) { showError(error.message); }
}

elements.connect.addEventListener("click", () => void perform({ type: "connect", tabID: activeTab?.id }));
elements["disconnect-all"].addEventListener("click", () => void perform({ type: "disconnectAll" }));

try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || tab.incognito || !Number.isSafeInteger(tab.id) || tab.pendingUrl) throw new Error("Choose a loaded regular website tab.");
    const url = normalPageURL(tab.url);
    activeTab = tab;
    elements["page-title"].textContent = tab.title || "Untitled page";
    elements["page-origin"].textContent = url.origin;
} catch (error) {
    elements["page-title"].textContent = "This page cannot connect";
    elements["page-origin"].textContent = "Open a normal HTTP or HTTPS website outside Incognito mode.";
}
await refresh();
const refreshTimer = setInterval(() => void refresh(), 500);
window.addEventListener("pagehide", () => clearInterval(refreshTimer), { once: true });
