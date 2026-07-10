# Ad-hoc persona registry

Standing personas (Archie, Riku, Petra) live in `format.md`.
This file holds personas introduced ad-hoc in past meetings, available for re-onboarding across any project.

Registry personas are loaded at meeting start but onboarded only when the lens intersects the topic — or when a project override explicitly promotes them to standing (see `format.md` "Onboarding new personas per meeting").

Format: `- **Name** — one-sentence lens. Introduced YYYY-MM-DD (<project>/<meeting-slug>).`

---

- 🧠 **Mira** — multimodal ML lens; classifier cost, failure modes, privacy. Introduced 2026-05-08 (zkm/information-flow).
- 🗺️ **Flora** — information-flow architecture; content-type vs file-format, routing topology. Introduced 2026-05-08 (zkm/information-flow).
- ⚙️ **Sage** — skill-runtime lens; Claude Code skill mechanics, frontmatter, tool integration. Introduced 2026-05-08 (.claude/meeting-skill).
- 🔌 **Felix** — firmware/embedded lens; ESP-IDF, ESP-ADF/GMF, FreeRTOS, board bring-up, audio pipelines, abort triggers. Introduced 2026-05-08 (helferli/firmware-base).
- 📊 **Lexi** — Lean Six Sigma / DMAIC lens; Measurement System Analysis, coefficient of variation, control charts, process-quality estimation. Introduced 2026-05-08 (.claude/meeting-skill-v3).

- 🧬 **Nora** — IE / NER typology lens (schema.org / Wikidata entity-vs-value taxonomy, typed-slot extraction vs flat entities[]). Introduced 2026-05-12 (zkm/n9d-gate-c).

- 📬 **Pim** — Personal-info-management engineering lens (signature detection, quoted-reply stripping, structured email-client recipes; position-as-signal). Introduced 2026-05-12 (zkm/n9d-gate-c).

- 🗄️ **Cassi** — derived-data persistence / build-cache patterns: ccache/Nix/Bazel remote analogues, sharded-file vs fat-blob trade-offs, sync vs. backup separation. Introduced 2026-05-13 (zkm/derivable-expensive-data-in-git).

- 🎮 **Valve** — Steam/Proton platform lens; Steam runtime pipeline, shader pre-caching sequencing, Proton version mechanics, what Steam 'updates' actually touch. Introduced 2026-05-19 (zomni/dbh-startup-hang-workaround).

- 🎮 **Kira** — indie game design / visual novel lens; narrative branching, player agency, art direction, asset pipelines, gamedev-team handoff briefs. Introduced 2026-05-20 (meeting-rpg/meeting-rpg-vision-mvp).

- 🎨 **Vera** — creative frontend UX; TUI vs web rendering tradeoffs, typography, animation timing, audio integration, felt-experience quality judgements. Introduced 2026-05-20 (meeting-rpg/meeting-rpg-vision-mvp).

- 🌐 **Polly** — PWA / cross-platform web delivery + headless-test topology; browser-served frontends, mobile/responsive, service workers, Playwright/headless CI. Introduced 2026-05-21 (meeting-rpg/renderer-verdict-web-frontend-first).

- 🔧 **Quinn** — inference-server internals; llama.cpp/llama-server embedding mode, KV-cache, slot/sequence/batch management, pooling modes. Introduced 2026-05-21 (zkm/embed-rebuild-500).

- 🔐 **Dario** — E2E-encrypted PIM API reuse lens; DAV protocol constraints, Proton go-proton-api vs reinvention, write-path risk + rehearsal gates, CardDAV/CalDAV server topology. Introduced 2026-05-29 (proton-moresync/proton-moresync-scope-codereuse).

- 🔭 **Otto** — observability / measurement-without-perturbation lens; MITM-proxy mechanics, where ground truth lives, zero-perturbation instrumentation. Introduced 2026-06-03 (dotclaude-skills/llm-proxy-token-ctx-and-persona-split).

- 🎛️ **Orla** — multi-agent orchestration lens; fan-out topology, model-tier cost/capability economics, worktree-per-agent isolation, verification-before-merge gating. Introduced 2026-06-04 (dotclaude-skills/subagent-parallel-class1).

- 🧪 **Xander** — Intel GPU compute-stack lens: oneAPI/SYCL/Level-Zero, IPEX vs native torch-XPU vs OpenVINO, iGPU UMA shared-memory budgeting, install isolation (uv venv vs system packages). Introduced 2026-06-04 (zomni/intel-arc-xpu-local-sd).

- 🔩 **Gil** — git object-model / plumbing lens; index locking, hash-object/commit-tree/write-tree/update-ref CAS, GIT_INDEX_FILE isolation, ref reflog semantics, concurrent-commit integrity vs attribution hazards. Introduced 2026-06-04 (dotclaude-skills/worktree-per-session-d5).

- 🧠 **Mira** — multimodal ML lens; SD/CLIP token economics, img2img denoise tradeoffs, encoder failure modes, classifier cost and privacy. Introduced 2026-05-08 (zkm/information-flow); extended 2026-06-04 (meeting-rpg/portrait-clip-truncation-compute-r5).

- 🧩 **Memo** — agent-memory-systems lens; data model tradeoffs (peers/sessions/representations), LLM-deriver cost models, benchmark context (LongMem/LoCoMo), managed-vs-self-host risk surface, corpus-scale warranting thresholds. Introduced 2026-06-05 (dotclaude-skills/honcho-memory-eval).

- 🗺️ **Flora** — information-flow architecture; content-type vs file-format, routing topology, corpus classification, plugin routing. Introduced 2026-06-06 (zkm/zkm-claude-ai-claude-code-scoping).

- ⚖️ **Cleo** — data-acquisition legality / platform-ToS / third-party-privacy lens; single-subject vs bulk risk gradient, network-specific TOS analysis, privacy obligations when ingesting third-party data. Introduced 2026-06-06 (zkm/social-network-profile-scraping-scope).

- ⛓️ **Tycho** — Bitcoin signature-construction lens; BIP-322 to_spend/to_sign transaction building, BIP-341 (taproot) vs BIP-143 (segwit) sighash, witness encoding (SIGHASH_DEFAULT vs SIGHASH_ALL), what wallets actually sign. Introduced 2026-06-06 (zkWhale/s5-p2tr-bip322-sighash-mismatch).

- ⚙️ **Sage** — skill-runtime lens; Claude Code skill mechanics, frontmatter, tool integration, TSV contract design for skill-called scripts. Extended 2026-06-11 (dotclaude-skills/classify-gate-text-check): framed advisory-only constraint as collapsing downside of dumb detection; cited orphan-scan ADVISORY as the pattern precedent.

- ⚙️ **Sage** — skill-runtime lens; Claude Code skill mechanics, frontmatter, tool integration, TSV contract design, opencode command/tool/agent primitives. Extended 2026-06-11 (meeting-rpg/opencode-multi-tool-port): mapped Claude Code ↔ opencode primitive parity for meeting skill port.

- 🧪 **Mara** — meta-learning / learned-optimizer lens (L2O, MAML/hypernetworks, ES/PES, meta-gradient stability & truncation/chaos failure modes, coordinate-sharing). Introduced 2026-06-15 (leAIrn2learn/leairn2learn-learning-how-to-learn).

- 🧠 **Dax** — RL / neuromodulation / Hebbian-hormone lens (scalar-reward credit assignment & variance, three-factor rules, eligibility traces, backpropamine, online learning, async-SGD teacher-staleness). Introduced 2026-06-15 (leAIrn2learn/leairn2learn-learning-how-to-learn).

- 📐 **Della** — computational-geometry & raster↔vector fidelity lens; marching-squares/iso-extraction fidelity, polygon-clipping degeneracies, Douglas–Peucker error bounds, Minkowski/capsule-union robustness, self-intersection & fold handling. Introduced 2026-06-16 (isochrone/ratify-per-edge-time-producer-contract).

- 🎛️ **Orla** — multi-agent orchestration lens; fan-out topology, model-tier cost/capability economics, worktree-per-agent isolation, verification-before-merge gating, relay-fleet neediness triage. Introduced 2026-06-04 (dotclaude-skills/subagent-parallel-class1); extended 2026-06-16 (project_manager/proj-relay-integration): framed the relay cockpit as a pre-spend triage tool and dissolved the 'rows of dashes' concern by pointing to ROADMAP.md-gating as self-scoping.

- 🔎 **Dex** — compiler/static-analysis diagnostics + structured-text parser lens; undefined-vs-unused-vs-declared-free distinction, declaration scoping, reaching-definitions, diagnostic severity (ERROR/WARN); .mw parser brace-attribute grammar, fragment-type lowering design, open-enum link-type routing, fence-info-string attr extraction, Fragment handle semantics. Introduced 2026-06-16 (mathematical-writing/dangling-symbol-staleness); extended 2026-06-18 (toesnail/veq-macro-verify-carrier).

- 📈 **Milo** — quant-trading lens: backtest methodology, overfitting, transaction costs, statistical significance, exposure-adjustment. Insists objectives be operationalized so 'maximize money' doesn't become 'maximize activity'. Introduced 2026-06-12 (trAIdBTC/kickoff), registry 2026-06-16.

- 🔬 **Greta** — proof-engineering / formal-methods lens; what is mechanizable in a proof assistant, axiom hygiene (assume vs. prove), and the model-vs-deployed-artifact fidelity gap. Introduced 2026-06-16 (zkWhale/lean4-zk-formal-proofs).

- 🛠️ **Sven** — systemd --user units, .path/.timer edge-trigger semantics, keyring preconditions under the user session manager, oneshot restart behaviour. Introduced 2026-06-16 (zkm-whatsapp/w10-auto-decryption-install-readiness).

- 🔧 **Quinn** — inference-server internals lens; llama.cpp/llama-server mmap/warmup/mlock mechanics, KV-cache, cold-start latency decomposition (llama_load_s vs first_byte_s), /health poll patterns. Introduced 2026-06-16 (zelegator/fievel-cold-start-mitigation).

- 📊 **Cal** — probability-calibration / uncertainty-quantification lens; reliability curves, Beta-Binomial small-sample intervals, isotonic vs Platt, self-anchored-prior traps, calibrate-the-measurement-device framing. Introduced 2026-06-17 (chidiai/calibrated-credibility-decision-log).

- 🔬 **Lennart** — formal-methods / Lean4 + Mathlib proof ergonomics; sorry-driven and blackbox proof structuring; what symbolic/implementation/type-level tiers (SymPy/Nagini-CrossHair/Lean4) can each discharge; elaboration/kernel latency. Introduced 2026-06-15 (mathematical-writing/kickoff); re-onboarded 2026-06-17 (mathematical-writing/lean-smoke-slice).

- 🔭 **Otto** — observability/measurement-without-perturbation lens; MITM-proxy mechanics, ground-truth source identification, zero-perturbation instrumentation, three-axis session-transcript decomposition (context-depth / elapsed-wall-time / idle-gap) for discriminating long-context fatigue from wall-duration effects. Extended 2026-06-17 (dotclaude-skills/opus-degradation-investigation).

- ⚖️ **Cleo** — data-acquisition legality / platform-ToS / third-party-privacy lens; single-subject vs bulk risk gradient, network-specific TOS analysis, two-limb automated-access analysis (API-key limb vs explicit-permission limb in Consumer Terms §3), live-fetch-not-from-memory ToS reading pattern. Extended 2026-06-17 (dotclaude-skills/model-probe-tos-and-band).

- 📊 **Lexi** — Lean Six Sigma / DMAIC / SPC lens; Measurement System Analysis, control charts, pre-registration discipline (commit the formula not the number), small-n caveat (n=5 σ is garbage — start with a wide robust band), c-chart for pass/fail counts, individuals chart for throughput. Extended 2026-06-17 (dotclaude-skills/model-probe-tos-and-band).

- 🌐 **Edda** — Cloudflare edge / DNS / tunnel-topology lens; cert tiers (universal vs ACM), orange-cloud port restrictions, wildcard namespace ownership, tunnel-ingress routing. Introduced 2026-06-17 (zomni/zomni-local-port-routing-scheme).

- 🛡️ **Fenn** — host-firewall / attack-surface lens: default-deny vs denylist, fail-safe-off-LAN, SSH-lockout avoidance, per-network trust (home vs public WLAN), listening-port inventory as the design input. Introduced 2026-06-17 (zomni/zomni-firewall-public-wlan-hardening).

- ⚡ **Lana** — Lightning/L2-payments lens; LN invoice/LSP/custodial-vs-self-custody, Cashu mints, on-chain↔LN settlement latency, payment-rail trust assumptions (receiving is node-bound → cloud control-plane). Introduced 2026-06-17 (zkWhale/matt-donation-funnel-decisions).

- ⛓️ **Tycho** — Bitcoin signature-construction lens; BIP-322 to_spend/to_sign, BIP-341/BIP-143 sighash, what wallets actually sign. Re-onboarded 2026-06-17 (zkWhale/interactive-freshness-v1-scope): noted that since challenge_digest is a circuit public input, V1 interactive freshness is host-side only (zero circuit change); confirmed freshness is a property of the verification session, not the artifact.

- 🌐 **Polly** — PWA/web-delivery lens: theme persistence in service workers and CSS, SPA routing topology, build-mode vs runtime feature delivery, headless-test topology for PWA features. Introduced 2026-06-17 (zkWhale/dark-light-theme-moodboard-emoji-demo).

- 🎛️ **Orla** — multi-agent orchestration lens; fan-out topology, model-tier cost/capability economics, worktree-per-agent isolation, verification-before-merge gating, relay-fleet skeleton triage. Introduced 2026-06-04 (dotclaude-skills/subagent-parallel-class1); extended 2026-06-16 (project_manager/proj-relay-integration); extended 2026-06-18 (dotclaude-skills/relay-skeleton-token-reduction): identified thin-glue mechanization lever (shell-runner glue agents carrying fixed recipe prompts = biggest skeleton win) and push-seed discoverCache pattern; judged model-tier lever saturated (no haiku-ify integrator).

- 📐 **Della** — computational-geometry & raster↔vector fidelity lens; marching-squares/iso-extraction fidelity, polygon-clipping degeneracies, Douglas–Peucker error bounds, Minkowski/capsule-union robustness, self-intersection & fold handling, AABB label-collision geometry. Introduced 2026-06-16 (isochrone/ratify-per-edge-time-producer-contract); extended 2026-06-18 (isochrone/osm-overlay-stage-c-decompose): applied AABB overlap + greedy cull framing to label-collision geometry, including measureText stub test idiom.

- 🧮 **Reni** — multi-writer set merge / ref-counted retraction / provenance-ledger lens; CRDT-ish "observed set per producer", attribution-aware removal, idempotence-by-construction, lock discipline. Introduced 2026-06-18 (zkm/f103-tag-removal-core-semantic).

- 🕵️ **Priya** — private-information-retrieval / anonymity-set lens; PIR/ORAM practicality on a browser client, what leaks from CDN range/range-request access patterns, k-anonymity bucket sizing over a public dataset, two-anonymity-set separation (proof-set vs retrieval-set). Introduced 2026-06-21 (zkWhale/ring-coverage-investigation).

- 🎙️ **Aria** — speech-pipeline engineering lens; ASR backend selection (whisper.cpp /inference vs OpenAI-compatible vs audio-LLM), codec decode + ffmpeg resampling (8→16 kHz), VAD/noise gating, sha256-keyed transcription caching, segment-vs-word timestamps, diarisation. Introduced 2026-06-21 (zkm/zkm-stt-scope).

- 🔐 **Crys** — backup-crypto / KDF / keyring lens; SQLCipher DB keys, scrypt-derived backup passwords, OS-keyring (libsecret/KWallet) unwrap, the fetch-vs-parse decryption boundary (decrypt = out-of-band fetch step, plugin parses plaintext). Introduced 2026-06-22 (zkm/messenger-plugins-telegram-signal-threema).

- 📐 **Theo** — computational-geometry / lattices & honeycombs lens; space-filling polyhedra, Voronoi/BCC addressing, polytope subdivision (octant cuts via mirror planes), cross-section tilings (4.8.8 truncated-square), anisotropic neighbour metrics. Introduced 2026-06-22 (truncocraft/octant-split-foundation).

- 🧊 **Vox** — WebGL/three.js voxel-rendering lens; InstancedMesh vs per-block Mesh vs chunk greedy-mesh, draw-call budgeting, raycaster faceIndex→source-face mapping, BufferGeometry winding/normals, face culling. Introduced 2026-06-22 (truncocraft/octant-split-foundation).

- 🛡️ **Bastian** — web-exposure / deploy-boundary threat lens; what's reachable over :80, safe-vs-unsafe default for a new file (copy-allowlist vs path-whitelist), .git exposure, served-tree vs working-tree. Introduced 2026-06-23 (kienzler-homepage/data-boundary-audit).

- 🪟 **Winkler** — X11/EWMH window-management lens; multi-monitor reflow semantics, CRTC-removal eviction, devilspie2/xfwm4-rule limits, wmctrl/xdotool gravity + _NET_FRAME_EXTENTS quirks, autorandr postswitch hooks, maximized-window move semantics. Introduced 2026-06-23 (zomni/window-placement-dock-undock).

- 🛰️ **Hank** — host-fleet config-management lens; dotfiles/config topology, branch-per-host anti-pattern, hostname-dispatch, shared-module extraction (N=2 gate), NixOS/ansible/chezmoi patterns, system-vs-home tree separation. Introduced 2026-06-26 (zomni/consolidate-device-repos-monorepo).

- 💰 **Marisa** — game-monetisation & distribution economics lens; app-store (TWA/Capacitor, Apple 4.2, 15-30% cut) vs web-direct (merchant-of-record, VAT/sales-tax, ~85-97% kept), one-time-unlock vs subscription fit, entitlement-backend cost as the real monetisation precondition. Introduced 2026-06-29 (truncocraft/pwa-platform-commercialisation).

- 🔬 **Quill** — peer-reviewer / typologist lens: will this survive ACL/EMNLP review, is the claim defensible against reviewer-2, typological validity and confound-honesty. Introduced 2026-06-30 (linguistic-unversals/confound-control-sequencing).

- 🏷️ **Nomi** — naming & brand-linguistics lens; phonaesthetics, memorability, trademark distinctiveness (coinage vs genre-cliché suffixes), domain/handle availability, cross-language meaning/insult screening. Introduced 2026-06-30 (truncocraft/game-public-name-loderite).

- 🏔️ **Terra** — procedural terrain / landscape synthesis lens; midpoint displacement, value-noise, PCHIP silhouettes, deterministic pinned-seed (value-axis-anchored) roughness, honest data→terrain mapping (amplitude bounded by interpolation uncertainty). Introduced 2026-07-02 (whalemountain/whalemountain-wealth-mountainscape-design).

- 💼 **Bruno** — Swiss self-employment / social-insurance & RAV lens; AHV/IV/ALV, Zwischenverdienst declaration mechanics (hours↔income coupling), Schenkung/Zuwendung vs earned income, in-kind benefit valuation, Handelsregister threshold, Sallis/payroll-umbrella vs selbständig registration. Introduced 2026-07-03 (kienzler-homepage/zkwhale-financials-settlement-scrutiny).

- 🛡️ **Ivo** — OS privilege-separation lens; dedicated service users, userns/subuid, ACL vs group write-isolation, setgid dirs, DynamicUser/bubblewrap/firejail, what a separate uid actually buys vs a MAC layer ("a separate user is a sandbox only if the protected thing is not writable by that user — enumerate the write set first"). Introduced 2026-07-08 (dotclaude-skills/sandboxing-relay-os-users).

- 🏷️ **Nomi** — naming & brand-linguistics lens; phonaesthetics, memorability, trademark distinctiveness (coinage vs genre-cliché suffixes), domain/handle availability, cross-language meaning/insult screening. Introduced 2026-06-30 (truncocraft/game-public-name-loderite); extended 2026-07-10 (yinyang-puzzle/naming-round2-zetalith-loderix): lens now covers GAME-ITEM-database + mineral-database (mindat/IMA) screening, near-homograph detection as the top killer, the defensive-registration bill (typo / SI-prefix / foreign-rendering variants), and 'family is a convention, not a prefix' — a shared coined-mineralogy lore convention beats a sub-brand name-dependency on an uncleared sibling.

- 🔬 **Lennart** — formal-methods / Lean4 + Mathlib proof ergonomics; sorry-driven and blackbox proof structuring; what the symbolic/implementation/type-level tiers can each discharge; elaboration/kernel latency. Introduced 2026-06-15 (mathematical-writing/kickoff); extended 2026-07-10 (mathematical-writing/lean-toolchain-pin-ownership): lens now covers Lean TOOLCHAIN topology — a Mathlib consumer's `lean-toolchain` is determined by the pinned Mathlib rev (read `.lake/packages/mathlib/lean-toolchain`, never author it); elan handles multiple toolchains natively so per-repo pins are cheap; the static-link archive matrix (libgmp, +libuv on recent toolchains) varies by toolchain, so the repo shipping binaries owns that matrix.

- 🛰️ **Hank** — host-fleet config-management lens; dotfiles/config topology, branch-per-host anti-pattern, hostname-dispatch, shared-module extraction (N=2 gate), NixOS/ansible/chezmoi patterns, system-vs-home tree separation. Introduced 2026-06-26 (zomni/consolidate-device-repos-monorepo); extended 2026-07-10 (mathematical-writing/lean-toolchain-pin-ownership): lens now covers CACHE-vs-DERIVATION topology — separate 'who decides the value' from 'who stores it'; a per-repo file a tool requires (elan's `lean-toolchain`) is a cache of a derivation, not a decision, so the thing to forbid is a HAND-EDITED cache, not the cache itself; CoW reflinks are snapshots not live links, so a drift guard should compare a cache against its own local derivation source rather than against a sibling repo's cache.
