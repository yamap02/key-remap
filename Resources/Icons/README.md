# ReKey icons

`AppIcon.png` is the transparent source artwork. `scripts/build-icons.sh` creates
the standard 16–1024 px representations and `build/AppIcon.icns` for the app bundle.
`CFBundleIconFile` points to this icon in both the main app and the background
Agent, so macOS can identify ReKey consistently in privacy settings.

The menu bar uses three 18 pt vector PDFs, generated with
`swift scripts/render-menu-icons.swift`: exchange arrows for active remapping,
pause bars for paused remapping, and dots when setup is required. AppKit template
rendering adapts them to light and dark menu bars. The menu label also exposes the
current state through accessibility text and a tooltip.

The app artwork was created with the built-in imagegen tool. Final prompt:

> Use case: logo-brand. A refined FLAT macOS app icon for ReKey keyboard remapping utility. Square canvas 1024x1024. ONE flat rounded square tile, solid muted dark navy-blue #253B68, with generous rounded corners, centered occupying 82% of canvas. Truly transparent outside tile. Inside: one extremely clean minimalist white exchange symbol, two thin but clearly legible horizontal arrows, upper points right and lower points left, monoline strokes with round caps, simple short diagonal arrowheads, airy spacing. Symbol occupies about 48% of tile width. Perfect geometric balance. Sophisticated restrained flat vector aesthetic, practical developer tool, timeless and understated. Absolutely NO gradients, NO bevels, NO 3D, NO gloss, NO texture, NO lighting, NO shadows, NO highlights, NO outlines around the tile, NO keycap inset, NO text, NO letters, NO mockup. Just two solid colors and transparency. The image should look like a carefully drawn vector icon, crisp clean flat surfaces.

Validation: all 26 Swift tests pass; release app and installer build successfully.
The menu artwork was inspected at 18 pt on light and dark backgrounds. Installed
Finder/menu bar appearance remains to be checked after updating the installed app.

## Publication review

The prompt and creation method above record provenance; they do not establish
trademark clearance, freedom from resemblance to third-party artwork, or
exclusive rights in generated artwork. Before release, review the product name,
app icon, and promotional images under the applicable creation-service terms
and third-party rights. Preserve provenance and permissions for any new
reference images or assets. No trademark or artwork clearance is recorded here.
See [the publication checklist](../../docs/publication-rights-ja.md).

The validation paragraph above records earlier development checks, not approval
of a current signed or notarized public release.
