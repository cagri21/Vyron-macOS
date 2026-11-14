import assert from "node:assert/strict";
import test from "node:test";

function event() {
    const listeners = [];
    return { addListener: callback => listeners.push(callback), emit: (...args) => listeners.map(callback => callback(...args)) };
}

const id = number => "a11d4524-885b-4884-bd56-" + String(number).padStart(12, "0");
const snapshotID = "73b9b93a-ff2a-4dfb-a914-85f7b925f0d2";
const tick = () => new Promise(resolve => setImmediate(resolve));

test("worker connects only trusted popup tabs and routes snapshot, reviewed action, cancellation, and disconnect", async (t) => {
    const previous = Object.getOwnPropertyDescriptor(globalThis, "chrome");
    const schedule = globalThis.setTimeout;
    const unschedule = globalThis.clearTimeout;
    // Chromium rejects timer calls with a BridgeSession receiver. Node's timers accept it.
    t.mock.method(globalThis, "setTimeout", function (callback, delay) {
        if (this !== globalThis) throw new TypeError("Illegal invocation");
        return schedule(callback, delay).unref();
    });
    t.mock.method(globalThis, "clearTimeout", function (timer) {
        if (this !== globalThis) throw new TypeError("Illegal invocation");
        unschedule(timer);
    });
    const onMessage = event();
    const nativeMessage = event();
    const nativeDisconnect = event();
    const outbound = [];
    const scripts = [];
    const port = {
        onMessage: nativeMessage, onDisconnect: nativeDisconnect,
        postMessage: message => outbound.push(message), disconnect: () => nativeDisconnect.emit()
    };
    const popupURL = "chrome-extension://abcdefghijklmnopabcdefghijklmnop/popup.html";
    const api = {
        action: { setBadgeText() {}, setBadgeBackgroundColor() {}, setTitle() {} },
        runtime: { id: "abcdefghijklmnopabcdefghijklmnop", onMessage,
            getURL: () => popupURL,
            connectNative: name => { assert.equal(name, "ai.vyron.chrome"); return port; } },
        tabs: {
            query: async () => [{ id: 7, title: "Example", url: "https://example.com/", incognito: false }],
            get: async () => ({ id: 7, title: "Example", url: "https://example.com/", incognito: false }),
            onRemoved: event(), onUpdated: event()
        },
        scripting: { executeScript: async options => {
            scripts.push(options);
            assert.deepEqual(options.target, { tabId: 7, frameIds: [0] });
            assert.equal(options.world, "ISOLATED");
            return [{ frameId: 0, result: options.func.name === "readPageSnapshot"
                ? { snapshotID, capturedAt: Date.now(), text: "Example page", elements: [{ id: 1, role: "button", label: "Find", actions: ["click"] }] }
                : { status: "sent" } }];
        } }
    };
    Object.defineProperty(globalThis, "chrome", { configurable: true, value: api });
    const sender = { id: api.runtime.id, url: popupURL };
    const popup = message => new Promise(resolve => onMessage.emit(message, sender, resolve));
    const request = (number, method, args) => ({ version: 1, id: id(number), method, arguments: args, expiresAt: Date.now() + 29_000 });
    try {
        await import("../worker.js?worker-lifecycle-test");
        assert.deepEqual(onMessage.emit({ type: "connect", tabID: 7 }, { id: api.runtime.id, url: "https://example.com", tab: { id: 7 } }, () => {
            assert.fail("A website sender must not get extension control.");
        }), [false]);
        assert.equal((await popup({ type: "connect", tabID: 7 })).ok, true);
        assert.equal(outbound[0].type, "hello");
        nativeMessage.emit(request(1, "snapshot", { tabID: 7 })); await tick();
        assert.equal(outbound.find(item => item.id === id(1)).ok, true);
        nativeMessage.emit(request(2, "click", { tabID: 7, snapshotID, elementID: 1 })); await tick();
        assert.equal(scripts.length, 1);
        assert.equal(outbound.find(item => item.id === id(2)), undefined);
        const status = await popup({ type: "status" });
        assert.equal(status.pending[0].targetLabel, "Find");
        assert.equal((await popup({ type: "approve", id: id(2) })).ok, true);
        assert.equal(scripts.length, 2);
        assert.equal(scripts.at(-1).func.name, "actOnPage");
        assert.equal(outbound.find(item => item.id === id(2)).ok, true);
        nativeMessage.emit(request(3, "snapshot", { tabID: 7 })); await tick();
        nativeMessage.emit(request(4, "click", { tabID: 7, snapshotID, elementID: 1 })); await tick();
        nativeMessage.emit({ version: 1, type: "cancel", id: id(4) }); await tick();
        assert.equal((await popup({ type: "status" })).pending.length, 0);
        assert.equal((await popup({ type: "approve", id: id(4) })).ok, false);
        assert.equal(scripts.length, 3);
        nativeDisconnect.emit();
        const ended = await popup({ type: "status" });
        assert.equal(ended.connected, false);
        assert.equal(ended.tabs.length, 0);
    } finally {
        await popup({ type: "disconnectAll" });
        if (previous) Object.defineProperty(globalThis, "chrome", previous);
        else delete globalThis.chrome;
    }
});
