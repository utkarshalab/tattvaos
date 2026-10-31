"""Variable test fonts (development machine only).

    make_featvar(src, out): src (a variable TrueType font) with GSUB FeatureVariations added -
    substitutions that switch on above wght 0.5 (a, e, o to other glyphs), and another set where
    wght is below -0.3 and wdth below -0.5 - through the rvrn feature.
"""
from fontTools.ttLib import TTFont
from fontTools.varLib.featureVars import addFeatureVariations


def make_featvar(src, out):
    f = TTFont(src)
    cmap = f.getBestCmap()
    g = {ch: cmap[ord(ch)] for ch in 'aeoxyzn'}
    addFeatureVariations(f, [
        ([{'wght': (0.5, 1.0)}], {g['a']: g['x'], g['e']: g['y'], g['o']: g['z']}),
        ([{'wght': (-1.0, -0.3), 'wdth': (-1.0, -0.5)}], {g['n']: g['o']}),
    ])
    f.save(out)
    return out
