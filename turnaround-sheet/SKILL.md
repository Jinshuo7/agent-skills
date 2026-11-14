---
name: turnaround-sheet
description: Character sheet for our films: a 4-view turnaround (front, side profile, back, face close-up) plus separate expression and gear sheets on demand. Replaces castkit-v1 Station 4 and its 3-panel default. Use whenever a character sheet, turnaround or model sheet is made.
---

# Turnaround sheet

Studio decision (2026-11-14): every main character gets one **turnaround**: four views in one wide image. It replaces castkit's 3-panel because our video model needs the side view (profile shots, gear that only reads from the side), and one image keeps the character to one reference slot (Seedance rations slots, see shotcaller-v2). Everything else in castkit still applies.

## Steps

1. **Gate.** The character has an approved face lock and an approved outfit image (castkit Stations 0 and 3; picks read through `eagle.py picks`). Missing either: stop and say which. Done when both files are named.
2. **Write the turnaround prompt** (layout below). Attach the outfit image; add the face lock as a second reference only on castkit's conditions (Station 4, "References"). The film's style reference rides along automatically. Done when every panel carries its orientation clause.
3. **Generate** on the film's image route (studio `CLAUDE.md`), 2 options per character, 16:9. Done when both images exist.
4. **Check** with `check-batch.sh` against the checklist below, then add to Eagle as `Characters/<Name>/Sheet · round 1`. Done when the user has a pick or a named fault to fix.
5. **Extras, only when a shot needs them** (name the shot):
   - **Expression sheet**: castkit's expression set (3 faces), for characters whose face is seen acting.
   - **Gear sheet**: a prop design reference of the weapon or rig, its states side by side (e.g. a sword's charge stages).
   - **Single view**: one panel of the turnaround re-rendered alone, larger, when one angle carries a whole shot.

## Layout

One horizontal frame, four equal vertical panels left to right, thin clean separation, the same figure and outfit identical in all four, flat 18% grey field, no shadow, no text or labels.

1. **Front, full body, head attached.** castkit's front clause, verbatim.
2. **Side, full body, true 90-degree profile.** Name which way the figure faces on screen. *"Seen exactly side-on, the far shoulder and far leg hidden behind the near ones, the ear centred on the head, the nose, chin and the full length of the gear in clean silhouette against the field; no three-quarter turn."*
3. **Back, full body.** castkit's rear clause, verbatim.
4. **Face, chest-up.** castkit's face clause, verbatim. For a character whose face is always covered (helmet, mask), this panel shows the headgear dead-on instead.

Identity and wardrobe are written once, above the panels; each panel says only what differs. Close with the film's flat-style line, stated as uniform across all four panels. The orientation clauses and castkit's skin-tone line come from castkit-v1 Station 4: that is their single source.

## Check

- Four panels, in order, same scale, feet at the same line.
- Front and back dead-on, side a true profile, face dead-on.
- Outfit and colours identical across panels and matching the approved outfit image.
- Flat grey field, no shadow, no text, no extra figures.
