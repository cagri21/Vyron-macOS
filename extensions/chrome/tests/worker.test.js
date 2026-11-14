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
        nativeMessage.emit(request(25, "openTabs", groupRequest)); await tick();
        assert.match(outbound.find(item => item.id === id(25)).error, /Connect for opening tabs/);
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

let groupWorkerCount = 0;

async function withGroupWorker(run) {
    const previous = Object.getOwnPropertyDescriptor(globalThis, "chrome");
    const onMessage = event();
    const nativeMessage = event();
    const nativeDisconnect = event();
    const outbound = [];
    const operations = [];
    const controls = { permission: true };
    const port = {
        onMessage: nativeMessage, onDisconnect: nativeDisconnect,
        postMessage: message => outbound.push(message), disconnect: () => nativeDisconnect.emit()
    };
    const extensionID = "abcdefghijklmnopabcdefghijklmnop";
    const popupURL = `chrome-extension://${extensionID}/popup.html`;
    const api = {
        action: { setBadgeText() {}, setBadgeBackgroundColor() {}, setTitle() {} },
        runtime: { id: extensionID, onMessage, getURL: () => popupURL, connectNative: () => port },
        permissions: { contains: async permissions => {
            assert.deepEqual(permissions, { permissions: ["tabGroups"] });
            return controls.permission;
        } },
        windows: { get: async id => ({ id, type: "normal", incognito: id === 8 }) },
        tabs: {
            query: async () => [{ id: 7, title: "Example", url: "https://example.com/", incognito: false }],
            create: async options => {
                const tabID = (controls.lastTabID ?? 50) + 1;
                controls.lastTabID = tabID;
                operations.push(["create", options]);
                await controls.beforeCreateReturns?.();
                return { id: tabID };
            },
            group: async options => { operations.push(["group", options]); return 90; },
            remove: async tabID => operations.push(["remove", tabID]),
            onRemoved: event(), onUpdated: event()
        },
        tabGroups: { update: async (groupID, options) => {
            operations.push(["update", groupID, options]);
            if (controls.titleError) throw new Error("Chrome rejected the group title.");
        } },
        scripting: { executeScript: async () => [] }
    };
    Object.defineProperty(globalThis, "chrome", { configurable: true, value: api });
    const popup = message => new Promise(resolve => onMessage.emit(message, { id: extensionID, url: popupURL }, resolve));
    const request = (number, method, args) => {
        nativeMessage.emit({ version: 1, id: id(number), method, arguments: args, expiresAt: Date.now() + 29_000 });
        return tick();
    };
    try {
        await import(`../worker.js?group-worker=${groupWorkerCount++}`);
        await run({ popup, request, controls, operations, outbound, api, nativeMessage });
    } finally {
        await popup({ type: "disconnectBrowser" });
        await popup({ type: "disconnectAll" });
        if (previous) Object.defineProperty(globalThis, "chrome", previous);
        else delete globalThis.chrome;
    }
}

const groupRequest = { groupTitle: "Trip planning", urls: ["https://example.com", "https://example.org/guide"] };

test("browser connection reviews and opens exactly one group without connecting the new pages", async () => {
    await withGroupWorker(async ({ popup, request, controls, operations, outbound, api }) => {
        assert.equal((await popup({ type: "connectBrowser", windowID: 8 })).ok, false);
        controls.permission = false;
        assert.equal((await popup({ type: "connectBrowser", windowID: 7 })).ok, false);
        controls.permission = true;
        assert.equal((await popup({ type: "connectBrowser", windowID: 7 })).ok, true);
        api.tabs.onRemoved.emit(42);
        await request(1, "openTabs", groupRequest);
        const review = await popup({ type: "status" });
        assert.equal(review.browserConnected, true);
        assert.deepEqual(review.pending[0].arguments, {
            groupTitle: "Trip planning", urls: ["https://example.com/", "https://example.org/guide"]
        });
        assert.equal((await popup({ type: "approve", id: id(1), windowID: 8 })).ok, false);
        controls.permission = false;
        assert.equal((await popup({ type: "approve", id: id(1), windowID: 7 })).ok, false);
        assert.deepEqual(operations, []);
        await popup({ type: "deny", id: id(1) });
        assert.match(outbound.find(item => item.id === id(1)).error, /declined/);

        controls.permission = true;
        await request(2, "openTabs", groupRequest);
        assert.equal((await popup({ type: "approve", id: id(2), windowID: 7 })).ok, true);
        assert.deepEqual(operations, [
            ["create", { windowId: 7, active: false, url: "https://example.com/" }],
            ["create", { windowId: 7, active: false, url: "https://example.org/guide" }],
            ["group", { tabIds: [51, 52], createProperties: { windowId: 7 } }],
            ["update", 90, { title: "Trip planning" }]
        ]);
        assert.deepEqual(outbound.find(item => item.id === id(2)).result, { groupID: 90, groupTitle: "Trip planning", tabCount: 2 });
        assert.equal((await popup({ type: "approve", id: id(2), windowID: 7 })).ok, false);
        await request(3, "tabs", {});
        assert.deepEqual(outbound.find(item => item.id === id(3)).result, { tabs: [] });

        await popup({ type: "connect", tabID: 7 });
        await request(4, "openTabs", groupRequest);
        await popup({ type: "disconnectBrowser" });
        const disconnected = await popup({ type: "status" });
        assert.equal(disconnected.browserConnected, false);
        assert.equal(disconnected.connected, true);
        assert.equal(disconnected.tabs.length, 1);
        assert.deepEqual(disconnected.pending, []);
        assert.match(outbound.find(item => item.id === id(4)).error, /disconnected before approval/);
        assert.equal((await popup({ type: "approve", id: id(4), windowID: 7 })).ok, false);
    });
});

test("failed group naming and cancellation roll back only tabs opened by the request", async () => {
    await withGroupWorker(async ({ popup, request, controls, operations, outbound, nativeMessage }) => {
        await popup({ type: "connectBrowser", windowID: 7 });
        controls.titleError = true;
        await request(1, "openTabs", groupRequest);
        await popup({ type: "approve", id: id(1), windowID: 7 });
        assert.match(outbound.find(item => item.id === id(1)).error, /rejected the group title/);
        assert.deepEqual(operations.slice(-2), [["remove", 51], ["remove", 52]]);

        operations.length = 0;
        let finishCreate;
        controls.beforeCreateReturns = () => new Promise(resolve => { finishCreate = resolve; });
        await request(2, "openTabs", groupRequest);
        const approval = popup({ type: "approve", id: id(2), windowID: 7 });
        await tick();
        await request(3, "openTabs", groupRequest);
        await popup({ type: "approve", id: id(3), windowID: 7 });
        assert.match(outbound.find(item => item.id === id(3)).error, /wait for the approved browser action/i);
        nativeMessage.emit({ version: 1, type: "cancel", id: id(2) });
        finishCreate();
        await approval;
        assert.deepEqual(operations, [
            ["create", { windowId: 7, active: false, url: "https://example.com/" }], ["remove", 53]
        ]);
        assert.match(outbound.find(item => item.id === id(2)).error, /cancelled/);
    });
});
