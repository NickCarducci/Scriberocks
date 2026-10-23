"""Replace the App Store screenshots of Scriberocks' editable App Store version
(en-US) with the PNGs in a folder, via the App Store Connect API.

usage: python3 upload-screenshots.py <issuer id> <key .p8> <shots dir>
  <shots dir>/iphone/*.png -> the 6.9-inch iPhone set (1320 x 2868)
  <shots dir>/ipad/*.png   -> the 13-inch iPad set (2064 x 2752)
Files upload in name order. Needs PyJWT + cryptography (a throwaway venv).
"""
import glob, hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt

ISSUER, KEY_PATH, SHOTS = sys.argv[1:4]
KEY_ID = os.path.basename(KEY_PATH).removeprefix("AuthKey_").removesuffix(".p8")
BUNDLE_ID = "sayists.Scriberocks"
API = "https://api.appstoreconnect.apple.com/v1"
# App Store Connect display types for these sizes (6.9-inch iPhone, 13-inch iPad).
SETS = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129"}

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})

def call(method, path, body=None, url=None):
    req = urllib.request.Request(url or API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            data = r.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:600]}")

app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
print("app", app["attributes"]["name"], app["id"])
versions = call("GET", f"/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=10")["data"]
editable = [v for v in versions if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
if not editable:
    sys.exit("no editable App Store version (create the next version in App Store Connect first): " + ", ".join(f"{v['attributes']['versionString']} {v['attributes']['appStoreState']}" for v in versions))
version = editable[0]
print("version", version["attributes"]["versionString"], version["attributes"]["appStoreState"])
locs = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0])
sets = {s["attributes"]["screenshotDisplayType"]: s for s in call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]}

for device, display in SETS.items():
    files = sorted(glob.glob(os.path.join(SHOTS, device, "*.png")))
    if not files:
        continue
    s = sets.get(display) or call("POST", "/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
    old = call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]
    for o in old:
        call("DELETE", f"/appScreenshots/{o['id']}")
    print(f"{device} ({display}): removed {len(old)} old screenshot(s)")
    for f in files:
        data = open(f, "rb").read()
        shot = call("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], method=op["method"], data=part, headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            urllib.request.urlopen(req).read()
        call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"  uploaded {os.path.basename(f)}")
print("done; App Store Connect finishes processing the images in a few minutes")
