import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";
import { actOnPage, clearPageSnapshot, consumeNavigationSnapshot, readPageSnapshot } from "../dom.js";

const stateKey = "__vyronChromeBridgeSnapshotV1";

class FakeElement {
    constructor(tag, options = {}) {
        this.tagName = tag.toUpperCase();
        this.attrs = { ...options.attrs };
        this.textNodes = options.text ? [{ textContent: options.text, parentElement: this }] : [];
        this.textContent = options.text ?? "";
        this.isConnected = true;
        this.disabled = false;
        this.visible = true;
        this.events = [];
    }
    getAttribute(name) { return this.attrs[name] ?? null; }
    matches() { return ["INPUT", "TEXTAREA", "SCRIPT", "STYLE", "OPTION", "SELECT"].includes(this.tagName) || this.attrs.contenteditable === "true"; }
    closest(selector) {
        if (selector.includes("contenteditable") && this.attrs.contenteditable === "true") return this;
        if (selector.startsWith("script,") && this.matches()) return this;
        if (selector.startsWith("[hidden]") && this.attrs.hidden) return this;
        return null;
    }
    getClientRects() { return this.visible ? [{ width: 100, height: 30 }] : []; }
    click() { this.clicked = (this.clicked ?? 0) + 1; }
    dispatchEvent(event) { this.events.push(event.type); }
}

class FakeInput extends FakeElement {
    constructor(type, name, options = {}) {
        super("input", options);
        this.type = type;
        this.name = name;
        this.id = name;
        this.autocomplete = "";
        this.labels = [];
        this.readOnly = false;
    }
    get value() { throw new Error("A snapshot must never read a field value."); }
    set value(value) { this.writtenValue = value; }
}

class FakeTextArea extends FakeElement {
    constructor() { super("textarea"); this.name = "notes"; this.type = "textarea"; this.labels = []; }
    get value() { throw new Error("A snapshot must never read a textarea value."); }
    set value(value) { this.writtenValue = value; }
}

class FakeAnchor extends FakeElement {
    constructor(href, text) { super("a", { text }); this.href = href; }
}

function page() {
    const button = new FakeElement("button", { text: "Find results" });
    const field = new FakeInput("search", "query", { attrs: { "aria-label": "Search" } });
    const password = new FakeInput("password", "password");
    const creditCard = new FakeInput("text", "cc-number");
    const email = new FakeInput("email", "email");
    const file = new FakeInput("file", "attachment");
    const editable = new FakeElement("div", { text: "Private editor text", attrs: { contenteditable: "true" } });
    const hidden = new FakeElement("button", { text: "Hidden content" }); hidden.visible = false;
    const anchor = new FakeAnchor("https://example.com/next", "Next page");
    const body = new FakeElement("body", { text: "Public article" });
    const candidates = [button, field, password, creditCard, email, file, editable, hidden, anchor];
    body.textNodes.push(...candidates.flatMap(item => item.textNodes));
    const document = {
        body, title: "Example page",
        querySelectorAll: () => candidates,
        getElementById: () => null,
        createTreeWalker(element) {
            let index = -1;
            return { currentNode: null, nextNode() { index += 1; this.currentNode = element.textNodes[index]; return Boolean(this.currentNode); } };
        }
    };
    for (const element of [body, ...candidates]) element.ownerDocument = document;
    const globals = { document, location: { href: "https://example.com/", origin: "https://example.com", protocol: "https:" },
        Element: FakeElement, HTMLElement: FakeElement, HTMLInputElement: FakeInput, HTMLTextAreaElement: FakeTextArea,
        HTMLAnchorElement: FakeAnchor, NodeFilter: { SHOW_TEXT: 4 },
        getComputedStyle: element => ({ display: element.visible ? "block" : "none", visibility: "visible", opacity: "1" }) };
    const previous = Object.fromEntries(Object.keys(globals).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    for (const [key, value] of Object.entries(globals)) Object.defineProperty(globalThis, key, { configurable: true, writable: true, value });
    if (!globalThis.crypto) Object.defineProperty(globalThis, "crypto", { configurable: true, value: webcrypto });
    const context = { tabID: 7, origin: "https://example.com", expiresAt: Date.now() + 30_000 };
    return { button, field, password, anchor, context, restore() {
        clearTimeout(globalThis[stateKey]?.expiryTimer);
        delete globalThis[stateKey];
        for (const key of Object.keys(globals)) {
            if (previous[key]) Object.defineProperty(globalThis, key, previous[key]);
            else delete globalThis[key];
        }
    } };
}

test("snapshot omits secure fields, field values, hidden content, and editors", () => {
    const p = page();
    try {
        const snapshot = readPageSnapshot(p.context);
        assert.equal(snapshot.text, "Public article\nFind results\nNext page\n");
        assert.deepEqual(snapshot.elements.map(item => item.label), ["Find results", "Search", "Next page"]);
        assert.deepEqual(snapshot.elements.map(item => item.actions), [["click"], ["fill"], ["click"]]);
        assert.equal(snapshot.elements[2].url, "https://example.com/next");
        assert.equal(JSON.stringify(snapshot).includes("password"), false);
    } finally { p.restore(); }
});

test("fill uses the native setter and consumes its snapshot once", () => {
    const p = page();
    try {
        const snapshot = readPageSnapshot(p.context);
        const context = { ...p.context, method: "fill", snapshotID: snapshot.snapshotID, elementID: 2, text: "new query" };
        assert.equal(actOnPage(context).status, "sent");
        assert.equal(p.field.writtenValue, "new query");
        assert.deepEqual(p.field.events, ["input", "change"]);
        assert.throws(() => actOnPage(context), /snapshot expired or changed/);
    } finally { p.restore(); }
});

test("changed labels, detached elements, and stale snapshots cannot be clicked", () => {
    for (const change of [
        p => { p.button.isConnected = false; },
        p => { p.button.attrs["aria-label"] = "Delete account"; },
        () => { globalThis[stateKey].capturedAt -= 30_001; },
        () => { globalThis.location.href = "https://example.com/other"; }
    ]) {
        const p = page();
        try {
            const snapshot = readPageSnapshot(p.context);
            change(p);
            assert.throws(() => actOnPage({ ...p.context, method: "click", snapshotID: snapshot.snapshotID, elementID: 1 }));
            assert.equal(p.button.clicked, undefined);
        } finally { p.restore(); }
    }
});

test("a link changed beyond the displayed URL limit is rejected as stale", () => {
    const p = page();
    try {
        const prefix = "https://example.com/next?padding=" + "a".repeat(1_100);
        p.anchor.href = prefix + "&action=view";
        const snapshot = readPageSnapshot(p.context);
        const target = snapshot.elements.find(item => item.role === "link");
        assert.equal(target.url.length, 1_000);
        p.anchor.href = prefix + "&action=delete";
        assert.equal(p.anchor.href.slice(0, 1_000), target.url);
        assert.throws(() => actOnPage({
            ...p.context, method: "click", snapshotID: snapshot.snapshotID, elementID: target.id
        }), /target changed/);
        assert.equal(p.anchor.clicked, undefined);
    } finally { p.restore(); }
});

test("a field becoming sensitive after snapshot refuses input", () => {
    const p = page();
    try {
        const snapshot = readPageSnapshot(p.context);
        p.field.name = "one-time-password";
        assert.throws(() => actOnPage({ ...p.context, method: "fill", snapshotID: snapshot.snapshotID, elementID: 2, text: "no" }));
        assert.equal(p.field.writtenValue, undefined);
    } finally { p.restore(); }
});

test("navigation snapshot verifies the same document and cannot be reused", () => {
    const p = page();
    try {
        const snapshot = readPageSnapshot(p.context);
        const context = { ...p.context, snapshotID: snapshot.snapshotID };
        assert.equal(consumeNavigationSnapshot(context).url, "https://example.com/");
        assert.throws(() => consumeNavigationSnapshot(context));
    } finally { p.restore(); }
});

test("disconnect cleanup erases isolated-world references without reading page content", () => {
    const p = page();
    try {
        readPageSnapshot(p.context);
        assert.equal(globalThis[stateKey].references.size, 3);
        clearPageSnapshot();
        assert.equal(globalThis[stateKey], undefined);
    } finally { p.restore(); }
});
