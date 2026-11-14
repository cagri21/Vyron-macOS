import assert from "node:assert/strict";
import test from "node:test";
import { normalPageURL, sameOriginURL, successResponse, validateRequest } from "../protocol.js";

const id = "e01d4524-885b-4884-bd56-2ab134fdbe03";
const snapshotID = "73b9b93a-ff2a-4dfb-a914-85f7b925f0d2";
const now = 1_000_000;
const request = (method, args = {}) => ({ version: 1, id, method, arguments: args, expiresAt: now + 30_000 });

test("accepts only bounded, known requests and exact argument keys", () => {
    assert.equal(validateRequest(request("tabs"), now).method, "tabs");
    assert.equal(validateRequest(request("fill", { tabID: 12, snapshotID, elementID: 2, text: "Search" }), now).arguments.text, "Search");
    for (const value of [
        { ...request("tabs"), version: 2 }, { ...request("tabs"), id: "../../private" },
        { ...request("tabs"), expiresAt: now }, { ...request("tabs"), expiresAt: now + 30_001 },
        { ...request("tabs"), extra: true }, request("eval", { text: "anything" }), request("constructor"),
        request("snapshot", { tabID: -1 }), request("snapshot", { tabID: 1, url: "https://example.com" }),
        request("click", { tabID: 1, snapshotID, elementID: 201 }),
        request("navigate", { tabID: 1, url: "https://example.com" }), request("reload", { tabID: 1 }),
        request("fill", { tabID: 1, snapshotID, elementID: 1, text: "é".repeat(4_001) }),
        request("fill", { tabID: 1, snapshotID, elementID: 1, text: "abc\0def" })
    ]) assert.throws(() => validateRequest(value, now));
});

test("navigation accepts only credential-free normal pages on the connected origin", () => {
    assert.equal(sameOriginURL("https://example.com/path", "https://example.com").pathname, "/path");
    for (const value of ["chrome://extensions", "file:///tmp/report", "javascript:alert(1)", "https://user:secret@example.com/"]) {
        assert.throws(() => normalPageURL(value));
    }
    for (const value of ["https://different.example/path", "http://example.com", "https://example.com:444"]) {
        assert.throws(() => sameOriginURL(value, "https://example.com"));
    }
});

test("tab groups accept only a name and a bounded list of explicit web URLs", () => {
    const args = { urls: ["HTTPS://Example.com", "http://example.org/a#part"], groupTitle: "Trip planning" };
    assert.deepEqual(validateRequest(request("openTabs", args), now).arguments, {
        urls: ["https://example.com/", "http://example.org/a#part"], groupTitle: "Trip planning"
    });
    for (const overrides of [
        { tabID: 12 }, { urls: [] }, { urls: Array(9).fill("https://example.com") },
        { urls: ["https://" + "é".repeat(4094) + ".example"] },
        { urls: ["https://example.com/a b"] }, { urls: ["https://example.com\\path"] },
        { urls: ["https:/example.com"] }, { urls: ["chrome://newtab"] },
        { urls: ["https://user:secret@example.com/"] }, { groupTitle: "" },
        { groupTitle: " name" }, { groupTitle: "name\nline" }, { groupTitle: "a\u202Eb" }, { groupTitle: "é".repeat(41) }
    ]) assert.throws(() => validateRequest(request("openTabs", { ...args, ...overrides }), now));
});

test("native responses are bounded by encoded UTF-8 bytes", () => {
    assert.equal(successResponse(id, { text: "Hello" }).ok, true);
    assert.throws(() => successResponse(id, { text: "é".repeat(450_000) }));
});
