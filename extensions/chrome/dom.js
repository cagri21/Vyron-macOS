// These functions run in Chrome's isolated world. They deliberately have no module closures.
export function readPageSnapshot(context) {
    const stateKey = "__vyronChromeBridgeSnapshotV1";
    const previous = globalThis[stateKey];
    if (previous?.expiryTimer) clearTimeout(previous.expiryTimer);
    delete globalThis[stateKey];
    if (Date.now() >= context.expiresAt) throw new Error("The request expired before the page could be read.");
    if (location.origin !== context.origin || !["http:", "https:"].includes(location.protocol)) {
        throw new Error("The page changed. Connect the current tab again.");
    }
    const omitted = "script,style,noscript,template,input,textarea,select,option,[contenteditable]:not([contenteditable='false'])";
    function visible(element) {
        if (!(element instanceof Element) || element.closest("[hidden],[inert],[aria-hidden='true']")) return false;
        const style = getComputedStyle(element);
        return style.display !== "none" && style.visibility !== "hidden" && style.visibility !== "collapse"
            && Number(style.opacity) !== 0 && [...element.getClientRects()].some(rect => rect.width > 0 && rect.height > 0);
    }
    function compact(text, length = 300) { return String(text ?? "").replace(/\s+/g, " ").trim().slice(0, length); }
    function safeText(element) {
        if (element.matches?.(omitted)) return "";
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        let text = "";
        let visited = 0;
        while (walker.nextNode() && visited++ < 500 && text.length < 1_000) {
            const parent = walker.currentNode.parentElement;
            if (parent && !parent.closest(omitted) && visible(parent)) text += " " + walker.currentNode.textContent;
        }
        return compact(text);
    }
    function sensitive(element) {
        if (!(element instanceof HTMLInputElement) && !(element instanceof HTMLTextAreaElement)) return false;
        const identity = [element.type, element.name, element.id, element.autocomplete, element.getAttribute("aria-label"),
            element.labels ? [...element.labels].map(label => label.textContent).join(" ") : ""].join(" ");
        return /password|passcode|one.?time|\botp\b|credit|\bcc-|card.?number|\bcvc\b|\bcvv\b|\biban\b|routing|token|secret|auth|login|sign.?in|username|email/i.test(identity)
            || ["file", "hidden", "password", "email"].includes(element.type);
    }
    function describe(element) {
        const explicit = element.getAttribute("aria-label") ?? "";
        const labelled = (element.getAttribute("aria-labelledby") ?? "").split(/\s+/).slice(0, 6)
            .map(id => document.getElementById(id)).filter(label => label && visible(label)).map(safeText).join(" ");
        const labels = element.labels ? [...element.labels].map(safeText).join(" ") : "";
        return compact(explicit || labelled || labels || safeText(element) || element.getAttribute("placeholder")
            || element.getAttribute("title") || element.getAttribute("alt") || element.tagName.toLowerCase());
    }
    function role(element) {
        const explicit = element.getAttribute("role");
        if (explicit) return compact(explicit, 60);
        if (element instanceof HTMLAnchorElement) return "link";
        if (element instanceof HTMLTextAreaElement) return "textbox";
        if (element instanceof HTMLInputElement) {
            if (["button", "submit", "reset"].includes(element.type)) return "button";
            return ["checkbox", "radio"].includes(element.type) ? element.type : "textbox";
        }
        return element.tagName.toLowerCase();
    }
    function href(element) {
        if (!(element instanceof HTMLAnchorElement)) return "";
        try {
            const url = new URL(element.href);
            return ["http:", "https:"].includes(url.protocol) && !url.username && !url.password ? url.href : "";
        } catch { return ""; }
    }
    const snapshotID = crypto.randomUUID();
    const capturedAt = Date.now();
    const references = new Map();
    const elements = [];
    const candidates = document.querySelectorAll("a[href],button,input,textarea,[role='button'],[role='link'],[role='textbox']");
    let examined = 0;
    for (const element of candidates) {
        if (elements.length >= 200 || examined++ >= 10_000) break;
        if (!visible(element) || sensitive(element) || element.disabled || element.getAttribute("aria-disabled") === "true"
            || element.closest("[contenteditable]:not([contenteditable='false'])")) continue;
        const actions = [];
        if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
            if (!element.readOnly && (element instanceof HTMLTextAreaElement || ["text", "search", "url", "tel", "number"].includes(element.type))) {
                actions.push("fill");
            }
            if (element instanceof HTMLInputElement && ["button", "submit", "reset", "checkbox", "radio"].includes(element.type)) {
                actions.push("click");
            }
        } else if (element instanceof HTMLElement) {
            actions.push("click");
        }
        if (!actions.length) continue;
        const item = { id: elements.length + 1, role: role(element), label: describe(element), actions };
        const destination = href(element);
        if (destination) item.url = destination.slice(0, 1_000);
        elements.push(item);
        references.set(item.id, { element, role: item.role, label: item.label, href: destination, type: element.type, actions });
    }
    let text = "";
    let visited = 0;
    if (document.body) {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode() && visited++ < 8_000 && text.length < 24_000) {
            const parent = walker.currentNode.parentElement;
            if (parent && !parent.closest(omitted) && visible(parent)) {
                const content = compact(walker.currentNode.textContent, 2_000);
                if (content) text += content + "\n";
            }
        }
    }
    const expiryTimer = setTimeout(() => {
        if (globalThis[stateKey]?.snapshotID === snapshotID) delete globalThis[stateKey];
    }, 30_000);
    globalThis[stateKey] = { snapshotID, capturedAt, references, document, location: location.href, describe, role, href, visible, sensitive, expiryTimer };
    return { tabID: context.tabID, snapshotID, url: location.href.slice(0, 8_192), title: document.title.slice(0, 300),
        text: text.slice(0, 24_000), elements, capturedAt };
}

export function actOnPage(context) {
    const stateKey = "__vyronChromeBridgeSnapshotV1";
    const state = globalThis[stateKey];
    const now = Date.now();
    if (now >= context.expiresAt || location.origin !== context.origin || !state || state.document !== document
        || state.location !== location.href || state.snapshotID !== context.snapshotID
        || now < state.capturedAt || now - state.capturedAt >= 30_000) {
        throw new Error("The page snapshot expired or changed. Read the page again before acting.");
    }
    const reference = state.references.get(context.elementID);
    const element = reference?.element;
    if (!element || !element.isConnected || element.ownerDocument !== document || !state.visible(element)
        || state.sensitive(element) || element.disabled || element.getAttribute("aria-disabled") === "true"
        || !reference.actions.includes(context.method)
        || element.closest("[contenteditable]:not([contenteditable='false'])")
        || state.role(element) !== reference.role || state.describe(element) !== reference.label
        || state.href(element) !== reference.href || element.type !== reference.type) {
        throw new Error("The target changed. Read a fresh page snapshot.");
    }
    // Each snapshot authorizes one mutation only, even if a page event handler throws.
    clearTimeout(state.expiryTimer);
    delete globalThis[stateKey];
    if (context.method === "click") {
        if (!(element instanceof HTMLElement)) throw new Error("This element cannot be clicked.");
        element.click();
    } else if (context.method === "fill") {
        if (typeof context.text !== "string" || context.text.includes("\0")
            || new TextEncoder().encode(context.text).length > 8_000 || element.readOnly
            || (!(element instanceof HTMLTextAreaElement) && (!(element instanceof HTMLInputElement)
                || !["text", "search", "url", "tel", "number"].includes(element.type)))) {
            throw new Error("This field does not allow text input.");
        }
        const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
        if (!setter) throw new Error("This field does not support text input.");
        setter.call(element, context.text);
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
        throw new Error("This page action is unavailable.");
    }
    return { tabID: context.tabID, action: context.method, status: "sent", message: "Check a fresh snapshot to verify the result." };
}

export function consumeNavigationSnapshot(context) {
    const stateKey = "__vyronChromeBridgeSnapshotV1";
    const state = globalThis[stateKey];
    const now = Date.now();
    if (now >= context.expiresAt || location.origin !== context.origin || !state || state.document !== document
        || state.location !== location.href || state.snapshotID !== context.snapshotID
        || now < state.capturedAt || now - state.capturedAt >= 30_000) {
        throw new Error("The page snapshot expired or changed. Read the page again before navigating.");
    }
    clearTimeout(state.expiryTimer);
    delete globalThis[stateKey];
    return { url: location.href };
}

export function clearPageSnapshot() {
    const key = "__vyronChromeBridgeSnapshotV1";
    clearTimeout(globalThis[key]?.expiryTimer);
    delete globalThis[key];
}
