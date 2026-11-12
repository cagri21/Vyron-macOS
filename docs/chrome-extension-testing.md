# Test Vyron for Chrome locally

The extension is a local development build. Nothing has been submitted to the
Chrome Web Store. Use regular Google Chrome on macOS and a model that supports
Work tools. A Work conversation needs a selected project; ordinary Chat and the
existing Mac accessibility panel do not use these extension tools.

The provided test app was built from the stable app revision plus the Chrome
feature in `.build/chrome-source-20261105`, because concurrent, unfinished image
processing edits in the main working folder prevented a combined build. Those
edits are preserved. The isolated source checkout is retained for inspection.

## Install the test build

1. Quit your existing Vyron app when you are ready to switch. Open
   `.build/chrome-testing/Vyron.app`. This is a separate development build; the
   existing app bundle and saved chats/model connections are retained.
2. Open `chrome://extensions` in Chrome and turn on **Developer mode**.
3. Choose **Load unpacked** and select this repository's `extensions/chrome`
   folder. Load the folder, rather than the ZIP file.
4. Copy the extension's 32-letter **ID** from its card.
5. In Vyron, open **Settings → Mac & browser**. Paste that ID under **Chrome
   extension**, then select **Enable Chrome connection**.
6. Open a normal HTTP or HTTPS website, such as `https://example.com`. Open
   **Vyron for Chrome** from Chrome's extensions menu and choose **Connect this
   tab**. Pin the extension for easy access to action reviews.

Registration allows only the extension ID you entered. If you move Vyron.app or
load a copy of the extension from a different folder, repeat registration with
the current app path and extension ID. Loading an unpacked folder at the same
path preserves its ID. The Chrome helper is started by Chrome only while the
extension is connected; no web server or listening port is installed.

## Try it

Start a Work conversation in a selected project and send:

> Use the Chrome extension to list my connected tabs and summarize the page I connected.

For a page with a normal search field, try:

> Use the Chrome extension to inspect my connected tab and enter “Vyron” in its search field. Wait for my Chrome approval.

Vyron can list connected tabs, read visible main-frame text and controls, and
request a click, text entry, same-origin navigation, or reload. Every page change
waits for **Approve once** in the extension popup. An amber **!** badge indicates
a pending review. Requests and snapshots expire after 30 seconds. Declining,
disconnecting, stopping the Work response, or changing the page invalidates a
pending request. Check the page after a change; do not repeat a side effect
whose result is uncertain. Plan conversations expose only read tools.
Stopping cannot undo an action that was already approved and sent to Chrome.

Only tabs explicitly connected in Chrome are available. Cross-origin navigation,
closing a connected tab, extension reloads, and browser restarts end the relevant
connection. Reconnect the current page when needed. Connecting does not grant
access to browsing history or cookies. Incognito, Chrome internal pages, file
URLs, password/authentication/payment fields, contenteditable editors, frames
other than the main frame, shadow DOM controls, and canvas controls are outside
this first version. It does not use the existing Mac accessibility permission.

Page text and control labels are sent to the selected model when Work reads the
tab. Choose the model/provider accordingly. The extension itself has no analytics
or remote requests. Request/response mailbox files are temporary, private to the
current Mac user, under `~/Library/Application Support/VyronAI/ChromeBridge`;
successful reads consume their response files, and a clean disconnect removes
the session. An interrupted host can leave a stale session directory; stale
sessions are ignored. Browser tool results can remain in Vyron's saved chat
history under the existing conversation retention behavior.

## Troubleshooting

- **Host not found / connection ended:** verify that you opened the test app and
  registered this extension ID there. Do not rename/move the app after registration.
- **No sessions:** use **Connect this tab** in Chrome, then **Refresh connection**
  in Vyron. The extension deliberately does not reconnect automatically.
- **No browser tools in Chat:** use Work with a selected project. Include
  “Chrome extension” in your request to use these tools instead of the existing
  Mac accessibility workflow.
- **Snapshot changed/expired:** read a new snapshot. Pending actions are never
  retried automatically.
- **Unpacked source changed:** choose **Reload** on the extension's card at
  `chrome://extensions`, then reconnect the tab.

To remove the integration, disconnect its tabs, remove the extension in Chrome,
and remove only
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/ai.vyron.chrome.json`.
This does not affect Vyron chats or model connections.

## Rebuild locally

Run project commands from the repository root through the Vyron runner.

```sh
python3 ~/.codex/skills/vyron/scripts/vyron.py run --project "$(pwd -P)" --timeout 240 -- \
    swift test --build-system native --disable-sandbox --filter VyronChrome
python3 ~/.codex/skills/vyron/scripts/vyron.py run --project "$(pwd -P)" -- \
    node --test extensions/chrome/tests/*.test.js
python3 ~/.codex/skills/vyron/scripts/vyron.py run --project "$(pwd -P)" -- \
    python3 scripts/package-chrome-extension.py
```

The ZIP contains runtime files and icons only; it is a convenient local archive.
Build a new packaged app at a fresh `.build/…/Vyron.app` destination with
`zsh scripts/build-app.sh debug <absolute-new-app-path>` through the same runner.
The build script refuses to overwrite an existing custom output path.
