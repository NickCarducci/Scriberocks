"""Custom SF Symbol (template 3.0) for rocks, from the logo's corners (traced with
OpenCV: alpha-channel contour, approxPolyDP epsilon 3px, max distance 1.92px at
1024px). Writes the SVG and checks the round trip against the source drawing:

  python3 scripts/make-rock-symbol.py Scriberocks/Assets.xcassets/rock.symbolset/rock.svg logo.png

Needs opencv-python-headless and numpy (only for the round-trip check)."""
import json, sys
import cv2, numpy as np

V = [(766, 349), (552, 284), (522, 398), (573, 513), (508, 423), (351, 389), (229, 540), (405, 739), (752, 688)]
xs, ys = [v[0] for v in V], [v[1] for v in V]
# Medium-scale guides: baseline y=1126, capline y=625.541 (cap height 70.459).
CAP = 70.459
H = 116.0                                 # glyph height: matches the visual weight of circle symbols (e.g. person.crop.circle.fill) in a tab bar
k = H / (max(ys) - min(ys))
mid = -CAP / 2                            # centered on the cap height
pad = 3.0                                  # side bearing inside the margins
def glyph(x, y):
    return (pad + (x - min(xs)) * k, mid + (y - (min(ys) + max(ys)) / 2) * k)
pts = [glyph(x, y) for x, y in V]
width = pad * 2 + (max(xs) - min(xs)) * k
d = "M" + " L".join(f"{x:.3f} {y:.3f}" for x, y in pts) + " Z"

cols = {"Regular-M": 1391.27}  # filled: one glyph serves every weight
guides = "\n".join(
    f'  <line id="left-margin-{n}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{x:.3f}" x2="{x:.3f}" y1="1030.79" y2="1150.12"/>\n'
    f'  <line id="right-margin-{n}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{x + width:.3f}" x2="{x + width:.3f}" y1="1030.79" y2="1150.12"/>'
    for n, x in cols.items())
symbols = "\n".join(
    f'  <g id="{n}" transform="matrix(1 0 0 1 {x:.3f} 1126)">\n   <path d="{d}"/>\n  </g>' for n, x in cols.items())
svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!--Scriberocks rock: corners traced from the logo (OpenCV contour, approxPolyDP epsilon 3px; max distance 1.92px at 1024px).-->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <g id="Notes">
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 322)">Template v.3.0</text>
  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 342)">Scriberocks rock</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.577;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
{guides}
 </g>
 <g id="Symbols">
{symbols}
 </g>
</svg>
'''
open(sys.argv[1], "w").write(svg)

# Round trip: draw the symbol's polygon back at the source scale; compare to the source mask.
raw = cv2.imread(sys.argv[2], cv2.IMREAD_UNCHANGED)
src = (raw[:, :, 3] > 128).astype(np.uint8)
back = np.zeros_like(src)
poly = np.array([[min(xs) + (x - pad) / k, (min(ys) + max(ys)) / 2 + (y - mid) / k] for x, y in pts])
cv2.fillPoly(back, [np.round(poly).astype(np.int32)], 1)
inter, union = (src & back).sum(), (src | back).sum()
print(f"glyph {width:.1f} x {H:.1f} units (cap height {CAP}); overlap with the drawing: IoU {inter / union:.4f}")
