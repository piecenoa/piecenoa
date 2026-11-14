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

# Abuse limits and reports (stage 5).
sub('const COPY={', r'''const COPY={"rate_limited":["You are doing that too often. Please wait a little and try again.","너무 자주 요청했어요. 잠시 후 다시 시도해 주세요."],"report_title":["Report this listing","이 작품 신고하기"],"report_reason":["Reason","신고 사유"],"report_spam":["Spam or misleading","스팸 또는 오해의 소지"],"report_scam":["Possible scam","사기 의심"],"report_counterfeit":["Counterfeit or wrong artist","위작 또는 작가 표기 오류"],"report_prohibited":["Prohibited item","판매 금지 품목"],"report_offensive":["Offensive content","불쾌한 내용"],"report_other":["Something else","기타"],"report_details":["Tell us what is wrong (optional)","무엇이 문제인지 알려 주세요 (선택)"],"report_submit":["Send report","신고 보내기"],''')
sub("code==='CONFLICT'?'market_conflict':'market_action_error')}",
    "code==='CONFLICT'?'market_conflict':code==='RATE_LIMIT'?'rate_limited':'market_action_error')}")
sub("+'</div></div>';updateDetailHeart();syncMarketLabels();",
    "+(!isPreview&&!p.mine&&!p.demo?'<details class=\"report-listing\"><summary>'+t('report_title')+'</summary><form data-report-form data-listing=\"'+esc(p.id)+'\"><select name=\"reason\" aria-label=\"'+esc(t('report_reason'))+'\">'+['spam','scam','counterfeit','prohibited','offensive','other'].map(r=>'<option value=\"'+r+'\">'+t('report_'+r)+'</option>').join('')+'</select><textarea name=\"details\" maxlength=\"1000\" aria-label=\"'+esc(t('report_details'))+'\" placeholder=\"'+esc(t('report_details'))+'\"></textarea><button type=\"submit\">'+t('report_submit')+'</button></form></details>':'')+'</div></div>';updateDetailHeart();syncMarketLabels();")

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

# Live market: never claim chats stay on this device or that the site is a preview.
sub("isPreview=repository.mode==='local-preview';",
    "isPreview=repository.mode==='local-preview';if(!isPreview){COPY.chat_disclaimer=COPY.chat_live_note;COPY.market_footer=COPY.market_footer_live}")

# Blocking and departed members (chat history kept after account deletion).
sub('const COPY={', r'''const COPY={"chat_live_note":["Messages are delivered to the other member and kept with your account. Never send passwords or card numbers.","메시지는 상대방에게 전달되고 계정에 보관돼요. 비밀번호나 카드 번호는 절대 보내지 마세요."],"chat_block":["Block this member","이 회원 차단하기"],"chat_unblock":["Unblock","차단 풀기"],"chat_block_confirm":["Block this member? Neither of you will be able to send new messages. You can unblock later.","이 회원을 차단할까요? 서로 새 메시지를 보낼 수 없게 돼요. 나중에 풀 수 있어요."],"chat_blocked_done":["Member blocked.","회원을 차단했어요."],"chat_unblocked_done":["Member unblocked.","차단을 풀었어요."],"chat_member_left":["Deleted member","탈퇴한 회원"],"chat_member_left_note":["This member deleted their account. You can read past messages, but you cannot reply.","탈퇴한 회원이에요. 지난 메시지는 볼 수 있지만 답장할 수 없어요."],"chat_blocked_note":["You blocked this member. Unblock them to send messages again.","내가 차단한 회원이에요. 다시 메시지를 보내려면 차단을 풀어 주세요."],"chat_closed_note":["You can no longer send messages in this chat.","이 대화에는 더 이상 메시지를 보낼 수 없어요."],"chat_member_left_chat":["Left the chat","대화를 나감"],"chat_left_chat_note":["The other person deleted this chat. You can read past messages, but you cannot reply.","상대방이 대화를 나갔어요. 지난 메시지는 볼 수 있지만 답장할 수 없어요."],"chat_leave":["Delete chat","채팅 삭제"],"chat_leave_confirm":["Delete this chat? It is removed only for you and cannot be undone. The other person keeps the past messages but can no longer reply.","이 채팅을 삭제할까요? 내 목록에서만 사라지고 되돌릴 수 없어요. 상대방에게는 지난 메시지가 남지만 더 이상 답장할 수 없어요."],"chat_left_done":["Chat deleted.","채팅을 삭제했어요."],''')
sub("return{id:String(c.id),listingId:String(c.listingId||c.id),title:String(c.title||''),",
    "return{id:String(c.id),listingId:String(c.listingId||c.id),title:String(c.title||''),chatState:['open','left','left_chat','blocked','closed'].includes(c.chatState)?c.chatState:'open',counterpartId:c.counterpartId?String(c.counterpartId):null,")
sub("function repositoryError(error){const code=error?.code;",
    "function repositoryError(error){const code=error?.code;if(code==='CHAT_CLOSED'){const th=currentChatThread();if(th&&th.chatState==='open')th.chatState='closed';notify('chat_closed_note');return}")
sub("""strong><span class="chat-thread-preview">'+esc(last?.text||'')+'</span>""",
    """strong>'+(c.chatState==='left'||c.chatState==='left_chat'?'<span class="chat-thread-gone">'+esc(chatCopy(c.chatState==='left'?'chat_member_left':'chat_member_left_chat'))+'</span>':'')+'<span class="chat-thread-preview">'+esc(last?.text||'')+'</span>""")
sub("const compose=Boolean(thread);$('.chat-quick-questions')",
    "const compose=Boolean(thread)&&(thread.chatState||'open')==='open';renderChatSafety(thread);$('.chat-quick-questions')")
sub("function renderChats(scrollToEnd=true){",
    r"""function renderChatSafety(thread){let box=$('#chat-safety');if(!box){box=document.createElement('div');box.id='chat-safety';box.className='chat-safety';$('.chat-main-header').after(box)}
 const state=!isPreview&&thread&&!String(thread.id).startsWith('draft-')?(thread.chatState||'open'):null,note={left:'chat_member_left_note',left_chat:'chat_left_chat_note',blocked:'chat_blocked_note',closed:'chat_closed_note'}[state],action=thread?.counterpartId?(state==='open'?'block':state==='blocked'?'unblock':''):'';
 box.hidden=!state;box.innerHTML=state?(note?'<p>'+esc(chatCopy(note))+'</p>':'')+'<span class="chat-safety-actions">'+(action?'<button type="button" class="chat-safety-button" data-chat-block="'+action+'">'+esc(chatCopy(action==='block'?'chat_block':'chat_unblock'))+'</button>':'')+(typeof repository.leaveConversation==='function'?'<button type="button" class="chat-safety-button" data-chat-leave>'+esc(chatCopy('chat_leave'))+'</button>':'')+'</span>':'';
}
function renderChats(scrollToEnd=true){""")
sub("$('#chat-form').addEventListener('submit',sendInquiry);",
    "$('#chat-form').addEventListener('submit',sendInquiry);$('#chat-dialog').addEventListener('click',async event=>{const leave=event.target.closest('[data-chat-leave]');if(leave&&!leave.disabled){const thread=currentChatThread();if(!thread||String(thread.id).startsWith('draft-')||!requireMarketReady()||!window.confirm(chatCopy('chat_leave_confirm')))return;leave.disabled=true;try{await repository.leaveConversation(thread.id);conversations=conversations.filter(c=>c.id!==thread.id);chatReadMarks.delete(thread.id);chatViewVersion++;chatScope=null;activeThread=null;draftInquiry=null;retryChatMessage=null;$('#chat-input').value='';notify('chat_left_done');render()}catch(error){repositoryError(error)}finally{leave.disabled=false;renderChats(false)}return}const button=event.target.closest('[data-chat-block]');if(!button||button.disabled)return;const thread=currentChatThread(),block=button.dataset.chatBlock==='block';if(!thread?.counterpartId||typeof repository.setBlocked!=='function'||!requireMarketReady())return;if(block&&!window.confirm(chatCopy('chat_block_confirm')))return;button.disabled=true;try{await repository.setBlocked(thread.counterpartId,block);conversations.forEach(c=>{if(c.counterpartId===thread.counterpartId&&!['left','left_chat'].includes(c.chatState))c.chatState=block?'blocked':'open'});notify(block?'chat_blocked_done':'chat_unblocked_done')}catch(error){repositoryError(error)}finally{renderChats(false)}});")

# A chat whose artwork is gone shows that instead of a zero price.
sub("chatState:['open','left','left_chat','blocked','closed'].includes(c.chatState)?c.chatState:'open',",
    "chatState:['open','left','left_chat','blocked','closed'].includes(c.chatState)?c.chatState:'open',listingGone:c.listingAvailable===false,")
sub("const priced=post||thread,", "const listingGone=Boolean(thread?.listingGone&&!post),priced=listingGone?null:post||thread,")
sub("money(priced)+(post?' · '+areaName(post):''):chatCopy('chat_no_product_hint')",
    "money(priced)+(post?' · '+areaName(post):''):chatCopy(listingGone?'chat_listing_gone':'chat_no_product_hint')")
sub('const COPY={', r'''const COPY={"chat_listing_gone":["This artwork is no longer listed.","더 이상 판매하지 않는 작품이에요."],''')

# Delete a message (for me / for everyone) and delete several chats from the list.
sub('const COPY={', r'''const COPY={"message_deleted":["This message was deleted.","삭제된 메시지예요."],"message_options":["Message options","메시지 옵션"],"message_delete_me":["Delete for me","나에게서 삭제"],"message_delete_all":["Delete for everyone","모두에게서 삭제"],"message_delete_me_confirm":["Delete this message only for you? The other person will still see it.","이 메시지를 나에게서만 삭제할까요? 상대방에게는 그대로 보여요."],"message_delete_all_confirm":["Delete this message for everyone? It disappears from both chats. This is possible within 24 hours of sending.","이 메시지를 모두에게서 삭제할까요? 두 사람의 채팅에서 모두 사라져요. 보낸 지 24시간 안에만 할 수 있어요."],"message_deleted_me_done":["Deleted for you.","나에게서 삭제했어요."],"message_deleted_all_done":["Deleted for everyone.","모두에게서 삭제했어요."],"message_delete_too_late":["Messages can be deleted for everyone only within 24 hours of sending.","보낸 지 24시간이 지난 메시지는 모두에게서 삭제할 수 없어요."],"chat_edit":["Edit","편집"],"chat_edit_done":["Done","완료"],"chat_pick_all":["Select all","전체 선택"],"chat_unpick_all":["Clear","선택 해제"],"chat_delete_picked":["Delete ({count})","삭제 ({count})"],"chat_delete_picked_confirm":["Delete {count} chat(s)? They are removed only for you and cannot be undone. The other people keep the past messages but can no longer reply.","선택한 채팅 {count}개를 삭제할까요? 내 목록에서만 사라지고 되돌릴 수 없어요. 상대방에게는 지난 메시지가 남지만 더 이상 답장할 수 없어요."],"chat_delete_partial":["Some chats could not be deleted. Please try again.","일부 채팅을 삭제하지 못했어요. 다시 시도해 주세요."],''')
sub("filter(m=>m&&typeof m.text==='string'&&m.text.trim()).slice(-100).map(m=>({id:m.id,text:m.text.slice(0,500),",
    "filter(m=>m&&m.deleted!==true&&typeof m.text==='string'&&m.text.trim()).slice(-100).map(m=>({id:m.id,text:String(m.text||'').slice(0,500),deleted:false,")
sub("thread.messages.some(message=>message&&typeof message.text==='string'&&message.text.trim())",
    "thread.messages.some(message=>message&&message.deleted!==true&&typeof message.text==='string'&&message.text.trim())")
sub("""'<span class="chat-thread-preview">'+esc(last?.text||'')+'</span>""",
    """'<span class="chat-thread-preview">'+esc(last?.deleted?chatCopy('message_deleted'):last?.text||'')+'</span>""")
sub("""'<div class="message '+(message.direction==='incoming'?'is-incoming':'')+'"><p>'+esc(message.text)+'</p><small>'+esc(time)+(time?' · ':'')+t(message.state==='sent'?'message_sent':'stored_inquiry')+'</small></div>'""",
    """'<div class="message '+(message.direction==='incoming'?'is-incoming':'')+(message.deleted?' is-deleted':'')+'"><p>'+esc(message.deleted?chatCopy('message_deleted'):message.text)+'</p><small>'+esc(time)+(time?' · ':'')+t(message.state==='sent'?'message_sent':'stored_inquiry')+messageMenuButton(thread,message)+'</small>'+messageMenuActions(thread,message)+'</div>'""")
sub("""'<button type="button" class="thread-button '+(selected?'active':'')+'" data-thread="'+esc(c.id)+'" aria-pressed="'+selected+'">'""",
    """'<button type="button" class="thread-button '+(chatEditing?'is-selecting'+(chatPicked.has(c.id)?' is-picked':''):selected?'active':'')+'" data-thread="'+esc(c.id)+'" aria-pressed="'+(chatEditing?chatPicked.has(c.id):selected)+'">'""")
sub("""'no_threads'))+'</p>';
 $('#chat-product').textContent=""",
    """'no_threads'))+'</p>';
 renderChatEditor(visible);$('#chat-product').textContent=""")
sub("function renderChatSafety(thread){",
    r"""let chatEditing=false,openMessageMenu=null;const chatPicked=new Set();
function messageMenuAvailable(thread,message){return !isPreview&&Boolean(message?.id)&&typeof repository.deleteMessage==='function'&&Boolean(thread)&&!String(thread.id).startsWith('draft-')}
function messageMenuButton(thread,message){if(!messageMenuAvailable(thread,message))return '';return ' <button type="button" class="message-more" data-message-menu="'+esc(message.id)+'" aria-expanded="'+(openMessageMenu===String(message.id))+'" aria-label="'+esc(chatCopy('message_options'))+'">⋯</button>'}
function messageMenuActions(thread,message){if(!messageMenuAvailable(thread,message)||openMessageMenu!==String(message.id))return '';const canAll=message.direction!=='incoming'&&!message.deleted&&Date.now()-(Date.parse(message.time)||0)<864e5;return '<span class="message-actions"><button type="button" data-message-delete="me" data-id="'+esc(message.id)+'">'+esc(chatCopy('message_delete_me'))+'</button>'+(canAll?'<button type="button" data-message-delete="all" data-id="'+esc(message.id)+'">'+esc(chatCopy('message_delete_all'))+'</button>':'')+'</span>'}
function renderChatEditor(visible){const heading=$('.chat-sidebar-heading'),can=!isPreview&&typeof repository.leaveConversation==='function';if(!heading||!can)return;let toggle=$('#chat-edit');if(!toggle){toggle=document.createElement('button');toggle.type='button';toggle.id='chat-edit';toggle.className='chat-edit-toggle';heading.append(toggle)}
 [...chatPicked].forEach(id=>{if(!visible.some(c=>c.id===id))chatPicked.delete(id)});if(chatEditing&&!visible.length)chatEditing=false;
 toggle.hidden=!visible.length;toggle.textContent=chatCopy(chatEditing?'chat_edit_done':'chat_edit');toggle.setAttribute('aria-pressed',String(chatEditing));
 let bar=$('#chat-edit-bar');if(!bar){bar=document.createElement('div');bar.id='chat-edit-bar';bar.className='chat-edit-bar';$('#threads').before(bar)}
 bar.hidden=!chatEditing;const all=visible.length>0&&visible.every(c=>chatPicked.has(c.id));bar.innerHTML=chatEditing?'<button type="button" data-chat-pick-all>'+esc(chatCopy(all?'chat_unpick_all':'chat_pick_all'))+'</button><button type="button" class="is-danger" data-chat-delete-picked'+(chatPicked.size?'':' disabled')+'>'+esc(chatCopy('chat_delete_picked').replace('{count}',String(chatPicked.size)))+'</button>':'';
}
function renderChatSafety(thread){""")
sub("function openChats(){chatViewVersion++;",
    "function openChats(){chatEditing=false;chatPicked.clear();openMessageMenu=null;chatViewVersion++;")
sub("$('#threads').addEventListener('click',event=>{const button=event.target.closest('[data-thread]');",
    "$('#threads').addEventListener('click',event=>{if(chatEditing){const pick=event.target.closest('[data-thread]');if(pick){const id=pick.dataset.thread;chatPicked.has(id)?chatPicked.delete(id):chatPicked.add(id);renderChats(false)}return}const button=event.target.closest('[data-thread]');")
sub("function repositoryError(error){const code=error?.code;",
    "function repositoryError(error){const code=error?.code;if(code==='TOO_LATE'){notify('message_delete_too_late');return}")
sub("$('#chat-dialog').addEventListener('click',async event=>{const leave=",
    r"""$('#chat-dialog').addEventListener('click',async event=>{
 if(event.target.closest('#chat-edit')){chatEditing=!chatEditing;chatPicked.clear();openMessageMenu=null;renderChats(false);return}
 if(event.target.closest('[data-chat-pick-all]')){const visible=scopedConversations(),all=visible.every(c=>chatPicked.has(c.id));visible.forEach(c=>all?chatPicked.delete(c.id):chatPicked.add(c.id));renderChats(false);return}
 const deletePicked=event.target.closest('[data-chat-delete-picked]');if(deletePicked){const ids=[...chatPicked];if(deletePicked.disabled||!ids.length||!requireMarketReady()||!window.confirm(chatCopy('chat_delete_picked_confirm').replace('{count}',String(ids.length))))return;deletePicked.disabled=true;const results=await Promise.allSettled(ids.map(id=>repository.leaveConversation(id))),done=ids.filter((id,index)=>results[index].status==='fulfilled');conversations=conversations.filter(c=>!done.includes(c.id));done.forEach(id=>{chatReadMarks.delete(id);chatPicked.delete(id)});if(done.includes(activeThread)){activeThread=null;chatScope=null;draftInquiry=null}if(!chatPicked.size)chatEditing=false;chatViewVersion++;notify(done.length===ids.length?'chat_left_done':'chat_delete_partial');render();renderChats(false);return}
 const menu=event.target.closest('[data-message-menu]');if(menu){openMessageMenu=openMessageMenu===menu.dataset.messageMenu?null:menu.dataset.messageMenu;renderChats(false);return}
 const removeMessage=event.target.closest('[data-message-delete]');if(removeMessage){const thread=currentChatThread(),id=removeMessage.dataset.id,scope=removeMessage.dataset.messageDelete==='all'?'all':'me';if(removeMessage.disabled||!thread||!requireMarketReady()||!window.confirm(chatCopy(scope==='all'?'message_delete_all_confirm':'message_delete_me_confirm')))return;removeMessage.disabled=true;try{await repository.deleteMessage(id,scope);thread.messages=thread.messages.filter(m=>String(m.id)!==id);if(!hasConversationMessages(thread)){conversations=conversations.filter(c=>c.id!==thread.id);activeThread=null;chatScope=null;draftInquiry=null;chatViewVersion++}openMessageMenu=null;notify(scope==='all'?'message_deleted_all_done':'message_deleted_me_done');render()}catch(error){repositoryError(error)}finally{renderChats(false)}return}
 const leave=""")

# Show the other person's nickname (and photo) in the chat list and chat header.
sub('const COPY={', r'''const COPY={"chat_with":["Chatting with {name}","{name} 님과의 대화"],''')
sub("counterpartId:c.counterpartId?String(c.counterpartId):null,",
    "counterpartId:c.counterpartId?String(c.counterpartId):null,counterpartName:String(c.counterpartName||'').slice(0,40),counterpartAvatar:typeof c.counterpartAvatarUrl==='string'&&/^https:\\/\\//.test(c.counterpartAvatarUrl)?c.counterpartAvatarUrl:'',")
sub("""<strong>'+esc(threadTitle(c))+'</strong>'""",
    """<strong>'+esc(threadTitle(c))+'</strong>'+(c.counterpartName?'<span class="chat-thread-who">'+esc(c.counterpartName)+'</span>':'')""")
sub("function renderChatSafety(thread){",
    r"""function renderChatPartner(thread){let who=$('#chat-with');if(!who){who=document.createElement('p');who.id='chat-with';who.className='chat-with';$('#chat-product').after(who)}
 const draft=Boolean(thread)&&String(thread.id).startsWith('draft-'),name=isPreview||!thread?'':thread.counterpartName||(draft?findPost(thread.listingId)?.sellerInfo?.name||'':''),gone=!isPreview&&(thread?.chatState==='left'||thread?.chatState==='left_chat'),avatar=!draft&&thread?.counterpartAvatar?thread.counterpartAvatar:draft?findPost(thread.listingId)?.sellerInfo?.avatarUrl||'':'';
 who.hidden=!name&&!gone;who.innerHTML=name?(avatar?'<img class="chat-with-avatar" alt="" src="'+esc(avatar)+'">':'<span class="chat-with-avatar" aria-hidden="true">'+esc(name.slice(0,1).toUpperCase())+'</span>')+'<span>'+esc(chatCopy('chat_with').replace('{name}',name))+'</span>':gone?'<span>'+esc(chatCopy(thread.chatState==='left'?'chat_member_left':'chat_member_left_chat'))+'</span>':'';
}
function renderChatSafety(thread){renderChatPartner(thread);""")

# Live update: if every visible message of a chat was deleted, drop the chat from the list.
sub("const dto=event?.conversation||(Array.isArray(event?.messages)?event:null);if(!dto)return;mergeConversation(dto)}",
    "const dto=event?.conversation||(Array.isArray(event?.messages)?event:null);if(!dto)return;if(!hasConversationMessages(fromConversationDTO(dto,viewerId))){conversations=conversations.filter(c=>c.id!==String(dto.id));if(activeThread===String(dto.id)){activeThread=null;chatScope=null;draftInquiry=null;chatViewVersion++}}else mergeConversation(dto)}")

# Database search and "show more" for the live market (the first page holds the newest 500).
sub('const COPY={', r'''const COPY={"load_more":["Show more artworks","작품 더 보기"],"load_more_loading":["Loading…","불러오는 중…"],''')
sub("posts=(Array.isArray(data.listings)?data.listings:[]).map(p=>fromListingDTO(p,viewerId)).filter(Boolean);",
    "posts=(Array.isArray(data.listings)?data.listings:[]).map(p=>fromListingDTO(p,viewerId)).filter(Boolean);feedHasMore=data.hasMoreListings===true;searchedQueries.clear();")
sub("function mergeListing(dto){",
    r"""let feedHasMore=false,feedLoading=false,searchTimer=0;const searchedQueries=new Set();
function mergeListings(list){let added=0;for(const dto of Array.isArray(list)?list:[]){const p=fromListingDTO(dto,viewerId);if(!p||posts.some(item=>item.id===p.id))continue;posts.push(p);added++}return added}
function remoteSearch(rawQuery){if(isPreview||!repositoryReady||typeof repository.searchListings!=='function')return;const key=rawQuery.trim().toLowerCase();if(key.length<2||searchedQueries.has(key))return;clearTimeout(searchTimer);searchTimer=setTimeout(async()=>{if($('#search').value.trim().toLowerCase()!==key)return;searchedQueries.add(key);try{if(mergeListings(await repository.searchListings(key)))render()}catch(error){searchedQueries.delete(key);console.warn('[PIECENOA] search failed',error?.code||error)}},350)}
function renderLoadMore(){const grid=$('#product-grid');if(!grid)return;let more=$('#load-more-listings');if(!more){more=document.createElement('button');more.type='button';more.id='load-more-listings';more.className='load-more-listings';grid.after(more)}more.hidden=isPreview||mode!=='all'||!feedHasMore;more.disabled=feedLoading;more.textContent=t(feedLoading?'load_more_loading':'load_more')}
async function loadMoreListings(){if(feedLoading||!feedHasMore||typeof repository.loadMoreListings!=='function')return;feedLoading=true;renderLoadMore();try{const page=await repository.loadMoreListings();mergeListings(page?.listings);feedHasMore=page?.hasMore===true}catch(error){repositoryError(error)}finally{feedLoading=false;render()}}
document.addEventListener('click',event=>{if(event.target.closest('#load-more-listings'))loadMoreListings()});
function mergeListing(dto){""")
sub("$('#product-grid').innerHTML=renderCurrencyResults(items,sort);",
    "$('#product-grid').innerHTML=renderCurrencyResults(items,sort);renderLoadMore();if(rawQuery&&mode==='all')remoteSearch(rawQuery);")

open(path, 'w', encoding='utf-8', newline='').write(out)
print('v2 app.js patch applied:', len(src), '->', len(out), 'chars')
