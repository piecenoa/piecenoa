import re, sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()

def sub(old, new):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'expected 1 match, found {n}: {old[:80]!r}')
    s = s.replace(old, new)

codes = ['USD', 'EUR', 'GBP', 'KRW', 'JPY', 'CNY', 'HKD', 'TWD', 'SGD', 'AUD', 'CAD', 'CHF']
opts = ''.join(f'<option value="{c}">{c}</option>' for c in codes)

# Sell form: currency next to the price.
m = re.search(r'<input id="post-price"[^>]*>', s)
if not m:
    raise SystemExit('post-price input not found')
sub(m.group(0), '<div class="price-input"><select id="post-currency" aria-label="Currency" data-i18n-aria="currency_label">' + opts + '</select>' + m.group(0) + '</div>')
sub('<span data-i18n="price_help">KRW · enter 0 to give it away</span>', '<span data-i18n="price_help_live">Enter 0 to give it away</span>')

# Explore filters: currency before the budget.
sub('<label class="market-select"><span data-i18n="budget_label">Budget</span>',
    '<label class="market-select"><span data-i18n="currency_label">Currency</span><select id="currency-filter" aria-label="Currency" data-i18n-aria="currency_label"><option value="all" data-i18n="currency_any">Any currency</option>' + opts + '</select></label><label class="market-select"><span data-i18n="budget_label">Budget</span>')

# Studio dialog: profile photo (shown only with a live backend).
sub('<form id="studio-form" class="sell-form" novalidate>',
    '<form id="studio-form" class="sell-form" novalidate><div class="form-field avatar-field" id="profile-avatar-field" hidden><span class="form-label" data-i18n="avatar_label">Profile photo</span><label class="avatar-picker"><span class="studio-avatar" id="profile-avatar-preview" translate="no">S</span><span class="avatar-picker-text" data-i18n="avatar_change">Choose a photo</span><input id="profile-avatar" class="sr-only" type="file" accept="image/jpeg,image/png,image/webp"></label></div>')

# Styles and the market data script.
sub('<link rel="stylesheet" href="css/account.css">', '<link rel="stylesheet" href="css/account.css">\n<link rel="stylesheet" href="css/market-live.css">')
sub('<script src="js/account.js"></script>', '<script src="js/account.js"></script>\n<script src="js/market-supabase.js"></script>')

open(path, 'w', encoding='utf-8').write(s)
print('index.html patched')
