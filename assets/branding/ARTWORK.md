# MMT artwork

`bandaged-mount.png` is the approved clay-style broken mount with crossed orange
bandages, generated with OpenAI image generation for this project. It replaces
the previous Stitch emblem in the app and Android launcher.

Prompt: Preserve the selected clay mount, purple texture, crooked plate, wide
jagged fracture, tripod and oversized orange bandages; remove the concept label,
presentation tile and background; isolate the complete mount on transparency.

Run `bash scripts/generate-launcher-icons.sh` with ImageMagick to regenerate Android
launcher assets. The adaptive foreground includes safe-area padding. The welcome
screen uses the transparent master on the same dark purple background.

`polaris-stitch.png` is the generated mount-chooser illustration from Stitch
project https://stitch.google.com/projects/16144176762086228608. The live-design
verification receipt records extraction of the corrected PNG data URI from the
live chooser on 2026-11-21. Its SHA-256 matches the bundled asset:
`7d1776dd481127fa8d7033ca2300115ea5208b4552d6dd6aaff96d546d35352c`.
The fourteen-screen export predates that correction and is not the source of the
final PNG. The manufacturer product image was used as a visual reference; the
asset is recorded as generated artwork, not a project photograph. This provenance
record does not imply endorsement or transfer rights in Benro's trademarks.
The user's approved mount-chooser design is retained.
