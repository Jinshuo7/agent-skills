# Who builds what: lessons from Shreddr, 2026-11-03

What one long night on Shreddr showed about splitting work between a strong head model (Opus) and a cheap worker (DeepSeek V4.1 Flash, via pi on OpenCode Go or Command Code). Read it when choosing the Worker slot, writing worker briefs, or when the owner asks to go faster.

## What the night measured
| | Opus subagent | DeepSeek worker |
|---|---|---|
| Time to a reviewed PR | 12–21 min, even for three linked tickets in one build | 20–60 min per ticket |
| First review | Clean on all three builds | Often sent back: 3–4 fix rounds on two tickets |
| Judgment | Found problems nobody had written down (overlapping work, a generator wiping files, a deprecated API) and said what it could not check | Follows the brief; misses whatever isn't written in it |
| Cost | High (~350k tokens for one large feature) | Flat plan, near free |

The saving is not faster typing; it is skipped round trips. Every fix round costs 30–60 min of waiting, plus the head's review tokens.

## Route by the kind of work
- **Opus builds:** large, multi-file or vague features; anything touching saved state, migrations or deletion; new screens; deadlines. Opus subagents compile and run unit tests but boot no simulator, so CI keeps the machine.
- **DeepSeek builds:** wording, small fixes, test-only changes, anything specified down to the file and the line.
- **The head (Opus) always** plans, writes the briefs, checks screenshots against the design, decides risky merges. It never skips the cheap reviewer, whoever built the change.
- **Cheap reviewer** (GLM-5.3 Flash) reviews everything, Opus's work included. Read its P2s against the ticket; "clean" can hide unmet criteria.

## About half of DeepSeek's round trips were the brief's fault
End every DeepSeek brief with:
1. **Never touch:** generated or scheme files (`*.xcscheme`, the project file unless listed), CI files unless listed. Never launch a browser.
2. **Never weaken** a test, a threshold or the approved design to pass a check. If it can't pass, stop and report. (A worker once made a whole screen flat black to satisfy an accessibility check.)
3. **Change only what's named:** keep every unnamed size, color and position. Compare before and after screenshots of every touched screen. (A fix once shrank tiles and a headline nobody asked about.)
4. **Freeze scope** before the worker starts. Additions go in a follow-up brief; a worker never re-reads a ticket mid-run.
5. **Write the edge cases:** already decided, save fails, cancelled system prompt, empty state, largest text size, second language.
6. **Allowed files** go only in the section the pipeline's file guard reads. Workers read the ticket once at start, so fix the ticket before (re)starting them.

## The machine is the real bottleneck
- One Mac runs CI and local simulators. A full UI suite took about 85 min, and a red run cost about 1.5 h. Four workers running simulators beside CI made it time out twice (about 3.5 h lost): **at most one local simulator worker while CI runs.**
- Starting several simulators in the same second crashed their test runners (XCTWaiter stall). Boot them one at a time, wait for boot to finish, start each shard about 20 s apart, and retry a crashed shard once.
- Any local multi-simulator test shuts its simulators down when it finishes, pass or fail. One run left 4 booted, and with CI's simulators that pushed the Mac to its per-user process limit (about 2,670 processes), where new programs fail to start.
- Measure per-test time before buying hardware: 36 of 432 tests (mostly screenshot captures relaunching the app per variant) used two-thirds of the suite time.
- Don't chain dependent tickets one at a time when the deadline is close. Build in parallel, let one strong builder merge dependent branches, and batch.

## Worker sandbox side effects
- A throwaway `HOME` has no keychain. Anything a worker starts that wants one (headless Chrome) puts a "Keychain Not Found" prompt on the owner's screen, again on every relaunch. Deny browser exec in the worker sandbox. Tell the owner never to press "Reset To Defaults", which wipes the real keychain.
- Pipeline claims and labels (`claimed:pipeline`, `stuck`) outlive killed workers. Clear them before restarting a ticket by hand, but only once the old worker is confirmed gone: a label removed from a live worker hides it from the watcher (Shreddr #420). `belt watch` does this itself on its own restarts.
