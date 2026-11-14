export const PROTOCOL_VERSION = 1;
export const REQUEST_LIFETIME_MS = 30_000;
export const RESPONSE_LIMIT_BYTES = 480 * 1_024;
export const PAGE_MUTATIONS = new Set(["click", "fill", "navigate", "reload"]);
export const MUTATING_METHODS = new Set([...PAGE_MUTATIONS, "openTabs"]);

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const requiredArguments = {
    tabs: [],
    openTabs: ["urls", "groupTitle"],
    snapshot: ["tabID"],
    click: ["tabID", "snapshotID", "elementID"],
    fill: ["tabID", "snapshotID", "elementID", "text"],
    navigate: ["tabID", "snapshotID", "url"],
    reload: ["tabID", "snapshotID"]
};

export function isRequestID(value) {
    return typeof value === "string" && uuid.test(value);
}

export function normalPageURL(value) {
    if (typeof value !== "string" || value.length > 8_192) throw new Error("A normal HTTP or HTTPS page is required.");
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password) {
        throw new Error("A normal HTTP or HTTPS page is required.");
    }
    return url;
}

export function sameOriginURL(value, origin) {
    const url = normalPageURL(value);
    if (url.origin !== origin) throw new Error("Connect the destination tab in Chrome before using another website.");
    return url;
}

function openTabsArguments({ urls, groupTitle }) {
    const encoder = new TextEncoder();
    if (!Array.isArray(urls) || urls.length < 1 || urls.length > 8) {
        throw new Error("Choose between one and eight URLs to open.");
    }
    if (typeof groupTitle !== "string" || !groupTitle || groupTitle !== groupTitle.trim()
        || /[\p{Cc}\p{Cf}]/u.test(groupTitle) || encoder.encode(groupTitle).length > 80) {
        throw new Error("Enter a group name of up to 80 bytes, without surrounding spaces or control characters.");
    }
    const destinations = urls.map(url => {
        if (typeof url !== "string" || !/^https?:\/\/[^/]/i.test(url) || /[\p{White_Space}\p{Cc}\p{Cf}\\]/u.test(url)
            || encoder.encode(url).length > 8_192) {
            throw new Error("Each tab needs a normal HTTP or HTTPS URL of up to 8,192 bytes.");
        }
        return normalPageURL(url).href;
    });
    return { urls: destinations, groupTitle };
}

export function validateRequest(value, now = Date.now()) {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid request.");
    if (Object.keys(value).some(key => !["version", "id", "method", "arguments", "expiresAt"].includes(key))) {
        throw new Error("Unexpected request fields.");
    }
    if (value.version !== PROTOCOL_VERSION || !isRequestID(value.id)) throw new Error("Unsupported request format.");
    if (!Number.isFinite(value.expiresAt) || value.expiresAt <= now || value.expiresAt > now + REQUEST_LIFETIME_MS) {
        throw new Error("Request expired or exceeds the 30 second review window.");
    }
    if (!Object.hasOwn(requiredArguments, value.method)) throw new Error("This browser command is unavailable.");
    const args = value.arguments ?? {};
    if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("Invalid command arguments.");
    const keys = Object.keys(args);
    const expected = requiredArguments[value.method];
    if (keys.length !== expected.length || keys.some(key => !expected.includes(key))) {
        throw new Error("Unexpected or missing command arguments.");
    }
    if (expected.includes("tabID") && (!Number.isSafeInteger(args.tabID) || args.tabID < 0)) {
        throw new Error("A connected tab is required.");
    }
    if ("snapshotID" in args && !isRequestID(args.snapshotID)) throw new Error("A fresh page snapshot is required.");
    if ("elementID" in args && (!Number.isSafeInteger(args.elementID) || args.elementID < 1 || args.elementID > 200)) {
        throw new Error("The target element is invalid.");
    }
    if ("text" in args && (typeof args.text !== "string" || args.text.includes("\0")
        || new TextEncoder().encode(args.text).length > 8_000)) throw new Error("Text must fit within 8,000 bytes.");
    if ("url" in args) normalPageURL(args.url);
    const normalized = value.method === "openTabs" ? openTabsArguments(args) : { ...args };
    return { version: PROTOCOL_VERSION, id: value.id, method: value.method, arguments: normalized, expiresAt: value.expiresAt };
}

export function successResponse(id, result) {
    const message = { version: PROTOCOL_VERSION, id, ok: true, result };
    if (new TextEncoder().encode(JSON.stringify(message)).length > RESPONSE_LIMIT_BYTES) {
        throw new Error("The page snapshot exceeds the response limit.");
    }
    return message;
}

export function errorResponse(id, error) {
    return { version: PROTOCOL_VERSION, id, ok: false, error: String(error?.message ?? error).slice(0, 400) };
}
