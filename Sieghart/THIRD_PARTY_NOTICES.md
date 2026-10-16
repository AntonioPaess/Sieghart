# Third-party notices

## Sprint 5 behavior reference

Vorssaint Utils source at commit `fe24c1766d568b132c1c78c554cc422381a3a17d` was inspected for folder/partial download events, bookmarked shelf references, Finder workflows, native matching-style paste and capture behavior. [Source repository](https://github.com/vorssaint/vorssaint-utils/tree/fe24c1766d568b132c1c78c554cc422381a3a17d), GPL-3.0-or-later. No Vorssaint source or assets were incorporated into these runtime modules. The local Apple/Darwin adapters were written for Sieghart. This is reference attribution, not a claim that GPL source is relicensed under the project's MIT license.

## Provider marks

OpenAI (used for Codex, matching the reference) and Claude SVG path artwork comes from [LobeHub Icons](https://github.com/lobehub/lobe-icons), package `@lobehub/icons-static-svg` version 1.90.0, retrieved October 5, 2026. These are library-supplied provider marks, not artwork authored by Sieghart.

Sources: [openai.svg](https://unpkg.com/@lobehub/icons-static-svg@1.90.0/icons/openai.svg), [claude.svg](https://unpkg.com/@lobehub/icons-static-svg@1.90.0/icons/claude.svg). Path geometry is unchanged; intrinsic dimensions and fill are adapted for the Xcode vector asset compiler.

Provider names and marks identify optional integrations. No affiliation or endorsement is implied.

```text
MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```


## Coucou chat and companion motion

October 14 Apple-agent follow-up: Ada's explicit GitHub PAT connection, service-data tool pattern and fixed PR/review/default-branch CI GraphQL field selection are adapted from Coucou's MIT `SettingsView`, `GithubPoller`, `GitHubPulse`, `VoiceDataSources` and `VoiceBrain.ServiceTool` at the same `71b773f08101237e1ec950efdaee17a626c830e6` commit. Copyright (c) 2026 Louis Raillé; the MIT text below applies. Sieg owns its credential namespace, bounded transport, connection UI and Apple 27 mode/eligibility layer. No Coucou credential or account is read.

October 14: the compact chat layout, message bubbles, card background, typing indicator, send-button geometry and Markdown parser/renderer are adapted directly from Coucou's MIT `PromptView`, `ChatBubble`, `CardBackground`, `TypingDotsView`, `SendButtonStyle`, `ChatMarkdown.swift` and `ChatMarkdownView.swift` at commit `71b773f08101237e1ec950efdaee17a626c830e6`. Copyright (c) 2026 Louis Raillé. The MIT text below applies to these portions as well as greeting timing. Sieg's Ada artwork, agent workstation drawing, native immediate-edit field and coding-runtime adapters are its own. No Mochi artwork, authored animation assets or sounds were copied.

October 13: Coucou's native PromptView/provider chat/stream throttling and separate hook-based session monitoring were also studied at `71b773f08101237e1ec950efdaee17a626c830e6`. The room state model, JSON-RPC transport and Claude SDK glue are independently authored and use Sieg artwork. The October 14 chat UI port is identified above.

October 13: Coucou's native file-drag/reveal/context workflow was also studied at commit `71b773f08101237e1ec950efdaee17a626c830e6`. Sieg's file-following receiver, own-body top intake and original-preserving bookmark admission were written for this app. No Mochi imagery, authored animation asset or audio was included; the existing source attribution below remains.

Portions of the greeting timing are adapted from Louis-CFM/coucou (commit 5cb2a27af352cf7319569920aac899efd42b54bc), under the MIT License. Character art and native 2.5D geometry are Sieghart originals. No Mochi artwork or audio is included.

```text
MIT License

Copyright (c) 2026 Louis Raillé

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```
