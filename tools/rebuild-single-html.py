"""Rebuild the original single-file HTML from a split public/ folder.

Usage: python3 -I tools/rebuild-single-html.py <public dir> <split-manifest.json> <output.html>
Inverse of split-single-html.py: inlines css/js back into the page and every asset back as a
base64 data URI. Running it on the first commit's public/ reproduces the source byte for byte.
"""
import base64, json, re, sys

public, manifest_path, output = sys.argv[1], sys.argv[2], sys.argv[3]
manifest = json.load(open(manifest_path))
mime = {f['path']: f['mime'] for f in manifest['files']}

def uri(path):
    with open(f'{public}/{path}', 'rb') as f:
        return 'data:%s;base64,%s' % (mime[path], base64.b64encode(f.read()).decode())

page = open(f'{public}/index.html', encoding='utf-8', newline='').read()

def css(match):
    text = open(f'{public}/{match.group(2)}', encoding='utf-8', newline='').read()
    text = re.sub(r'\.\./(assets/[\w/.-]+)', lambda m: uri(m.group(1)), text)
    return '<style%s>%s</style>' % (match.group(1), text)

page = re.sub(r'<link rel="stylesheet"((?: id="[\w-]+")?) href="([\w/.-]+)">', css, page)
page = re.sub(r'<script src="([\w/.-]+)"></script>',
              lambda m: '<script>%s</script>' % open(f'{public}/{m.group(1)}', encoding='utf-8', newline='').read(), page)
page = re.sub(r'(?<=["(])(assets/(?:images|fonts|models)/[\w.-]+)(?=[")])', lambda m: uri(m.group(1)), page)
open(output, 'w', encoding='utf-8', newline='').write(page)
print('wrote', output, len(page), 'chars')
