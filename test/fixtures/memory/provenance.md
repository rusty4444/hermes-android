# Server-produced memory API contract fixtures

These fixtures contain only synthetic facts and a synthetic skill created in an isolated scratch Hermes home. No production user memory, database, credentials, or config was read.

## Source and execution scope

- Installed Hermes Agent backend source (Git checkout; no source changes).
- Source Git HEAD: `d923a5eb487a17c0a68801bba9ef0f56c81040a8`; relevant source files were clean when inspected.
- Used the installed backend’s selected Python environment, not a system Python.
- The installed `hermes_cli.web_routers.status.router` GET APIRoute objects were mounted unchanged on a disposable FastAPI app and invoked with FastAPI/Starlette TestClient (in-process ASGI, no listener or running gateway).
- Actual handler identity was asserted against `get_learning_graph` and `get_learning_node`; real `scoped_to_thread`, `_profile_scope`, memory parsing, graph building, and `node_detail` ran unpatched.
- `HERMES_HOME` was set to a newly created scratch directory before every Hermes import; `HERMES_DISABLE_LAZY_INSTALLS=1` and bytecode writes were disabled. Environment variables were cleared before supplying the disposable home and minimal environment.
- An audit hook allowed SQLite only in the scratch tree and file reads only from scratch/fixtures, installed code, selected Python, and system timezone files; writes were allowed only under scratch/fixtures. Network connections, binds, DNS, and subprocesses were prohibited.
- Isolation audit: 25 denied system-probe/subprocess attempts; 0 SQLite connections. The only blocked probes were reads of `/proc/1/cgroup` and `/proc/self/mountinfo` and a `git rev-parse HEAD` subprocess. They were caught by installed backend code, and all requested routes still succeeded. Blocked attempts did not access user files or start processes; the source commit was independently verified with a read-only Git command outside the capture process.
- No optional packages were installed, no backend source was modified, and no responses were mocked or hand-amended. JSON files are the decoded real response bodies, pretty-printed only.
- Scope limit: these captures validate mounted dashboard handlers and serialization for the scratch current profile, not a live gateway, authentication middleware, named/multiplexed profiles, or Android transport/UI behavior.

### Exact installed source path exercised

- `hermes_cli/web_routers/status.py:677-692`: registered GET graph route -> real `scoped_to_thread` (`hermes_cli/web_routers/_common.py:40-47`) -> real `_profile_scope` (`hermes_cli/web_server_profiles.py:243-273`) -> `agent/learning_graph.py:218-255`.
- `hermes_cli/web_routers/status.py:704-708`: registered GET node route -> real `_learning_mutation` / `scoped_to_thread` -> `agent/learning_mutations.py:139-148` (full memory detail).
- The capture ran with `python -B -I` from a scratch-only generator and allocated a new disposable home on every execution. An independent second capture reproduced the JSON byte-for-byte. No machine-specific paths or production data are included in these fixtures.

## Requests and assertions

1. `GET /api/learning/graph` -> HTTP 200, JSON. Saved as `graph.json`; 4 saved facts (2 `memory`, 2 `profile`) and 1 genuine `kind: skill` node from disposable SKILL.md + usage metadata.
   - MEMORY.md: `The test workspace uses Dart.` plus the synthetic long fact.
   - USER.md: `User prefers concise replies.` and `User lives in Melbourne.`.
   - Files used the actual `\n§\n` delimiter and fixed input mtimes of 1700000000 for reproducibility.
   - Each memory node ID, global index, source, and full-entry SHA-256 fingerprint was asserted. Route output matched the real `agent.learning_graph.build_learning_graph()` under the real current-profile scope.
2. `GET /api/learning/node?id=memory:memory:1:efe23fed20c4` -> HTTP 200. Saved as `long_fact.json`; exact full content equals the synthetic input and real `agent.learning_mutations.node_detail()` result.
   - Long fact: 1462 ASCII codepoints; graph body: 1200 codepoints; full detail retains `END_ANDROID_MEMORY_FIXTURE`, which the graph preview omits.
3. `GET /api/learning/node?id=<server-returned profile node ID>` -> HTTP 200 for both profile facts. Full content matched the seeded input. USER.md node IDs use global indices 2 and 3.
4. Removed only disposable MEMORY.md and USER.md, then `GET /api/learning/graph` -> HTTP 200. Saved as `empty_graph.json`; `memory: []`, 0 memory nodes, 1 unchanged skill node.

The name `empty_graph.json` means **no saved facts**, not no skill nodes: Android must not display the retained skill as a memory fact.

## Legacy positional-ID regression

`legacy_graph.json` comes from the historical pre-fingerprint graph builder and
contains two synthetic facts with the same 1,200-code-point preview but different
suffixes. `shifted_legacy_detail.json` is the real installed full-node HTTP
response after the first disposable fact was removed: the old positional ID now
resolves to the second fact. The same removal makes the fingerprinted identity
return HTTP 404 instead. These fixtures were generated in the same kind of
isolated scratch home, without real user data or authentication middleware.

The Android regression requires refusing a full read for the unhashed identity
before any detail GET. Matching the preview prefix alone is not identity proof.
The UI retains the preview with an update notice and no unsafe expansion action.

## Source SHA-256

- `hermes_cli/web_routers/status.py`: `15817402186f010fba182518ff5569700d84ac6437860cb9575465346283ba55`
- `hermes_cli/web_routers/_common.py`: `c92a6cb2c8e84461e77ffd550204895d76b3ae1b7e797e09bc113bddc3c29942`
- `hermes_cli/web_server_profiles.py`: `d5a8fdd14de5ad5ce88ab263fc1068bebf2e1692d5a06c8f4f7af6b2024c54b8`
- `agent/learning_graph.py`: `c60d99eb9c633624ec7566f19ff9367ea909173d7dd091617f95bd12d4f0df03`
- `agent/learning_mutations.py`: `744d4683b6d5019ca254c27bd1a56626fabf2a476cd8b59c1084056d0d0f1efa`
- `tools/memory_tool.py`: `3ac1975d5d34a8e0fd20ea538aa084fc48c5ba21e8b2da4f97f58a7bf3cafaab`
- `tools/memory_tool_store.py`: `3280e2294928815ab2dd52479c5616aee805e27819b901f9af40831a293728c6`
- `tools/skill_usage.py`: `3777d9dff05df654ba054bb8fbd77ee46bb630b9f423efa09bd24e984ee3151e`
- `agent/skill_utils.py`: `fbf04204de0e7ab29e694aea2b099f971955e94223866b8abee545855eb2d3d0`
- `hermes_constants.py`: `8d55a41452b625061f1f2e2f507a7e7ffb2a396e711afcc7aee28b03a6e8fa9d`
