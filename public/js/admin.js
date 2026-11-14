/* PIECENOA admin page.
 * Uses the same sign-in as the site (same browser storage key). Every action is checked again
 * in the database: admin functions call is_admin() and row level security limits reads.
 * This page only shows what the database already allows the signed-in admin to see.
 */
(() => {
  'use strict';
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const gate = (text, showLink) => {
    $('#admin-gate-text').textContent = text;
    $('#admin-gate-link').hidden = !showLink;
    $('#admin-gate').hidden = false;
    $('#admin-app').hidden = true;
  };

  const config = window.PIECENOA_CONFIG;
  if (!config?.supabaseUrl || typeof window.supabase?.createClient !== 'function') {
    gate('Supabase 연결 설정이 없어요. js/config.js를 확인해 주세요.', false);
    return;
  }
  const db = window.supabase.createClient(config.supabaseUrl, config.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'piecenoa.auth.v1' },
  });
  const storageBase = config.supabaseUrl.replace(/\/$/, '') + '/storage/v1/object/public/';
  const imageUrl = (path) => (path ? storageBase + 'listing-images/' + path.split('/').map(encodeURIComponent).join('/') : '');
  const MINOR = { JPY: 0, KRW: 0, VND: 0 };
  const money = (minor, currency) => {
    const digits = MINOR[currency] ?? 2;
    try {
      return new Intl.NumberFormat('ko-KR', { style: 'currency', currency, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(minor / 10 ** digits);
    } catch { return minor + ' ' + currency; }
  };
  const when = (iso) => (iso ? new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso)) : '—');
  const REASONS = { spam: '스팸·오해 소지', scam: '사기 의심', counterfeit: '위작·작가 표기 오류', prohibited: '판매 금지 품목', offensive: '불쾌한 내용', other: '기타' };
  const STATUS = { open: '접수', reviewing: '검토 중', resolved: '처리 완료', dismissed: '기각' };

  let toastTimer = 0;
  function toast(text, isError) {
    const box = $('#admin-toast');
    box.textContent = text;
    box.classList.toggle('is-error', Boolean(isError));
    box.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => box.classList.remove('show'), 3200);
  }
  function explain(error) {
    const m = String(error?.message || '');
    if (/FORBIDDEN|42501/.test(m) || error?.code === '42501') return '관리자 권한이 없어요.';
    if (/CANNOT_BAN_SELF/.test(m)) return '자기 자신은 제재할 수 없어요.';
    if (/CANNOT_BAN_ADMIN/.test(m)) return '관리자 계정은 제재할 수 없어요.';
    if (/NOT_FOUND/.test(m)) return '대상을 찾지 못했어요. 새로고침해 주세요.';
    return '처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }
  async function run(button, task, done) {
    if (button) button.disabled = true;
    try {
      await task();
      if (done) toast(done);
    } catch (error) {
      console.warn('[PIECENOA admin]', error);
      toast(explain(error), true);
    } finally {
      if (button) button.disabled = false;
    }
  }
  const ask = (question, fallback = '') => {
    const value = window.prompt(question, fallback);
    return value === null ? null : value.trim();
  };

  // ---- Overview -------------------------------------------------------------
  async function loadStats() {
    const { data, error } = await db.rpc('admin_stats');
    if (error) throw error;
    const cards = [
      ['회원', data.members, '최근 7일 가입 ' + data.members_7d + '명'],
      ['제재 중인 회원', data.members_banned, ''],
      ['작품 (삭제 제외)', data.listings, '최근 7일 등록 ' + data.listings_7d + '개'],
      ['공개 중', data.listings_public, '비공개 ' + data.listings_private + ' · 숨김 ' + data.listings_hidden],
      ['처리 대기 신고', data.reports_open, ''],
      ['대화', data.conversations, '최근 7일 메시지 ' + data.messages_7d + '개'],
      ['관심 저장', data.favorites, ''],
    ];
    $('#stats').innerHTML = cards.map(([label, value, note]) =>
      '<div class="admin-stat"><span>' + esc(label) + '</span><strong>' + esc(Number(value).toLocaleString('ko-KR')) + '</strong>' +
      (note ? '<small>' + esc(note) + '</small>' : '') + '</div>').join('');
    $('#reports-badge').textContent = data.reports_open;
    $('#reports-badge').hidden = !data.reports_open;
  }

  // ---- Reports --------------------------------------------------------------
  async function loadReports() {
    const filter = $('#report-filter').value;
    let query = db.from('reports')
      .select('id, target_type, reason, details, status, created_at, snapshot, resolution_note, listing_id, ' +
        'reporter:profiles!reports_reporter_id_fkey(display_name), listing:listings(id, title, moderation_status, image_path, deleted_at)')
      .order('created_at', { ascending: false }).limit(100);
    if (filter === 'open') query = query.in('status', ['open', 'reviewing']);
    if (filter === 'closed') query = query.in('status', ['resolved', 'dismissed']);
    const { data, error } = await query;
    if (error) throw error;
    $('#reports').innerHTML = data.length ? data.map((r) => {
      const listing = r.listing;
      const title = listing?.title || r.snapshot?.title || '(삭제된 대상)';
      const hidden = listing?.moderation_status === 'hidden';
      return '<article class="admin-row" data-report="' + esc(r.id) + '" data-listing="' + esc(r.listing_id || '') + '">' +
        (listing?.image_path || r.snapshot?.image_path ? '<img alt="" src="' + esc(imageUrl(listing?.image_path || r.snapshot.image_path)) + '">' : '<span class="admin-thumb"></span>') +
        '<div class="admin-row-body"><p class="admin-row-title">' + esc(title) +
        ' <span class="admin-chip">' + esc(STATUS[r.status] || r.status) + '</span>' + (hidden ? ' <span class="admin-chip is-warn">숨김</span>' : '') + '</p>' +
        '<p>사유: ' + esc(REASONS[r.reason] || r.reason) + (r.details ? ' — ' + esc(r.details) : '') + '</p>' +
        '<p class="admin-meta">신고자 ' + esc(r.reporter?.display_name || '알 수 없음') + ' · ' + esc(when(r.created_at)) +
        (r.resolution_note ? ' · 메모: ' + esc(r.resolution_note) : '') + '</p></div>' +
        '<div class="admin-actions">' +
        (r.listing_id && listing ? '<button data-act="listing-hide" data-hidden="' + (hidden ? '0' : '1') + '">' + (hidden ? '작품 다시 공개' : '작품 숨기기') + '</button>' : '') +
        (r.status === 'open' ? '<button data-act="report-status" data-status="reviewing">검토 중</button>' : '') +
        (['open', 'reviewing'].includes(r.status) ? '<button data-act="report-status" data-status="resolved">처리 완료</button><button data-act="report-status" data-status="dismissed">기각</button>'
          : '<button data-act="report-status" data-status="open">다시 열기</button>') +
        '</div></article>';
    }).join('') : '<p class="admin-empty">신고가 없어요.</p>';
  }

  // ---- Listings -------------------------------------------------------------
  async function loadListings() {
    const filter = $('#listing-filter').value, term = $('#listing-query').value.trim();
    let query = db.from('listings')
      .select('id, title, price_minor, currency, visibility, moderation_status, moderation_reason, deleted_at, created_at, image_path, ' +
        'favorite_count, conversation_count, seller:profiles!listings_seller_id_fkey(id, display_name)')
      .order('created_at', { ascending: false }).limit(100);
    if (filter === 'deleted') query = query.not('deleted_at', 'is', null);
    else query = query.is('deleted_at', null);
    if (filter === 'public') query = query.eq('visibility', 'public').eq('moderation_status', 'active');
    if (filter === 'private') query = query.eq('visibility', 'private');
    if (filter === 'hidden') query = query.eq('moderation_status', 'hidden');
    if (term) query = query.ilike('title', '%' + term.replace(/[\\%_]/g, (c) => '\\' + c) + '%');
    const { data, error } = await query;
    if (error) throw error;
    $('#listings').innerHTML = data.length ? data.map((l) => {
      const hidden = l.moderation_status === 'hidden';
      const chips = [l.deleted_at ? '삭제됨' : '', l.visibility === 'private' ? '비공개' : '', hidden ? (l.moderation_reason === 'ACCOUNT_SUSPENDED' ? '회원 제재로 숨김' : '숨김') : '']
        .filter(Boolean).map((c) => '<span class="admin-chip is-warn">' + esc(c) + '</span>').join(' ');
      return '<article class="admin-row" data-listing="' + esc(l.id) + '">' +
        (l.image_path ? '<img alt="" src="' + esc(imageUrl(l.image_path)) + '">' : '<span class="admin-thumb"></span>') +
        '<div class="admin-row-body"><p class="admin-row-title">' + esc(l.title) + ' ' + chips + '</p>' +
        '<p>' + esc(money(l.price_minor, l.currency)) + ' · 판매자 ' + esc(l.seller?.display_name || '알 수 없음') + '</p>' +
        '<p class="admin-meta">관심 ' + esc(l.favorite_count) + ' · 대화 ' + esc(l.conversation_count) + ' · 등록 ' + esc(when(l.created_at)) +
        (hidden && l.moderation_reason && l.moderation_reason !== 'ACCOUNT_SUSPENDED' ? ' · 사유: ' + esc(l.moderation_reason) : '') + '</p></div>' +
        '<div class="admin-actions">' + (l.deleted_at ? '' : '<button data-act="listing-hide" data-hidden="' + (hidden ? '0' : '1') + '">' + (hidden ? '다시 공개' : '숨기기') + '</button>') + '</div></article>';
    }).join('') : '<p class="admin-empty">조건에 맞는 작품이 없어요.</p>';
  }

  // ---- Members --------------------------------------------------------------
  async function loadMembers() {
    const { data, error } = await db.rpc('admin_members', { p_search: $('#member-query').value.trim(), p_limit: 100, p_offset: 0 });
    if (error) throw error;
    $('#members').innerHTML = data.length ? data.map((m) =>
      '<article class="admin-row" data-member="' + esc(m.id) + '"><span class="admin-thumb is-person">' + esc((m.display_name || m.email || '?').slice(0, 1).toUpperCase()) + '</span>' +
      '<div class="admin-row-body"><p class="admin-row-title">' + esc(m.display_name || '(이름 없음)') +
      (m.is_admin ? ' <span class="admin-chip">관리자</span>' : '') + (m.banned ? ' <span class="admin-chip is-warn">제재 중</span>' : '') +
      (m.email_confirmed ? '' : ' <span class="admin-chip">이메일 미인증</span>') + '</p>' +
      '<p>' + esc(m.email) + ' · 작품 ' + esc(m.listing_count) + '개</p>' +
      '<p class="admin-meta">가입 ' + esc(when(m.created_at)) + ' · 마지막 로그인 ' + esc(when(m.last_sign_in_at)) +
      (m.banned && m.ban_reason ? ' · 제재 사유: ' + esc(m.ban_reason) : '') + '</p></div>' +
      '<div class="admin-actions">' + (m.is_admin ? '' : '<button data-act="member-ban" data-banned="' + (m.banned ? '0' : '1') + '">' + (m.banned ? '제재 풀기' : '제재하기') + '</button>') + '</div></article>'
    ).join('') : '<p class="admin-empty">회원을 찾지 못했어요.</p>';
  }

  const loaders = { overview: loadStats, reports: loadReports, listings: loadListings, members: loadMembers };
  let current = 'overview';
  function show(tab) {
    current = tab;
    $$('[data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
    $$('[data-panel]').forEach((p) => { p.hidden = p.dataset.panel !== tab; });
    return run(null, loaders[tab]);
  }
  const refresh = () => Promise.all([run(null, loadStats), current === 'overview' ? null : run(null, loaders[current])]);

  document.addEventListener('click', (event) => {
    const tab = event.target.closest('[data-tab]');
    if (tab) { show(tab.dataset.tab); return; }
    const button = event.target.closest('[data-act]');
    if (!button) return;
    const row = button.closest('.admin-row');
    if (button.dataset.act === 'listing-hide') {
      const hide = button.dataset.hidden === '1';
      const reason = hide ? ask('숨기는 사유를 적어 주세요. 판매자에게 보여요.', '운영 정책 위반') : '';
      if (reason === null) return;
      run(button, async () => {
        const { error } = await db.rpc('admin_set_listing_hidden', { p_listing: row.dataset.listing, p_hidden: hide, p_reason: reason });
        if (error) throw error;
        await refresh();
      }, hide ? '작품을 숨겼어요.' : '작품을 다시 공개했어요.');
    } else if (button.dataset.act === 'report-status') {
      const status = button.dataset.status;
      const note = ['resolved', 'dismissed'].includes(status) ? ask('처리 메모 (선택)', '') : '';
      if (note === null) return;
      run(button, async () => {
        const { error } = await db.rpc('admin_update_report', { p_report: row.dataset.report, p_status: status, p_note: note });
        if (error) throw error;
        await refresh();
      }, '신고 상태를 바꿨어요.');
    } else if (button.dataset.act === 'member-ban') {
      const ban = button.dataset.banned === '1';
      const reason = ban ? ask('제재 사유를 적어 주세요. 이 회원의 작품도 마켓에서 숨겨져요.', '운영 정책 위반') : '';
      if (reason === null) return;
      if (!ban && !window.confirm('이 회원의 제재를 풀까요? 제재 때문에 숨겨진 작품도 다시 공개돼요.')) return;
      run(button, async () => {
        const { error } = await db.rpc('admin_set_member_ban', { p_user: row.dataset.member, p_banned: ban, p_reason: reason });
        if (error) throw error;
        await refresh();
      }, ban ? '회원을 제재했어요.' : '제재를 풀었어요.');
    }
  });
  // Storage cleanup: removes listings deleted 30+ days ago and unused photo files.
  $('#run-cleanup').addEventListener('click', (event) => {
    const button = event.currentTarget;
    if (!window.confirm('삭제한 지 30일이 지난 작품과 쓰이지 않는 사진 파일을 지울까요? 되돌릴 수 없어요.')) return;
    run(button, async () => {
      const { data, error } = await db.functions.invoke('cleanup-storage', { method: 'POST' });
      if (error) throw Object.assign(new Error(error.message || 'CLEANUP_FAILED'), { cause: error });
      $('#cleanup-result').textContent = '완료: 작품 ' + (data?.listingsRemoved ?? 0) + '개, 사진 파일 ' + (data?.filesRemoved ?? 0) + '개를 지웠어요. (' + when(new Date().toISOString()) + ')';
      await loadStats();
    }, '저장소를 정리했어요.');
  });

  $('#report-filter').addEventListener('change', () => run(null, loadReports));
  $('#listing-search').addEventListener('submit', (e) => { e.preventDefault(); run(null, loadListings); });
  $('#listing-filter').addEventListener('change', () => run(null, loadListings));
  $('#member-search').addEventListener('submit', (e) => { e.preventDefault(); run(null, loadMembers); });

  (async () => {
    const { data } = await db.auth.getSession();
    const session = data.session;
    if (!session) { gate('관리자 화면은 로그인한 뒤에 볼 수 있어요. 사이트에서 로그인한 다음 이 페이지를 다시 열어 주세요.', true); return; }
    const { data: isAdmin, error } = await db.rpc('is_admin');
    if (error || !isAdmin) { gate('관리자만 볼 수 있는 페이지예요.', false); return; }
    $('#admin-who').textContent = session.user.email + ' · 관리자';
    $('#admin-gate').hidden = true;
    $('#admin-app').hidden = false;
    show('overview');
  })();
})();
