"""Split the single-file PIECENOA HTML into index.html + css/ + js/ + assets/.

Usage: python3 -I split.py <source.html> <output public dir>
Writes manifest.json (published path -> original data URI key info) for verification.
"""
import base64, json, os, re, sys

src, out = sys.argv[1], sys.argv[2]
html = open(src, encoding="utf-8").read()

EXT = {
    "font/woff2": "woff2", "font/ttf": "ttf", "image/jpeg": "jpg", "image/webp": "webp",
    "image/avif": "avif", "image/svg+xml": "svg", "image/png": "png",
    "application/gzip": "glb.gz", "model/gltf-binary": "glb",
}
FOLDER = {"font": "fonts", "image": "images", "application": "models", "model": "models"}
KEEP_INLINE_BELOW = 4096  # base64 chars

DATA_RE = re.compile(r"data:([\w/+.-]+);base64,([A-Za-z0-9+/=]+)")


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


manifest, used, font_count = [], set(), {}


def name_for(mime, start):
    before = html[max(0, start - 200):start]
    ext = EXT[mime]
    folder = FOLDER[mime.split("/")[0]]
    m = re.search(r'font-family:\s*"?([^;"]+)"?;[^{}]*$', before)
    if mime.startswith("font/") and m:
        fam = slug(m.group(1))
        font_count[fam] = font_count.get(fam, 0) + 1
        base = f"{fam}-{font_count[fam]}"
    elif 'class="gallery-poster" src="' in before[-40:]:
        base = "gallery-poster"
    else:
        k = re.search(r'"([\w]+)":"$', before)
        if not k:
            raise SystemExit(f"Unknown context for data URI at {start}: {before[-80:]!r}")
        key = k.group(1)
        base = ("photo-" + key) if key.isdigit() else slug(re.sub(r"(?<!^)([A-Z0-9]+)", r"-\1", key))
    name = f"{folder}/{base}.{ext}"
    if name in used:
        raise SystemExit("duplicate " + name)
    used.add(name)
    return name


def externalize(match):
    mime, data = match.group(1), match.group(2)
    if len(data) < KEEP_INLINE_BELOW:
        return match.group(0)
    rel = name_for(mime, match.start())
    path = os.path.join(out, "assets", rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = base64.b64decode(data, validate=True)
    with open(path, "wb") as f:
        f.write(raw)
    manifest.append({"path": "assets/" + rel, "mime": mime, "bytes": len(raw), "offset": match.start()})
    return "\0ASSET:" + rel + "\0"


body = DATA_RE.sub(externalize, html)

# Pull <style> and <script> blocks into files, in document order.
styles = list(re.finditer(r"<style((?: id=\"[\w-]+\")?)>(.*?)</style>", body, re.S))
scripts = list(re.finditer(r"<script>(.*?)</script>", body, re.S))
assert len(styles) == 2 and len(scripts) == 3, (len(styles), len(scripts))

css_names = ["css/gallery.css", "css/market.css"]
js_names = ["js/vendor/three.min.js", "js/gallery.js", "js/app.js"]


def write(rel, text):
    path = os.path.join(out, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


pieces, last = [], 0
blocks = [(m, "style", i) for i, m in enumerate(styles)] + [(m, "script", i) for i, m in enumerate(scripts)]
for m, kind, i in sorted(blocks, key=lambda b: b[0].start()):
    pieces.append(body[last:m.start()])
    content = m.group(m.lastindex)
    if kind == "style":
        # CSS lives in /css, so asset URLs step up one folder.
        write(css_names[i], content.replace("\0ASSET:", "../assets/").replace("\0", ""))
        pieces.append(f'<link rel="stylesheet"{m.group(1)} href="{css_names[i]}">')
    else:
        write(js_names[i], content.replace("\0ASSET:", "assets/").replace("\0", ""))
        pieces.append(f'<script src="{js_names[i]}"></script>')
    last = m.end()
pieces.append(body[last:])
index = "".join(pieces).replace("\0ASSET:", "assets/").replace("\0", "")
assert "\0" not in index
write("index.html", index)

with open(os.path.join(out, "..", "split-manifest.json"), "w") as f:
    json.dump({"source": os.path.basename(src), "files": manifest,
               "css": css_names, "js": js_names}, f, indent=1)
print(len(manifest), "assets written,", sum(x["bytes"] for x in manifest) // 1024, "KB")
