# Vyron local authentication

This optional local service keeps an **encrypted backup of model API keys** in a
persistent Docker volume. Vyron performs AES-256-GCM encryption and decryption;
the service stores only the combined nonce, ciphertext, and authentication tag.
It never receives an OpenAI API key in plaintext and never calls a model provider.

The native client authenticates automatically with a private bootstrap token.
This is local authentication for Vyron; it does not sign in to an OpenAI account,
claim subscription credits, or replace a provider's own API authorization.

## Setup

Use Python 3.9 or later and a running local Docker installation with Compose v2.17 or later.
The container uses the official `python:3.13-slim` image and only the Python
standard library. There are no pip packages to install.

From the repository root, explicitly start the service:

```sh
python3 scripts/local-auth.py start
```

`start` creates private configuration files if absent, builds the image, starts
the service, and waits for its health response. A valid configuration marker is
written before Docker starts, so an unavailable daemon remains visible to the
app as an unavailable configured service. Existing tokens and data are retained
if startup fails. Remote Docker hosts and contexts are rejected.

Other commands:

```sh
python3 scripts/local-auth.py setup
python3 scripts/local-auth.py status
python3 scripts/local-auth.py stop
python3 scripts/local-auth.py start --dry-run
```

`setup` creates configuration without starting Docker. `stop` stops the service
without removing its volume, token, or configuration. `--dry-run` validates paths
without writing files, reading existing token contents, contacting Docker, or
making network requests. `--data-dir /absolute/private/path` selects an isolated
configuration directory for tests or a deliberately separate setup; Vyron's
standard installation reads the default path below.

The helper prints status and locations, never token values. It uses the current
account's numeric UID/GID for the container, a read-only token bind mount, and an
absolute Compose file path. It does not rotate an existing token on an upgrade.

## Persistence and reinstall behavior

- Host configuration: `~/Library/Application Support/VyronAI/LocalAuth/config.json`.
- Host bootstrap token: `~/Library/Application Support/VyronAI/LocalAuth/bootstrap.token`.
- Both files are owner-only `0600`; their directory is `0700`. Symlinks, hardlinked
  files, unsafe ownership, and unexpected permissions are rejected.
- Docker volume: **`vyron-local-auth-data`**, mounted at `/data`. It contains the
  SQLite service identity, encrypted records, and revision tombstones.
- The encryption key stays in the macOS login Keychain. The bootstrap token and
  encryption key are different credentials.

Replacing or reinstalling `Vyron.app` leaves these locations intact. Preserve the
existing `VyronAI/model-connections.json` profile UUIDs, Keychain entries, host
token, and Docker volume. The service backs up credentials associated with those
UUIDs; it is not a backup of connection names, endpoints, chats, or project files.
Deleting the login Keychain/encryption key prevents decryption of existing backup
records. A client must fail closed in that case rather than overwrite old records
with a newly generated encryption key. No reset or volume-removal command is
provided by this helper.

## Local boundary

Compose publishes **`127.0.0.1:8327` only** on a small ingress gateway. The auth
backend stays exclusively on an **internal Docker network**, retaining its egress
isolation. The gateway connects that network to a separate ordinary bridge and
relays bytes only to the fixed `auth:8000` destination. A request URL, CONNECT
target, environment variable, or command argument cannot choose another target.
It has no token or data mounts, dependencies, request logging, or HTTP rewriting.

Both containers use the same Python image and run without root, capabilities,
Docker socket mounts, or writable root filesystems; `/tmp` is bounded temporary
storage. Only the backend receives the named data volume and read-only token
file. The service has no outbound API integration and emits no access logs,
request bodies, authorization headers, or database exception details.

This separate ingress is necessary because Docker does not publish ports for a
container attached exclusively to an internal network. The backend is not attached
to the ordinary bridge. See the [Docker maintainer explanation](https://github.com/moby/moby/discussions/53256#discussioncomment-15141564)
and [Docker bridge networking documentation](https://docs.docker.com/engine/network/drivers/bridge/).

Requests with `Origin` or `Referer` headers are rejected, including `Origin: null`.
There is no CORS allowance. Hostnames outside the fixed local published/internal
addresses are rejected. Redirects and proxy behavior are unnecessary for this
protocol. Local OS/Docker administrators can access local files and container
state; this design does not attempt to protect an already compromised account.

## Protocol, version 1

Authenticated requests use `Authorization: Bearer <bootstrap token>`. The token is
32 random bytes encoded as unpadded base64url (43 characters), compared in constant
time. The service accepts no credentials in a URL, cookie, or request body.

| Request | Result |
| --- | --- |
| `GET /health` | Public `status`, `service`, `schema_version`, and `version` metadata. |
| `GET /v1/session` | Authenticated `service`, `schema_version`, persistent UUID `instance_id`, and Boolean `has_encrypted_credentials`. Tombstones do not count as encrypted credentials. |
| `GET /v1/credentials/<UUID>` | `revision` and `encrypted_payload`. A never-created record returns `0` and `null`. |
| `PUT /v1/credentials/<UUID>` | JSON `{ "expected_revision": n, "encrypted_payload": "<standard base64>" }`; returns the new `revision`. |
| `DELETE /v1/credentials/<UUID>` | JSON `{ "expected_revision": n }`; returns the new `revision` and keeps a tombstone. |

UUID paths are canonical hyphenated UUIDs, with case normalized to lowercase.
PUT and DELETE require JSON content types and a known `Content-Length`; chunked
transfer and ambiguous duplicate framing headers are rejected. Encrypted payloads
must be canonical standard base64 containing 28–32,768 decoded bytes. The native
client uses AAD `vyron.credential.v1:<lowercase UUID>` for AES-GCM.

Writes use a SQLite transaction and compare the supplied revision atomically.
A stale mutation returns **409** without disclosing the current payload. DELETE
increments the revision even for an absent record, preventing an earlier
in-flight PUT from recreating that credential. Clients must not fetch a fresh
revision and blindly retry an old PUT: they must first recheck the current local
credential and mutation intent. Tombstones are retained across process restarts.

Limits: 256 records including tombstones; 45,056 body bytes; 32 headers totaling
8 KiB; 2 KiB per header/request line; 8 workers and a 16-request listen backlog;
5-second absolute request-read deadline and 5-second response-write timeout.
The ingress also caps each tunnel at 5 seconds, 55,296 request bytes, and 65,536
response bytes, reusing the 8-worker limit. Every HTTP response closes the connection
and uses noncacheable JSON. Storage failures and malformed requests produce fixed
error codes without echoing sensitive values.

## Offline verification

The unit tests exercise routes, authorization, framing limits, SQLite persistence,
concurrent CAS conflicts, tombstones, and isolated setup paths. They do not bind
ports, launch Docker, pull images, inspect real user tokens, or read Keychain data.
Run them through the repository's configured Vyron runner:

```text
python3 <absolute-vyron-runner> run --project <absolute-Vyron-macOS-root> -- python3 -m unittest discover -s services/local-auth/tests -v
```

Actual Docker startup, health, port binding, restart persistence, and native app
integration require a separate explicitly authorized runtime check.
