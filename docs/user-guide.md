# Vyron user guide

See the [project README](../README.md) for build instructions, a quick start, and the repository layout.

## Work in a project

Open Vyron, choose a project folder, and start a task. **Return** sends the
message; **Shift–Return** adds a new line. **Command–Return** also sends, and
**Command–N** starts a new task. These send shortcuts also save queued-message
edits and send follow-ups using the current queue or steer setting.

When the agent needs an answer, a compact **Question** card stays directly above
the message box. Select a numbered option or write your own answer, then choose
**Send**. **Skip** preserves any answers already provided and asks the agent to
use its judgment for unanswered questions. Closing the card stops the task.
Your message draft and queued follow-ups stay intact.

Adding a project creates missing `AGENTS.md`, `README.md`, `PLANS.md`, and
`.gitignore` files in its source folder. Saving newly attached source folders
does the same for each added folder. Setup uses local project markers for its
starter guidance and never executes project scripts. Existing files, empty
files, directories, and symbolic links at those names are preserved. Repeated
adds create only what is still missing. Setup errors are shown while the
project remains available; files already created are retained.

Opening recent projects, restoring chats, switching source folders, and running
scheduled tasks do not create setup files. Work and Plan load root
`AGENTS.override.md` or `AGENTS.md` as bounded project guidance before the
current request. The guidance read limit is 32 KiB; the complete request must
also fit the existing model and development context budgets. Unreadable,
invalid, or oversized guidance fails visibly instead of being silently cut.
Project instructions retain the existing tool restrictions.

The workspace starts with a compact **Chat / Work** switch and a single composer.
Choose the mode before sending the first message. The mode then stays fixed;
start a new chat to choose another mode. Each response's elapsed work time appears
in the conversation timeline. Chat uses a centered welcome and compact composer without project, access, or terminal
controls. Work keeps the larger composer and project tools. Turn on **Plan** in
the model menu for read-only planning within a Work conversation.

### Long project prompts

In a Work or Plan conversation with a project selected, a prompt longer than
3,000 characters or 12,000 UTF-8 bytes appears as `task-description.txt` in
the composer and saved conversation. Open the attachment to read the full
text or choose **Save** to export it as a plain-text file. Vyron includes the
original text in the model request. Project task descriptions can be up to
128,000 UTF-8 bytes, subject to the selected model’s context budget and any
image or folder context attached to the request.

### Workspace tools and local pages

Fresh conversations show only the centered welcome message and composer.
The grid button in the title bar and new tabs open **Tools**, **Suggested**, and **Recents**.
**Changes**, **Files**, and **Terminal** reuse the Work inspector and command-output
pane; **Side chat** opens an independent conversation when a model and source chat
are available. **More tools** opens Plugins, scheduled tasks, and advanced tools.
Command output stays available in the background. The terminal pane opens when
you choose it and keeps your open or closed choice during responses and questions.

The main conversation hides the browser tab strip and address bar. Opening a
website, page, or new tab shows those controls. The first tab returns to the
conversation. The **Tabs** menu switches between open tabs even while the
conversation is selected. Choose **Tabs → New tab**, **Command–T**, or **+** in
the tab strip for a new tab with Tools, Suggested, and Recents. Use the
address bar to enter an HTTP/HTTPS URL or search DuckDuckGo. **Command–L** focuses
the address field; the back, forward, reload/stop, and external-browser controls
apply to the selected website. Each website retains its own navigation history
when switching tabs. Links requesting another window open another tab. Up to
24 tabs can be open, including the permanent conversation tab.

**New page** opens a plain-text tab with explicit Save. Switching tabs retains
the draft; closing an edited page offers Save, Discard, or Cancel. **Command–S**
saves the selected page, and **Command–W** closes the selected website or page.
Tabs and unsaved drafts last for the current app session; Save keeps page content
in the local library across launches. Saved pages remain accessible in **Pages**, even after
their recent entry is removed. **Add website** creates a shortcut in Suggested;
selecting one opens an embedded website tab. Right-click a shortcut to remove it.
Web content uses WebKit without receiving model credentials. Downloads require
the explicit **Open in default browser** action. HTTP support is limited to web
content; the app's model requests retain their existing transport policy.
**Open file…** opens a chosen file in its default application. Pages, visits to
saved website shortcuts, and project-file previews appear in a deduplicated list of 20 recent
items; the first five are shown until **Show all** is selected.

This library is local to the Mac, stored separately from conversations at
`~/Library/Application Support/VyronAI/WorkspaceLibrary/library.json`.
Invalid or unreadable library data blocks saves and offers Retry, preserving
the existing file. It does not import browser history or sync cloud Pages.

Type **/** at the start of the composer to open a compact skill picker. Keep
typing to search every discovered local skill, use **↑ / ↓** to choose, and
press **Return** or **Tab** to insert its command. **Esc** closes the picker.
For example, choose `/vyron`, then write `run add a settings screen`. Personal,
project, system, and cached plugin skills use the same local folders as the
Skills browser. Plugin commands include their package name; duplicate names
remain separate. Refresh reloads local files without connecting a service.

Choose **/compact** from the same menu and send it to shorten the context used
by future replies. You can add a focus, such as `/compact keep the current plan
and verification results`. Vyron asks the currently selected model for a concise
summary, then carries that summary and subsequent messages into future requests.
The full transcript remains visible and saved, and **Continue in** carries the
summary into the copied chat. Chat, Plan, and Work support the command; compaction
of a saved Work chat does not require its project folder to be available.

During a response, `/compact` waits in the queue and runs after that response
finishes. Stop, a failed summary, or a storage error preserves the previous
summary. Work checkpoints and the original task stay intact. Earlier image
attachments remain in history; the text summary retains their names without
their pixels. Attach an image again when a future reply needs to analyze it.

Sending `/name` or `$name` loads that skill's current instructions for the
request, including queued messages and live Work updates. Chat retains the
original user message and stores its supplied context separately. Work keeps
selected instructions alongside its original task and can read supporting text
through `read_skill_resource`; this tool is restricted to selected skill folders
and exact local links to companion skills already in the discovered catalog.
Instructions exceeding Chat's context budget fail visibly instead of being
silently shortened. Skill files and supporting reads are limited to 64 KiB.
Skill selection uses Vyron's existing tools and permissions; another host's
connectors, private runtimes, and credentials are not imported. Skills requiring
those capabilities need a compatible connection or workflow in Vyron.

### Automatic skill setup

**Settings → Plugins → Automatic skill setup** is on by default. When a Work
request asks to create, read, or update a PDF, Word document, spreadsheet, or
presentation, Vyron selects the matching skill from its reviewed built-in
catalog, installs it if needed, and continues the request with those instructions.
The catalog ships with the app and works offline; this setting does not download
arbitrary community skills or activate plugins. Explicit aliases such as `/pdf`
can select a built-in skill as well. Existing exact local commands retain their
meaning.

Managed skills live in `~/Library/Application Support/VyronAI/Skills`, outside
the app bundle, and appear in the Skills browser and composer picker. Repeated
setup preserves existing skill edits. Setup rejects symbolic links, invalid
packages, and conflicting destinations rather than replacing user files.
Turning the setting off keeps installed skills available for explicit selection.
Chat and Plan do not install skills. Format discussions and application feature
requests do not activate automatic document workflows.

These are Vyron-compatible instructions, not another host's private runtime.
Additional software such as PDF libraries, a document renderer, or a spreadsheet
calculation engine may still be needed. The skill checks available tools and
reports a missing requirement; installation of the instructions alone does not
claim the artifact workflow is ready or verified.

### Local Office processing

Work provides `office_status`, `office_convert`, `office_render`, and
`office_recalculate`. Ask to convert a document to PDF, render page images, or
recalculate an XLSX workbook. Input and output paths are relative to the active
project. Output creation uses the existing native tool review and refuses to
overwrite existing files. Plan can check Office availability but does not create
outputs. Scheduled Work uses the same tools and review requirements.

PDF page rendering uses macOS Core Graphics. Other document operations use the optional
[DeepSeek Harness Office API](https://github.com/deepseek-ai/deepseek-harness/blob/master/python/sdk/README.md#optional-office-operations)
in a separate local Python environment. This invokes file-processing operations
without starting the Harness agent or making a model request. The Office engine
requires no API key; a Work conversation still uses its selected model provider.
The app does not install or download the SDK or Office engine automatically.

For an explicit manual setup, create a dedicated environment and install its
optional Office payload:

```sh
python3 -m venv "$HOME/Library/Application Support/VyronAI/OfficeRuntime"
"$HOME/Library/Application Support/VyronAI/OfficeRuntime/bin/python3" -m pip install deepseek-harness-sdk
"$HOME/Library/Application Support/VyronAI/OfficeRuntime/bin/python3" -c 'from deepseek_harness_runtime import download_office; download_office()'
```

Open **Settings → Plugins → Office processing**, choose that environment's Python
executable if needed, and select **Check setup**. An empty runtime field tries
the app's OfficeRuntime environment and common installed Python locations.
Checks run only when requested; missing packages or the Office payload are
reported as unavailable. Runtime changes apply to new tasks. These optional
packages retain their [upstream dependency licences](https://github.com/deepseek-ai/deepseek-harness/blob/master/THIRD_PARTY_NOTICES.md).
Recalculation is a calculation-engine result and does not establish Excel fidelity
or validate a workbook's business logic.

### Conversation actions

The native title bar contains the sidebar toggle
and three controls at the right: **Chat actions**, **Task overview**, and the
inspector toggle. Chat actions include Rename, Pin, Copy, native Share, Archive,
project opening, and separate chat windows. Right-click any chat in the sidebar
for the same actions, applied to that chat, plus **Delete chat**. **Continue in** creates a new Chat
or Work conversation with copied history and verified task evidence; the original
chat keeps its mode and history. Completed checkpoints remain complete, so a bare
Continue cannot silently restart finished work. Forking and archiving the open
chat wait for active work, drafts, and queued updates to be resolved. Archiving
another idle chat preserves the open chat and its draft.

The same menu includes **Mark as unread** and **Section**. Unread markers survive
relaunch and clear when the chat is opened; Section uses saved sidebar folders
without changing the chat's code project. **Copy** offers a local deeplink,
Markdown, plain text, and the actual working directory when the chat has one.
Packaged Vyron registers `vyron://chat/<conversation-id>` links to open saved
chats without sending a message. Opening a link preserves active work and drafts.
Paste one of these links into a request to include bounded visible text from
that saved chat as reference; hidden file context and image pixels are excluded.
New chats combine the linked chat's title with your request instead of using
the raw address as their title. Work and Plan can read additional pages of that
explicitly linked chat's saved user and assistant text through a read-only tool.
The reader does not open the source project or expose its tools, attachments,
queued drafts, or hidden context. Side chats and live Work/Plan updates also
include the linked chat's bounded reference text.
These addresses identify Vyron chats on this Mac, not chats in another app.

**Continue in → Hand off to a project** lets you choose another saved project,
its source folder, and a new or existing Work chat. Edit the request and choose
whether to start after opening or leave it as a draft. The destination receives
bounded recent conversation, the original request, and a saved summary as
reference; the source chat remains saved. Work starts only after the destination
workspace loads and the existing model and command permissions allow it. Earlier
images need to be attached again. Active tasks, attachments, drafts that are not
being transferred, and queued messages prevent a handoff from discarding work.

An explicit request such as “Move this request to iOS-Study” opens that chooser
without consuming the draft. Unknown or ambiguous destinations require a project
selection. Work agents can list saved destination metadata and prepare the same
chooser after their response completes. A prepared chooser has not sent a request
or started work; choosing **Hand off and start** performs the transfer. These
local chat actions do not add website publishing or another app's connectors.

Chat replies, Work tasks, and Plan replies keep running when you choose
**New Task** or switch chats in the left sidebar. Start a reply in the new chat
and return to the original chat from the sidebar to see its progress, answer
an approval or question, or stop it. Vyron runs one project Work or Plan task
at a time. Its built-in Ollama server processes one model request at a time,
so another reply may wait for the model. If a reply finishes while you're
away, any queued follow-ups stay saved in that chat. Reopen it and choose
**Send now** to send them.

Type `/side` in an existing conversation and press Return to open a temporary
side chat. Submit `/side <question>` to ask the first question immediately.
The side chat opens in its own window and uses a bounded text snapshot of the
original conversation. The original conversation stays selected, its task can
keep running, and unsent attachments stay in its composer. Closing the side
window stops its reply and discards the temporary conversation.

**New side chat** opens an independent Chat conversation with a bounded text
snapshot of the original. It keeps the captured model/connection and does not
cancel the original task. Image pixels are not copied into that text snapshot.
Closing its window stops only that side chat; saved messages remain in history.
Opening an existing conversation in another window provides a live read-only
transcript with an **Open in main window** action. All windows share one history
owner. **Add scheduled task** opens an unsaved editor populated with the original
user goal, verified updates, and selected execution context; Save remains an
explicit user action.

Task overview links to actual project changes and newly created outputs, the
latest response's subagents, and user-attached images. Recent images appear
first; **View all** expands the source list. The inspector toggle closes either
Files/Changes or Activity. In Chat it can close Activity while project tools
remain unavailable.

The shield menu controls approval for interactive project commands. **Ask for
approval** reviews every permitted command. **Approve for me** runs recognized
build, test, and inspection commands automatically and asks about other allowed
commands. **Full access** runs all permitted project commands without asking.
The default is **Approve for me**. Each response keeps the choice captured when
it starts; the menu is disabled during active work. Scoped file edits, blocked
commands, plugin reviews, Mac permissions, and scheduled-task approvals retain
their existing rules.

### Workspace controls

The sidebar contains projects and conversation history. Below
the composer, choose a project, open **Files**, manage **Plugins**, or toggle the
terminal. The sidebar opens beside a slim navigation rail, with compact project
groups, chat rows, and five recent chats per expanded project. **Show more**
reveals the rest; search includes every matching chat, and the selected chat
stays visible. A loading indicator beside the project name stays visible while
any of its chats has active work, including when the project is collapsed.
The sidebar button hides the project list while keeping the rail
available. Drag the divider beside the project list or the right inspector to
make either panel wider or narrower. The chat keeps a minimum usable width.
The inspector starts collapsed. The composer shows the selected model and effort
together, plus **Fast** when that response speed is selected. Auto model selection
also retains the current model name. Select this control to open a compact purple
popover with six snapped effort levels and a reset button for Auto. Selection
changes use an ease-out transition; macOS Reduce Motion disables this animation.
The colored track ends at the
white handle; the remaining track stays dark. Hover over the level or slider for
its task description. Arrow keys and VoiceOver move one level; Home/End select
Low/Ultra. The levels are:

| Level | Intended work |
| --- | --- |
| Low | Fast, contained edits and obvious tasks. |
| Medium | Default setting for routine feature work and normal debugging. |
| High | Complex debugging, multi-file changes, and production risks. |
| Extra High | Security audits, architecture updates, and migrations. |
| Max | Hardest single, deeply complex problems. |
| Ultra | Large, parallel multi-agent coordination. |

These are Vyron effort profiles with bounded output and planning budgets. Native
model reasoning uses only verified supported controls; stronger profiles use High
when that is the model's highest supported level. Unknown controls keep the
provider default, and explicit saved model settings take precedence. Ultra can
coordinate the existing independent read-only helper tool when useful; it retains
the three-helper limit and does not start helpers merely because Ultra is selected.
Chat responses and side chats capture their selected effort; scheduled chats use
their saved effort. Existing Quick/Balanced/Deep saved values still load as
Low/Medium/High. Auto retains its existing task selection and native defaults.

**Speed** is separate from effort. Supported OpenAI connections offer Standard
or Fast in the effort popover, with a higher-rate notice beside Fast. The choice
is saved per connection and applies to subsequent Chat and Work requests through
that provider. Existing side chats retain their captured provider; scheduled
runs use their saved connection's current settings. Standard explicitly requests
OpenAI's standard tier, overriding a project-level Fast default. Local models,
other compatible servers, and unverified model variants keep standard behavior
and cannot enable this OpenAI-specific option. OpenAI bills according to the tier
it actually serves, including any downgrade to standard processing; review the
official Billing page for account credit and charges.

Select
the model name beneath the effort label to choose a model or connection, toggle
Plan, inspect model features, or manage models. Effort changes wait for active
work to finish.

### Notifications

The bell beside sidebar Search opens **Notifications**. **Priority** contains
active work, pending input or approval requests, and unread completed or failed
responses. Read results are grouped under Today, Yesterday, or Earlier using their
actual finish times. Cards include the chat, project, public response preview,
and status. Opening the bell does not mark updates read. Open a card, use its
**Mark as read** menu, or choose **Mark all as read** to save that choice locally.
Reading an approval notification does not approve it or answer a question.

Opening an update preserves an active task, voice conversation, and unsent draft.
When the main chat cannot switch safely, conversation updates open in a read-only
window. Scheduled failures without a chat open Scheduled tasks without running
anything. Switching back with the bell or Search retains the project list's scroll
position. Archived chats stay out of the inbox. Read status lives separately in
`VyronAI/notification-read.json`; storage errors preserve the previous status and
offer Retry. This is an in-app inbox and does not request system push permissions.

### Project organization

Hover over a project name for its chat count, running-chat count, folder path,
and **Edit project**. Project rows show an ellipsis menu and a new-chat button
on hover or selection. The menu includes **Pin / Unpin**, **Edit**, **Section**,
**Reveal in Finder**, **Archive chats**, and **Remove project**. Editing changes
the sidebar name; Section uses your sidebar folders. Archiving hides every chat
belonging to that project, including pinned chats and chats placed in a section.
Open **Archived chats** from the sidebar’s **Vyron** menu to restore them with their
original pins and sections. Archive and Remove wait until project work finishes.
Removing a project clears its sidebar and recent-project references while keeping
its files and chat history; retained chats appear in their sections or the chat list.

**Edit project** also manages its **Source folders**. Add or remove folders in the
dialog, then choose **Save**; Cancel or the close button discards the draft. A
project needs 1–16 distinct source folders. Choose the active folder from the
project menu beneath the composer. Each chat and scheduled run keeps its actual
source-folder path alongside its sidebar project, so chats from different folders
remain in one project group. Switching folders starts a new chat. Detaching a
folder preserves its files and old chats; project tools require an attached folder
before starting new work. Folder changes wait for active project work to finish.

- **Agent** searches and reads the project, makes scoped edits, and runs guarded
  development commands. You do not need to select every source file manually.
- **Plan** can inspect source and propose a plan. Its tool layer refuses edits
  and commands, independently of the model's instructions.
- **Chat** provides a normal local conversation.
- **Auto** chooses an installed local model and effort budget. Coding uses the
  stronger compatible coding model. Choosing a model manually uses that exact
  model or reports why it cannot run the task. Low through Ultra effort profiles
  remain available.

### Changes and terminal output

Work responses with text edits show a summary beneath the answer with edited
files and green addition and red deletion counts. Hover over a file to preview
its diff, or click the file to review it in the right inspector. **View changes**
opens the response diff and the project. When the folder contains an iOS Xcode
project, Vyron opens the linked workspace or project in Xcode along with the
changed files that still exist. Other projects open in Finder, which also opens
the folder if Xcode is unavailable. **Undo** is available while the response’s
edits still match the project and preserves earlier edits.

The right inspector contains **Files**, **Changes**, and **Activity**.
**Changes** shows a unified diff or Before/After content. Switch to
**Project changes** to review or revert the project’s pending file-tool edits.
Revert preserves later user edits by refusing to overwrite a changed file.
Response and project diffs survive closing and reopening the app. They track
source edits from Work’s file tools.

The **Terminal** pane shows actual command output and exit status. Drag its top
divider up or down to expand or shrink the logs while keeping space for the
conversation. Closing and reopening the pane retains its height for the current
window. Known local build/test commands run automatically. Other permitted
commands require review.
Network, privileged, destructive, remote Git, shell pipelines, and background
commands are refused. Dependencies must already be available locally.

Git is optional for project work. If a Git inspection reports that the selected
folder is not a repository, Vyron keeps that result for the current run, skips
later Git inspections, and tells the model to continue with files and appropriate
local build or test commands. It does not initialize a repository. Other Git
errors remain failures, and repeated skipped requests do not renew the work budget.

Stop cancels the current model request and command process group. Completed
edits remain available for review; stopping does not roll them back. Recent
conversation context is bounded and carried into follow-up development requests.

### Checkpoints and verification

For multi-part Agent work, Vyron can save a plan of up to twelve stages and
carry a compact checkpoint into later model requests. Checkpoints retain the
original goal, user updates, completed file hashes, command results, and
integration outcomes separately from the model's conversation window. A stage
that changes source must pass an appropriate local build or test before it can
be marked complete. Each work cycle keeps the selected effort's tool-round
allowance. When a cycle ends after useful progress, Vyron saves its checkpoint,
compacts prior results, and continues the same task automatically. Automatic
cycles preserve the selected model, user guidance, permissions, action records,
and verification state. The three verification attempts belong to the active
stage and renew only after a verified stage completes. An overall round limit
of twelve work cycles bounds a task, including rounds in completed stages.
Repeated, unsuccessful, or unchanged actions receive explicit guidance to try
a different approach; three consecutive rounds without new progress stop with
unfinished work saved. Folder-analysis guidance directs repeated discovery toward
reading representative contents and answering from evidence. After this progress
limit, one text-only request to the same model can summarize collected findings
and remaining limits; it cannot execute tools or mark unfinished work complete.
If that request fails or produces no usable answer, the saved pause reason remains.
Changing list/search arguments without new results,
repeating plan explanations, or replaying completed actions does not renew a
cycle. Cancellation and required reviews remain active between cycles. A
declined command is not requested again during the active run.

### Model context and recovery

Request budgeting includes model-specific instructions, tool schemas, and the
serialized provider messages. Older exchanges can be compacted before sending;
completed file writes return short confirmations while their full diffs remain
in Changes. Context-budget failures and unusable development replies share at
most two compacted inference retries per tool round. Completed tool actions are
not automatically replayed by that recovery. OpenAI Responses output exhaustion
(`incomplete_details.reason = max_output_tokens`) uses that same allowance, with
guidance to split remaining work into smaller edits. Incomplete response text and
tool calls are discarded. Other incomplete reasons, including content filters,
are reported without content-recovery retries. Responses request budgeting
reserves the selected output allowance before compacting older exchanges, instead
of letting retained history silently reduce it to the minimum. If the conservative
byte-based estimate cannot fit a Responses development request, Vyron keeps its
message byte bounds and asks the same connection's `/responses/input_tokens`
endpoint to count the exact input and all tool schemas. Generation proceeds only
when the measured input, selected output allowance, and existing overhead fit the
same context limit. Count failures remain visible and do not generate an answer.
Official OpenAI Responses connections using GPT-6.1 Sol, GPT-6 Sol, or GPT-6 Astra
default to a 131,072-token context budget in Vyron. Their Agent message compaction
target is 96 KiB and the hard message limit is 128 KiB. Saved context and output
overrides take precedence. Ultra reserves 12,288 output tokens by default.

Native Claude connections use Anthropic's published limits for known model IDs.
Current Claude Opus, Sonnet and Haiku 5.5 and Fable 5.2 support a 1,000,000-token
context window and up to 128,000 output tokens. Vyron retains its 96 KiB Agent
message compaction target and 128 KiB hard message limit. If its local estimate
cannot fit the bounded request, Vyron checks `/messages/count_tokens` on the same
server with the same messages, system instructions and tool schemas. Generation
requires enough context for the returned estimate, the selected output allowance
and a small margin for differences in Anthropic's count.
[Claude context limits](https://platform.claude.com/docs/en/build-with-claude/context-windows)

Official DeepSeek Flash and V4 Pro use a 1,048,576-token context window and a
393,216-token maximum output allowance. Work reserves the selected output before
compacting history and uses a 96 KiB compaction target with a 128 KiB hard
message limit. Vyron estimates input tokens locally using serialized UTF-8 bytes.
**Customized settings** accepts context and output overrides up to those limits.
[DeepSeek model limits](https://api-docs.deepseek.com/api/list-models/)

An empty or output-truncated Ollama
reply first gets one adapter repair request. If both adapter attempts fail, the
agent can use its remaining compacted retries, for at most six generation
requests in that tool round. Recovery preserves the selected model and settings,
the original goal, user updates, and completed action records. Private thinking
is never treated as an answer or a tool call. Blank replies cannot mark work
complete; repeated unusable replies leave the task unfinished with its progress
saved. HTTP, malformed JSON, and lifecycle-only responses do not use these
content-recovery retries. Diagnostic details contain only allowlisted completion
reasons, token counts, and request sizes; they exclude prompts and private thinking.
Identical file writes are skipped against the current disk contents. Integration
writes and reviewed non-verification commands keep bounded action records;
uncertain outcomes require inspection before repeating the same action.

Routine work-cycle boundaries do not require a Continue message. After a real
interruption, ask to continue in the same chat to restore its unfinished task. Restoration
uses the original user request and the saved plan, progress, and ordered user
updates, including older checkpoints whose goal was saved as just "continue".
Auto effort is resolved from the restored task and its constraints. Restoration
keeps the current request authoritative and rechecks source-stage verification.
Conflicting or ambiguous task records require clarification, and a completed
task is not silently restarted. A different chat or project does not inherit
the checkpoint. Task checkpoints live under
`~/Library/Application Support/VyronAI/DevelopmentProjects/<project>/TaskStates/<chat>/`;
existing conversation and change-journal formats remain unchanged. Full or
unusable requests and unavailable verification can still stop safely with the
remaining work saved. Interrupted work does not automatically send queued
follow-ups or restart when the app opens.

You can keep typing while a response runs. **Return** queues a follow-up
above the composer; queued messages run in order after a successful response.
Use **Steer** to apply a queued update to the current task, or use its menu to
edit it, delete it, or turn off queuing for subsequent messages. Editing restores
your existing draft when saved or canceled. Queued messages stay with their chat
and survive reopening; Stop or an error keeps them pending for **Send now**.
Drag a message by its text or queue icon onto another row to move it up or down.
The row highlights as a drop target; its menu also offers **Move up** and
**Move down**. Reordering saves the new execution order without sending a message.
Updates already being applied to the running task stay locked.

Agent and project Plan tasks apply steering between model/tool steps and
reconsider actions that have not started. A running tool finishes first; steering
does not undo completed edits or repeat that tool. Chat steering stops the current
reply, keeps its partial text, and continues with the conversation and your update.

Progress appears inline in the conversation. Public explanations use normal
prose, with compact, collapsed tool rows between them. Expand a tool row, then
select a step to open its recorded details in Activity. Active tool summaries,
helper rows, and the clickable **Thinking** label have a subtle shimmer that
respects Reduce Motion. Elapsed time remains available after a response finishes;
earlier preparation statuses stay out of the conversation, and the final
answer appears once. Stopped and failed responses retain their status and details.
Activity stays with its response and survives reopening the app. This is
observable progress and explanations shared by the AI; private internal reasoning
is not displayed. The latest 120 activity entries are retained per response.

Each response starts with a **Worked for…** row, or **Working for…** while it is
active. Select it to expand that response's timeline, with recorded event times
and details. A task's recorded start time appears above its request. The workspace
header keeps navigation and chat actions; elapsed time stays in the response timeline.
Elapsed time includes waiting for approvals and answers. Finished, stopped, and
failed response timers stay fixed, and reopening does not count time while the
app was closed. Older messages without timing data do not receive invented dates.

The timeline includes individual file, search, command, and integration steps.
Final replies do not automatically append changed-file or command lists. Choose
**View activity** after tool work finishes to open its recorded details in the
right panel. Tracking is tied to its chat and response, including completed,
stopped, and failed work. Material failures and verification limitations remain
in the reply when they affect the result.

Project **Agent** and **Plan** tasks can delegate independent reading, analysis,
and review to up to three parallel subagents per run. Helpers use the task's
selected model and project in read-only Plan mode; the main agent applies edits.
The chat shows actual helper starts and status. Select a helper to inspect its
model, task, elapsed time, activity, and result in the **Subagents** panel. The
main agent receives their results before continuing. **Stop** cancels helpers
together with the main task. Helper activity and results stay in chat history;
reopening interrupted work marks unfinished helpers stopped.

During project **Agent** and **Plan** tasks, Vyron can ask up to three short
questions when it needs a choice or missing detail. Questions appear inside the
chat with suggested options when useful and a field for your own answer. Answer
each question and choose **Continue** to resume the same task. Answers stay in
the conversation; your composer draft and queued follow-ups remain separate.
**Stop**, starting a new chat, or switching chats clears an unanswered request.
There is no automatic answer or timeout.

After a completed answer, the single best suggested follow-up can appear as faint
text only inside the empty composer. There is no suggestion list below the answer.
Press **Tab** while typing there, or click its small Tab
button, to add the hint to your draft. Review and send it with **Command–Return**.
Typing your own text hides the hint. Suggestions never send automatically or
replace a draft, and stay hidden during voice input or queue editing. Suggestions
are saved with the answer. This optional background model request stops after
12 seconds and is canceled when you send another request or leave the chat.

## Appearance

Open **Vyron → Settings… → Appearance** (**Command–Comma**). Under **Mode**,
choose **System** to follow macOS, or select **Light** or **Dark**. The mode
works with any theme. The default **Vyron** theme preserves the original look.
**Theme** also includes **ChatGPT**, **Codex**, and presets such as **Catppuccin**,
**Dracula**, **Everforest**, and **GitHub**.

Use **Accent**, **Background**, and **Foreground** to pick colors or enter a
six-digit hex code. Choose an installed font for the interface and conversation
text. **Advanced** lets you edit the other mode’s colors and adjust **Success**,
**Warning**, **Error**, and **Full access** for either mode. Failed response
details and their sidebar icons use the Error color. Changes apply immediately
and are saved locally. Use **Copy theme** or **Paste theme** to move a Vyron theme
between Macs. **Reset to default** restores the original appearance.

## Interface language

Open Settings from the navigation rail's gear or **Vyron → Settings…**
(**Command–Comma**). Use the searchable sidebar to find **General**, which contains
language, follow-up message queuing, and workspace panel controls. Select **General → Language**:
**System Default**, **English**, **Türkçe**, or **Українська**. The selection
is saved and updates the interface immediately while preserving drafts, active
tasks, and open views. System Default uses the first supported macOS language,
with English as the fallback. Dates and count labels follow the selected
language. User messages, project files, model IDs, and server responses retain
their original content.

## Voice conversations

Use the **microphone** beside Send to dictate into your draft. Dictation does
not send a message; review it and send when ready. Use the **waveform** button
to start a hands-free conversation in Chat mode. Finish or clear your draft
and pending messages first. Vyron sends each turn after a short pause, reads
the completed reply aloud, and listens again. **Interrupt** stops the reply
and listens for your next turn; the end button stops the conversation.

Open **Vyron → Settings… → Voice** (**Command–Comma**) to select and preview a voice.
The selection is remembered, and the list uses voices already installed on
your Mac. Speech recognition uses the Mac's current language and requires
on-device recognition support. If it is unavailable, Vyron reports the issue
without sending audio to a remote transcription service. Microphone and
Speech Recognition permissions are requested the first time you use voice.
Recognized text uses the same AI connection as your chat; a remote model
receives that text. Voice input requires the packaged `Vyron.app` so macOS
can show the permission prompts.

Voice capture stops while Vyron prepares or speaks a reply, when you switch
chats or modes, and when you stop or quit. Scheduled tasks wait while voice
is active. The hands-free mode uses complete AI turns, so response latency
depends on your selected model.

## Scheduled tasks

Open **Scheduled tasks** directly from the sidebar, its clock button in the
navigation rail, or the app menu to create a one-time, daily, or weekly task. Each task saves its prompt,
Agent/Plan/Chat mode, project, model selection, and time zone. Editing a task can
reuse the current project and model. Pause/resume controls, **Run now**, and
**Stop** are available beside each schedule. Results and observable activity
are saved in separate chats; **Open result** opens the latest run without
replacing an existing draft when the run starts.

Vyron must stay open and the Mac must be awake. Schedules are checked every
15 seconds when the app is free; they do not launch Vyron or wake the Mac.
After sleep, reopening, or another task finishing, missed occurrences coalesce
into one run, then recurring tasks continue at their saved local time. Pausing
a recurring schedule and resuming it starts with its next future occurrence.
Completed one-time schedules can be run again explicitly or edited for a new
date. Existing project command reviews and MCP write reviews still apply.

An occurrence is saved before work starts. Interrupted or failed occurrences
are not automatically replayed; review the result before using **Run now**.
Schedules are stored separately in
`~/Library/Application Support/VyronAI/scheduled-tasks.json`. Invalid or
unsupported saved files are preserved and scheduled execution stops until
storage is recovered. Existing conversations and sidebar formats are retained.

## MCP connections and Penpot

Open **Plugins** below the composer (also available in the app menu or under
**Advanced tools → Plugins**, and in the project sidebar).
This opens a dedicated **Customize → Plugins** page with installed connections,
search, **All plugins / Installed / Connected** filters, and an **Add** menu.
Choose an installed plugin in the sidebar or its card to inspect its connection,
permissions, and discovered tools. Use the connection menu to edit, enable,
disable, or remove it; removal asks for confirmation.

Choose **Add → Add MCP server…** for a Streamable HTTP URL or a local stdio
executable, or **Add → Add Penpot…** for the preset. The available Penpot and
Custom MCP server cards open the same editors. **Back to workspace** returns
to your task. Opening the page keeps drafts, active responses, project state,
downloads, and existing MCP sessions in place.
The editor supports both a form and editable JSON configuration. You can set
HTTP headers, bearer tokens, URL parameters, and local command environment
values. Connection descriptions persist locally; credentials are kept in
Keychain. Connections start when you choose **Connect**, and the manager shows
the connection result and discovered tools. Enable, disable, edit, disconnect,
or remove connections here. Local command connections start a program under
your user account, so use trusted servers.

Connected tools are available in project **Agent** tasks alongside file and
command tools. **Read only** exposes tools the server identifies as read-only.
**Ask before changes** also allows write tools in Agent, with a native review
showing the server, tool, and exact arguments before each call. General code
execution and export tools require review even if marked read-only. **Plan**
receives only read-only tools; **Chat** does not execute MCP tools. Server
annotations are trust hints, not an isolation boundary. Tool output is treated
as untrusted data and bounded before entering model context.

For hosted Penpot, use **Your account → Integrations → MCP Server** to enable
MCP and copy its connection URL. Paste it into the Penpot connection, then
open the design file and choose **File → MCP Server → Connect**. URL query
parameters such as `userToken` are separated into Keychain when saved.
**Import existing Penpot** can reuse the named Penpot URL from your existing
local MCP configuration without displaying its token.

For the official local server, run `npx -y @penpot/mcp@stable`, use
`http://localhost:4401/mcp`, install the plugin from
`http://localhost:4400/manifest.json`, and connect the open Penpot file.
See the [official Penpot setup](https://help.penpot.app/mcp/).

After connecting, open your source project and ask Agent to inspect the Penpot
design and implement it. For design changes, choose **Ask before changes** and
review the proposed tool call. A stopped or failed write may already have
reached the service; inspect its result there before retrying. Servers may
receive project excerpts in tool arguments. MCP sampling, server-driven roots,
OAuth sign-in, legacy HTTP+SSE transport, and image input are not implemented.

### Browse local skills

Open **Plugins → Skills** in the Customize sidebar to browse local Claude,
Codex, and shared agent skills. Search by name, description, or path; source
filters separate Claude, Codex, and Shared results. Personal, project, and
plugin-cache skills have separate sections. Select a skill to read its bounded
preview or reveal its file in Finder, and use **Refresh skills** after changing files.

The browser reads `SKILL.md` files from `~/.claude/skills`, `~/.codex/skills`
(including `.system`), `~/.agents/skills`, the selected project's corresponding
folders, and Claude/Codex plugin caches when present. Missing folders are allowed.
Files and traversal are bounded, symbolic links are skipped, and duplicate names
retain their separate paths. Browsing does not activate skills, execute their
instructions, or transfer another app's tools, credentials, or account permissions.

The **Plugins** page has **Available** and **Personal** tabs, compact connection
rows, search, local refresh, and a shortcut to plugin settings. Available entries
are Vyron's supported setup options; saved connections remain in Personal and the
Customize sidebar. Refresh reloads saved profiles without connecting services.

### Bring Claude and Codex skills into agent tasks

Choose **Plugins → Add → Add Claude & Codex bridge…**. The local MCP connection
opens in the existing editor, with read-only access and disabled by default.
Review and save it, then use **Enable → Connect**. Python 3 is the only runtime
requirement; no packages need to be downloaded. The connection reads local files
and does not contact Claude or OpenAI.

The bridge exposes six MCP tools to a project **Work / Agent** task:

| Tool | Purpose |
| --- | --- |
| `list_sources` | Show which configured local skill folders and plugin caches are available |
| `list_skills` | Search and filter personal, project, and cached-plugin skills by source and scope |
| `read_skill` | Read a bounded `SKILL.md` preview using a returned skill ID |
| `list_plugins` | Search cached Claude and Codex package metadata |
| `inspect_plugin` | Inspect declared skills, MCP servers, and compatibility requirements |
| `prepare_connection` | Prepare a disabled, read-only connection JSON for separate setup |

For example: “List my Claude and Codex skills, find the Swift cleanup guide, and
read it as a reference for this task.” Returned skill text can inform the task;
it does not grant additional command permissions or enable its external tools.
All existing project boundaries, Plan restrictions, and action reviews still apply.

The bridge reads the same standard skill folders as the Skills browser, plus
`~/.claude/plugins/cache` and `~/.codex/plugins/cache`. Claude packages use
`.claude-plugin/plugin.json` and conventional `.mcp.json` / `skills` locations;
Codex's existing portable and compatibility package formats remain supported.
Missing source folders produce empty results. Duplicate skill names retain
distinct opaque IDs. Reads reject symbolic links in every path component and
return at most 64 KiB per skill, with explicit truncation and scan-limit flags.
Skill responses also fit a 40,000-character JSON budget for Vyron's tool display;
long previews are shortened explicitly and list pagination advances by the number
of entries actually returned.

The preset supplies the actual home directory explicitly. If a project is open
when adding it, that project's directory is captured in the saved connection.
It does not change automatically when switching projects. Add another connection
or edit its `--project-root` argument to change project scope. Neither account
settings nor authentication stores are imported. Cached packages may be present
without being installed or enabled; private app runtimes, platform connectors,
and OAuth sessions cannot be transferred through this catalog.

The bundled entrypoint is
`Apps/Vyron/Resources/CodexCatalog/agent_catalog_mcp.py`. It uses newline-delimited
MCP JSON-RPC over stdio. `--home-root /absolute/home` chooses the local skill/cache
home, and optional `--project-root /absolute/project` adds that project's skill
folders. `--inventory` prints a one-time metadata inventory without starting MCP.
The previous Codex-only entrypoint and its four-tool interface remain available.

For an existing Vyron build without the new preset, open **Add MCP server… → JSON**
and use this configuration, replacing both absolute paths with the local checkout
and home directory. Save, then enable and connect. No app rebuild is needed for
this manual configuration; the Python files must remain at the configured path.

```json
{
  "name": "Claude & Codex bridge",
  "type": "stdio",
  "command": "python3",
  "args": [
    "-I",
    "/absolute/Vyron-macOS/Apps/Vyron/Resources/CodexCatalog/agent_catalog_mcp.py",
    "--home-root",
    "/absolute/home"
  ],
  "enabled": false,
  "permission": "readOnly"
}
```

Offline protocol, skill, path-safety, and legacy catalog regression tests run with
`python3 -m unittest discover -s scripts/tests -p 'test_*catalog.py'`. Coding agents
must run that command through the Vyron runner as described below.

### Explore cached Codex plugins

Choose **Plugins → Add → Add Codex plugins…**, then review and save the local
connection. **Connect** starts the bundled read-only catalog MCP. It requires
Python 3 and reads package metadata from `~/.codex/plugins/cache`; it does not
read Codex account configuration, authentication files, or credential stores.
Cache presence does not establish that a plugin is installed or enabled.

In a project **Work / Agent** task, ask Vyron to list cached Codex plugins,
inspect a package, or read one of its skills. The catalog exposes
`list_plugins`, `inspect_plugin`, `read_skill`, and `prepare_connection`.
It supports portable root `plugin.json` / `mcp.json` packages and the
`.codex-plugin/plugin.json` compatibility format. Skill text is reference
material; the catalog does not install skills or execute their instructions.

For a compatible MCP server, `prepare_connection` returns a disabled,
read-only connection JSON preview. Open **Add MCP server… → JSON**, review
the configuration, and supply any required credentials directly in Vyron.
Save it, then explicitly enable and connect. The catalog does not install
dependencies, download plugins, start their commands, or copy Codex credentials.
Registered platform connectors and private Codex runtime services cannot be
transferred. Declared OAuth connections are unavailable until Vyron supports
that authentication flow; other servers may also need account or runtime setup.

The bundled entrypoint is
`Apps/Vyron/Resources/CodexCatalog/codex_catalog_mcp.py`. It uses only the
Python standard library and newline-delimited MCP JSON-RPC over stdio.
`--cache-root /absolute/path` selects a different cache directory;
`--inventory` prints a one-time metadata inventory without starting MCP.
Offline regression tests are in `scripts/tests/test_codex_catalog.py`.
Package parsing follows the
[official OpenAI plugin formats](https://developers.openai.com/plugins/build/plugins).

## Organize the sidebar

Use **+** beside Vyron to open a project or create a sidebar folder. Right-click a folder to
add a subfolder, rename it, move it, or remove it while keeping its contents.
Right-click a project or chat to **Pin / Unpin** or **Move to** a folder. Chats
can also be renamed. Use a project's folder/disclosure button to expand its chats, then
**Show more / Show less** to control long histories. Click the search icon beside
Vyron to search by project, chat, or folder name. The navigation rail opens the
workspace, scheduled tasks, and plugins; its **Advanced tools** menu retains Mac
and browser controls and model management.

Folders are organization inside Vyron; project directories stay in place.
Moving a chat between sidebar folders keeps its original project association.
Pins, nested folders, and expanded/collapsed states survive reopening. The
project registry retains opened projects beyond the eight most recent entries.
Organization is stored separately from messages in
`~/Library/Application Support/VyronAI/sidebar.json`. Existing history is
imported without rewriting its messages; an unreadable sidebar file is preserved.

Unavailable projects do not retain another project's editing tools. Reopen the
project or choose a different one before running an Agent task.

## Models, connections, and storage

Open **Manage Models…** from the model picker to browse these local options,
download one, pause/resume its download, or select an installed model. The
catalog was checked against the official Ollama library on November 2, 2026:

| Role | Model | Approximate download |
| --- | --- | --- |
| Newer coding and reasoning option | [Qwen3.8 27B](https://ollama.com/library/qwen3.8:27b) | 18 GB |
| MoE coding and reasoning alternative | [Qwen3.6 35B](https://ollama.com/library/qwen3.6:35b) | 23 GB |
| Another coding model family | [Devstral Small 2 24B](https://ollama.com/library/devstral-small-2:24b) | 15 GB |
| Established coding option | [Qwen3-Coder 30B](https://ollama.com/library/qwen3-coder:30b) | 18.6 GB |
| Large coding option | [Qwen3-Coder-Next Q4](https://ollama.com/library/qwen3-coder-next:q4_K_M) | 52 GB |
| Lightweight routing and supporting tasks | [Qwen3 4B](https://ollama.com/library/qwen3:4b) | 2.5 GB |

Running a model also requires memory for its context, macOS, and other apps.
Automatic selection considers the Mac’s available memory. Models with vision
support can analyze explicitly attached screenshots in Chat, Work, and Plan.
Text-only Ollama models can use text extracted locally with Apple Vision.

The built-in Ollama engine loads one model at a time. Model weights remain fixed; effort changes
context, output, and step budgets. Tasks choose only among installed local
models and never download another model automatically. Custom connections use the exact selected model. The smaller helper model
is not used as the coding agent. Other local Ollama tags can be added from the
model manager; unsupported agent models produce a clear error.

The model picker lists installed coding choices by **Coding Auto score**, highest
first, with raw ranking points beside each name. The score reuses Auto's local
selection rules: catalog priority, tool support, model preference, and a size
adjustment for the selected effort. Quick and Auto use the Balanced coding
ranking. These points are a selection heuristic, not published benchmark results
or a percentage quality rating. Chat helpers and other unranked choices remain
available separately. Custom connections keep their exact model IDs and do not
receive local Auto scores. Opening the list does not change the selected model.

Models live in `~/.ollama/models`. Chats, edit backups, bounded engine logs, and
command results live in `~/Library/Application Support/VyronAI`. These files
stay in the local user account. Conversations may contain project excerpts.
The `VyronAI` storage directory is retained for compatibility so the rename to
Vyron preserves existing chats, settings, and project history.

If the installed runtime explicitly reports that constrained JSON output is
unavailable, typed planners retry once with the same JSON contract in the
prompt. Responses still pass the existing strict decoding and target checks
before any action can be proposed. Printed tool commands are never executed.

**On this Mac** uses `http://127.0.0.1:11434` for local inference. It accepts
downloaded local models and rejects redirects, cloud tags, and remote-backed
models. The app-owned engine disables cloud features. Initial model downloads
need internet access.

### Add a model by URL

For DeepSeek, choose **Add DeepSeek** in **Manage Models…**. Enter your DeepSeek
API key, choose `deepseek-flash` or `deepseek-v4-pro` (or enter another exact
model ID), and select **Save & use**. The preset uses
`https://api.deepseek.com/v1`; discovery, response testing, and saving contact
DeepSeek only when requested. The key is stored in the existing macOS Keychain
entry for that connection. Existing saved connection IDs and API keys are
preserved; no profile migration is required.

For Claude, choose **Add Claude** in **Manage Models…**. Paste your Anthropic
API key and use `claude-sonnet-5-5` or select another model with **Discover models**.
The preset uses `https://api.anthropic.com/v1`. **Customized settings** lets you
enter a context budget and maximum response tokens when adding or editing a
connection. Leave either field blank to use its automatic value. Vyron validates
Claude overrides against the selected model's published limits when available.

Choose **Add OpenAI** to prefill `https://api.openai.com/v1` and `gpt-6.1-sol`.
Enter your OpenAI API key, keep the preselected model or use **Discover models**,
then select **Save & use**.

Use **Add server URL** to save an Ollama, Anthropic, or OpenAI-compatible
connection. Enter its HTTPS URL (HTTP is available for loopback servers), an API
key if the server requires one, and an exact model ID. **Discover models** lists the server's
models and published precision variants; enter the ID manually when discovery
is unavailable. **Test response** checks a short reply and Agent tool support.
**Save & use** verifies a reply, saves the profile, and selects it. Profiles
can also be edited, removed, and switched from the model picker.

Open **Settings → Billing** for account credit and provider-reported balances.
Billing is also available beside supported connections in Models. The composer
has no balance badge or manual estimate entry.

- **DeepSeek:** reports its actual account totals, keeping USD and CNY separate.
- **OpenRouter:** reports the remaining spending allowance on the current API key,
  labeled **Key**. This differs from total account credit. An uncapped key shows
  **No key limit**, without inventing a remaining balance.
- **OpenAI:** choose **View OpenAI balance** to load its official billing page
  inside Settings. Sign in and select the organization associated with your API
  key. This displays OpenAI's own account credit, including free subscription
  grants, instead of calculating a local balance. Opening Settings alone does
  not load the account page. **Refresh** reloads the official page and
  **Open in browser** supports sign-ins that require an external browser.
  A normal API key has no verified supported remaining-credit endpoint; the
  administrator Costs API reports spending, rather than remaining credit.
- Local and other unsupported connections have no native balance card.

DeepSeek and OpenRouter checks use the saved connection's existing Keychain entry.
The active supported connection refreshes when activated, every minute, and
shortly after responses; other connections can be refreshed manually in Billing.
Changing the actual key or balance provider clears old account values; renaming
a connection or changing models keeps its balance and retry state. Only the
active connection polls. Transient failures back off, provider Retry-After dates
are honored, and rejected or inaccessible keys stop automatic checks until an
explicit retry or key change. An old amount remains marked **Last** and stale;
missing, failed, or unsupported results never become a fabricated zero.

The embedded OpenAI page uses WebKit's website session, independent of model API
keys. Vyron supplies no API credentials, script injection, or page-content
extraction. Top-level navigation stays on OpenAI domains; external identity
providers use the browser fallback. Loading errors offer Refresh and browser
access. Closing the page stops loading. Existing local estimate files remain
intact for compatibility, but estimates are not displayed or updated by normal
inference requests. No value from an old screenshot is used as a live balance.

Provider contracts are documented in
[DeepSeek balance](https://api-docs.deepseek.com/api/get-user-balance/),
[OpenRouter key allowance](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key),
and [OpenAI Costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs).
OpenAI credit viewing is described in
[API credit benefits](https://developers.openai.com/api/docs/guides/chatgpt-api-credits).

For the official OpenAI endpoint, `https://api.openai.com/v1`, GPT-6 Astra,
GPT-6 Sol, GPT-6 Luna, GPT-6.1 Sol, and GPT-6.1 Terra use the Responses API for
Chat and native project tools. Dated snapshots of those models use the same
route. Existing saved connections work without a profile migration. The API key
needs **List models: Read** and **Responses: Write** permissions. Leave
temperature and top P empty for these reasoning models. Low through Ultra use
bounded task budgets; the model's default native reasoning effort is retained.
The data-only tool capability check uses low reasoning effort.

Older OpenAI models and other compatible servers keep Chat Completions. Ollama,
including Qwen models, keeps its existing API, settings, and local execution
checks. Provider-specific continuation data stays with its own tool exchange
and is excluded from requests to other providers. Changing a connection does
not download a model or enable paid API billing.

The model manager, connection editor, and composer show which features are
available, unavailable, or not verified for the selected model. Unavailable
features are disabled individually; unavailable project tools do not disable
Chat. Thinking controls stay disabled until compatible support is known.
Unverified tool support is checked before project work and can be retried with
**Check model features**. Availability uses model/runtime metadata and checks
for the current selection.

For the official DeepSeek connection, Chat, Work, project Plan, and plugin tools
use the compatible API with native tool verification. Known supported DeepSeek
models expose an optional thinking toggle; Work effort maps to DeepSeek's
supported reasoning levels. Private reasoning is retained only as opaque,
connection-, endpoint-, and model-scoped tool-history metadata and is never
shown as answer text or sent to another connection. Other hosts and unknown
model IDs remain subject to their own feature checks. The implementation follows
DeepSeek's [thinking and tool-history contract](https://api-docs.deepseek.com/guides/thinking_mode/).

Under **Download a model by URL**, paste an Ollama library page, a public
Hugging Face GGUF repository/file URL, or a direct `.gguf` download URL. Choose
a published variant using **Bits / precision**, then download it or import it
into local Ollama. Size and precision come from the source; unknown metadata
stays unknown. Imports verify the file and reject names already installed.
Ollama downloads can be paused/resumed; canceling a file import removes its
temporary download and requires restarting the import. Single-file GGUF is
supported; split files and private/gated repositories are not supported yet.

For an installed Ollama model, choose **Change precision…** on its card to see
matching variants. Vyron uses the selected variant if it is already installed or
downloads it first. It tests a short response and selects the replacement before
removing the exact previous tag. Canceling or failing before the switch keeps
the previous variant installed.

Precision is a specific weight variant, not an arbitrary generation switch.
Hosted servers expose bit options only when they publish separate variants.
The runtime must support the chosen model's architecture. Storage size is
shown when published; it is not a measurement of total running memory.

**Local model settings** and each connection's editor support optional context
and output budgets, temperature, and top P. Ollama also supports thinking
controls when the model advertises compatible values. Explicit contexts are
checked against Ollama's advertised limits when available. OpenAI-compatible
context settings bound Vyron's request budget; they do not resize a hosted
model. Empty fields restore Vyron's automatic defaults. Settings and exact
model IDs persist in `~/Library/Application Support/VyronAI/model-connections.json`;
API keys are stored separately in macOS Keychain. Existing chats and local
model preferences are retained.

For **On this Mac**, set **Request timeout (seconds)** in **Local model settings**
and select **Apply**. The field accepts whole seconds from 1 to 3,600. An empty
field uses 600 seconds per Ollama inference request in Work and Plan.

On the same Mac, deleting or replacing only `Vyron.app` and installing a new
version keeps those connection settings and Keychain entries. They are outside
the app bundle. Future builds retain the same connection IDs and Keychain
service, so the saved OpenAI key and selected model remain available. Removing
the saved app data or the Keychain entry also removes that part of the setup.
Saved profiles load before credential access. The active key is read off the
presentation actor after the window opens, so macOS Keychain checks cannot
prevent the window from appearing. Access remains subject to macOS permissions;
an app signed with a different identity, including a new ad-hoc build, may need
access approved again even though the stored key is retained.

### Local Docker authentication and credential backup

The optional local service uses a device token. Start it from the repository root.

```sh
python3 scripts/local-auth.py start
```

Docker Desktop must be running. The helper retains its private device token
and configuration in `~/Library/Application Support/VyronAI/LocalAuth`, then
starts only the `vyron-local-auth` Compose project on `127.0.0.1:8327`.
Its small ingress relay exposes that loopback endpoint; the credential store
stays on an internal Docker network without an internet route. The relay has
no credential-file or data-volume mounts and forwards only to that store.
The persistent volume `vyron-local-auth-data` survives app replacement and
ordinary container recreation. `python3 scripts/local-auth.py stop` stops the
service without deleting that volume or the saved app credentials.

API keys remain in the existing macOS Keychain. Vyron encrypts backup copies
with AES-GCM before sending them to the local service; the encryption key stays
in Keychain. **Manage Models** shows connection status and a Retry button.
Unavailable Docker does not disable existing model connections. Recovery only
fills a missing API-key entry for an existing saved connection; it never
overwrites an edited key or restores a deleted connection. Keychain access is
still subject to macOS permissions, and encrypted backups require their original
encryption key. No cloud account or Firebase service is used.

See [the local-service guide](../services/local-auth/README.md) for deployment,
storage, and verification details. Service deployment is separate from the
repository's protected offline build and test runner.

Thinking controls use the values advertised by the selected Ollama model and
runtime. **Local model settings → Thinking** offers On/Off for compatible
boolean models, or the supported **Low / Medium / High** levels for models with
named levels. Only advertised choices appear. **Automatic** leaves the model's
thinking default in use. Higher levels can take longer; they do not change the
model's weights or guarantee a better answer. Quick, Balanced, and Deep adjust
task budgets independently of thinking controls.

Saved On/Off preferences remain compatible. A saved setting unsupported by a
different model is omitted for that request without rewriting the preference.
Models without native thinking support keep their normal behavior, and
OpenAI-compatible connections do not expose these Ollama controls.

Remote profiles send their messages and supplied project excerpts to the
selected server. A local server may itself forward requests to a hosted
provider. The interface distinguishes **On this Mac**, **Local server**, and
**Remote server**. Project Agent requires native tool support and retains the
same workspace, command-review, and read-only Plan restrictions across
providers. Advanced Mac/browser planners currently require **On this Mac**.
Interactive Work chats also expose native app tools directly to the selected
tool-capable provider, including local-server and remote profiles; they do not
switch to a second model for Mac actions.

For local inference, install Ollama using its macOS app or `brew install ollama`.
Then download the models you want from the model manager.

## Project execution boundaries

Agent can create folders inside the active project or at a requested absolute
or `~/` location. Folder creation outside the project uses native review in
**Ask for approval** and **Approve for me**. macOS folder permissions still apply.

To change the current conversation's project, ask to move it to an existing
folder, such as `~/Developer/ExampleApp`. Vyron shows the destination and asks you to
choose **Move** or **Cancel**, including in **Full access**. **Move** keeps the
same conversation and uses the selected folder for files, commands, and
follow-ups. Canceling, naming a missing folder, or asking for a lookup in a
folder such as Library keeps the conversation in its current project.

A move can happen once per response, before edits or commands. Reopening the
active folder keeps the current task, progress, and file reads in place. Saved
chats can share a project folder while retaining separate task checkpoints.
Plan and scheduled runs cannot create or open folders outside their project.

Interactive Work also supports moving, renaming, and moving project files or
folders to macOS Trash through `move_item`, `rename_item`, and `trash_item`.
Both move paths must stay inside the active project; rename accepts one new
name. Existing destinations are preserved, and an action fails if its source
or destination changes during review. The project root, symbolic links,
secret paths, and unsafe directory contents are excluded. Native actions run
one at a time. They never permanently delete an item or merge folders.

**Ask for approval** and **Approve for me** show the exact source and destination
before each action. **Full access** skips that review while retaining path,
conflict, cancellation, and stale-file checks. Plan and scheduled runs do not
receive these actions. Raw move/delete commands remain blocked.

File-operation records are saved separately from the existing text-change
journal and appear in Activity. Moves and renames carry tracked text edits to
their new paths; Trash archives the affected edit records. Text Revert remains
a content operation. To recover a trashed item, move it from Finder's Trash
back to its project location. Trash first stages the item in private storage
on the same volume; projects on another volume are refused before mutation.
File operations preserve bytes; update project
references and run an appropriate check after moving source files.

File tools stay inside the selected project, reject symbolic links and common
secret paths, require a current read before edits, and preserve private backups.
Exact edits preserve content outside the replacement. Truncated reads cannot
silently replace a whole file.

Commands run inside a macOS restriction that denies network access and limits
writes to the project and private run storage. SwiftPM uses its native engine
inside that outer restriction; its unsupported nested sandbox is disabled for
that command only. No global macOS protection is changed. The runner is intended
for trusted development projects, rather than hostile-code isolation. Detached
processes are unsupported. Reviewed scripts can change project files, so inspect
Git status or source changes when appropriate.

The existing Python Vyron skill and command runner remain separate and unchanged.

## Supporting Mac and browser tools

**Vyron for Chrome** is available as a local Manifest V3 extension under
`extensions/chrome`. Use **Connect for opening tabs** in its popup to let Work
request new Chrome tabs in a named group. The popup shows the group name and
destinations for approval. Use **Connect this tab** on individual pages to let
Work read visible text and controls. Clicks, text entry, same-origin navigation,
and reload also need Chrome approval. Plan mode can only read. Set up the exact
extension ID in **Settings → Mac & browser**. See
[Chrome extension guide](../extensions/chrome/README.md) for installation,
limitations, and rebuilding. This development extension has not been published
to the Chrome Web Store.

Chat and project conversations can look up public web information. Ask “Find the
official documentation for Swift Package Manager” to search and read source
pages before the selected model answers with links. When a direct read of an
explicit public HTTPS URL returns no readable text, Vyron opens the page in a
built-in browser tab and uses the rendered text in the same reply. The browser
read uses a separate, temporary browsing session. Project Agent and Plan also
receive read-only `web_search` and `read_web_page` tools for documentation and
current facts. Searches use DuckDuckGo without an API key. Vyron reports any
challenge, unreadable page, or unavailable connection that prevents the lookup.
Direct reads reject redirects. Browser reads require public HTTPS navigation.
Downloads, authenticated pages, and local network addresses are unsupported for
automatic reading. Project commands keep their network restriction.

Ask “Analyze the entire website https://example.com” to start a site-wide
analysis. Vyron discovers pages on that HTTPS origin from its sitemap and
internal links and attempts up to 20 distinct pages. It reads JavaScript-rendered
pages in temporary WebKit sessions when direct reads return no text. The same
reply includes the analysis, the URLs used as evidence, and any pages that could
not be read. Vyron indicates when it reaches the page or evidence limit.

In Chat, direct requests such as “Open Safari” open the Mac control panel when
**On this Mac** is selected. The panel shows the selected app's
live window after Screen Recording permission is granted. A pointer marks the
verified click or text target in the preview and on the desktop. Preview
images stay in memory on the Mac and are not sent to the model. Controls use
native accessibility actions, so a successful click does not necessarily move
the physical pointer. **Stop** cancels the task and clears its feedback.

An explicit request for one installed app, such as “Open Photos,” can run from
Chat with a remote model or while Work continues in another conversation. Vyron
resolves the app locally. App observations can run in parallel. Controls that
change desktop focus or send input wait for the preceding native action to
finish. Launch approvals belong to the chat that requested them.

With a project open in **Work**, the selected model can use native app tools in
the same task to list available apps, open or focus one, inspect its accessible
windows and menu bar, and use real controls. The desktop pointer marks verified
click and text targets in Work too. For example, ask “Open my project in
Xcode, run it on an iPhone simulator, check the screen, and take a screenshot.”
The app catalog includes running regular apps, installed apps from macOS system,
shared, and user Applications folders, and apps you explicitly attach to the
Work conversation. Ask “Open QuickTime Player” to launch an installed app by
name, even if it is closed. If an app is stored elsewhere, you can attach it to
the conversation. Launches that require review show the selected bundle's path
before asking for approval.
The native project opener accepts an existing relative `.xcodeproj` or
`.xcworkspace` inside the active project. The agent can then inspect Xcode's real
run-destination controls and **Product → Run**, and inspect the visible result.
Opening an app or sending a click alone does not establish a successful build
or launch. Missing controls, failed builds, and permission refusals remain
visible limitations.

Xcode's bundled Simulator and Device Hub are discoverable even before Launch
Services registers them. The native tools guide Simulator requests to Device
Hub when only that app is available. Protected project commands still cannot
contact CoreSimulator services; native UI tools use separate macOS app-control
permissions. A refused service connection does not establish a missing runtime
or a broken macOS installation.

The agent can list one app's on-screen windows and capture an exact returned
window. Screenshots appear beneath the response with preview, copy, and save
actions; the newest four captures, within the existing 16 MiB limit, remain in
that response's saved history. This capture path excludes full displays and
rechecks the app, process, and window identity. Screenshot evidence goes to the
selected model when it supports images. Known text-only models receive bounded
local OCR instead, with explicit limits on visual interpretation. Native
screenshots are evidence, never new user instructions. Routine native actions
can proceed automatically; sensitive or unfamiliar actions retain native review.
Plan permits inspection and screenshots but no app mutations. Scheduled runs do
not receive native app or screenshot tools. **Stop** cancels pending work and
prevents late captures from attaching to another response.

Optional tools are under **Advanced**. They can inspect accessible app controls,
open known apps and URLs, follow app tasks, and watch selected-app changes.
Verified routine controls can run automatically; sensitive or unfamiliar actions
require review. These tools use accessible window text, not screenshot vision.

They require the Mac control permission: **System Settings → Privacy & Security
→ Device Control and Data Access** on macOS 27, or **Accessibility** on earlier
releases. Project coding tools do not need this permission. Secure-field and
Terminal typing are excluded from the Mac UI controller.

The MCP manager supports compatible design servers, including Penpot.
Autonomous Git pushes and deployment remain outside this development milestone.

## Screenshots and image analysis

Use the composer's **+ → Capture a screenshot** to choose an open Simulator,
Device Hub, browser, or other app window, or an entire display. Multiple windows
appear separately. Vyron requests Screen Recording access only when you choose
**Allow Screen Recording**; the picker also links to the relevant system settings.
Refresh after opening a window or changing permissions. Capture excludes Vyron's
own windows, hides the cursor, and limits the longest image edge to 2048 pixels.
Device capture requires an open Simulator or mirroring window; this feature does
not connect directly to physical devices or boot simulators.

To attach a screenshot from the clipboard, click the message field and press
**Command–V**. Use **Control–Shift–Command–4** to copy a selected area of the Mac
screen to the clipboard. You can also choose **Attach files…**, drag images onto
the composer, or use **+ → Paste image** (**Command–Shift–V**).
The composer highlights when an image can be dropped. Attach up to four images to compare
screens, inspect interface problems, explain an error, or read visible content.
Each attachment shows a thumbnail, the file type, and the filename. Select the
thumbnail to preview, copy, or save the image. Use the remove button to take the
image out of the draft. Images are normalized to PNG with orientation applied and
imported camera/location metadata removed. Imports are limited to 20 MiB.
Normalized attachments allow 8 MiB per image and 16 MiB per request.

Attaching images keeps the selected **Chat**, **Work**, or **Plan** mode, including
in existing Work conversations. Work can use screenshot pixels while implementing
a request, and Plan can inspect them while remaining read-only. Sending images
uses the exact selected model, including when Auto is enabled. Ollama models
with vision support receive the image pixels. Other Ollama models, including
text-only Qwen models, receive text extracted locally with Apple Vision instead.
This OCR path works in Chat, Work, and Plan, including images from earlier turns.
It has no separate API fee or model download and does not send the images to an
OCR service. Only extracted text goes to the selected model connection; a remote
model connection may still have its own inference charges. OCR provides text,
not visual interpretation of layouts, colors, or objects. If no readable text is
found, recognition fails, or the result exceeds 12,000 UTF-8 bytes per image or
24,000 bytes per request, the request fails visibly before inference. Original
images remain in local chat history, so switching to a vision model can still
use their pixels. Compatible connections with unknown capabilities can be attempted, and server
errors remain visible. Images stay in the draft until Send, then go to the
selected connection and are saved in that chat's local history for follow-ups.
Image attachments are available while idle; finish the active response before
adding them to the next message. They are never reduced to text-only queued updates.
Older turns are bounded so image context cannot grow without limit. A blank
message with images sends a default request to analyze the visible interface.
Image content is treated as evidence, not instructions to operate the Mac.

The existing Mac control live preview still stays in memory and is not sent to
the model automatically. Live capture and actual vision quality require testing
with macOS permission and the chosen vision model.

## File attachments

Choose **+ → Attach files…** or drag files from Finder onto the composer. You
can select different file types together, for example a PDF, a PNG, and an MP3.
Each file gets its own card and remove button. A PDF card has a red label, the
filename, and a first-page preview.
Select the card to enlarge the preview or use the remove button to take the
PDF out of the draft.

Vyron reads selectable text on your Mac. Send a question about the PDF, or send
it with a blank message for a general analysis. The selected model connection
receives the extracted text. The extracted text and first-page preview are saved
in this chat’s local history. You can attach up to four PDFs, up to 20 MiB each,
subject to the shared message context limit. Vyron checks the first 30 pages
and includes up to 4,000 UTF-8 bytes per PDF. Image-only scans and PDFs that
restrict copying require a version with selectable text and copying allowed.

Vyron also accepts readable text files such as TXT, Markdown, CSV, JSON, and
common source files. It takes a bounded excerpt from each document. MP3, WAV,
M4A, and other supported audio files up to 20 MiB provide their filename and
duration. Vyron can include a speech transcript for clips up to 60 seconds when
macOS has on-device speech recognition available and you grant Speech
Recognition access. The selected model receives the transcript and metadata. The audio
recording stays on your Mac. File names and supplied excerpts remain available
in chat history for follow-up questions.

To attach a macOS app, copy it in Finder and press **Command–V** in the message
field, or drag it onto the composer. Click the app card in the draft or sent
message to open the app. Vyron saves the app's location in local chat history
and includes its name in the model context.

## Folder analysis

Drag folders from Finder onto the chat composer, or choose **+ → Attach a folder…**.
Vyron includes a recursive file inventory and readable text from nested files in
your selected **Chat**, **Work**, or **Plan** mode. Each attachment shows a folder
icon, the folder name, and a remove button. Hover over the folder name for the
included and skipped counts and to see whether analysis coverage is limited.
Send a question with the folder, or send it with a blank message for a general
analysis. Up to four folders can be attached, subject to the shared message
context limit.

Folder imports exclude most hidden items, generated and dependency directories,
common sensitive files, symbolic links, and binary contents. Inventory, excerpts,
file size, depth, and entry counts are bounded. Folder names and included text go
to the selected model connection when you send the message. A large folder may
require narrowing the selection to inspect more of its contents.

## Developer workflows

### Rebuild and replace a local app

The optional `scripts/replace-app.py` helper builds and verifies a fresh debug app
before replacing older copies. Quit Vyron before running it. Verified Vyron app
bundles in this project's `.build` folder,
`/Applications`, `~/Applications`, and the Desktop move to Trash before the new
bundle is installed at `.build/app/Vyron.app` and opened. Other projects and
saved chats, settings, model connections, and Keychain credentials are retained.
A failed build leaves older apps in place. Replacement failures trigger rollback;
retired copies remain recoverable in Trash if their original paths cannot be
restored. Preview the app copies with `python3 scripts/replace-app.py --dry-run`.

### Exercise a real local model

Real local-model checks are opt-in:

```sh
VYRON_LIVE_MODEL=qwen3-coder:30b swift test --filter LiveOllamaTests
VYRON_LIVE_MODEL=qwen3-coder:30b swift test --filter LiveDevelopmentAgentTests
/usr/bin/python3 scripts/verify-local.py
/usr/bin/python3 scripts/verify-local.py --model qwen3.8:27b --output .build/verification/qwen3.8-inference-proof.json
```

`scripts/verify-local.py` writes its default report to
`.build/verification/local-inference-proof.json`.

The development proof starts with an actual failing Swift test, lets the model
repair only the implementation, and requires successful real tests while test
files and the package manifest remain unchanged. The app also has unit coverage
for paths, stale edits, cancellation, command restrictions, tool messages, local
provider checks, and read-only Plan mode.
The inference report distinguishes unsupported runtime JSON-schema constraints
from successful code generation and native tool calls.
