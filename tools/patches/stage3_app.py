"""Stage 3 edits to public/js/app.js (currency, live search, seller profiles, visibility, avatars).

Each replacement must match exactly once, otherwise nothing is written.
Usage: python3 -I tools/patches/stage3_app.py public/js/app.js
"""
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()
out = src

def sub(old, new, count=1):
    global out
    found = out.count(old)
    if found != count:
        raise SystemExit(f'expected {count} match(es), found {found}: {old[:90]!r}')
    out = out.replace(old, new)

# --- Copy -----------------------------------------------------------------
sub('const COPY={', r'''const COPY={"currency_label":["Currency","통화"],"currency_any":["Any currency","모든 통화"],"budget_pick_currency":["Choose a currency first","통화를 먼저 고르세요"],"budget_under":["Under {a}","{a} 미만"],"budget_between":["{a}–{b}","{a}–{b}"],"budget_over":["{a} and above","{a} 이상"],"budget_upto":["Up to {a}","{a} 이하"],"price_help_live":["Enter 0 to give it away","0을 입력하면 나눔"],"visibility_label":["Visibility","공개 설정"],"visibility_public":["Public","공개"],"visibility_private":["Private (only you)","비공개 (나만 보기)"],"private_badge":["Private","비공개"],"hidden_badge":["Hidden after review","운영 검토로 숨겨짐"],"demo_action_blocked":["This is an example piece and is not for sale.","예시 작품이라 실제로 판매하지 않아요."],"favorite_unavailable":["No longer available","더 이상 볼 수 없는 작품"],"favorite_unavailable_hint":["The seller removed this piece or made it private.","판매자가 삭제했거나 비공개로 바꿨어요."],"unsave_unavailable":["Remove from favorites","관심 작품에서 빼기"],"avatar_label":["Profile photo","프로필 사진"],"avatar_change":["Choose a photo","사진 고르기"],"error_avatar":["Use a JPG, PNG or WebP photo up to 8 MB.","8MB 이하의 JPG, PNG, WebP 사진을 골라 주세요."],''')
sub('"example":["Preview","예시"]', '"example":["Example","예시"]')
sub('"sample_listing":["Preview listing","예시 판매글"]', '"sample_listing":["Example listing","예시 판매글"]')

# --- Currency helpers (defined before the repositories use them) -----------
sub('function toListingDTO', r'''const CURRENCY_MINOR={USD:2,EUR:2,GBP:2,KRW:0,JPY:0,CNY:2,HKD:2,TWD:2,SGD:2,AUD:2,CAD:2,CHF:2};
const currencyOf=p=>CURRENCY_MINOR[p?.currency]!==undefined?p.currency:'KRW';
function priceInputOk(raw,currency){const digits=CURRENCY_MINOR[currency]??0;return(digits?new RegExp('^[0-9]{1,9}(\\.[0-9]{1,'+digits+'})?$'):/^[0-9]{1,9}$/).test(String(raw))}
const BUDGET_SCALE={KRW:1000,JPY:100,TWD:30,CNY:5,HKD:5};
function budgetBounds(range,currency){const f=BUDGET_SCALE[currency]||1;return range==='under50'?{max:50*f}:range==='50to200'?{min:50*f,max:200*f}:range==='200to500'?{min:200*f,max:500*f}:range==='over500'?{min:500*f}:range==='under100'?{max:100*f,maxInclusive:true}:{}}
function guessCurrency(){try{const saved=localStorage.getItem('piecenoa.currency');if(CURRENCY_MINOR[saved]!==undefined)return saved}catch{}const language=navigator.language||'',region=(language.split('-')[1]||'').toUpperCase(),EURO=['DE','FR','ES','IT','NL','AT','BE','IE','PT','FI','GR','LU','SK','SI','EE','LV','LT','MT','CY','HR'];return{KR:'KRW',JP:'JPY',GB:'GBP',CN:'CNY',HK:'HKD',TW:'TWD',SG:'SGD',AU:'AUD',CA:'CAD',CH:'CHF'}[region]||(EURO.includes(region)?'EUR':language.startsWith('ko')?'KRW':language.startsWith('ja')?'JPY':'USD')}
function toListingDTO''')
sub("currency:'KRW',category:CATEGORY_CODES[p.category]||p.category,",
    "currency:currencyOf(p),visibility:p.visibility==='private'?'private':'public',category:CATEGORY_CODES[p.category]||p.category,")
sub("p.currency&&p.currency!=='KRW'||!Number.isInteger(p.price)||p.price<0",
    "p.currency&&CURRENCY_MINOR[p.currency]===undefined||!Number.isFinite(p.price)||p.price<0")
sub("const money=value=>Number(value)===0?t('free'):locale==='ko'?new Intl.NumberFormat('ko-KR').format(value)+'원':new Intl.NumberFormat('en-US',{style:'currency',currency:'KRW',maximumFractionDigits:0}).format(value);",
    r'''const money=(value,currency='KRW')=>{if(Number(value)===0)return t('free');const code=CURRENCY_MINOR[currency]!==undefined?currency:'KRW';if(locale==='ko'&&code==='KRW')return new Intl.NumberFormat('ko-KR').format(value)+'원';const digits=Number.isInteger(Number(value))?0:CURRENCY_MINOR[code];return new Intl.NumberFormat('en-US',{style:'currency',currency:code,minimumFractionDigits:digits,maximumFractionDigits:digits}).format(value)};''')
sub('money(p.price)', 'money(p.price,p.currency)', count=2)
sub('money(post?.price??thread.price)', 'money(post?.price??thread.price,post?.currency||thread.currency)')

# --- State --------------------------------------------------------------
sub('let publishing=false,sendingMessage=false;',
    "let publishing=false,sendingMessage=false;\nlet remoteKey='',remoteIds=null,remoteSeq=0,remoteTimer=0,liveTimer=0,liveUnsubscribe=null,sellerSeq=0,pendingAvatar=null;")

# --- Sign-in prompts and example pieces in the live market -----------------
sub("function requireMarketReady(){if(repositoryReady){if(!isPreview&&!viewerId){notify('auth_required');return false}return true;}",
    "function requireMarketReady(){if(repositoryReady){if(!isPreview&&!viewerId){notify('auth_required');document.querySelector('#market-account')?.click();return false}return true;}")
sub("async function toggleFavorite(id){if(!requireMarketReady()||pendingFavorites.has(id))return;",
    "async function toggleFavorite(id){if(!isPreview&&findPost(id)?.demo){notify('demo_action_blocked');return}if(!requireMarketReady()||pendingFavorites.has(id))return;")
sub("async function startThread(p){if(!requireMarketReady())return;",
    "async function startThread(p){if(!isPreview&&p.demo){notify('demo_action_blocked');return}if(!requireMarketReady())return;")
sub("$$('[data-sell]').forEach(button=>button.addEventListener('click',openSell));",
    "$$('[data-sell]').forEach(button=>button.addEventListener('click',()=>{if(!isPreview&&repositoryReady&&!viewerId){requireMarketReady();return}openSell()}));")
sub('const allPosts=()=>[...posts,...(isPreview?seeds:[])];', 'const allPosts=()=>[...posts,...seeds];')

# --- Bootstrap: profile photo, Explore results, live updates ----------------
sub("value.role:'artist'};repositoryReady=true",
    "value.role:'artist',avatarUrl:safeMediaURL(value.avatarUrl)?value.avatarUrl:'',avatarPath:value.avatarPath||null};repositoryReady=true;if(!liveUnsubscribe&&typeof repository.subscribe==='function')liveUnsubscribe=repository.subscribe(onLiveChange)")
sub("conversations=(Array.isArray(data.conversations)?data.conversations:[]).map(fromConversationDTO);",
    "conversations=(Array.isArray(data.conversations)?data.conversations:[]).map(fromConversationDTO);remoteIds=Array.isArray(data.feedIds)?data.feedIds:null;remoteKey='';")

# --- Sellers -----------------------------------------------------------------
sub("function sellerFor(p){if(p.mine)return{id:'local-studio',name:profile.name||t('my_studio'),bio:profile.bio,...normalizeLocation(profile),role:profile.role};",
    "function sellerFor(p){if(p.mine)return{id:'local-studio',name:profile.name||t('my_studio'),bio:profile.bio,...normalizeLocation(profile),role:profile.role,avatarUrl:profile.avatarUrl};")
sub("role:['artist','collector','studio'].includes(value.role)?value.role:'collector'}}",
    "role:['artist','collector','studio'].includes(value.role)?value.role:'collector',avatarUrl:safeMediaURL(value.avatarUrl)?value.avatarUrl:''}}\nconst avatarHTML=seller=>seller?.avatarUrl&&safeMediaURL(seller.avatarUrl)?'<img src=\"'+esc(seller.avatarUrl)+'\" alt=\"\" loading=\"lazy\" decoding=\"async\">':esc(studioInitials(seller?.name||''))")
sub('esc(studioInitials(seller.name))', 'avatarHTML(seller)', count=2)
sub("$('#studio-avatar').textContent=studioInitials(name);",
    "$('#studio-avatar').innerHTML=avatarHTML({name,avatarUrl:profile.avatarUrl});")

old_seller_start = "function openSeller(id){const p=findPost(id);if(!p)return;const seller=sellerFor(p),items=allPosts().filter(item=>p.mine?item.mine:p.demo?item.demo&&item.sellerId===p.sellerId:!item.demo&&item.ownerId===p.ownerId);$('#seller-content').innerHTML='<header class=\"seller-profile\"><span class=\"studio-avatar\" translate=\"no\">'+avatarHTML(seller)+'</span><div><p class=\"eyebrow\">'+esc(t('seller_role_'+seller.role))+'</p><h2 id=\"seller-title\">'+esc(seller.name)+'</h2><p>'+esc(areaName(seller))+'</p><p>'+esc(seller.bio||'')+'</p></div></header><h3 class=\"seller-section-title\">'+t('seller_works')+'</h3><div class=\"product-grid\">'+items.map(renderCard).join('')+'</div>';$('#detail-dialog').close();showDialog($('#seller-dialog'))}"
sub(old_seller_start, r'''function sellerHTML(seller,items){return'<header class="seller-profile"><span class="studio-avatar" translate="no">'+avatarHTML(seller)+'</span><div><p class="eyebrow">'+esc(t('seller_role_'+seller.role))+'</p><h2 id="seller-title">'+esc(seller.name)+'</h2><p>'+esc(areaName(seller))+'</p><p>'+esc(seller.bio||'')+'</p></div></header><h3 class="seller-section-title">'+t('seller_works')+'</h3><div class="product-grid">'+items.map(renderCard).join('')+'</div>'}
function openSeller(id){const p=findPost(id);if(!p)return;const seller=sellerFor(p),items=allPosts().filter(item=>p.mine?item.mine:p.demo?item.demo&&item.sellerId===p.sellerId:!item.demo&&item.ownerId===p.ownerId&&item.visibility!=='private');$('#seller-content').innerHTML=sellerHTML(seller,items);$('#detail-dialog').close();if(!$('#seller-dialog').open)showDialog($('#seller-dialog'));
 if(isPreview||p.demo||p.mine||typeof repository.loadSeller!=='function')return;const seq=++sellerSeq;
 repository.loadSeller(p.ownerId).then(result=>{if(seq!==sellerSeq||!$('#seller-dialog').open)return;const fresh=(result.listings||[]).map(dto=>{try{return mergeListing(dto)}catch{return null}}).filter(Boolean);$('#seller-content').innerHTML=sellerHTML(sellerFor({...p,sellerInfo:result.seller||p.sellerInfo}),fresh)}).catch(error=>console.warn('[PIECENOA] seller load failed',error))}''')

# --- Studio profile with photo ---------------------------------------------
sub("function openStudio(){const form=$('#studio-form');form.reset();",
    "function openStudio(){const form=$('#studio-form');form.reset();pendingAvatar=null;const avatarField=$('#profile-avatar-field');if(avatarField){avatarField.hidden=typeof repository.uploadAvatar!=='function';$('#profile-avatar-preview').innerHTML=avatarHTML({name:profile.name||t('my_studio'),avatarUrl:profile.avatarUrl})}")
sub("try{const place=normalizeLocation(profile),next=await repository.updateProfile({name,bio,region:place.region,location:{text:place.locationText,countryCode:place.countryCode,city:place.city},role});profile={name:String(next.name||name).slice(0,40),bio:String(next.bio||'').slice(0,240),...normalizeLocation(next.location||next.countryCode||next.region?next:profile),role:['artist','collector','studio'].includes(next.role)?next.role:role};",
    "try{const previousAvatar=profile.avatarPath;let avatarPath;if(pendingAvatar&&typeof repository.uploadAvatar==='function')avatarPath=(await repository.uploadAvatar({dataUrl:pendingAvatar})).path;const place=normalizeLocation(profile),next=await repository.updateProfile({name,bio,region:place.region,location:{text:place.locationText,countryCode:place.countryCode,city:place.city},role,...(avatarPath?{avatarPath}:{})});profile={name:String(next.name||name).slice(0,40),bio:String(next.bio||'').slice(0,240),...normalizeLocation(next.location||next.countryCode||next.region?next:profile),role:['artist','collector','studio'].includes(next.role)?next.role:role,avatarUrl:safeMediaURL(next.avatarUrl)?next.avatarUrl:profile.avatarUrl,avatarPath:next.avatarPath??profile.avatarPath};if(avatarPath&&previousAvatar&&previousAvatar!==avatarPath)repository.removeFile?.('avatars',previousAvatar);pendingAvatar=null;")

# --- Listing cards: private / hidden markers, unavailable favorites -----------
sub("(p.status!=='판매중'?'<span class=\"status-chip '",
    "(p.mine&&p.visibility==='private'?'<span class=\"status-chip\">'+t('private_badge')+'</span>':'')+(p.mine&&p.moderation==='hidden'?'<span class=\"status-chip sold\">'+t('hidden_badge')+'</span>':'')+(p.status!=='판매중'?'<span class=\"status-chip '")

# --- Owner controls: visibility ------------------------------------------------
sub("statusName(value)+'</option>').join('')+'</select><button class=\"delete-post\" id=\"delete-post\" data-delete>'",
    "statusName(value)+'</option>').join('')+'</select>'+(isPreview?'':'<select id=\"post-visibility\" data-post-visibility aria-label=\"'+esc(t('visibility_label'))+'\"><option value=\"public\" '+(p.visibility!=='private'?'selected':'')+'>'+t('visibility_public')+'</option><option value=\"private\" '+(p.visibility==='private'?'selected':'')+'>'+t('visibility_private')+'</option></select>')+'<button class=\"delete-post\" id=\"delete-post\" data-delete>'")
sub("$('#detail-dialog').addEventListener('change',async event=>{const select=event.target;if(!select.matches('[data-post-status]'))return;const p=findPost(selectedId),next=select.value;if(!p?.mine||!statuses.includes(next)||!requireMarketReady())return;select.disabled=true;try{const full=toListingDTO({...p,status:next}),",
    "$('#detail-dialog').addEventListener('change',async event=>{const select=event.target,isStatus=select.matches('[data-post-status]');if(!isStatus&&!select.matches('[data-post-visibility]'))return;const p=findPost(selectedId),next=select.value;if(!p?.mine||!(isStatus?statuses.includes(next):['public','private'].includes(next))||!requireMarketReady())return;select.disabled=true;try{const full=toListingDTO({...p,...(isStatus?{status:next}:{visibility:next})}),")
sub("render();renderDetail()}catch(error){select.value=p.status;repositoryError(error)}",
    "render();renderDetail()}catch(error){select.value=isStatus?p.status:p.visibility||'public';repositoryError(error)}")

# --- Sell form: currency and a larger photo ------------------------------------
sub("fillLocationForm('post',{});const value=editing||sellDraft;if(value){",
    "fillLocationForm('post',{});$('#post-currency').value=guessCurrency();const value=editing||sellDraft;if(value){if(CURRENCY_MINOR[value.currency]!==undefined)$('#post-currency').value=value.currency;")
sub("$('#post-price').value=/^[0-9]{1,9}$/.test(String(value.price))?String(value.price):'';",
    "$('#post-price').value=priceInputOk(value.price,$('#post-currency').value)?String(value.price):'';")
sub("$('#photo').required=!uploadedImage;$('#sell-title').textContent=",
    "updatePriceStep();$('#photo').required=!uploadedImage;$('#sell-title').textContent=")
sub("price:$('#post-price').value,", "price:$('#post-price').value,currency:$('#post-currency').value,")
sub("art=artworkFromForm();if(!uploadedImage)",
    "art=artworkFromForm(),postCurrency=CURRENCY_MINOR[$('#post-currency').value]!==undefined?$('#post-currency').value:'KRW';if(!uploadedImage)")
sub("!/^[0-9]{1,9}$/.test(rawPrice)||!Number.isInteger(price)||price<0||price>999999999",
    "!priceInputOk(rawPrice,postCurrency)||!Number.isFinite(price)||price<0||price>999999999")
sub("const full=toListingDTO({...existing,...art,title,description,price,category:postCategory,",
    "try{localStorage.setItem('piecenoa.currency',postCurrency)}catch{}const full=toListingDTO({...existing,...art,title,description,price,currency:postCurrency,category:postCategory,")
sub('1000/Math.max(image.naturalWidth,image.naturalHeight)', '1600/Math.max(image.naturalWidth,image.naturalHeight)')
sub("const result=canvas.toDataURL('image/jpeg',.82);", "const result=canvas.toDataURL('image/jpeg',.85);")

# --- Filters: currency + budget in that currency, server-side Explore ------------
sub("function priceMatches(value,range){",
    "function priceMatches(p,range,currency){if(range==='all'||currency==='all')return true;if(currencyOf(p)!==currency)return false;const b=budgetBounds(range,currency),v=Number(p.price);return(b.min===undefined||v>=b.min)&&(b.max===undefined||(b.maxInclusive?v<=b.max:v<b.max))}\nfunction legacyPriceMatches(value,range){")
sub("$('#mine-status').value='all'}",
    "$('#mine-status').value='all';if($('#currency-filter'))$('#currency-filter').value='all';updateBudgetOptions()}\nfunction updateBudgetOptions(){const select=$('#price-range'),currency=$('#currency-filter')?.value||'all';if(!select)return;const off=currency==='all';if(off)select.value='all';select.disabled=off;for(const option of select.options){if(option.value==='all'){option.textContent=t(off?'budget_pick_currency':'budget_all');continue}if(off)continue;const b=budgetBounds(option.value,currency);option.textContent=option.value==='over500'?t('budget_over',{a:money(b.min,currency)}):option.value==='under100'?t('budget_upto',{a:money(b.max,currency)}):b.min===undefined?t('budget_under',{a:money(b.max,currency)}):t('budget_between',{a:money(b.min,currency),b:money(b.max,currency)})}}\nfunction updatePriceStep(){const digits=CURRENCY_MINOR[$('#post-currency')?.value]??0;if($('#post-price'))$('#post-price').step=digits?String(10**-digits):'1'}\nfunction requestRemoteResults(params){const key=JSON.stringify(params);if(key===remoteKey)return;remoteKey=key;clearTimeout(remoteTimer);const seq=++remoteSeq;remoteTimer=setTimeout(async()=>{try{const list=await repository.searchListings(params);if(seq!==remoteSeq)return;const ids=[];for(const dto of list){try{ids.push(mergeListing(dto).id)}catch{}}remoteIds=ids;render()}catch(error){if(seq===remoteSeq)remoteKey='';console.warn('[PIECENOA] search failed',error)}},remoteIds===null?0:250)}\nfunction onLiveChange(kind){if(kind!=='listings')return;clearTimeout(liveTimer);liveTimer=setTimeout(()=>{remoteKey='';if(document.body.dataset.view==='market')render()},800)}")

sub("const rawQuery=$('#search').value.trim(),query=searchText(rawQuery),available=$('#available-only').checked,kind=$('#work-kind').value,budget=$('#price-range').value,delivery=$('#delivery-filter').value,mineStatus=$('#mine-status').value;\n const items=allPosts().filter(",
    "const rawQuery=$('#search').value.trim(),query=searchText(rawQuery),available=$('#available-only').checked,kind=$('#work-kind').value,filterCurrency=$('#currency-filter')?.value||'all',budget=filterCurrency==='all'?'all':$('#price-range').value,delivery=$('#delivery-filter').value,mineStatus=$('#mine-status').value,sort=$('#sort').value;\n let pool=allPosts();if(!isPreview&&repositoryReady&&mode==='all'&&typeof repository.searchListings==='function'){requestRemoteResults({query:rawQuery,category:category==='전체'?'':CATEGORY_CODES[category]||'',kind:kind==='all'?'':kind,delivery:delivery==='all'?'':delivery,availableOnly:available,sort,currency:filterCurrency==='all'?'':filterCurrency,...(budget!=='all'?budgetBounds(budget,filterCurrency):{})});pool=[...(remoteIds||[]).map(id=>posts.find(p=>p.id===id)).filter(Boolean),...seeds]}\n const items=pool.filter(")
sub("&&priceMatches(p.price,budget)&&", "&&(filterCurrency==='all'||currencyOf(p)===filterCurrency)&&priceMatches(p,budget,filterCurrency)&&")
sub(" const sort=$('#sort').value;items.sort(sort==='price-low'?(a,b)=>a.price-b.price:sort==='price-high'?(a,b)=>b.price-a.price:(a,b)=>b.created-a.created);\n $('#product-grid').innerHTML=items.map(renderCard).join('');",
    " items.sort(sort==='price-low'?(a,b)=>currencyOf(a).localeCompare(currencyOf(b))||a.price-b.price:sort==='price-high'?(a,b)=>currencyOf(a).localeCompare(currencyOf(b))||b.price-a.price:(a,b)=>b.created-a.created);\n const unavailable=mode==='favorites'&&!isPreview?[...favorites].filter(id=>!findPost(id)):[];\n $('#product-grid').innerHTML=items.map(renderCard).join('')+unavailable.map(id=>'<article class=\"product-card is-unavailable\"><button class=\"card-save saved\" data-save=\"'+esc(id)+'\" aria-label=\"'+esc(t('unsave_unavailable'))+'\" aria-pressed=\"true\">'+icon('heart')+'</button><div class=\"product-open\"><div class=\"product-image unavailable-art\"></div><div class=\"product-info\"><h3>'+t('favorite_unavailable')+'</h3><p class=\"card-artist\">'+t('favorite_unavailable_hint')+'</p></div></div></article>').join('');")
sub("budget!=='all'?$('#price-range')", "filterCurrency!=='all'?filterCurrency:'',budget!=='all'?$('#price-range')")
sub("$('#empty-state').hidden=items.length!==0;", "$('#empty-state').hidden=items.length+unavailable.length!==0;")

sub("for(const id of ['work-kind','price-range','delivery-filter','mine-status'])",
    "$('#currency-filter')?.addEventListener('change',()=>{updateBudgetOptions();render()});$('#post-currency')?.addEventListener('change',updatePriceStep);$('#profile-avatar')?.addEventListener('change',readAvatar);\nasync function readAvatar(event){const file=event.target.files?.[0];if(!file)return;if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>8*1024*1024){event.target.value='';$('#profile-error').textContent=t('error_avatar');$('#profile-error').hidden=false;return}try{const url=URL.createObjectURL(file),image=await new Promise((resolve,reject)=>{const photo=new Image();photo.onload=()=>resolve(photo);photo.onerror=reject;photo.src=url}),side=Math.min(image.naturalWidth,image.naturalHeight),size=Math.min(512,side),canvas=document.createElement('canvas');canvas.width=canvas.height=size;const context=canvas.getContext('2d');context.drawImage(image,(image.naturalWidth-side)/2,(image.naturalHeight-side)/2,side,side,0,0,size,size);URL.revokeObjectURL(url);pendingAvatar=canvas.toDataURL('image/jpeg',.86);$('#profile-avatar-preview').innerHTML='<img src=\"'+pendingAvatar+'\" alt=\"\">';$('#profile-error').hidden=true}catch{event.target.value='';$('#profile-error').textContent=t('error_avatar');$('#profile-error').hidden=false}}\nfor(const id of ['work-kind','price-range','delivery-filter','mine-status'])")
sub("window.addEventListener('hashchange',applyRoute);",
    "window.addEventListener('hashchange',applyRoute);\nwindow.addEventListener('piecenoa:viewer-changed',()=>{remoteKey='';remoteIds=null;initializeMarketData()});")
sub('applyTranslations();applyRoute();', 'applyTranslations();updateBudgetOptions();applyRoute();')

open(path, 'w', encoding='utf-8').write(out)
print('stage3 app.js patch applied:', len(src), '->', len(out), 'chars')
