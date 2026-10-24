#!/usr/bin/env python3
"""Check ugfx SVG: parsing (elements, attributes, styles, transforms, colours,
path data, shapes) and drawing.

Usage: svg_check.py <host_ctx binary>

Each document is parsed and drawn by ugfx (ugfx_svg_parse, ugfx_svg_draw)
through host_ctx, and separately turned by tools/svgmodel.py - a model of
the same subset and rules - into the context calls the drawing should
make, which host_ctx then runs. The images must match: exactly where only
arithmetic is involved, within 1 per channel on at most 3 pixels where
arcs or rotations go through trigonometry (umath's last bit may differ
from Python's).

Development-machine tooling only; not part of any OS image.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import svgmodel  # noqa: E402
from ctx_check import encode  # noqa: E402


def div255(x):
    x += 128
    return (x + (x >> 8)) >> 8


def premul(c):
    a = c >> 24
    return (a << 24) | sum(div255(((c >> s) & 255) * a) << s for s in (0, 8, 16))


def expected_calls(doc, current, x, y, size):
    vb = doc.viewbox
    if vb is None:
        w = doc.width if doc.width and doc.width > 0 else 300.0
        h = doc.height if doc.height and doc.height > 0 else 150.0
        vb = [0.0, 0.0, w, h]
    vx, vy, w, h = vb
    s = size / max(w, h)
    dx = x + (size - w * s) * 0.5
    dy = y + (size - h * s) * 0.5
    out = [('save',), ('translate', dx, dy), ('scale', s, s), ('translate', 0.0 - vx, 0.0 - vy), ('dash', 0, [])]

    def paint(p):
        kind, c = p
        if kind == "current":
            c = (div255((current >> 24) * (c >> 24)) << 24) | (current & 0xFFFFFF)
        return premul(c)

    for it in doc.items:
        out += [('save',), ('transform', *it.matrix)]
        fill, stroke = [], []
        if it.fill:
            if it.fill[0] == 'paint':
                _, kind, spread, geom, stops, m, a = it.fill
                fill += [('fill_gradient', kind, spread, geom, stops, m), ('alpha', a)]
            else:
                fill += [('alpha', 255), ('fill_color', paint(it.fill))]
            fill += [('rule', it.rule), ('new_path',)] + it.path + [('fill',)]
        if it.stroke:
            if it.stroke[0] == 'paint':
                _, kind, spread, geom, stops, m, a = it.stroke
                stroke += [('stroke_gradient', kind, spread, geom, stops, m), ('alpha', a)]
            else:
                stroke += [('alpha', 255), ('stroke_color', paint(it.stroke))]
            stroke += [('stroke_style', it.width, it.miter, it.join, it.cap)]
            if it.dash:
                stroke.append(('dash', it.dash_off, it.dash))
            stroke += [('new_path',)] + it.path + [('stroke',)]
        out += (stroke + fill if it.order else fill + stroke) + [('restore',)]
    return out + [('restore',)]


def svg(body, attrs='viewBox="0 0 24 24"'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" {attrs}>{body}</svg>'


CASES = [
    ("lines abs/rel", svg('<path d="M2 2 L22 2 L22 10 H12 V22 h-8 v-6 l-2 -2 Z" fill="#1060e0"/>'), False),
    ("implicit lineto", svg('<path d="M2 2 22 2 22 22 m-4 -4 -6 0 0 -6z" fill="#e04010"/>'), False),
    ("cubic + smooth", svg('<path d="M2 12 C2 2 12 2 12 12 S22 22 22 12 s-5 -8 -10 -4 S4 20 2 12z" fill="#208040"/>'), False),
    ("quad + smooth", svg('<path d="M2 12 Q7 2 12 12 T22 12 t-10 8 T2 12 q5 -8 10 -9z" fill="#8020a0"/>'), False),
    ("smooth after line", svg('<path d="M2 2 L10 2 S20 2 20 12 T12 20 Z" fill="#c08000"/>'), False),
    ("numbers", svg('<path d="M.5.5L+23.5-.0e1 2.35e1 1.2E1 -0 2.4e+1zM12 12l.5.5.5-.5" fill="#000"/>'), False),
    ("arcs", svg('<path d="M4 12 A8 8 0 0 1 20 12 A8 8 0 1 1 4 12 Z" fill="#e02060"/>'), True),
    ("arc flags packed", svg('<path d="M4 12a8 4 30 1012 0a8 4 30 01-12 0z" fill="#20a0a0" fill-rule="evenodd"/>'), True),
    ("arc tiny radii", svg('<path d="M3 3 A1 1 0 0 0 21 21 A0.5 2 45 1 0 3 3" fill="#a0a020"/>'), True),
    ("arc zero radius", svg('<path d="M3 12 A0 5 0 0 1 21 12 L12 3z" fill="#304050"/>'), False),
    ("rect plain", svg('<rect x="3" y="4" width="18" height="12" fill="red"/>'), False),
    ("rect rx", svg('<rect x="2" y="2" width="20" height="16" rx="5" fill="blue"/>'), True),
    ("rect rx ry", svg('<rect x="2" y="2" width="20" height="16" rx="8" ry="3" fill="green"/>'), True),
    ("rect rx clamped", svg('<rect x="2" y="6" width="20" height="10" ry="40" fill="navy"/>'), True),
    ("rect zero size", svg('<rect width="0" height="10" fill="red"/><circle cx="12" cy="12" r="0" fill="red"/>'
                           '<circle cx="12" cy="12" r="4"/>'), False),
    ("circle ellipse", svg('<circle cx="8" cy="8" r="6" fill="teal"/><ellipse cx="15" cy="16" rx="7" ry="4" fill="purple"/>'
                           '<ellipse cx="18" cy="6" rx="3" fill="orange"/>'), False),
    ("line poly", svg('<line x1="2" y1="2" x2="22" y2="20" stroke="black" stroke-width="2"/>'
                      '<polyline points="2,22 8,12 14,20 22,4" fill="none" stroke="#c00" stroke-width="1.5"/>'
                      '<polygon points="12 2, 20 10 12 18 4 10 7" fill="#0a0" fill-opacity=".5"/>'), False),
    ("stroke styles", svg('<path d="M3 20 L12 4 L21 20" fill="none" stroke="#123" stroke-width="3" '
                          'stroke-linecap="round" stroke-linejoin="round"/>'
                          '<path d="M3 22 L12 14 L21 22" fill="none" stroke="#f60" stroke-width="2" '
                          'stroke-linecap="square" stroke-linejoin="bevel"/>'), False),
    ("miter limit", svg('<path d="M2 20 L12 18 L22 20" fill="none" stroke="#000" stroke-width="3" stroke-miterlimit="12"/>'), False),
    ("transforms", svg('<g transform="translate(12 12) scale(0.8, 1.2)"><rect x="-6" y="-6" width="12" height="12" '
                       'fill="#e04" transform="skewX(15)"/></g><g transform="matrix(1 0 0 1 2 2)">'
                       '<circle cx="4" cy="4" r="2" transform="scale(1.5)"/></g>'), True),
    ("rotate about", svg('<rect x="8" y="4" width="8" height="16" fill="#08f" transform="rotate(30 12 12)"/>'
                         '<rect x="10" y="10" width="4" height="4" transform="rotate(-45)" fill="#f80"/>'), True),
    ("nested groups", svg('<g fill="#f00" stroke="#00f" stroke-width="2" opacity="0.6"><g fill="#0f0" opacity="0.5">'
                          '<circle cx="8" cy="12" r="6"/></g><rect x="13" y="6" width="9" height="12" stroke="none"/></g>'), False),
    ("style overrides", svg('<rect x="2" y="2" width="20" height="20" fill="red" style="fill: #0c0 ; stroke:#000;'
                            'stroke-width:2px;opacity:.75"/><circle cx="12" cy="12" r="5" fill="blue" '
                            'style="fill:yellow !important"/>'), False),
    ("current colour", svg('<path d="M4 4h16v16H4z" fill="currentColor" fill-opacity="0.5"/>'
                           '<path d="M6 12h12" stroke="currentColor" stroke-width="2" fill="none"/>'), False),
    ("colours", svg('<rect width="6" height="6" fill="#f0a"/><rect x="6" width="6" height="6" fill="#f0a8"/>'
                    '<rect x="12" width="6" height="6" fill="rgb(10%, 50%, 255)"/>'
                    '<rect x="18" width="6" height="6" fill="rgba(200,100,0,0.4)"/>'
                    '<rect y="6" width="6" height="6" fill="#11223380"/><rect x="6" y="6" width="6" height="6" fill="Teal"/>'
                    '<rect x="12" y="6" width="6" height="6" fill="url(#missing) orange"/>'
                    '<rect x="18" y="6" width="6" height="6" fill="url(#missing)" stroke="#000"/>'
                    '<rect y="12" width="6" height="6" fill="nonsense"/><rect x="6" y="12" width="6" height="6" fill="transparent" stroke="red"/>'), False),
    ("fill rules", svg('<path d="M12 2 L18 20 L3 8 L21 8 L6 20 Z" fill="#000" fill-rule="evenodd"/>', 'viewBox="0 0 24 24"'), False),
    ("display none", svg('<g display="none"><rect width="24" height="24"/></g><rect x="4" y="4" width="8" height="8" '
                         'style="display:none"/><rect x="12" y="12" width="8" height="8" fill="#0af"/>'), False),
    ("skipped content", '<?xml version="1.0"?><!DOCTYPE svg><!-- a comment <rect/> -->'
                        + svg('<defs><rect id="r" width="24" height="24"/></defs><title>x</title><desc>y</desc>'
                              '<linearGradient id="g"><stop offset="0"/></linearGradient>'
                              '<style><![CDATA[ rect { fill: red } ]]></style>'
                              '<circle cx="12" cy="12" r="8" fill="#a0f"/><unknown><rect x="1" y="1" width="4" height="4"/></unknown>'), False),
    ("viewBox offset", svg('<circle cx="0" cy="0" r="10" fill="#fa0"/>', 'viewBox="-12 -12 24 24"'), False),
    ("wide viewBox", svg('<rect width="48" height="16" fill="#08a"/>', 'viewBox="0 0 48 16"'), False),
    ("width height only", svg('<rect width="20" height="10" fill="#a08"/>', 'width="20px" height="10"'), False),
    ("no size", svg('<rect width="300" height="150" fill="#555"/><circle cx="150" cy="75" r="60" fill="#fff"/>', ''), False),
    ("path error stops", svg('<path d="M2 2 L22 2 L22 22 L x 2 2" fill="#000"/><path d="M2 22 L12 12 Z Q" stroke="#f00" fill="none"/>'), False),
    ("linear default", svg('<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/>'
                            '<stop offset="1" stop-color="#00f"/></linearGradient></defs>'
                            '<rect x="2" y="4" width="20" height="16" fill="url(#g)"/>'), False),
    ("linear user space", svg('<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="10%" y1="0" x2="90%" '
                              'y2="24" spreadMethod="reflect" gradientTransform="rotate(20 12 12)">'
                              '<stop offset="0%" stop-color="#0a0"/><stop offset="50%" stop-color="#ff0" '
                              'stop-opacity=".5"/><stop offset="100%" style="stop-color: #a00"/></linearGradient>'
                              '<path d="M2 2h20v20H2z" fill="url(#g)"/>'), True),
    ("linear repeat", svg('<linearGradient id="g" x1="0" y1="0" x2="0.25" y2="0.25" spreadMethod="repeat">'
                          '<stop offset=".2" stop-color="#000"/><stop offset=".8" stop-color="#fff"/></linearGradient>'
                          '<rect x="3" y="3" width="18" height="18" fill="url(#g)" stroke="#000"/>'), False),
    ("radial default", svg('<radialGradient id="r"><stop offset="0" stop-color="#fff"/><stop offset="1" '
                           'stop-color="#048"/></radialGradient><circle cx="12" cy="12" r="10" fill="url(#r)"/>'), True),
    ("radial focal", svg('<radialGradient id="r" cx="0.5" cy="0.5" r="0.5" fx="0.3" fy="0.3" fr="0.05">'
                         '<stop offset="0" stop-color="#ff8"/><stop offset="0.6" stop-color="#f80"/>'
                         '<stop offset="1" stop-color="#800"/></radialGradient>'
                         '<rect x="2" y="2" width="20" height="20" rx="4" fill="url(#r)"/>'), True),
    ("radial user space", svg('<radialGradient id="r" gradientUnits="userSpaceOnUse" cx="12" cy="12" r="40%" '
                              'spreadMethod="repeat"><stop offset="0" stop-color="#00f"/><stop offset="1" '
                              'stop-color="#0ff"/></radialGradient><path d="M2 12 L12 2 L22 12 L12 22Z" '
                              'fill="url(#r)"/>'), False),
    ("href chain", svg('<linearGradient id="base"><stop offset="0" stop-color="#f0f"/><stop offset=".5" '
                       'stop-color="#ff0"/><stop offset="1" stop-color="#0ff"/></linearGradient>'
                       '<linearGradient id="mid" href="#base" x2="0" y2="1"/>'
                       '<linearGradient id="top" xlink:href="#mid" spreadMethod="reflect" y2="0.5"/>'
                       '<radialGradient id="rad" href="#base" r="0.3"/>'
                       '<rect x="1" y="1" width="10" height="22" fill="url(#top)"/>'
                       '<rect x="13" y="1" width="10" height="22" fill="url(#rad)"/>',
                       'viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink"'), False),
    ("stops edge cases", svg('<linearGradient id="one"><stop offset=".5" stop-color="#e40"/></linearGradient>'
                             '<linearGradient id="none"/>'
                             '<linearGradient id="odd"><stop offset=".7" stop-color="#00f"/><stop offset=".2" '
                             'stop-color="#f00"/><stop offset="2" stop-color="rgb(0,200,0)" stop-opacity="0.3"/>'
                             '</linearGradient>'
                             '<rect x="2" y="2" width="9" height="9" fill="url(#one)"/>'
                             '<rect x="13" y="2" width="9" height="9" fill="url(#none)" stroke="#000"/>'
                             '<rect x="2" y="13" width="20" height="9" fill="url(#odd)"/>'), False),
    ("stroke gradient", svg('<linearGradient id="g" x2="0" y2="1"><stop offset="0" stop-color="#f00"/>'
                            '<stop offset="1" stop-color="#00f"/></linearGradient>'
                            '<path d="M4 4 L20 4 L20 20 L4 20 Z" fill="#eee" stroke="url(#g)" stroke-width="3"/>'
                            '<path d="M4 12 H20" stroke="url(#g)" stroke-width="2"/>'), False),
    ("gradient opacity", svg('<linearGradient id="g"><stop offset="0" stop-color="#000"/><stop offset="1" '
                             'stop-color="#f80"/></linearGradient><g opacity=".7"><rect x="2" y="2" width="20" '
                             'height="20" fill="url(#g)" fill-opacity=".5" stroke="#000" stroke-width="1.5"/></g>'), False),
    ("forward + fallback", svg('<rect x="2" y="2" width="9" height="20" fill="url(&quot;#later&quot;)"/>'
                               '<rect x="13" y="2" width="9" height="9" fill="url(#missing) #0a0"/>'
                               '<rect x="13" y="13" width="9" height="9" fill="url(#missing)" stroke="#000"/>'
                               '<defs><linearGradient id="later" x2="0" y2="1"><stop offset="0" stop-color="#08f"/>'
                               '<stop offset="1" stop-color="#f08"/></linearGradient></defs>'), False),
    ("css illustrator", svg('<defs><style>.cls-1{fill:#e94;}.cls-2{fill:none;stroke:#333;stroke-width:2px;}'
                            '.cls-3{fill:#3a7}</style></defs><circle class="cls-1" cx="9" cy="9" r="7"/>'
                            '<rect class="cls-2" x="3" y="3" width="18" height="18"/>'
                            '<rect class="extra cls-3" x="12" y="12" width="9" height="9"/>'), True),
    ("css specificity", svg('<style>rect{fill:red} .a{fill:green} #x{fill:blue} rect.a{fill:#ff0} '
                            '.b{fill:#f0f} .c{fill:#0ff} *{stroke:#000}</style>'
                            '<rect x="1" y="1" width="6" height="6"/><rect class="a" x="9" y="1" width="6" height="6"/>'
                            '<rect id="x" class="a" x="17" y="1" width="6" height="6"/>'
                            '<circle class="a" cx="4" cy="12" r="3"/><circle class="b c" cx="12" cy="12" r="3"/>'
                            '<circle class="c b" cx="20" cy="12" r="3"/>'), True),
    ("css precedence", svg('<style>.p{fill:#08f;stroke:#f00}</style>'
                           '<rect class="p" fill="#000" x="2" y="2" width="9" height="20"/>'
                           '<rect class="p" style="fill:#0a0" stroke="#00f" x="13" y="2" width="9" height="20"/>'), False),
    ("css ignored", svg('<style>/* rect{fill:red} */ g rect{fill:red} rect:hover{fill:red} [fill]{fill:red} '
                        'g>rect{fill:red} @media screen { rect { fill: red } } @import "x.css"; '
                        'rect{fill:#2a6}</style><g><rect x="2" y="2" width="20" height="20" fill="#000"/></g>'), False),
    ("css groups", svg('<style>.grp{fill:#808;stroke:#000;stroke-width:1.5}</style><style>.thin{stroke-width:.5}'
                       '.hide{display:none}.half{opacity:.5}</style>'
                       '<g class="grp"><circle cx="7" cy="7" r="5"/><circle class="thin" cx="17" cy="7" r="5"/>'
                       '<rect class="hide" width="24" height="24"/><rect class="half" x="2" y="14" width="20" '
                       'height="8"/></g>'), True),
    ("css gradient", svg('<style>.g{fill:url(#lg)}</style><linearGradient id="lg"><stop offset="0" '
                         'stop-color="#fc0"/><stop offset="1" stop-color="#c06"/></linearGradient>'
                         '<rect class="g" x="2" y="2" width="20" height="20"/>'), False),
    ("use sprite", svg('<defs><symbol id="dot" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></symbol>'
                       '<symbol id="bar" viewBox="0 0 20 10"><rect x="1" y="1" width="18" height="8" rx="2"/>'
                       '</symbol></defs><use href="#dot" x="1" y="1" width="8" height="8" fill="#e33"/>'
                       '<use href="#dot" x="12" y="1" width="10" height="6" fill="#3a3"/>'
                       '<use href="#bar" x="2" y="12" width="20" height="10" fill="#36f"/>'
                       '<use href="#bar" x="2" y="12" fill="none" stroke="#000"/>'), True),
    ("use transform", svg('<path id="tri" d="M0 0 L6 0 L3 5 Z" fill="#f80"/>'
                          '<use xlink:href="#tri" x="8" y="2"/><use href="#tri" transform="rotate(30 12 12)" x="10" y="10"/>'
                          '<use href="#tri" transform="scale(1.5)" x="1" y="9" fill="#00f" opacity=".5"/>',
                          'viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink"'), True),
    ("use inherit", svg('<style>.u{stroke:#c0c;stroke-width:1.5}</style><defs><g id="pair"><circle cx="4" cy="4" r="3"/>'
                        '<rect x="9" y="1" width="6" height="6" fill="#0aa"/></g></defs>'
                        '<use href="#pair" fill="#fa0"/><use href="#pair" class="u" y="8"/>'
                        '<use href="#pair" style="fill:#08f" x="4" y="15"/>'), True),
    ("use nested", svg('<defs><circle id="c" cx="2" cy="2" r="2"/><g id="row"><use href="#c"/><use href="#c" x="5"/>'
                       '<use href="#c" x="10"/></g><g id="grid"><use href="#row"/><use href="#row" y="6"/></g></defs>'
                       '<use href="#grid" x="2" y="2" fill="#555"/><use href="#grid" x="6" y="13" fill="#a22"/>'), True),
    ("use edge cases", svg('<g id="loop"><rect width="2" height="2" fill="#000"/><use href="#loop" x="2" y="2"/></g>'
                           '<use id="self" href="#self" x="3"/><use href="#missing" fill="#f00"/><use href="nohash"/>'
                           '<use href="#grad"/><linearGradient id="grad"/><symbol id="s"><rect x="14" y="14" '
                           'width="6" height="6" fill="#0c0"/></symbol><use href="#s"/>'
                           '<use href=" #c2 " display="none"/><circle id=" c2 " cx="20" cy="4" r="3" fill="#06c"/>'
                           '<use href="#c2" x="-4" y="16"/>'), True),
    ("named colours", svg('<rect x="0" y="0" width="6" height="8" fill="rebeccapurple"/><rect x="6" y="0" width="6" height="8" fill="CornflowerBlue"/><rect x="12" y="0" width="6" height="8" fill="darkSlateGrey"/><rect x="18" y="0" width="6" height="8" fill="papayawhip"/><rect x="0" y="8" width="6" height="8" fill="lightgoldenrodyellow"/><rect x="6" y="8" width="6" height="8" fill="tomato"/><rect x="12" y="8" width="6" height="8" fill="mediumspringgreen"/><rect x="18" y="8" width="6" height="8" fill="blueviolet"/><rect x="0" y="16" width="6" height="8" fill="Peru"/><rect x="6" y="16" width="6" height="8" fill="navajowhite"/><rect x="12" y="16" width="6" height="8" fill="firebrick"/><rect x="18" y="16" width="6" height="8" fill="olivedrab"/>'), False),
    ("hsl colours", svg('<rect x="0" y="0" width="6" height="8" fill="hsl(0, 100%, 50%)"/><rect x="6" y="0" width="6" height="8" fill="hsl(120deg 100% 25%)"/><rect x="12" y="0" width="6" height="8" fill="hsl(210, 60%, 70%)"/><rect x="18" y="0" width="6" height="8" fill="hsla(300, 50%, 50%, .5)"/><rect x="0" y="8" width="6" height="8" fill="hsl(-60 80% 40% / 75%)"/><rect x="6" y="8" width="6" height="8" fill="hsl(725, 40%, 55%)"/><rect x="12" y="8" width="6" height="8" fill="hsl(45, 0%, 30%)"/><rect x="18" y="8" width="6" height="8" fill="hsl(200 120% -5%)"/><rect x="0" y="16" width="6" height="8" fill="rgb(10 200 30 / .4)"/><rect x="6" y="16" width="6" height="8" fill="rgb(100% 50% 0% / 25%)"/><rect x="12" y="16" width="6" height="8" fill="hsl(30.5, 66.6%, 33.3%)"/><rect x="18" y="16" width="6" height="8" fill="HSL(90,100%,100%)"/>'), False),
    ("units", svg('<rect x="0.25in" y="2mm" width="12pt" height="1.5pc" fill="#c33"/>'
                  '<circle cx="1.6cm" cy="7.5px" r="0.25em" fill="#3c3"/><g font-size="8"><rect x="1em" y="2ex" '
                  'width="1.25em" height="1EM" fill="#33c" stroke="#000" stroke-width=".1em"/></g>'
                  '<line x1="1" y1="22" x2="23" y2="22" stroke="#880" stroke-width="2.4pt"/>'
                  '<rect x="3q" y="3" width="4" height="4"/><rect x="0" y="0" width="5zz" height="4"/>'), False),
    ("percent lengths", svg('<rect x="10%" y="25%" width="50%" height="12.5%" fill="#a5f"/>'
                            '<circle cx="75%" cy="75%" r="10%" fill="none" stroke="#063" stroke-width="2%"/>'
                            '<ellipse cx="25%" cy="80%" rx="20%" ry="5%" fill="#e90"/>', 'viewBox="0 0 40 20"'), False),
    ("font sizes", svg('<g font-size="x-small"><rect width="1em" height="1em" fill="#f00"/>'
                       '<g style="font-size:larger"><rect x="12" width="1em" height="1em" fill="#0a0"/>'
                       '<g font-size="150%"><rect y="12" width="1em" height="0.5em" fill="#00f"/></g></g>'
                       '<g font-size="smaller"><rect x="12" y="12" width="1em" height="1em" fill="#0aa"/></g>'
                       '<g font-size="xx-large" class="f"><rect x="20" y="20" width=".1em" height=".1em"/></g></g>'
                       '<style>.f{font-size:0.25in}</style>', 'viewBox="0 0 24 24"'), False),
    ("root units", svg('<rect width="12" height="12" fill="#246"/><rect x="12" y="12" width="12" height="12" fill="#642"/>',
                       'width="2em" height="1.5em"'), False),
    ("root percent", svg('<rect width="50%" height="50%" fill="#246"/>', 'width="100%" height="50%"'), False),
    ("inherit", svg('<g fill="#c00" stroke="#00c" stroke-width="2" opacity=".5"><g fill="#0c0" stroke-width="4">'
                    '<rect x="2" y="2" width="8" height="8" fill="inherit" style="stroke-width:inherit"/>'
                    '<rect x="14" y="2" width="8" height="8" style="fill:inherit" opacity="inherit"/>'
                    '<circle cx="6" cy="17" r="4" stroke="inherit" stroke-linecap="inherit" fill="#ff0"/></g>'
                    '<g style="fill:#0cc"><rect x="13" y="13" width="8" height="8" fill="red" style="fill: inherit !important"/>'
                    '</g></g>'), False),
    ("color property", svg('<g color="#d40"><rect x="1" y="1" width="10" height="10" fill="currentColor"/>'
                           '<g style="color:hsl(120,100%,30%)"><circle cx="17" cy="6" r="4" fill="none" '
                           'stroke="currentColor" stroke-width="2"/></g><rect x="1" y="13" width="10" height="10" '
                           'color="rgba(0,0,255,.5)" fill="currentColor"/><g color="currentColor">'
                           '<rect x="13" y="13" width="10" height="10" fill="currentColor"/></g></g>'), False),
    ("visibility", svg('<g visibility="hidden"><rect width="10" height="10" fill="#f00"/>'
                       '<rect x="12" width="10" height="10" visibility="visible" fill="#0a0"/>'
                       '<g style="visibility:collapse"><circle cx="5" cy="18" r="4"/></g></g>'
                       '<rect x="12" y="12" width="10" height="10" fill="#00f" visibility="bogus"/>'), False),
    ("paint order", svg('<g stroke="#000" stroke-width="4" fill="#fc0"><rect x="3" y="3" width="8" height="8" '
                        'paint-order="stroke"/><rect x="14" y="3" width="8" height="8" paint-order="markers stroke fill"/>'
                        '<rect x="3" y="14" width="8" height="8" style="paint-order:fill stroke"/>'
                        '<rect x="14" y="14" width="8" height="8" paint-order="stroke bogus"/></g>'), False),
    ("dashes", svg('<g fill="none" stroke="#039" stroke-width="2"><path d="M2 3H22" stroke-dasharray="4 2"/>'
                   '<path d="M2 7H22" stroke-dasharray="3" stroke-dashoffset="1.5"/>'
                   '<path d="M2 11H22" stroke-dasharray="1,2,3"/><circle cx="8" cy="18" r="4" '
                   'stroke-dasharray="25%" stroke-linecap="round"/><path d="M14 15H22" stroke-dasharray="0 0"/>'
                   '<path d="M14 18H22" stroke-dasharray="2 -1"/><path d="M14 21H22" stroke-dasharray=".5em 1x" '
                   'font-size="4"/><g stroke-dasharray="2 1"><path d="M2 23H12" stroke-dasharray="none"/>'
                   '<path d="M14 23.5H22" stroke-dashoffset="-1"/></g></g>'), False),
    ("lucide style", svg('<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
                         'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
                         'stroke-linejoin="round"'), True),
    ("material style", svg('<path d="M0 0h24v24H0z" fill="none"/><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 '
                           '10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>'), False),
    ("fontawesome style", svg('<path d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm0 448c-110.5 0-200-89.5-200-200S145.5 56 256 56s200 89.5 200 200-89.5 200-200 200z"/>',
                              'viewBox="0 0 512 512"'), True),
]


def run(tool, d, cmds):
    sp, raw = os.path.join(d, "s.bin"), os.path.join(d, "s.raw")
    open(sp, "wb").write(encode(cmds))
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (np.frombuffer(open(raw, "rb").read(), np.uint8).astype(int) if r.returncode == 0 else None), r.returncode


def svg_cmd(text, current, x, y, size):
    return ('svg', text.encode(), current, x, y, size)


def main():
    tool = os.path.abspath(sys.argv[1])
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_svg.") as d:
        blank, _ = run(tool, d, [])
        for name, text, trig in CASES:
            for current, (x, y, size) in ((0xFF2050C0, (8, 0, 32)), (0x80E0E020, (2, 3, 27.5))):
                total += 1
                got, rc = run(tool, d, [svg_cmd(text, current, x, y, size)])
                doc = svgmodel.parse(text)
                want, rc2 = run(tool, d, expected_calls(doc, current, x, y, size))
                if got is None or want is None:
                    print(f"FAIL  {name:20} exit {rc}/{rc2}")
                    failed += 1
                    continue
                diff = np.abs(got - want).reshape(-1, 4).max(axis=1)
                off = int((diff > 1).sum())
                exact = int(diff.max()) == 0
                ok = exact or (trig and off <= 3)
                painted = int((want != blank).reshape(-1, 4).any(axis=1).sum())
                failed += not ok
                print(f"{'ok  ' if ok else 'FAIL'}  {name:20} items={len(doc.items):2} max_diff={int(diff.max()):3d} "
                      f"pixels_off={off} painted={painted}")
        for name, text in (("not svg", "<html><body/></html>"), ("empty", ""), ("text only", "hello"),
                           ("too deep", "<svg>" + "<g>" * 70 + "</g>" * 70 + "</svg>")):
            total += 1
            _, rc = run(tool, d, [svg_cmd(text, 0xFF000000, 0, 0, 16)])
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  refuse {name:16} exit={rc}")
        total += 1
        _, rc = run(tool, d, [svg_cmd('<svg viewBox="0 0 10 10"><rect width="5" height="5"/>', 0xFF000000, 0, 0, 16)])
        failed += rc != 0
        print(f"{'ok  ' if rc == 0 else 'FAIL'}  unterminated document kept   exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
