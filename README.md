# Debris

A desktop client for exploring **MongoDB** databases and **Rocket.Chat** REST
APIs side by side, modeled on the workflow of the old [Robo3T](https://github.com/Studio3T/robomongo)
Mongo client. It pairs a connection/endpoint sidebar with a tabbed workspace: a
code editor on top, results below, toggleable between **Tree**, **Table**, and
**Text (JSON)** views.

The app is built with [Godot 4.7](https://godotengine.org/) (GL Compatibility
renderer) and talks to MongoDB through a small bundled [Fastify](https://fastify.dev/)
proxy server it launches for you.

## Screenshots

**Browsing a MongoDB collection** — the connection sidebar (databases ▸
collections) on the left, a query tab with a JSON filter editor over a results
tree on the right.

![Database browser](docs/screenshots/database.png)

**Browsing a Rocket.Chat REST API** — the endpoint sidebar (grouped by resource,
driven by the server's OpenAPI spec), a per-endpoint request form with a user
selector, and the response.

![API browser](docs/screenshots/api.png)

## What it's good for

Debris grew out of everyday debugging — the kind where you bounce between a
database and an API and back, repeating the same fiddly steps. A few workflows it
is built to make painless:

- **Following an ID across collections.** Debugging often means pulling an
  identifier out of one document and looking it up in another, over and over.
  Right-click a record and jump straight to the linked records in other
  collections, instead of copying IDs by hand each time.
- **A database and an API, side by side.** Grab a value from a live document and
  fire an API call with it without juggling windows. This matters most when
  timing does — e.g. prepare a request in advance, read an ID off a record the
  moment it appears (while a call is still ringing), and send, all in one place,
  rather than shuttling between a Mongo client and a separate API tool.
- **Testing an API as different users.** Rather than pasting a permanent auth
  token into Swagger, Debris retrieves the token for you from a saved password.
  Calling the same endpoint as several users — or as no user at all, to confirm
  auth is actually being enforced — is a quick switch, so comparing responses is
  trivial.

## Concepts

Debris is a **document-based** app. You work in **projects** — a project is a
file (`.debris-project`) that optionally binds:

- **≤ 1 MongoDB database**, and
- **≤ 1 Rocket.Chat API**.

Both are optional; a project can have either, both, or neither. Keeping a database
and an API in the same project is what links them: a value in an API response can
open a matching MongoDB query in a sibling tab, with no cross-project plumbing.

A left-hand **activity bar** switches the sidebar between the project's views:
**Collections** (when a DB is attached), and **Endpoints** + **Users** (when an
API is attached). All open query and endpoint tabs share one tab strip.

Projects can be saved anywhere or kept memory-only as *Untitled*. Alongside a
saved project, Debris writes a per-user `.debris-workspace` sidecar (git-ignored)
holding your open tabs and an offline cache of the API's endpoint list, so
reopening the project restores your workspace.

## Repository layout

```
client/      Godot 4.7 project — the desktop app (GDScript, source/ui + source/data)
  server/    the bundled server, embedded into the app (produced by `yarn bundle`)
  dev/       headless validation kit (compile checks, mocked harness, fixtures)
  test/      logic-layer unit tests (addon-free runner)
server/      Node/TypeScript source for the MongoDB proxy server
docs/        screenshots and other documentation assets
```

The **server** is a stateless HTTP proxy: every request carries its own MongoDB
connection details, it runs the operation, and returns the result — nothing is
stored server-side. It exposes `GET /health` plus `POST /api/*` operations
(`ping`, `databases`, `collections`, `find`, `findOne`, `count`, `explain`,
`listIndexes`, `aggregate`, `insert`, `update`, `delete`, `command`). The client
never speaks the MongoDB wire protocol itself. Rocket.Chat, by contrast, is
called directly over its REST API by the client.

## Getting started

### Prerequisites

- **[Godot 4.7](https://godotengine.org/download)** (standard, non-.NET build) —
  to run or edit the client from source.
- **[Node.js](https://nodejs.org/) 20+** — required at runtime: the app launches
  the bundled server with `node`. If Node isn't found the app still runs, but
  MongoDB features stay offline until you start a server yourself.
- **[Yarn](https://yarnpkg.com/) 4** — only needed to build the server bundle
  from source.

### 1. Build the server bundle

The client runs a single-file server bundle it carries at
`client/server/debris-server.cjs`. Rebuild it from the TypeScript source with:

```bash
cd server
yarn install
yarn bundle
```

`yarn bundle` writes the bundled server into the client project so it can be
embedded in the app. (For working on the server on its own, `yarn dev` runs it in
watch mode and `yarn build` compiles to `dist/`.)

### 2. Run the client

Open the `client/` folder in the Godot editor and press **Play**, or run it
headless-free from the command line:

```bash
godot --path client
```

On launch the app checks whether a server is already answering at
`http://127.0.0.1:4020`; if not, it locates `node`, extracts the bundled server,
and starts it as a **quiet background process** (no console window). While the
app runs it heartbeats the server every 30s and sends a disconnect on close, so
the server knows who is connected. A server the app launched stops itself once
the last connected app goes away (so runs never leave an orphaned server behind);
a server you started by hand keeps running and is simply reused.

Useful environment overrides:

| Variable            | Purpose                                              |
| ------------------- | ---------------------------------------------------- |
| `DEBRIS_NODE`       | Path to a specific `node` binary.                    |
| `DEBRIS_SERVER_URL` | Point the client at an already-running server.       |
| `PORT` / `HOST`     | Where the server listens (default `4020` / `127.0.0.1`). |

## Using the app

1. **Create a project** — *New Project* on the start screen (or `File ▸ New
   Project`).
2. **Attach a source** — use the activity-bar icons or `File ▸ Attach Database…`
   / `Attach API…`.
   - *Database*: enter the MongoDB `host:port` (and optional auth), then pick a
     database.
   - *API*: enter the Rocket.Chat server URL. Add login users in the **Users**
     view.
3. **Query MongoDB** — click a collection to open a query tab, edit the JSON
   filter, choose an operation (`find`, `countDocuments`, `explain`,
   `listIndexes`, `findOne`), and press **Run**. Right-click a document for
   View / Edit / Insert / Delete.
4. **Call the API** — click an endpoint to open a request tab, pick the user to
   authenticate as, fill the parameter form (or switch to the raw-JSON editor),
   and press **Send**.
5. **Save** — `File ▸ Save Project` writes a `.debris-project` file; your open
   tabs are remembered next to it.

### Keyboard shortcuts

| Action                          | Shortcut                          |
| ------------------------------- | --------------------------------- |
| New / Open / Save / Save As     | `Ctrl/Cmd` + `N` / `O` / `S` / `Shift+S` |
| Run the active tab              | `F5` or `Ctrl/Cmd` + `Enter`      |
| Switch sidebar view (Collections / Endpoints / Users) | `Alt` + `1` / `2` / `3` |
| Jump to inner tab _n_ (`9` = last) | `Ctrl/Cmd` + `1`…`9`           |
| Cycle inner tabs                | `Ctrl` + `Tab` / `PageUp` / `PageDown` |
| Close the active tab            | `Ctrl/Cmd` + `W`                  |
| Quit                            | `Ctrl/Cmd` + `Q`                  |

## Development

The client ships with a headless validation kit (see
[`client/dev/README.md`](client/dev/README.md)) that runs without the editor and
against mocked servers — so logic changes can be checked deterministically.

```bash
cd client
dev/check.sh source/data/*.gd          # fast GDScript compile/type check
dev/harness.sh dev/checks/mock_smoke_check.gd   # boot headless against mocks
test/run.sh                            # logic-layer unit tests
```

The scripts invoke `godot` from your `PATH`; override with `GODOT=/path/to/godot`
if your binary is named or located differently.

For the server:

```bash
cd server
yarn typecheck    # tsc --noEmit
yarn build        # compile to dist/
```

## License

MIT.
