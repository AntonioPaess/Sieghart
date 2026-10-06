# Companion artwork and reactions

The approved five-character board remains unchanged in `avatar-directions.png` and is bundled as `AvatarSprites/approved-directions.png`. The first five neutral poses are cropped directly from this board; runtime backdrop removal keeps their original shapes, textures, and glow. Star Sprout is the sixth character.

Six local transparent sprite sheets provide nine poses: idle, blink, happy, annoyed, asleep, listening, focused, waking, surprised. The original board supplies the neutral pose for CRT Buddy, Arcade 1984, Minimal Spirit and Paper Pal. Coast Buddy and Ink Buddy use their own sheets. Soft Orbit and Star Sprout below are archived generation notes; they are retired from the current six. Body bounces, shakes, sleep, stretching, acknowledgement nods, and celebration particles add motion around the artwork.

The widget also gives each touch reaction a written response. A stroll stays within its stage; in the compact island the companion nudges the digits during the final 30 seconds without covering the camera or increasing the island’s height.

Method: built-in image generation using the approved board as the reference. No image or generation service is needed at runtime. Original generation outputs are retained separately; the app bundles the PNGs in `AvatarSprites`.

## crt-buddy

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Input image is the APPROVED five-character design board. Edit/extract ONLY character 01, CRT BUDDY, preserving its exact original identity, proportions, lilac rounded television body, glossy mint phosphor eyes, dark teal screen with fine scanlines, pink side ears, bent lilac antenna with mint tip, yellow status dot, three tiny lavender buttons, and two lilac feet. Keep the beautiful original polished texture and glow; do not simplify into a flat icon, do not redesign or recolor it.
Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, NO labels, NO borders, NO cell backgrounds, no grid lines. Every character has identical scale and baseline, centered at the exact center of its cell; complete silhouette fits within 84% of cell width and height, no cropping or overlap. All empty area genuinely transparent. Row-major poses: row 1: (1) original friendly idle pose identical to the source, (2) same idle body with eyes closed for a quick blink, (3) delighted expression with raised feet and antenna, a happy whole-body bounce pose. Row 2: (4) mildly irritated, angled eyebrows, small frown, body leaning back, antenna bent slightly, playful and friendly, (5) asleep with closed eyes, relaxed mouth and slumped body, (6) listening attentively, body leaning forward, antenna alert, small round mouth. Row 3: (7) focused, calm concentrated face and upright body, (8) waking and stretching its feet/side ears with a sleepy smile, (9) surprised, widened eyes and a small round mouth, tiny raised body. Expressions affect face AND silhouette/posture, while all original parts, materials, palette and visual identity remain the same. No extra objects, no speech bubbles, no Z letters, no outside shadows, no watermark. Preserve smooth antialiasing and actual alpha.

</details>

## arcade-1984

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Approved reference: the supplied five-character board. Target: 02 ARCADE 1984. Preserve the EXACT 1980s pixel-art mascot in column 02: stepped amber/gold TV chassis, little amber pixel arms and feet, green phosphor eyes, green pixel smile, pink pixel cheeks and bottom buttons, small magenta antenna. Authentic sharply stepped pixel art, preserve original pixel shapes and original shading, do not make it a rounded 3D robot. Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, labels, borders, cell backgrounds or grid. Every pose uses identical scale, cell center and baseline; complete silhouette inside 80% of each cell, no overlap, no cropping. True transparent alpha everywhere outside the artwork; clean edges, no colored speckle/noise outside the silhouettes. Row-major poses: row 1: original friendly idle (preserve original approved design), same body with closed eyes for blink, delighted with a whole-body bounce. Row 2: playful mild irritation (frown, slanted brows, lean back), asleep (closed eyes and relaxed slumped posture), listening (attentive forward lean, small O mouth). Row 3: calm focused upright, waking with a whole-body stretch, surprised with raised posture and wide eyes. Each pose retains exactly the same original materials, palette, proportions and identity; only expression and pose change. All parts and whole-body posture should express the mood, not merely the mouth. No extra props, no words, no speech bubbles, no external drop shadows, no watermark.

</details>

## minimal-spirit

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Approved reference: the supplied five-character board. Target: 03 MINIMAL SPIRIT. Preserve the EXACT minimal floating lavender face in column 03: ONLY two rounded lilac eyes with tiny white glints, curved lilac eyebrows, curved smile and two magenta cheek dashes. No head, no body, no shell, no silhouette added. Retain the original soft purple glow and clean restrained shapes; movements affect eye/brow/cheek arrangement together. Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, labels, borders, cell backgrounds or grid. Every pose uses identical scale, cell center and baseline; complete silhouette inside 80% of each cell, no overlap, no cropping. True transparent alpha everywhere outside the artwork; clean edges, no colored speckle/noise outside the silhouettes. Row-major poses: row 1: original friendly idle (preserve original approved design), same body with closed eyes for blink, delighted with a whole-body bounce. Row 2: playful mild irritation (frown, slanted brows, lean back), asleep (closed eyes and relaxed slumped posture), listening (attentive forward lean, small O mouth). Row 3: calm focused upright, waking with a whole-body stretch, surprised with raised posture and wide eyes. Each pose retains exactly the same original materials, palette, proportions and identity; only expression and pose change. All parts and whole-body posture should express the mood, not merely the mouth. No extra props, no words, no speech bubbles, no external drop shadows, no watermark.

</details>

## soft-orbit

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Approved reference: the supplied five-character board. Target: 04 SOFT ORBIT. Preserve the EXACT glossy pearl orb in column 04: original lavender/mint/peach iridescent round body, big black oval eyes with white reflections, pink cheeks and black curved smile, thin pink/lilac orbit ring with a small golden satellite. Preserve the original glossy lighting, color placement, ring inclination and all proportions. Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, labels, borders, cell backgrounds or grid. Every pose uses identical scale, cell center and baseline; complete silhouette inside 80% of each cell, no overlap, no cropping. True transparent alpha everywhere outside the artwork; clean edges, no colored speckle/noise outside the silhouettes. Row-major poses: row 1: original friendly idle (preserve original approved design), same body with closed eyes for blink, delighted with a whole-body bounce. Row 2: playful mild irritation (frown, slanted brows, lean back), asleep (closed eyes and relaxed slumped posture), listening (attentive forward lean, small O mouth). Row 3: calm focused upright, waking with a whole-body stretch, surprised with raised posture and wide eyes. Each pose retains exactly the same original materials, palette, proportions and identity; only expression and pose change. All parts and whole-body posture should express the mood, not merely the mouth. No extra props, no words, no speech bubbles, no external drop shadows, no watermark.

</details>

## paper-pal

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Approved reference: the supplied five-character board. Target: 05 PAPER PAL. Preserve the EXACT original origami creature in column 05: ivory pentagonal folded face, coral triangular ears, coral folded-paper arms on both sides and two triangular paper feet, original paper textures and fold lines, black oval eyes with white glints and black smile, pink cheeks. Preserve the original ears/arms/feet silhouette and rich handmade paper shading; do not turn into just a flat fox head. Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, labels, borders, cell backgrounds or grid. Every pose uses identical scale, cell center and baseline; complete silhouette inside 80% of each cell, no overlap, no cropping. True transparent alpha everywhere outside the artwork; clean edges, no colored speckle/noise outside the silhouettes. Row-major poses: row 1: original friendly idle (preserve original approved design), same body with closed eyes for blink, delighted with a whole-body bounce. Row 2: playful mild irritation (frown, slanted brows, lean back), asleep (closed eyes and relaxed slumped posture), listening (attentive forward lean, small O mouth). Row 3: calm focused upright, waking with a whole-body stretch, surprised with raised posture and wide eyes. Each pose retains exactly the same original materials, palette, proportions and identity; only expression and pose change. All parts and whole-body posture should express the mood, not merely the mouth. No extra props, no words, no speech bubbles, no external drop shadows, no watermark.

</details>

## star-sprout

<details>
<summary>Asset prompt</summary>

Use case: identity-preserve / sprite asset. Approved reference: the supplied five-character board. Target: NEW sixth character. Preserve one NEW sixth character matching this family: a warm golden FIVE-POINT star with a small mint sprout leaf, pink cheek dots, expressive black oval eyes with small white reflections and a small friendly smile. Soft polished volume and gentle amber shading, original friendly character, its own star silhouette. This is the ONLY new design; match the quality of the first five. Deliver one square transparent RGBA sprite sheet, EXACTLY 3 equal columns by 3 equal rows, NO text, labels, borders, cell backgrounds or grid. Every pose uses identical scale, cell center and baseline; complete silhouette inside 80% of each cell, no overlap, no cropping. True transparent alpha everywhere outside the artwork; clean edges, no colored speckle/noise outside the silhouettes. Row-major poses: row 1: original friendly idle (preserve original approved design), same body with closed eyes for blink, delighted with a whole-body bounce. Row 2: playful mild irritation (frown, slanted brows, lean back), asleep (closed eyes and relaxed slumped posture), listening (attentive forward lean, small O mouth). Row 3: calm focused upright, waking with a whole-body stretch, surprised with raised posture and wide eyes. Each pose retains exactly the same original materials, palette, proportions and identity; only expression and pose change. All parts and whole-body posture should express the mood, not merely the mouth. No extra props, no words, no speech bubbles, no external drop shadows, no watermark.

</details>

## Replacement directions — October 5, 2026

The user rejected humanoid office and beach robots. The replacements belong to the original object-mascot family: the face is the body, compact proportions, small expressive limbs. The vintage cartoon replaces the suit direction, preserving exactly six choices. Saved preferences migrate automatically.

- **Coast Buddy:** seafoam portable radio, mint face, straw hat and backpack strap; relaxed digital nomad. The focused pose carries a small laptop. Final bundled sheet: `AvatarSprites/coast-buddy.png`.
- **Ink Buddy:** rounded charcoal clock-shaped object, ivory face, oval eyes, tiny bow tie, rubber-hose arms, mittens and short shoes. Restrained work companion with classic cartoon gestures. Final bundled sheet: `AvatarSprites/ink-buddy.png`.

Both were produced with the built-in image generator as transparent 3 × 3 sheets of nine consistent poses: idle, blink, happy, annoyed, asleep, listening, focused, waking, startled. Each silhouette fits within its cell; no labels, grid, scene background or human anatomy. These are original characters, with no borrowed cartoon character identity. The approved five-character board remains unchanged as historical reference. Rejected humanoid sheets are not bundled.
