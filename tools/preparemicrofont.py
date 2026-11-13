"""Build the redistributable, bounded micrography font from the pinned source."""
import argparse
import base64
import hashlib
import json
import unicodedata
from io import BytesIO
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont

from preparescenefont import SOURCE_COMMIT, SOURCE_SHA256, outline

FAMILY = "Pattern Micrography"
ASCII = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,;:!?-'"
GREEK = "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρστυφχψως"
ACUTE = "áéíóúÁÉÍÓÚ"


def prepare(path):
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == SOURCE_SHA256
    assert fontTools.version == "4.60.1"
    font = TTFont(BytesIO(data), recalcTimestamp=False)
    aliases = {unicodedata.normalize("NFD", c): c for c in ACUTE}
    aliases.update({"fi": "ﬁ", "fl": "ﬂ"})
    repertoire = ASCII + GREEK + ACUTE
    glyphs = [outline(font, ord(c)) for c in repertoire]
    for sequence, value in aliases.items():
        glyph = outline(font, ord(value))
        glyph.update(id="cluster/"+"/".join(str(ord(c)) for c in sequence), unicode=sequence)
        glyphs.append(glyph)
    copyrights = sorted({n.toUnicode() for n in font["name"].names if n.nameID == 0})
    options = subset.Options()
    options.hinting = False
    options.recalc_timestamp = False
    options.drop_tables.extend(["MATH", "GSUB", "GPOS", "GDEF", "DSIG"])
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=[ord(c) for c in repertoire+"ﬁﬂ"])
    sub.subset(font)
    names = {1:FAMILY, 2:"Regular", 3:"PatternMicrography-1.000", 4:FAMILY+" Regular",
             5:"Version1.000; derived from Latin Modern Math1.959", 6:"PatternMicrography-Regular",
             16:FAMILY, 17:"Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    cff = font["CFF "].cff
    cff.fontNames[0] = "PatternMicrography-Regular"
    cff.topDictIndex[0].FamilyName = FAMILY
    cff.topDictIndex[0].FullName = FAMILY+" Regular"
    font["head"].created = font["head"].modified = 2082844800
    buffer = BytesIO()
    font.save(buffer, reorderTables=True)
    raw = buffer.getvalue()
    opened = TTFont(BytesIO(raw), recalcTimestamp=False)
    for glyph in glyphs:
        char = aliases.get(glyph["unicode"], glyph["unicode"])
        derived = outline(opened, ord(char))
        assert all(glyph[k] == derived[k] for k in ("advance", "bounds", "commands"))
    sha = hashlib.sha256(raw).hexdigest()
    return {"id":"font/micrography", "kind":"font", "profile":"positioned-outlines-v1",
            "units_per_em":font["head"].unitsPerEm, "family":FAMILY,
            "license":"GUST Font License / LPPL1.3c-or-later; docs/fonts/GUST-FONT-LICENSE.md and LPPL-1.3c.md",
            "font_sha256":sha, "glyphs":glyphs,
            "variants":{"opentype":{"encoding":"base64","content":base64.b64encode(raw).decode(),
                                   "sha256":sha,"media_type":"font/otf"}},
            "provenance":{"source":"Latin Modern Math1.959","source_sha256":SOURCE_SHA256,
                          "source_commit":SOURCE_COMMIT,"copyright":copyrights,
                          "preparation":"fontTools4.60.1 / preparemicrofont-v1",
                          "changes_file":"docs/fonts/README-PatternMicrography.md"}}


if __name__=="__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--font", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    result = prepare(args.font)
    data = (json.dumps(result, ensure_ascii=False, separators=(",",":"))+"\n").encode()
    if args.output.exists():
        assert args.output.read_bytes()==data,"refusing to overwrite a different font"
    else:
        args.output.write_bytes(data)
    print(result["font_sha256"],len(result["glyphs"]),len(data))
