# Third-party notices

BetterVolume itself is MIT licensed — see [LICENSE](LICENSE). It has no third-party code
dependencies. It does bundle one third-party asset:

## App icon

| | |
|---|---|
| Work | *Apps multimedia volume control* |
| Authors | The Oxygen Team (KDE) |
| From | [Oxygen icon theme](https://invent.kde.org/frameworks/oxygen-icons) |
| Obtained via | [IconArchive](https://www.iconarchive.com/show/oxygen-icons-by-oxygen-icons.org/Apps-multimedia-volume-control-icon.html) |
| License | GNU Lesser General Public License v3 — [Docs/licenses/LGPL-3.0.txt](Docs/licenses/LGPL-3.0.txt), which incorporates [Docs/licenses/GPL-3.0.txt](Docs/licenses/GPL-3.0.txt) |
| Upstream authors list | <https://www.iconarchive.com/icons/oxygen-icons.org/oxygen/authors.txt> |

Shipped as [Resources/AppIcon.icns](Resources/AppIcon.icns) and copied into
`BetterVolume.app/Contents/Resources/AppIcon.icns` at build time.

**Modifications:** none to the artwork. The original 16, 32, 128 and 256 px renderings were
repackaged into a modern `.icns` (adding the retina-tagged 16@2x, 32@2x and 128@2x slots; the
64 px slot is the 128 px art downscaled). The legacy 48 px rendering was dropped because macOS
no longer uses it.

**Replacing it:** as the LGPL intends, the icon can be swapped for a modified or entirely
different one without touching BetterVolume's own code — replace
`Resources/AppIcon.icns` and run `Scripts/build.sh install`, or replace
`AppIcon.icns` inside an installed `BetterVolume.app/Contents/Resources` and re-sign the bundle.

The icon is combined with BetterVolume by mere aggregation in an application bundle; it is not
linked into the program, and BetterVolume's own source remains under the MIT license.
