"""Live-market edits to the piecenoa-2 public/js/app.js.

Each replacement must match exactly once, otherwise nothing is written.
Usage: python3 -I tools/patches/v2_app.py public/js/app.js
"""
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8', newline='').read()
out = src

def sub(old, new, count=1):
    global out
    found = out.count(old)
    if found != count:
        raise SystemExit(f'expected {count} match(es), found {found}: {old[:90]!r}')
    out = out.replace(old, new)

sub('const COPY={', r'''const COPY={"demo_action_blocked":["This is an example piece and is not for sale.","예시 작품이라 실제로 판매하지 않아요."],"visibility_label":["Visibility","공개 설정"],"visibility_public":["Public","공개"],"visibility_private":["Private (only you)","비공개 (나만 보기)"],"private_badge":["Private","비공개"],''')
sub('"example":["Preview","예시"]', '"example":["Example","예시"]')
sub('"sample_listing":["Preview listing","예시 판매글"]', '"sample_listing":["Example listing","예시 판매글"]')

# Signed-out visitors get the log-in dialog instead of a dead end.
sub("function requireMarketReady(){if(repositoryReady){if(!isPreview&&!viewerId){notify('auth_required');return false}",
    "function requireMarketReady(){if(repositoryReady){if(!isPreview&&!viewerId){notify('auth_required');document.querySelector('#header-auth')?.click();return false}")
sub("$$('[data-sell]').forEach(button=>button.addEventListener('click',openSell));",
    "$$('[data-sell]').forEach(button=>button.addEventListener('click',()=>{if(!isPreview&&repositoryReady&&!viewerId){requireMarketReady();return}openSell()}));")

# Example pieces stay visible in the live market, labelled, and cannot be saved or inquired about.
sub('const allPosts=()=>[...posts,...(isPreview?seeds:[])];', 'const allPosts=()=>[...posts,...seeds];')
sub('async function toggleFavorite(id){if(!requireMarketReady()||pendingFavorites.has(id))return;',
    "async function toggleFavorite(id){if(!isPreview&&findPost(id)?.demo){notify('demo_action_blocked');return}if(!requireMarketReady()||pendingFavorites.has(id))return;")
sub('function startThread(post){if(!requireMarketReady())return;',
    "function startThread(post){if(!isPreview&&post?.demo){notify('demo_action_blocked');return}if(!requireMarketReady())return;")

# Explore shows only public, active pieces; the owner sees private ones in My page only.
sub("const items=allPosts().filter(p=>(mode==='all'||mode==='favorites'&&favorites.has(p.id)||mode==='mine'&&p.mine)&&",
    "const items=allPosts().filter(p=>(mode==='all'&&p.visibility!=='private'&&p.moderation!=='hidden'||mode==='favorites'&&favorites.has(p.id)||mode==='mine'&&p.mine)&&")

# Reload when a different member signs in or out.
sub('setupGalleryAuth({showDialog});',
    "setupGalleryAuth({showDialog});\nwindow.addEventListener('piecenoa:viewer-changed',()=>initializeMarketData());")

# Owners can make a piece public or private (live market only).
sub("statusName(value)+'</option>').join('')+'</select><button class=\"delete-post\"",
    "statusName(value)+'</option>').join('')+'</select>'+(isPreview?'':'<select id=\"post-visibility\" data-post-visibility aria-label=\"'+esc(t('visibility_label'))+'\"><option value=\"public\" '+(p.visibility!=='private'?'selected':'')+'>'+t('visibility_public')+'</option><option value=\"private\" '+(p.visibility==='private'?'selected':'')+'>'+t('visibility_private')+'</option></select>'+(p.visibility==='private'?'<span class=\"status-chip\">'+t('private_badge')+'</span>':''))+'<button class=\"delete-post\"")
sub("$('#detail-dialog').addEventListener('change',async event=>{const select=event.target;if(!select.matches('[data-post-status]'))return;const p=findPost(selectedId),next=select.value;if(!p?.mine||!statuses.includes(next)||!requireMarketReady())return;select.disabled=true;try{const full=toListingDTO({...p,status:next}),",
    "$('#detail-dialog').addEventListener('change',async event=>{const select=event.target,isStatus=select.matches('[data-post-status]');if(!isStatus&&!select.matches('[data-post-visibility]'))return;const p=findPost(selectedId),next=select.value;if(!p?.mine||!(isStatus?statuses.includes(next):['public','private'].includes(next))||!requireMarketReady())return;select.disabled=true;try{const full=toListingDTO({...p,...(isStatus?{status:next}:{visibility:next})}),")
sub("negotiable:Boolean(p.negotiable),region:p.region,location:{text:displayLocation(p)",
    "negotiable:Boolean(p.negotiable),visibility:p.visibility,region:p.region,location:{text:displayLocation(p)")
sub("render();renderDetail()}catch(error){select.value=p.status;repositoryError(error)}",
    "render();renderDetail()}catch(error){select.value=isStatus?p.status:p.visibility||'public';repositoryError(error)}")

open(path, 'w', encoding='utf-8', newline='').write(out)
print('v2 app.js patch applied:', len(src), '->', len(out), 'chars')
