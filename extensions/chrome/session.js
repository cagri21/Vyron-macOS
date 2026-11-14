import {
    errorResponse, isRequestID, MUTATING_METHODS, normalPageURL, sameOriginURL, successResponse, validateRequest
} from "./protocol.js";

// Session state lives only in the service worker. Restarting it disconnects every tab.
export class BridgeSession {
    constructor({
        execute, respond, changed = () => {}, now = Date.now,
        schedule = (callback, delay) => globalThis.setTimeout(callback, delay),
        unschedule = timer => globalThis.clearTimeout(timer)
    }) {
        this.execute = execute;
        this.respond = respond;
        this.changed = changed;
        this.now = now;
        this.schedule = schedule;
        this.unschedule = unschedule;
        this.tabs = new Map();
        this.snapshots = new Map();
        this.pending = new Map();
        this.seen = new Map();
        this.cancelled = new Map();
        this.generation = 0;
    }

    connect(tab) {
        if (!Number.isSafeInteger(tab.id) || tab.id < 0 || tab.incognito) {
            throw new Error("Choose a regular Chrome tab outside Incognito mode.");
        }
        const url = normalPageURL(tab.url);
        this.invalidate(tab.id, "The tab was reconnected.");
        this.tabs.set(tab.id, { id: tab.id, origin: url.origin, title: String(tab.title ?? "").slice(0, 300), url: url.href, revision: 0 });
        this.changed();
    }

    disconnect(tabID, reason = "The tab was disconnected in Chrome.") {
        this.tabs.delete(tabID);
        this.invalidate(tabID, reason);
        this.changed();
    }

    disconnectAll(reason = "The Vyron connection ended.") {
        this.generation += 1;
        this.tabs.clear();
        this.snapshots.clear();
        for (const item of [...this.pending.values()]) this.finishPending(item, errorResponse(item.request.id, reason));
        this.changed();
    }

    invalidate(tabID, reason = "The page changed. Read a fresh snapshot before acting.") {
        const tab = this.tabs.get(tabID);
        if (tab) tab.revision += 1;
        this.snapshots.delete(tabID);
        for (const item of [...this.pending.values()]) {
            if (item.request.arguments.tabID === tabID) this.finishPending(item, errorResponse(item.request.id, reason));
        }
    }

    update(tab) {
        const connected = this.tabs.get(tab.id);
        if (!connected) return;
        try {
            const url = sameOriginURL(tab.url, connected.origin);
            Object.assign(connected, { title: String(tab.title ?? connected.title).slice(0, 300), url: url.href });
        } catch {
            this.disconnect(tab.id, "The website changed. Connect this tab again in Chrome.");
        }
        this.changed();
    }

    requireTab(tabID) {
        const tab = this.tabs.get(tabID);
        if (!tab) throw new Error("Connect this tab using the Vyron extension button in Chrome.");
        return tab;
    }

    requireSnapshot(request) {
        if (!MUTATING_METHODS.has(request.method)) return null;
        const snapshot = this.snapshots.get(request.arguments.tabID);
        const age = this.now() - (snapshot?.capturedAt ?? 0);
        const element = snapshot?.elements.find(item => item.id === request.arguments.elementID);
        if (!snapshot || snapshot.snapshotID !== request.arguments.snapshotID || age < 0 || age >= 30_000
            || (["click", "fill"].includes(request.method) && (!element || !element.actions.includes(request.method)))) {
            throw new Error("Read a fresh snapshot of this tab before requesting this page action.");
        }
        return element;
    }

    async receive(value) {
        let request;
        try {
            request = validateRequest(value, this.now());
            for (const [id, expiry] of this.seen) if (expiry <= this.now()) this.seen.delete(id);
            for (const [id, expiry] of this.cancelled) if (expiry <= this.now()) this.cancelled.delete(id);
            if (this.cancelled.has(request.id)) throw new Error("This browser request was cancelled.");
            if (this.seen.has(request.id)) {
                const wasPending = this.pending.has(request.id);
                this.cancel(request.id);
                if (!wasPending) this.respond(errorResponse(request.id, "This request was already received. Actions are never replayed."));
                return;
            }
            if (this.seen.size >= 256) throw new Error("Too many browser requests. Wait a moment and try again.");
            this.seen.set(request.id, request.expiresAt + 30_000);
            if (request.method !== "tabs") this.requireTab(request.arguments.tabID);
            if (MUTATING_METHODS.has(request.method)) {
                const target = this.requireSnapshot(request);
                if (this.pending.size >= 8 || [...this.pending.values()].some(item =>
                    item.request.arguments.tabID === request.arguments.tabID)) {
                    throw new Error("Review the pending action for this tab first.");
                }
                const item = { request, generation: this.generation, targetLabel: target?.label, targetRole: target?.role,
                    targetURL: target?.url };
                item.timer = this.schedule(() => {
                    this.finishPending(item, errorResponse(request.id, "Browser action review expired. No action ran."));
                }, request.expiresAt - this.now());
                this.pending.set(request.id, item);
                this.changed();
                return;
            }
            await this.run(request, this.generation);
        } catch (error) {
            if (isRequestID(value?.id)) this.respond(errorResponse(value.id, error));
        }
    }

    async approve(id) {
        const item = this.pending.get(id);
        if (!item) throw new Error("This action is no longer waiting for review.");
        this.pending.delete(id);
        this.unschedule(item.timer);
        this.changed();
        // Remove first so a second click cannot repeat a side effect.
        await this.run(item.request, item.generation);
    }

    deny(id) {
        const item = this.pending.get(id);
        if (!item) return;
        this.finishPending(item, errorResponse(id, "The browser action was declined in Chrome. No action ran."));
    }

    cancel(id) {
        if (!isRequestID(id)) return;
        if (this.cancelled.size >= 256) {
            this.disconnectAll("Too many cancelled requests. Reconnect the tab.");
            this.cancelled.clear();
        }
        this.cancelled.set(id, this.now() + 60_000);
        const item = this.pending.get(id);
        if (item) this.finishPending(item, errorResponse(id, "The browser request was cancelled. No action ran."));
    }

    isCancelled(id) { return this.cancelled.has(id); }

    finishPending(item, response) {
        if (this.pending.get(item.request.id) !== item) return;
        this.pending.delete(item.request.id);
        this.unschedule(item.timer);
        this.respond(response);
        this.changed();
    }

    async run(request, generation) {
        try {
            if (generation !== this.generation || request.expiresAt <= this.now() || this.isCancelled(request.id)) {
                throw new Error("The request expired or the connection ended. No action was retried.");
            }
            const tab = request.method === "tabs" ? null : this.requireTab(request.arguments.tabID);
            const revision = tab?.revision;
            this.requireSnapshot(request);
            if (request.method === "navigate") sameOriginURL(request.arguments.url, tab.origin);
            if (MUTATING_METHODS.has(request.method)) this.snapshots.delete(tab.id);
            const result = await this.execute(request, tab);
            if (generation !== this.generation || this.isCancelled(request.id) || (tab && this.tabs.get(tab.id) !== tab)
                || (request.method === "snapshot" && tab.revision !== revision)) {
                throw new Error("The tab or connection changed while the command was running. Check the page before retrying.");
            }
            if (request.method === "snapshot") {
                this.snapshots.set(tab.id, { snapshotID: result.snapshotID, capturedAt: result.capturedAt, elements: result.elements });
            }
            this.respond(successResponse(request.id, result));
        } catch (error) {
            this.respond(errorResponse(request.id, error));
        }
    }

    view() {
        return {
            tabs: [...this.tabs.values()],
            pending: [...this.pending.values()].map(({ request, targetLabel, targetRole, targetURL }) => ({
                id: request.id, method: request.method, arguments: request.arguments, expiresAt: request.expiresAt,
                targetLabel, targetRole, targetURL
            }))
        };
    }
}
