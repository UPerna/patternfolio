# Pattern Scene Fixture font resource

This is a derived two-glyph validation fixture from Latin Modern Math1.959 by
B. Jackowski, P. Strzelczyk and P. Pianowski, on behalf of TeX users groups.
Original copyright2012–2014 is retained in the embedded font and resource metadata.
The font resource and its outlines use the GUST Font License, an instance of
LPPL1.3c-or-later. The surrounding platform code remains MIT; this font data is
separately licensed. Full verbatim licenses accompany this file.

Changes: renamed family/PostScript names to Pattern Scene Fixture, retained
only genuine U+0041/A and U+03B1/alpha plus the font's required notdef glyph,
removed hints and math/shaping tables, fixed file timestamps and serialized
original outlines/advance metrics. The original authors provide no support for
this derived fixture. It is a renderer validation resource, not an installable
replacement for Latin Modern Math or a general text shaping engine.

The original complete distribution is available from
[CTAN Latin Modern Math](https://mirrors.ctan.org/fonts/lm-math.zip).
The exact source OTF is also preserved in the
[pinned distribution copy](https://github.com/valxyz/fonts-lm-math/blob/a0bb94c14db8e1f950d344e1eb1d5947c0182665/fonts/latinmodern-math.otf).
Its SHA-256 is6075562b771f8b82f0c179e363389684f2dd09de30038269e2628e504bd7be0f,
and Git blob is0e4642e916c3e8206c8bf9c490c90eb3b20d9365. Both match the local
TeX Live2026 source used for preparation. This is the actual1.959 baseline;
there is no claim about an untested newer font release.

Reproduce with `tools/preparescenefont.py`, pinned fontTools4.60.1 and the exact
original OTF. The command requires an explicit output and refuses to overwrite a
different existing fixture. It verifies that subsetting retains both glyphs'
outlines and metrics. No fontTools dependency is required by the Lua renderers;
they consume the same portable resource and positioned glyphs on every host.
