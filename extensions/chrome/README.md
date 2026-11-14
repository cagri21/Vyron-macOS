# Vyron for Chrome — local preview

This Manifest V3 extension connects individually selected Chrome tabs to the
Vyron macOS app through the `ai.vyron.chrome` native messaging host. It uses no
server, API key, analytics, external script, or third-party package. It is a
local development preview, not a Chrome Web Store release.

## Load it locally

1. Build the Vyron app with its `VyronChromeHost` helper using the repository's
   app build instructions.
2. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**,
   and select this `extensions/chrome` folder.
3. Copy the extension ID shown by Chrome. Register that exact ID using
   `scripts/install-chrome-host.py --app /absolute/path/to/Vyron.app
   --extension-id THE_ID_FROM_CHROME`. The installer writes the current user's
   Chrome native messaging manifest and a private copy in Vyron's data folder.
   Use `--dry-run` to preview both destinations.
4. Open Vyron and a regular HTTP or HTTPS page in Chrome. Click the Vyron toolbar
   button and choose **Connect this tab**. Connect each additional tab separately.
5. In a Vyron **Work** conversation, ask the model to list connected Chrome tabs,
   read one, or request an action. Open the extension popup when the toolbar badge
   displays **!** to review and approve or decline the pending action.

Moving the unpacked extension folder can change its extension ID. Moving the
app changes the native host path. Repeat the corresponding setup if either
changes. Removing the extension or disconnecting all tabs ends its native host
connection. To unregister the helper, remove `ai.vyron.chrome.json` from
Chrome's user-level `NativeMessagingHosts` folder and `registration.json` from
`~/Library/Application Support/VyronAI/ChromeBridge`.

## What this preview supports

- List explicitly connected tabs and inspect their main-frame visible text,
  links, buttons, and ordinary editable fields.
- Request a click, fill, reload, or same-origin navigation with a fresh snapshot.
  Every mutation requires **Approve once** in the Chrome popup and expires within
  30 seconds. Each snapshot can be used for only one mutation.
- Cancel pending reviews when the app cancels a request, the page changes, a tab
  disconnects, or the native connection ends. A cancellation cannot undo an
  already approved action that has been sent to Chrome. Check the actual page
  before retrying any side effect.

Back/forward, arbitrary JavaScript, iframe interaction, file uploads, downloads,
Incognito, password/authentication/payment fields, and browser-internal pages are
not exposed. To switch to another website, open it in Chrome and connect that tab.
Chrome's temporary `activeTab` permission expires on cross-origin navigation.
Reloading the extension or restarting its service worker disconnects all tabs;
connections never resume automatically.

## Data handling

Connecting a tab explicitly lets Vyron request its page URL, title, visible text,
and control labels. The extension does not read input values, browsing history,
cookies, password field values, or page storage. Snapshot and review state stay in
memory. Worker state is cleared on disconnect or worker restart. Isolated page
references are erased on disconnect when Chrome permits cleanup and otherwise
expire after 30 seconds. Native messages use a local stdio
connection to the installed helper. Vyron may send requested page content to the
AI provider selected in the app and retain that content in the local conversation
or temporary bridge files according to the app's behavior. Do not connect a page
whose content you do not want to share with that provider.

## Offline checks

Use the repository's required Vyron runner with its absolute project root to run
`node --test extensions/chrome/tests/*.test.js`. Tests use Node's built-in test
runner and do not require dependency installation. These checks exercise request
validation, review/cancellation/session state, and DOM actions against a small
local fixture; they do not establish a successful live Chrome/native-host session.
