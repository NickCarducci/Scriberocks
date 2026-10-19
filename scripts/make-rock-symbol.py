"""Custom SF Symbol (variable template v6.0, Xcode 16+) for rocks, from the logo.

The logo's nine corners were traced with OpenCV (alpha-channel contour,
approxPolyDP epsilon 3px; max 1.92px from the drawn edge at 1024px). Two layers:
  0 (back)  the whole silhouette   - hierarchical secondary, multicolor brown
  1 (front) the right fragment, split along the crack's line from the notch
            to the bottom edge     - hierarchical primary, multicolor gray
In monochrome both layers share a color and the front sits exactly on the back,
so the symbol is the logo with no seam. Separate motion groups let the fragments
animate in turn (byLayer effects). Ultralight/Regular/Black sources (scaled
0.96/1.0/1.04 like Apple's filled symbols); Xcode interpolates all 27 variants.

  python3 scripts/make-rock-symbol.py Scriberocks/Assets.xcassets/rock.symbolset/rock.svg [logo.png]

The optional logo.png runs a round-trip check (needs opencv-python-headless).
"""
import sys

V = [(766, 349), (552, 284), (522, 398), (573, 513), (508, 423), (351, 389), (229, 540), (405, 739), (752, 688)]
NOTCH = (573, 513)
# The crack continued from the notch along the bisector of its mouth until it
# meets the bottom edge (405,739)-(752,688).
mouth = ((522 + 508) / 2, (398 + 423) / 2)
dx, dy = NOTCH[0] - mouth[0], NOTCH[1] - mouth[1]
(ax, ay), (bx, by) = (405, 739), (752, 688)
slope = (by - ay) / (bx - ax)
s = (ay + slope * (NOTCH[0] + 0 - ax) - NOTCH[1]) / (dy - slope * dx)
CRACK_END = (NOTCH[0] + dx * s, NOTCH[1] + dy * s)
FRONT = [(766, 349), (552, 284), (522, 398), NOTCH, CRACK_END, (752, 688)]

CAP = 70.459          # cap height (baseline 696, capline 625.541)
H = 116.0             # matches the visual weight of circle symbols in a tab bar
xs, ys = [v[0] for v in V], [v[1] for v in V]
k = H / (max(ys) - min(ys))
cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
WIDTH = (max(xs) - min(xs)) * k
PAD = 3.0
WEIGHTS = {"Ultralight-S": (515.649, 0.96), "Regular-S": (1403.58, 1.0), "Black-S": (2884.57, 1.04)}


def place(points, scale):
    """Glyph coordinates (origin at the left margin on the baseline), centered on the cap height."""
    w = WIDTH * scale
    return [(PAD + w / 2 + (x - cx) * k * scale, -CAP / 2 + (y - cy) * k * scale) for x, y in points]


def path(points):
    return "M" + " L".join(f"{x:.3f} {y:.3f}" for x, y in points) + " Z"


style = """.monochrome-0 {-sfsymbols-motion-group:0}
.monochrome-1 {-sfsymbols-motion-group:1}

.multicolor-0:systemBrownColor {-sfsymbols-motion-group:0}
.multicolor-1:systemGrayColor {-sfsymbols-motion-group:1}

.hierarchical-0:secondary {-sfsymbols-motion-group:0}
.hierarchical-1:primary {-sfsymbols-motion-group:1}

.SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:black;stroke-width:0.5}"""

margins, symbols, anchors = [], [], []
for name, (left, scale) in WEIGHTS.items():
    right = left + PAD * 2 + WIDTH * scale
    margins.append(f'  <line id="left-margin-{name}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{left:.3f}" x2="{left:.3f}" y1="600.785" y2="720.121"/>')
    margins.append(f'  <line id="right-margin-{name}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{right:.3f}" x2="{right:.3f}" y1="600.785" y2="720.121"/>')
    symbols.append(f'''  <g id="{name}" transform="matrix(1 0 0 1 {left:.3f} 696)">
   <path class="monochrome-0 multicolor-0:systemBrownColor hierarchical-0:secondary SFSymbolsPreviewWireframe" d="{path(place(V, scale))}"/>
   <path class="monochrome-1 multicolor-1:systemGrayColor hierarchical-1:primary SFSymbolsPreviewWireframe" d="{path(place(FRONT, scale))}"/>
  </g>''')
    anchors.append(f'  <circle id="{name}-rotate-anchor" style="fill:#FFCC00;opacity:1.0;" r="1" cx="{left + PAD + WIDTH * scale / 2:.3f}" cy="{696 - CAP / 2:.3f}"/>')

guides = "\n".join(
    f'  <line id="{n}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="{y}" y2="{y}"/>'
    for n, y in [("Baseline-S", 696), ("Capline-S", 625.541), ("Baseline-M", 1126), ("Capline-M", 1055.54), ("Baseline-L", 1556), ("Capline-L", 1485.54)])
svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 3300 2200">
 <style>{style}
</style>
 <g id="Notes">
  <rect id="artboard" x="0" y="0" width="3300" height="2200" style="fill:white;opacity:1"/>
  <text transform="matrix(1 0 0 1 263 322)" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;">Weight/Scale Variations</text>
  <text id="template-version" transform="matrix(1 0 0 1 3036 1933)" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;">Template v.6.0</text>
  <text transform="matrix(1 0 0 1 3036 1951)" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;">Requires Xcode 16 or greater</text>
  <text id="descriptive-name" transform="matrix(1 0 0 1 3036 1969)" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;">Scriberocks rock (from the logo)</text>
 </g>
 <g id="Guides">
{guides}
{chr(10).join(margins)}
 </g>
 <g id="Symbols">
{chr(10).join(symbols)}
 </g>
 <g id="Anchors">
{chr(10).join(anchors)}
 </g>
</svg>
'''
open(sys.argv[1], "w").write(svg)
print(f"glyph {WIDTH:.1f} x {H:.1f} units at Regular; crack meets the bottom edge at ({CRACK_END[0]:.1f}, {CRACK_END[1]:.1f})")

if len(sys.argv) > 2:
    import cv2, numpy as np
    raw = cv2.imread(sys.argv[2], cv2.IMREAD_UNCHANGED)
    src = (raw[:, :, 3] > 128).astype(np.uint8)
    back = np.zeros_like(src)
    cv2.fillPoly(back, [np.array(V, np.int32)], 1)
    front = np.zeros_like(src)
    cv2.fillPoly(front, [np.round(np.array(FRONT)).astype(np.int32)], 1)
    union = back | front
    print(f"monochrome (both layers) vs the drawing: IoU {(src & union).sum() / (src | union).sum():.4f}; "
          f"front fragment inside the silhouette: {(front & back).sum() / front.sum():.4f}")
