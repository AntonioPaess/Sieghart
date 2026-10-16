# OpenJarvis — assistant architecture reference

October 11, 2026. Additional reference suggested by the user. The project reviewed is [open-jarvis/OpenJarvis](https://github.com/open-jarvis/OpenJarvis). This records public documentation and selected source inspection; it is not an installed integration or a runtime validation.

## Confirmed in public material

- The repository publishes its source under [Apache 2.0](https://github.com/open-jarvis/OpenJarvis/blob/main/LICENSE).
- Its [architecture](https://open-jarvis.github.io/OpenJarvis/architecture/overview/) separates model/engine selection, agent execution, tools and memory, and learning/evaluation. It exposes a Python SDK and includes Rust components. Its orchestrator performs a tool-calling loop; scheduled agents retain state.
- The [tools guide](https://open-jarvis.github.io/OpenJarvis/user-guide/tools/) documents retrieval, memory storage/search, file access, web search, scheduling and an adapter for external MCP tools. A listed adapter is not proof that an arbitrary calendar/email account has been connected successfully.
- The [morning digest guide](https://open-jarvis.github.io/OpenJarvis/user-guide/morning-digest/) is a relevant reference for a finite briefing assembled from connected personal information and news. The availability and permissions of each source remain separate concerns.
- The [engine documentation](https://open-jarvis.github.io/OpenJarvis/architecture/engine/) includes multiple local backends and optional cloud routes, and describes energy measurement boundaries. Local execution depends on the chosen engine and configuration.

### Foundation Models already has a source adapter

The actual [apple_fm.py implementation](https://github.com/open-jarvis/OpenJarvis/blob/main/src/openjarvis/engine/apple_fm.py) imports `apple_fm_sdk`, registers an `afm` engine and implements model availability, preparation, streaming and shutdown. A separate shim exposes the model through a local HTTP API. The source documents Apple Silicon, macOS 26+, Apple Intelligence/model readiness and SDK prerequisites.

This makes it a useful lifecycle reference for Sieg's planned native Foundation Models adapter. It does not mean a Python implementation can be dropped into Swift, or that the adapter has been exercised on this Mac.

### Agent access is configurable

The [security guide](https://open-jarvis.github.io/OpenJarvis/user-guide/security/) distinguishes capability grants from action confirmations. Personal/default configuration keeps capability enforcement optional; shared/server profiles enable stricter defaults. These settings must be reviewed before reusing a runtime. The mere presence of a security module does not establish that a particular deployed configuration restricts every tool.

## Applying it to Sieg

Proposals only:

| OpenJarvis pattern | Sieg direction |
| --- | --- |
| Orchestrator plus selected tools | Sig identifies the requested outcome and delegates to the appropriate specialist; the active role receives only the relevant tools. |
| Persistent memory and task state | Keep useful preferences and a continuation point under user control; support viewing, editing and deleting retained information. |
| Scheduled, stateful work | Ada's chosen tech/AI briefing, Gantt's calendar check and other explicitly enabled routines share a bounded scheduler. |
| Engine interface and lifecycle | A shared engine protocol can use native Foundation Models first and optional other providers when selected. Model availability, cancellation, context limits and cleanup are explicit. |
| Execution traces and evaluation | Measure task completion, actual end-to-end latency, CPU/GPU, memory and energy. Report queued, working, waiting and completed states from real events. |
| External tools through MCP | A later integration layer can connect approved services independently of each avatar's appearance. |

Sieg's implementation remains organized in Features, Core and Shared. My recommendation is to keep the user experience and native services in Swift, use selected OpenJarvis patterns to guide the shared task engine, and evaluate an optional backend adapter separately if its capabilities justify the added runtime.

Specialist identity does not require six continuously active model processes. A user request can select instructions and tools for a role using the shared engine. The scheduling and model-residency policy needs measurements alongside the existing avatar CPU work.

## Boundaries and next study

- No installer, model download, backend, scheduler or microphone was run.
- No OpenJarvis source has been incorporated into the app.
- Foundation Models integration, memory semantics, cancellation and permission propagation still need tests before being promised as Sieg capabilities.
- The next focused source study should trace one complete request through the orchestrator, tool executor, stored task state and cancellation. Then compare those contracts with Sieg's existing native service interfaces.
- This reference does not change Sprint 5 acceptance or the mandatory offline Challenge demonstration.
