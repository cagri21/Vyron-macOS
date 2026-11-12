import assert from "node:assert/strict";
import test from "node:test";
import { BridgeSession } from "../session.js";

const snapshotID = "73b9b93a-ff2a-4dfb-a914-85f7b925f0d2";
const id = number => "e01d4524-885b-4884-bd56-" + String(number).padStart(12, "0");

function fixture(executeOverride) {
    let now = 1_000_000;
    const responses = [];
    const commands = [];
    const timers = new Set();
    const session = new BridgeSession({
        execute: async (request, tab) => {
            commands.push(request);
            if (executeOverride) return executeOverride(request, tab);
            if (request.method === "snapshot") return { snapshotID, capturedAt: now,
                elements: [{ id: 1, label: "Search", role: "textbox", actions: ["fill"] },
                    { id: 2, label: "Find", role: "button", actions: ["click"] }] };
            return { action: request.method };
        },
        respond: value => responses.push(value),
        now: () => now,
        schedule: callback => { timers.add(callback); return callback; },
        unschedule: callback => timers.delete(callback)
    });
    const request = (method, args = {}, number = commands.length + responses.length + session.pending.size + 1) => ({
        version: 1, id: id(number), method, arguments: args, expiresAt: now + 30_000
    });
    const connect = () => session.connect({ id: 7, url: "https://example.com/", title: "Example" });
    const read = async () => { await session.receive(request("snapshot", { tabID: 7 }, 100)); responses.length = 0; commands.length = 0; };
    return { session, request, connect, read, responses, commands, timers, advance: duration => { now += duration; } };
}

test("only a normal explicitly connected tab can be read", async () => {
    const f = fixture();
    await f.session.receive(f.request("snapshot", { tabID: 7 }));
    assert.equal(f.commands.length, 0);
    assert.match(f.responses[0].error, /Connect this tab/);
    assert.throws(() => f.session.connect({ id: 7, incognito: true, url: "https://example.com" }));
    assert.throws(() => f.session.connect({ id: 7, url: "chrome://settings" }));
    f.connect();
    await f.read();
    assert.equal(f.session.snapshots.get(7).snapshotID, snapshotID);
});

test("page mutations wait for review and one approval runs once", async () => {
    const f = fixture(); f.connect(); await f.read();
    const request = f.request("click", { tabID: 7, snapshotID, elementID: 2 });
    await f.session.receive(request);
    assert.equal(f.commands.length, 0);
    assert.equal(f.responses.length, 0);
    assert.equal(f.session.view().pending[0].targetLabel, "Find");
    await f.session.approve(request.id);
    assert.equal(f.commands.length, 1);
    assert.equal(f.responses[0].ok, true);
    assert.equal(f.session.snapshots.has(7), false);
    await assert.rejects(f.session.approve(request.id));
    assert.equal(f.commands.length, 1);
});

test("decline and native cancellation prevent later approval, including reordered frames", async () => {
    const f = fixture(); f.connect(); await f.read();
    const request = f.request("fill", { tabID: 7, snapshotID, elementID: 1, text: "query" });
    await f.session.receive(request);
    f.session.deny(request.id);
    await assert.rejects(f.session.approve(request.id));
    assert.equal(f.commands.length, 0);
    const cancelled = f.request("click", { tabID: 7, snapshotID, elementID: 2 }, 9);
    f.session.cancel(cancelled.id);
    await f.session.receive(cancelled);
    assert.equal(f.session.pending.size, 0);
    assert.equal(f.commands.length, 0);
    assert.match(f.responses.at(-1).error, /cancelled/);
});

test("cancelled pending action and duplicate request never replay a side effect", async () => {
    const f = fixture(); f.connect(); await f.read();
    const request = f.request("click", { tabID: 7, snapshotID, elementID: 2 });
    await f.session.receive(request);
    await f.session.receive(request);
    assert.equal(f.session.pending.size, 0);
    await assert.rejects(f.session.approve(request.id));
    assert.equal(f.commands.length, 0);
    assert.equal(f.timers.size, 0);
});

test("page changes invalidate snapshots and waiting reviews", async () => {
    const f = fixture(); f.connect(); await f.read();
    const request = f.request("click", { tabID: 7, snapshotID, elementID: 2 });
    await f.session.receive(request);
    f.session.invalidate(7);
    assert.equal(f.session.pending.size, 0);
    assert.equal(f.session.snapshots.size, 0);
    await assert.rejects(f.session.approve(request.id));
    assert.equal(f.commands.length, 0);
    f.session.update({ id: 7, url: "https://different.example/" });
    assert.equal(f.session.tabs.size, 0);
});

test("expired request, stale snapshot, and unsupported target action fail before execution", async () => {
    const f = fixture(); f.connect(); await f.read();
    await f.session.receive(f.request("fill", { tabID: 7, snapshotID, elementID: 2, text: "no" }));
    assert.equal(f.session.pending.size, 0);
    const waiting = f.request("click", { tabID: 7, snapshotID, elementID: 2 }, 3);
    await f.session.receive(waiting);
    f.advance(30_000);
    await f.session.approve(waiting.id);
    assert.equal(f.commands.length, 0);
    assert.equal(f.responses.at(-1).ok, false);
});

test("timer expiry removes pending review and sends a clear failure", async () => {
    const f = fixture(); f.connect(); await f.read();
    const waiting = f.request("reload", { tabID: 7, snapshotID });
    await f.session.receive(waiting);
    f.advance(30_000);
    for (const timer of [...f.timers]) timer();
    assert.equal(f.session.pending.size, 0);
    assert.equal(f.commands.length, 0);
    assert.match(f.responses.at(-1).error, /expired/);
});

test("navigation and reload require fresh snapshots and cross-origin navigation is refused", async () => {
    const f = fixture(); f.connect(); await f.read();
    const waiting = f.request("navigate", { tabID: 7, snapshotID, url: "https://other.example/" });
    await f.session.receive(waiting);
    await f.session.approve(waiting.id);
    assert.equal(f.commands.length, 0);
    assert.match(f.responses.at(-1).error, /another website/);
});

test("disconnect during a read suppresses its page result", async () => {
    let complete;
    const f = fixture(() => new Promise(resolve => { complete = resolve; })); f.connect();
    const reading = f.session.receive(f.request("snapshot", { tabID: 7 }));
    f.session.disconnectAll();
    complete({ snapshotID, capturedAt: 1_000_000, elements: [], text: "private page content" });
    await reading;
    assert.equal(f.responses.at(-1).ok, false);
    assert.equal(JSON.stringify(f.responses).includes("private page content"), false);
    assert.equal(f.session.snapshots.size, 0);
});

test("same-tab navigation during an in-flight read cannot cache the old document", async () => {
    let complete;
    const f = fixture(() => new Promise(resolve => { complete = resolve; })); f.connect();
    const reading = f.session.receive(f.request("snapshot", { tabID: 7 }));
    f.session.invalidate(7);
    f.session.update({ id: 7, url: "https://example.com/new" });
    complete({ snapshotID, capturedAt: 1_000_000, elements: [], text: "stale page" });
    await reading;
    assert.equal(f.responses.at(-1).ok, false);
    assert.equal(f.session.snapshots.size, 0);
});
