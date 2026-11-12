"""Apply the Supabase account layer to a piecenoa-2 public/index.html.

- Replaces the auth dialog with the stage 2 version (Google, forgot password, account panel)
  after checking the original dialog is unchanged from the version stage 2 was written for.
- Adds css/account.css and the Supabase scripts before js/app.js.
Usage: python3 -I tools/patches/v2_index.py <index.html> <stage2 index.html> <original v1 index.html>
"""
import re, sys

target, stage2, original = sys.argv[1:4]
read = lambda p: open(p, encoding='utf-8', newline='').read()
s, v2, v1 = read(target), read(stage2), read(original)
dialog = re.compile(r'<dialog id="auth-dialog".*?</dialog>', re.S)

current, before, after = dialog.search(s).group(0), dialog.search(v1).group(0), dialog.search(v2).group(0)
if current != before:
    raise SystemExit('auth dialog differs from the stage 2 base; review by hand')
s = s.replace(current, after)

def sub(old, new):
    global s
    if s.count(old) != 1:
        raise SystemExit('expected one match: ' + old[:80])
    s = s.replace(old, new)

sub('<link rel="stylesheet" id="marketplace-foundation-style" href="css/market.css">',
    '<link rel="stylesheet" id="marketplace-foundation-style" href="css/market.css">\n<link rel="stylesheet" href="css/account.css">')
sub('<script src="js/app.js"></script>',
    '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js"></script>\n'
    '<script src="js/config.js"></script>\n<script src="js/account.js"></script>\n<script src="js/market-supabase.js"></script>\n'
    '<script src="js/app.js"></script>')
open(target, 'w', encoding='utf-8', newline='').write(s)
print('index.html: auth dialog + account scripts applied')
