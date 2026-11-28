---
name: clip-craft
description: Our studio's video-stage rules, used on top of shotcaller-v2 with any provider. They cover reference stills built for video (boring photo, clay first, one job per reference), character video references with voice, blocking, fights, acting, clip overlap, and cheap draft takes before final takes. Use when planning or writing a video clip, choosing takes, or making reference stills that a clip will use.
---

# Clip craft

A studio layer over **shotcaller-v2** (Joey's skill; its source stays untouched). Shotcaller writes the video prompt; clip-craft adds what goes into the prompt and how the takes are run. Every rule here works with any provider. Sources and the reasoning behind each rule: `_studio/notes/higgsfield-videos-2026-11.md`.

## Steps

1. **Gate: references ready.** Every character, prop and place the clip shows has a locked still made to the reference rules below. A speaking character also needs a video reference. Done when each one is named by file; for anything missing, stop and say what it is.
2. **Write the clip** with shotcaller-v2, adding the prompt rules below. Done when every rule that applies to this clip appears in the prompt.
3. **Draft takes.** Run 3-4 takes at the lowest resolution the provider offers. Judge only framing, who stands where, and the action's order. Done when one take is picked, or when one named fault is fixed in the prompt and the drafts are run again.
4. **Final take.** Remake only the picked take at full resolution, with the same prompt and settings (and the same seed, where the provider exposes one). Done when the final matches the draft's framing and action.
5. **Coverage, when a moment needs more angles.** Feed the final back in as a video reference and ask for the same action from other camera positions. Done when the editor has matching moments to cut between.

## Reference rules (stills a clip will use)

- **Boring photo.** The stranger the subject, the plainer its reference: plain backdrop, flat or direct light, a straight-on view. The mood comes from the scene prompt, never from the reference.
- **Clay first** for creatures, gear and props: lock the shape as an uncoloured sculpt, then add materials and colour. Rooms go straight from a scene prompt, because clay rooms come out with clean, game-like geometry.
- **One job per reference.** Each attached image does one stated job, and a map says which part of the frame or body it goes to (the block-it-out legend is that map). Name every feature you locked, so it can't drift.
- **Anything that changes during the clip** (a wound, a charged blade, a lost limiter) gets its own reference of its end state.
- **Dialogue rooms get both sides:** one plate behind each speaker, so the model always knows which way it's looking.
- **Character video reference:** one short clip per speaking character before any scene: facing camera, speaking one line in their voice ("This is how I look, and this is how I sound"), from a voice recording. Make it with shotcaller-v2's video reference sheet. It acts better than an image reference.

## Prompt rules

- **Blocking.** Attach the top-view plan (block-it-out `plan.png`) with starting marks, labelled: "Blocking reference: use it for starting positions only, then follow the camera directions."
- **Small stage for fights:** pin all the action to a few metres around one named object.
- **Fights as a list:** who stands where, each move, where the foot lands, and how each opponent goes down. Medium shots show the move; close-ups sell the contact.
- **Acting by goal:** state what each character wants from the other and how it escalates. Dialogue goes in word for word. Leave room for pauses.
- **Order of events** for anything that changes, step by step (for example: the bullet comes out, falls, and the wound stays visible until the camera turns away).
- **Overlap:** start each clip with the last line or move of the clip before it, so the edit can choose the cut. Put cuts on movement, such as a whip pan or a body crossing the lens.
- **Batch:** run the same prompt several times. Keep a happy accident if it serves the shot.
