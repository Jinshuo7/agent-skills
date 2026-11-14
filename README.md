# Agent Skills

A working library of agent skills, published so other agents and people can read and
learn from it. **This repository is generated** — it is mirrored from a private library
on every change. Pull requests here will be overwritten; open an issue instead.

**167 skills.** Each top-level directory is one skill: a `SKILL.md` with YAML
frontmatter (`name`, `description`) plus whatever resources it needs.

## How to consume this

```bash
git clone https://github.com/Jinshuo7/agent-skills.git
```

Then point your agent at the directory, or copy the individual skill folders you want.
Skills are self-contained: read `SKILL.md` first, follow its references.

These are written for specific harnesses (Claude Code, Codex, DeepSeek Harness, Pi),
but the format is generic Markdown — any agent that can read files can use them.

## Index

| Skill | Description |
|---|---|
| [`accessibility`](./accessibility/) | Audit and improve web accessibility following WCAG 2.2 guidelines. Use when asked to "improve accessibility", "a11y audit", "WCAG compliance", "screen reader... |
| [`agent-browser`](./agent-browser/) | Browser automation CLI for AI agents. Use when the user needs to interact with websites, including navigating pages, filling forms, clicking buttons, taking... |
| [`algorithmic-art`](./algorithmic-art/) | Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, gener... |
| [`api-and-interface-design`](./api-and-interface-design/) | Guides stable API and interface design. Use when designing APIs, module boundaries, or any public interface. Use when creating REST or GraphQL endpoints, def... |
| [`app-store-review`](./app-store-review/) | Evaluates code against Apple's App Store Review Guidelines. Use this skill when reviewing iOS, macOS, tvOS, watchOS, or visionOS app code (Swift, Objective-C... |
| [`apple-design`](./apple-design/) | > |
| [`architect`](./architect/) | Sketch types, signatures, and module structure before code, then stay in the loop while implementation fills in. Use for /architect, 'architect this', 'desig... |
| [`arena`](./arena/) | Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /arena, 'arena this', 'throw it in the ar... |
| [`ask-matt`](./ask-matt/) | Ask which skill or flow fits your situation. A router over the skills in this repo. |
| [`automate-me`](./automate-me/) | Use for \"automate me\", \"create/update/refresh my -mode skill\", \"turn/capture my preferences or working style into a skill\", or wanting agents to follow... |
| [`bambu-print-handoff`](./bambu-print-handoff/) | Hand a 3D print job to BambuStudio on this Mac — unpack the archive, open the parts, flag plate-fit and orientation problems, then stop at the slicer. Use wh... |
| [`benchmark-checklist`](./benchmark-checklist/) | Vet a perf measurement (limiter, tuning, limits, errors, repeatability, relevance, and whether the work happened) before you report or act on it. Use when yo... |
| [`best-practices`](./best-practices/) | Apply modern web development best practices for security, compatibility, and code quality. Use when asked to "apply best practices", "security audit", "moder... |
| [`blast-radius`](./blast-radius/) | Find what a change could break somewhere else before it ships, beyond the diff, and prove the one fact it's safe because of by running real code instead of w... |
| [`bro`](./bro/) | Restate the last message in plain human language, with no jargon. |
| [`browser-testing-with-devtools`](./browser-testing-with-devtools/) | Tests in real browsers via Chrome DevTools MCP. Use when building or debugging anything that runs in a browser. Use when you need to inspect the DOM, capture... |
| [`canvas-design`](./canvas-design/) | Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art... |
| [`castkit-v1`](./castkit-v1/) | Castkit v1 — character builder. A skill made by Joey. Builds reusable character reference images, photoreal or animated, for Nano Banana Pro and other image... |
| [`chrome-devtools-axi`](./chrome-devtools-axi/) | Control a Chrome browser session through the chrome-devtools-axi CLI - navigate, snapshot, click, fill forms, run JavaScript, inspect console and network, ta... |
| [`ci-cd-and-automation`](./ci-cd-and-automation/) | Automates CI/CD pipeline setup. Use when setting up or modifying build and deployment pipelines. Use when you need to automate quality gates, configure test... |
| [`code-review`](./code-review/) | Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding sta... |
| [`code-review-and-quality`](./code-review-and-quality/) | Conducts multi-axis code review. Use before merging any change. Use when reviewing code written by yourself, another agent, or a human. Use when you need to... |
| [`code-simplification`](./code-simplification/) | Simplifies code for clarity. Use when refactoring code for clarity without changing behavior. Use when code works but is harder to read, maintain, or extend... |
| [`codebase-design`](./codebase-design/) | Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a... |
| [`constraint-driven-development`](./constraint-driven-development/) | Establishes a project's quality bar as a written contract and stops agents quietly lowering it. Interviews the user on which dimensions matter, supplies sane... |
| [`context-engineering`](./context-engineering/) | Optimizes agent context setup. Use when starting a new session, when agent output quality degrades, when switching between tasks, or when you need to configu... |
| [`core-web-vitals`](./core-web-vitals/) | Optimize Core Web Vitals (LCP, INP, CLS) for better page experience using field and lab evidence. Use when asked to "improve Core Web Vitals", "fix LCP", "re... |
| [`correct`](./correct/) | Find the mistakes agents keep repeating in this repo and make each one impossible. Try architecture first, then types, then a lint whose error names the fix,... |
| [`create-formal-verification-skill`](./create-formal-verification-skill/) | Generate a project-local skill that formally verifies the code where a bug costs the most and tests reach the least, in any language, with whichever verifica... |
| [`create-verification-skill`](./create-verification-skill/) | Generate a project-local verification skill that drives your app the way a user does — any language, framework, or platform. Use for /create-verification-ski... |
| [`debugging-and-error-recovery`](./debugging-and-error-recovery/) | Guides systematic root-cause debugging. Use when tests fail, builds break, something that worked yesterday broke, behavior doesn't match expectations, or you... |
| [`deprecation-and-migration`](./deprecation-and-migration/) | Manages deprecation and migration. Use when removing old systems, APIs, or features. Use when migrating users from one implementation to another. Use when mi... |
| [`diagnosing-bugs`](./diagnosing-bugs/) | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. |
| [`documentation-and-adrs`](./documentation-and-adrs/) | Records decisions and documentation. Use when you need to document an architecture decision (ADR) or the reasoning behind a design choice, when changing publ... |
| [`domain-modeling`](./domain-modeling/) | Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a GLOSSARY.md, or recording or editing an ADR. |
| [`doubt-driven-development`](./doubt-driven-development/) | Subjects every non-trivial decision to a fresh-context adversarial review before it stands. Use when you want every assumption cross-examined before proceedi... |
| [`factory-setup`](./factory-setup/) | Set up or re-tune a software project's agent team from the person's own tools, plans and preferences. Use when they start a new project, run /factory-setup,... |
| [`figma`](./figma/) | Bring Figma into a HyperFrames video - rendered assets, brand tokens, components, storyboard frames as reconstructed motion (frames read as states, not slide... |
| [`figure-it-out`](./figure-it-out/) | Design an auditable playbook when no narrower one fits: a large migration, an ambitious multi-part change, or work a human reviews after stepping away. Scale... |
| [`find-skills`](./find-skills/) | Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express... |
| [`frontend-design`](./frontend-design/) | Guidance for distinctive, intentional visual design when building new UI or reshaping an existing one. Helps with aesthetic direction, typography, and making... |
| [`frontend-ui-engineering`](./frontend-ui-engineering/) | Builds production-quality, accessible, responsive user-facing UIs. Use when building or modifying interfaces and pages, creating components, implementing lay... |
| [`gh-axi`](./gh-axi/) | Operate GitHub through the gh-axi CLI - issues, pull requests, discussions, stacked PRs, workflow runs, workflows, releases, repositories, labels, gists, Pro... |
| [`git-workflow-and-versioning`](./git-workflow-and-versioning/) | Structures git workflow practices. Use when making any code change. Use when committing, branching, resolving conflicts, splitting uncommitted work in a mess... |
| [`grill-me`](./grill-me/) | A relentless interview to sharpen a plan or design. |
| [`grill-with-docs`](./grill-with-docs/) | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| [`grilling`](./grilling/) | Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. |
| [`handoff`](./handoff/) | Compact the current conversation into a handoff document for another agent to pick up. |
| [`herdr`](./herdr/) | Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, t... |
| [`how`](./how/) | Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which... |
| [`humanizer-zh`](./humanizer-zh/) | 编辑中文文章、评论和文档中的空话、重复及模板化表达，让文字更自然，同时保留事实、确定程度和作者声音。适用于润色已有文本，不用于判断作者身份或保证通过 AI 检测器。 |
| [`hyperframes`](./hyperframes/) | Read first to make, edit, animate or render any video with HyperFrames (HTML rendered to video), including launch films, explainers, music videos, charts, ma... |
| [`hyperframes-cli`](./hyperframes-cli/) | HyperFrames CLI - scaffold, check frames, edit timelines, preview, render, share and project history; read JSON and recover from failures. |
| [`hyperframes-registry`](./hyperframes-registry/) | About 450 ready-made HyperFrames blocks and components installed as editable source - transitions, overlays, titles, kinetic type, captions, charts, map over... |
| [`idea-refine`](./idea-refine/) | Refines raw ideas into sharp, actionable concepts through structured divergent and convergent thinking. Use when an idea is still vague, when you need to str... |
| [`impeccable`](./impeccable/) | Use when the user wants to design, redesign, shape, critique, audit, polish, simplify, harden, animate, or otherwise improve a frontend interface: websites,... |
| [`implement`](./implement/) | Implement a piece of work based on a spec or set of tickets. |
| [`implement-spec`](./implement-spec/) | Implement the result of /to-spec and /to-tickets in code. |
| [`improve-codebase-architecture`](./improve-codebase-architecture/) | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| [`in-your-own-words`](./in-your-own-words/) | Restate in your own words what you think the user's goals are and what problem they're trying to solve. Use for /in-your-own-words. |
| [`incremental-implementation`](./incremental-implementation/) | Delivers changes incrementally in thin, verifiable slices. Use when implementing any feature or change that touches more than one file, or when picking up th... |
| [`interrogate`](./interrogate/) | Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this... |
| [`interview-me`](./interview-me/) | Extracts what the user actually wants instead of what they think they should want. Achieves this through one-question-at-a-time interview until ~95% confiden... |
| [`ios-simulator`](./ios-simulator/) | Manages iOS Simulator devices and app tests with xcrun simctl: lifecycle, install/launch, push and location simulation, privacy permissions, deep links, stat... |
| [`ketchup`](./ketchup/) | Catch the user up on what changed in this chat since their last message, in plain words and small visuals. List every item waiting on them with what they nee... |
| [`lavish`](./lavish/) | Turn complex or visual agent responses into rich, reviewable HTML artifacts (HTML files) the user can annotate and send feedback on, using the lavish-axi CLI... |
| [`loop-me`](./loop-me/) | Grill me about specs for the workflows I want to build, within this workspace. |
| [`maintain-formal-verification-skill`](./maintain-formal-verification-skill/) | Bring a project's formal verification back in line with the code after the code changes: find the commits that touched verified code, update the model, harne... |
| [`maintain-verification-skill`](./maintain-verification-skill/) | Periodic pass that keeps a project's verification skill and feature map honest: parallel source readers per feature, one live session driving every feature,... |
| [`make-bot-ui`](./make-bot-ui/) | >- |
| [`manage-skills`](./manage-skills/) | Manage the user's shared agent-skill library via skills-manager-cli — install, update, remove, deploy or undeploy skills per agent or into a project's own ag... |
| [`media-use`](./media-use/) | Get or make any media for a HyperFrames video - music, sound effects, images, icons, logos, voiceover, avatar and generated video, transcripts, cutouts, colo... |
| [`migrate-to-shoehorn`](./migrate-to-shoehorn/) | Migrate test files from `as` type assertions to @total-typescript/shoehorn. Use when user mentions shoehorn, wants to replace `as` in tests, or needs partial... |
| [`mobilebuildmcp`](./mobilebuildmcp/) | Official skill for MobileBuildMCP. Use when doing iOS/macOS/watchOS/tvOS/visionOS work (build, test, run, debug, log, UI automation). |
| [`motiondojo-v1`](./motiondojo-v1/) | Motiondojo v1 — motion transfer prompt director for Higgsfield Genjutsu. A skill made by Joey. Writes lean Genjutsu prompts that take the movement from an at... |
| [`no-comments`](./no-comments/) | Spawn Comment Sicko, fix accepted findings, and offer encodings for claimed constraints. |
| [`no-mistakes`](./no-mistakes/) | Validate your code changes through the no-mistakes pipeline - automated code review, tests, lint, docs, push, PR, and CI - before they reach the configured p... |
| [`observability-and-instrumentation`](./observability-and-instrumentation/) | Instruments code so production behavior is visible and diagnosable. Use when adding logging, metrics, tracing, or alerting. Use when shipping any feature tha... |
| [`performance`](./performance/) | Optimize web performance for faster loading and better user experience. Use when asked to "speed up my site", "optimize performance", "reduce load time", "fi... |
| [`performance-optimization`](./performance-optimization/) | Optimizes application performance across frontend, backend, queries, and databases. Use when performance requirements exist, when you suspect performance reg... |
| [`planning-and-task-breakdown`](./planning-and-task-breakdown/) | Breaks work into ordered tasks. Use when you have a spec or clear requirements and need to break work into implementable tasks. Use when a task feels too lar... |
| [`ponytail`](./ponytail/) | > |
| [`ponytail-audit`](./ponytail-audit/) | > |
| [`ponytail-debt`](./ponytail-debt/) | > |
| [`ponytail-gain`](./ponytail-gain/) | > |
| [`ponytail-help`](./ponytail-help/) | > |
| [`ponytail-review`](./ponytail-review/) | > |
| [`poteto-help`](./poteto-help/) | Guides users through pstack setup, /poteto-mode, and picking the skill, playbook, or principle for a task. Type /poteto-help with a question. |
| [`poteto-mode`](./poteto-mode/) | poteto's agent style for concise, detailed responses, deliberate subagents, unslopped prose, simple code, and verified work. Use for poteto, /poteto-mode, or... |
| [`principle-attack-the-premise`](./principle-attack-the-premise/) | Apply when two or more fixes that share one premise have failed the same gate. Write the premise down and test it directly before you write another fix that... |
| [`principle-boundary-discipline`](./principle-boundary-discipline/) | Apply when wiring validation, error handling, or framework adapters. Concentrate guards at system boundaries (CLI, config, network, external APIs); trust int... |
| [`principle-build-the-lever`](./principle-build-the-lever/) | Apply to any non-trivial work, not just bulk work: edits, migrations, analyses, checks. Build the tool that does it or proves it (codemod, script, generator,... |
| [`principle-encode-lessons-in-structure`](./principle-encode-lessons-in-structure/) | Apply when you catch yourself writing the same instruction a second time, or notice a recurring correction. Encode the rule as a lint, metadata flag, runtime... |
| [`principle-exhaust-the-design-space`](./principle-exhaust-the-design-space/) | Apply when facing a novel UI interaction or architectural decision with no precedent in the codebase. Build 2-3 competing prototypes and compare side by side... |
| [`principle-experience-first`](./principle-experience-first/) | Apply when product, UX, or feature-scope tradeoffs come up. Choose user delight over implementation convenience; ship fewer polished features over more rough... |
| [`principle-explain-the-number`](./principle-explain-the-number/) | Apply before you measure, and before you trust, report, or act on a number you measured: a speedup, a regression, a throughput, a latency, or an eval result.... |
| [`principle-fix-root-causes`](./principle-fix-root-causes/) | Apply when debugging. Trace each symptom back to the first place the system went wrong and fix it there. A guard is a fix only when the state it handles is l... |
| [`principle-foundational-thinking`](./principle-foundational-thinking/) | Apply before writing logic: choosing core types and data structures, sequencing scaffold-vs-feature work, asking what concurrent actors share. Get the data s... |
| [`principle-guard-the-context-window`](./principle-guard-the-context-window/) | Apply when context is filling up: large outputs, long files, repeated reads, fan-out planning. Route bulk to subagents; keep summaries in the main thread, no... |
| [`principle-laziness-protocol`](./principle-laziness-protocol/) | Apply when refactoring, evaluating diff size, or tempted to add abstractions, layers, or signal threading. Bias toward deletion and the smallest change that... |
| [`principle-make-operations-idempotent`](./principle-make-operations-idempotent/) | Apply when designing commands, lifecycle steps, or processing loops that run amid crashes, restarts, and retries. Converge to the same end state regardless o... |
| [`principle-migrate-callers-then-delete-legacy-apis`](./principle-migrate-callers-then-delete-legacy-apis/) | Apply when introducing a new internal API while old callers still exist. Migrate callers and delete the old API in the same wave instead of preserving compat... |
| [`principle-minimize-reader-load`](./principle-minimize-reader-load/) | Apply when reviewing or shaping code that's hard to trace. Count layers between question and answer, and hidden state in the reader's head; collapse one-call... |
| [`principle-model-the-domain`](./principle-model-the-domain/) | Apply when writing stateful logic, or when code branches a lot or repeats a shape assumption across files. |
| [`principle-never-block-on-the-human`](./principle-never-block-on-the-human/) | Apply when tempted to ask 'should I do X?' on reversible work. |
| [`principle-outcome-oriented-execution`](./principle-outcome-oriented-execution/) | Apply during planned rewrites and migrations with explicit phase boundaries. Converge on the target architecture; don't preserve smooth intermediate states w... |
| [`principle-prove-it-works`](./principle-prove-it-works/) | Apply after completing a task, before declaring done. Verify against the real artifact (run the feature, read the actual value, inspect the diff), not a prox... |
| [`principle-redesign-from-first-principles`](./principle-redesign-from-first-principles/) | Apply when integrating a new requirement into an existing design. |
| [`principle-separate-before-serializing-shared-state`](./principle-separate-before-serializing-shared-state/) | Apply when concurrent actors might write to the same file, branch, key, or state object. Eliminate the sharing first; serialize structurally only when one sh... |
| [`principle-sequence-verifiable-units`](./principle-sequence-verifiable-units/) | Apply to multi-step work (sweeps, migrations, runs of similar edits) and to how you stack commits and PRs. Break work into small units that each end in a ver... |
| [`principle-subtract-before-you-add`](./principle-subtract-before-you-add/) | Apply when sequencing an addition, refactor, or rewrite. Remove dead code, redundant validators, and stub references first, then build on the simpler base. |
| [`principle-test-behavior-not-implementation`](./principle-test-behavior-not-implementation/) | Apply when you write, change, or keep a test. Assert what the code's users can observe, so that the test fails when that behavior breaks and keeps passing wh... |
| [`principle-type-system-discipline`](./principle-type-system-discipline/) | Apply when designing types, reviewing a function signature, or writing code in any statically-typed language. Make illegal states unrepresentable, brand sema... |
| [`prototype`](./prototype/) | Build a throwaway prototype to answer a design question. Use when the user wants to sanity-check whether a state model or logic feels right, or explore what... |
| [`recall`](./recall/) | Reconstruct your recent working context from your own chat history, live state, and the shared record (user reports, prior fixes, incidents), then hand back... |
| [`reflect`](./reflect/) | Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the use... |
| [`remotion-to-hyperframes`](./remotion-to-hyperframes/) | Bring existing video code or footage into HyperFrames and verify it frame by frame against the original - Remotion first, also Motion Canvas, Lottie, Three.j... |
| [`research`](./research/) | Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched... |
| [`retro`](./retro/) | Conduct a retrospective on a coding session. |
| [`reverse-any-video`](./reverse-any-video/) | Rebuild any video file as an editable HyperFrames project - motion graphics, talking heads, live action or AI-generated footage - checked against the origina... |
| [`scaffold-exercises`](./scaffold-exercises/) | Create exercise directory structures with sections, problems, solutions, and explainers that pass linting. Use when user wants to scaffold exercises, create... |
| [`scenecraft-v1`](./scenecraft-v1/) | Scenecraft v1 — scene plate builder. A skill made by Joey. Writes photoreal environment plates, location plates, set and world plates, coverage angles, and p... |
| [`security-and-hardening`](./security-and-hardening/) | Hardens code against vulnerabilities. Use when auditing an input handler for vulnerabilities, when handling user input, authentication, data storage, or exte... |
| [`seo`](./seo/) | Optimize for search engine visibility and ranking. Use when asked to "improve SEO", "optimize for search", "fix meta tags", "add structured data", "sitemap o... |
| [`setup-matt-pocock-skills`](./setup-matt-pocock-skills/) | Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the ot... |
| [`setup-pre-commit`](./setup-pre-commit/) | Set up Husky pre-commit hooks with lint-staged (Prettier), type checking, and tests in the current repo. Use when user wants to add pre-commit hooks, set up... |
| [`setup-pstack`](./setup-pstack/) | Configure which models pstack uses per role and at what reasoning budget. Detects your available models and writes an always-applied rule that overrides the... |
| [`setup-ts-deep-modules`](./setup-ts-deep-modules/) | Wire dependency-cruiser into a TypeScript repo so each package is a deep module, with implementation hidden in subfolders and reachable only through its entr... |
| [`sharpen`](./sharpen/) | Make a task deeper, not bigger, then rewrite the prompt. Use for /sharpen. |
| [`shipping-and-launch`](./shipping-and-launch/) | Prepares production launches. Use when preparing to deploy to production, or when asking what needs to be in place before shipping. Use when you need a pre-l... |
| [`shotcaller-v2`](./shotcaller-v2/) | Shotcaller v2 — Seedance 2.0/2.5 cinema director by Joey; use instead of v1. Adds Element-handle-first tagging, video character reference sheets that lock lo... |
| [`show-dont-tell`](./show-dont-tell/) | Turn what we're talking about right now into images to look at. Picks Genspark or Codex and the model, confirms once, generates, and drops the round into Eagle. |
| [`show-me-your-work`](./show-me-your-work/) | Keep a reviewable decision trail for long-running or unattended work: a TSV log with one row per decision (what, why, evidence, result). Local by default; co... |
| [`shuorenhua`](./shuorenhua/) | 按用户要求审稿或去 AI 味，支持中英文；保留事实、术语与责任主体，支持只标问题。 |
| [`slideshow`](./slideshow/) | Build a HyperFrames slideshow to present live - slides, fragment reveals, branching hotspots and presenter mode with speaker notes, served by `hyperframes pr... |
| [`source-driven-development`](./source-driven-development/) | Grounds every implementation decision in official documentation. Use when you want to verify an approach against the official docs before implementing it, or... |
| [`spec-driven-development`](./spec-driven-development/) | Creates specs before coding. Use when starting a new project, feature, or significant change and no specification exists yet. Use when drafting a PRD or requ... |
| [`story-bible-builder`](./story-bible-builder/) | Interview-driven skill that helps AI filmmakers, worldbuilders, and storytellers turn their story into a single dense canon document — the story's bible. Out... |
| [`suit-up`](./suit-up/) | Equip one project with skills from the user's skill library - a manager kit linked into the project, a worker kit, and a phase-to-skill plan - so other proje... |
| [`swarm`](./swarm/) | Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration. |
| [`swift-accessibility-skill`](./swift-accessibility-skill/) | Apply platform accessibility best practices to SwiftUI, UIKit, and AppKit code. Essential companion to any SwiftUI, UIKit, or AppKit skill — always use toget... |
| [`swiftui-pro`](./swiftui-pro/) | Comprehensively reviews SwiftUI code for best practices on modern APIs, maintainability, and performance. Use when reading, writing, or reviewing SwiftUI pro... |
| [`tdd`](./tdd/) | Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. |
| [`teach`](./teach/) | Teach the user a new skill or concept, within this workspace. |
| [`technical-writing`](./technical-writing/) | Layered technical-writing standard: Diátaxis structure, Google developer style sentences, STE instruction rules, Global English syntax. Use for /technical-wr... |
| [`test-driven-development`](./test-driven-development/) | Drives development with tests using the red-green-refactor loop. Use when implementing any logic, fixing any bug, or changing any behavior. Use when you need... |
| [`to-questionnaire`](./to-questionnaire/) | Turn a decision you can't fully answer into a questionnaire for someone else to fill in. |
| [`to-spec`](./to-spec/) | Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed. |
| [`to-tickets`](./to-tickets/) | Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker (... |
| [`triage`](./triage/) | Move issues and external PRs through a state machine of triage roles, categorise, verify, grill if needed, and write agent-ready briefs. |
| [`turnaround-sheet`](./turnaround-sheet/) | Character sheet for our films: a 4-view turnaround (front, side profile, back, face close-up) plus separate expression and gear sheets on demand. Replaces ca... |
| [`typesafe-ai`](./typesafe-ai/) | > |
| [`typescript-best-practices`](./typescript-best-practices/) | TypeScript best practices. Use when reading or editing any .ts or .tsx file. |
| [`uni-app`](./uni-app/) | Comprehensive skill reference for uni-app cross-platform development framework |
| [`unslop`](./unslop/) | Cut AI tells from any writing. |
| [`using-agent-skills`](./using-agent-skills/) | Discovers and invokes agent skills. Use when starting a session, or when you need to decide which skill or workflow applies to the piece of work at hand. Thi... |
| [`wait-what`](./wait-what/) | Stop. That last message did not land: re-pitch it. |
| [`wayfinder`](./wayfinder/) | Plan a huge chunk of work (more than one agent session can hold) as a shared map of decision tickets on your issue tracker, and resolve them one at a time un... |
| [`web-quality-audit`](./web-quality-audit/) | Run an evidence-led web quality audit covering performance, accessibility, SEO, best practices, and agentic browsing. Use when asked to "audit my site", "rev... |
| [`why`](./why/) | Use for 'why does X work this way', 'why we picked Y', design rationale, regressions, postmortems, or data-backed thresholds. Discovers available MCPs and qu... |
| [`wizard`](./wizard/) | Generate an interactive bash wizard that walks a human through steps only they can perform. Use when provisioning infrastructure, setting up credentials or C... |
| [`write`](./write/) | Rewrites and polishes Chinese or English prose, technical instructions, and product copy. Use when drafting, editing, localizing, or cutting AI tone. Not for... |
| [`write-swift`](./write-swift/) | How to write modern Swift well — modeling with value types, Swift 6 data-race safety and approachable concurrency (@concurrent, main-actor-by-default, actors... |
| [`writing-beats`](./writing-beats/) | Writing, exploit; assemble raw material into a journey of beats, grounding each term before a beat leans on it. |
| [`writing-for-agents`](./writing-for-agents/) | Writing documents for agents. Use when creating or editing skills, or modifying AGENTS.md or CLAUDE.md. |
| [`writing-fragments`](./writing-fragments/) | Writing, explore: mine raw fragments, no structure yet. |
| [`writing-shape`](./writing-shape/) | Writing, exploit: shape raw material into an article, paragraph by paragraph. |
