# Vyron for macOS

Vyron is a native AI workspace for macOS. Chat with a model running on your Mac
or connect to a provider of your choice. In a project, Vyron can inspect source
code, propose a plan, make scoped changes, and run local checks. The workspace
shows the edits, command output, and approval requests alongside the conversation.

**v0.1.0** is Vyron’s first public source release. It is an early preview for
macOS 14 and later, built with Swift 6, SwiftUI, and Swift Package Manager.

[Build from source](#build-from-source) · [First run](#first-run) ·
[Model connections](#model-connections) · [User guide](docs/user-guide.md) ·
[Contributing](#contributing) · [License](#license)

## What you can do

| Mode | Use it for |
| --- | --- |
| **Chat** | Ask questions, attach folders or screenshots, browse public web information, dictate a draft, or start a voice conversation. |
| **Work** | Open a project and ask the agent to read and edit files, use supported integrations, and run guarded local development commands. Review edits in **Changes** and command results in **Terminal**. |
| **Plan** | Turn on **Plan** in the Work model menu to inspect the project and draft an implementation plan. Project edits and commands are disabled in this mode. |

- **Manage project conversations.** Organize chats by project or sidebar section,
  keep work running while switching chats, and return to pending approvals or
  questions from the sidebar.
- **Use the browser in the workspace.** Open sites in WebKit tabs, save local
  notes, or ask for a bounded analysis of a public HTTPS site using its sitemap
  and internal links.
- **Extend Work.** Connect compatible MCP servers such as Penpot, use local
  skills, or enable the optional Chrome bridge for tabs you explicitly connect.
  On macOS, supported native controls let Work inspect app windows and capture
  visual evidence with the applicable system permissions.
- **Schedule recurring tasks.** Save one-time, daily, or weekly requests.
  Schedules run while Vyron is open and the Mac is awake.
- **Choose an interface language.** Use English, Turkish, Ukrainian, or the
  first supported language in your macOS preferences.

## Build from source

You need:

- macOS 14 or later.
- Xcode selected as your developer toolchain, with Swift 6 available.
- Python 3 and SwiftGen on your `PATH`. The app packaging script uses them
  to verify the checked-in resources.

Clone this repository, then run the following from its root.

```sh
swift --version
zsh scripts/build-app.sh debug
open .build/app/Vyron.app
```

The script builds both executables, copies their resources, and ad-hoc signs
the development bundle at `.build/app/Vyron.app`. The bundle registers
`vyron://` chat links and includes the macOS metadata used by voice and the
Chrome host. Open [Package.swift](Package.swift) in Xcode to work on the Swift
targets. The package has zero third-party Swift dependencies.

## First run

1. Launch Vyron and open **Manage Models…** in the model picker.
2. For local inference, install Ollama, choose **On this Mac**, and select
   **Start engine** if Ollama is stopped. Download or select a local model. For
   hosted inference, add a provider connection and test the selected model.
3. Send a message in **Chat** to check the connection.
4. Start a new conversation in **Work**, select a source folder, and ask
   Vyron to inspect the project. Enable **Plan** to start with a read-only
   request such as “Find the app entry point and propose a plan for adding a
   settings screen.”
5. In Work, use **Files**, **Changes**, **Activity**, and **Terminal** to
   inspect what the agent read, changed, and ran.

When you add a project, Vyron creates starter `AGENTS.md`, `README.md`,
`PLANS.md`, and `.gitignore` files where those paths are missing. It preserves
existing files. Work and Plan read bounded project guidance from a root
`AGENTS.override.md` or `AGENTS.md` file.

Long project prompts appear as a text attachment you can open and save from
the conversation. [Long project prompts](docs/user-guide.md#long-project-prompts)

## Model connections

| Connection | Setup |
| --- | --- |
| **On this Mac** | Install Ollama and choose an installed model. Vyron uses a loopback connection at `127.0.0.1:11434`. Initial model downloads require internet access. |
| **OpenAI, Claude, or DeepSeek** | Choose the provider preset in **Manage Models…**, supply your API key, and choose a model. |
| **Custom server** | Use **Add server URL** for a compatible Ollama, Anthropic, or OpenAI-compatible endpoint. Remote endpoints use HTTPS. HTTP is available for loopback connections. |

Use **Test response** or **Check model features** to check a connection. Work
requires a model with native tool support. Available context, thinking, tool,
and image capabilities depend on the selected provider and model.

See the [model connection guide](docs/user-guide.md#models-connections-and-storage)
for discovery, downloads, model parameters, and provider-specific behavior.

## Project access and data

- **Local storage.** Chats, saved model profiles, and edit history live under
  `~/Library/Application Support/VyronAI`. API keys are stored in macOS Keychain.
  Ollama model files use Ollama’s own storage.
- **Model requests.** If you choose a hosted model, its server receives the
  conversation and any project, image, or tool context supplied for the request.
  Public web lookup and configured MCP servers have their own network requests.
- **Project execution.** Work file tools enforce project boundaries and path
  checks. Guarded development commands run with restricted writes and network
  access denied. Other actions, including supported file moves and external
  tool calls, follow their own permission and review rules.
- **macOS permissions.** Voice, screenshots, and native app control use the
  applicable system permissions when invoked. Choose which windows or browser
  tabs to make available to the task.

## Optional integrations

| Integration | Setup |
| --- | --- |
| **MCP and Penpot** | Add a Streamable HTTP or local stdio connection in **Plugins**. Choose its tool permissions and review proposed writes. [MCP setup](docs/user-guide.md#mcp-connections-and-penpot) |
| **Vyron for Chrome** | Load the extension locally and register its exact ID with the native host. In Work, ask Vyron to open and group Chrome tabs or connect individual tabs for page access. Browser actions require approval in Chrome. [Extension setup](extensions/chrome/README.md) |
| **Local Office processing** | Use macOS PDF rendering or configure the optional Python-based Office engine for supported conversion and recalculation. [Office setup](docs/user-guide.md#local-office-processing) |
| **Local credential backup** | Run the optional loopback Docker service to store encrypted API-key backups. The encryption key stays in macOS Keychain. [Service setup](services/local-auth/README.md) |

## Repository layout

| Path | Responsibility |
| --- | --- |
| [Apps/Vyron](Apps/Vyron) | SwiftUI app, application composition, presentation state, and resources. |
| [Apps/VyronChromeHost](Apps/VyronChromeHost) | Native messaging executable packaged alongside Vyron. |
| [Packages/VyronCore](Packages/VyronCore) | Conversation and development workflow coordination, skills, web lookup, and scheduled tasks. |
| [Packages/VyronModelDomain](Packages/VyronModelDomain) and [Packages/VyronModelData](Packages/VyronModelData) | Model contracts, provider adapters, transport, and connection persistence. |
| [Packages/VyronDevelopment](Packages/VyronDevelopment), [Packages/VyronRuntime](Packages/VyronRuntime), and [Packages/VyronAutomation](Packages/VyronAutomation) | Project operations, Ollama runtime management, and automation infrastructure. |
| [Packages/VyronLocalization](Packages/VyronLocalization) and [Resources](Resources) | Shared localization resources, app bundle metadata, and app icon. |
| [Tests](Tests) and [scripts](scripts) | Swift tests, packaging, resource checks, and development utilities. |
| [extensions/chrome](extensions/chrome) and [services/local-auth](services/local-auth) | Optional browser extension and local credential-backup service. |

## Contributing

Keep changes focused and include the affected workflow, the reason for the
change, and the checks you ran. For bug reports, include the macOS version, Vyron
version, reproduction steps, and model or provider when relevant. Redact API
keys and private project content from logs and screenshots.

From the repository root, run the Swift suite and the localization checks.

```sh
swift test
python3 Apps/Vyron/Resources/generate_resources.py --check
python3 scripts/test-localization-resources.py
```

The app’s [String Catalog](Apps/Vyron/Resources/Localizable.xcstrings),
[SF Symbols manifest](Apps/Vyron/Resources/Symbols.json), and
[theme assets](Apps/Vyron/Resources/Theme.xcassets) are the sources for generated
resources. When editing those sources or their templates, run
`python3 Apps/Vyron/Resources/generate_resources.py` and include the generated
updates with the source change. The app packaging script checks resource
freshness before building.

See the [user guide](docs/user-guide.md) for the full feature reference, local
app replacement, and opt-in live-model verification.

## License

Vyron is released under the [MIT License](LICENSE).
