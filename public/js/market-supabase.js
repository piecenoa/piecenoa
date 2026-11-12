/* PIECENOA market data on Supabase.
 *
 * Implements the window.PIECENOA_MARKET_REPOSITORY contract that js/app.js documents
 * ("MARKET DATA BOUNDARY"). Loaded only when js/account.js created a Supabase client;
 * otherwise app.js keeps its browser-only preview repository.
 *
 * Who may read or change what is decided by row level security in the database
 * (supabase/migrations/20261112100100_marketplace_schema.sql), not by this file.
 */
(() => {
  'use strict';
  const account = window.PIECENOA_ACCOUNT;
  if (!account?.client) return;
  const db = account.client;
  const storageBase = window.PIECENOA_CONFIG.supabaseUrl.replace(/\/$/, '') + '/storage/v1/object/public/';

  const MINOR_UNITS = { USD: 2, EUR: 2, GBP: 2, KRW: 0, JPY: 0, CNY: 2, HKD: 2, TWD: 2, SGD: 2, AUD: 2, CAD: 2, CHF: 2 };
  const minor = (currency) => MINOR_UNITS[currency] ?? 2;
  const toMinor = (price, currency) => Math.round(Number(price) * 10 ** minor(currency));
  const toMajor = (amount, currency) => Number(amount) / 10 ** minor(currency);

  const SELLER = 'seller:profiles!listings_seller_id_fkey(id, display_name, bio, role, location_text, country_code, avatar_path)';
  const LISTING = 'id, seller_id, title, description, price_minor, currency, category, status, image_path, artist, medium, ' +
    'dimensions, year, kind, condition, delivery, framed, negotiable, location_text, country_code, visibility, ' +
    'moderation_status, created_at, updated_at, deleted_at, ' + SELLER;
  const PAGE_SIZE = 120;

  const failure = (code, cause) => Object.assign(new Error(code), { code, cause });
  function check(error, fallback = 'SERVER') {
    if (!error) return;
    console.warn('[PIECENOA] market request failed', error.code || '', error.message || error);
    const status = Number(error.status || error.statusCode || 0);
    if (status === 401 || error.code === 'PGRST301' || /jwt|not authenticated/i.test(error.message || '')) throw failure('AUTH_REQUIRED', error);
    if (error.code === '42501' || status === 403) throw failure('FORBIDDEN', error);
    if (error.code === '23514' || error.code === '22P02' || error.code === '23502' || error.code === '23503') throw failure('VALIDATION', error);
    if (error.code === 'P0001' && /NOT_FOUND/.test(error.message || '')) throw failure('NOT_FOUND', error);
    throw failure(fallback, error);
  }
  const viewerId = () => account.session?.user?.id || null;
  function requireViewer() {
    const id = viewerId();
    if (!id) throw failure('AUTH_REQUIRED');
    return id;
  }

  const publicUrl = (bucket, path) => (path ? storageBase + bucket + '/' + path.split('/').map(encodeURIComponent).join('/') : '');
  function pathFromUrl(bucket, url) {
    const prefix = storageBase + bucket + '/';
    if (typeof url !== 'string' || !url.startsWith(prefix)) return null;
    return url.slice(prefix.length).split('/').map(decodeURIComponent).join('/');
  }

  function sellerDTO(row) {
    if (!row) return undefined;
    return {
      id: row.id,
      name: row.display_name,
      bio: row.bio || '',
      role: row.role,
      location: row.location_text ? { text: row.location_text, countryCode: row.country_code || undefined } : undefined,
      region: row.location_text || '',
      avatarUrl: publicUrl('avatars', row.avatar_path),
    };
  }

  function listingDTO(row) {
    return {
      id: row.id,
      ownerId: row.seller_id,
      title: row.title,
      description: row.description,
      price: toMajor(row.price_minor, row.currency),
      currency: row.currency,
      category: row.category,
      status: row.status,
      image: publicUrl('listing-images', row.image_path),
      artist: row.artist || '',
      medium: row.medium || '',
      dimensions: row.dimensions || '',
      year: row.year ? String(row.year) : '',
      kind: row.kind,
      condition: row.condition,
      delivery: row.delivery,
      framed: row.framed,
      negotiable: Boolean(row.negotiable),
      location: { text: row.location_text, countryCode: row.country_code || undefined },
      region: row.location_text,
      visibility: row.visibility,
      moderation: row.moderation_status,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      version: row.updated_at,
      seller: sellerDTO(row.seller),
    };
  }

  // ListingInput (app shape) -> database columns the member is allowed to write.
  function listingRow(input, uid) {
    const currency = String(input.currency || '').toUpperCase();
    if (!Object.hasOwn(MINOR_UNITS, currency)) throw failure('VALIDATION');
    const imagePath = pathFromUrl('listing-images', input.image);
    if (!imagePath || !imagePath.startsWith(uid + '/')) throw failure('VALIDATION');
    const year = /^[12][0-9]{3}$/.test(String(input.year || '')) ? Number(input.year) : null;
    const location = String(input.location?.text || input.region || '').trim().slice(0, 80);
    const row = {
      title: String(input.title || '').trim(),
      description: String(input.description || '').trim(),
      price_minor: toMinor(input.price, currency),
      currency,
      category: input.category,
      status: input.status || 'available',
      image_path: imagePath,
      artist: String(input.artist || '').trim().slice(0, 80),
      medium: String(input.medium || '').trim().slice(0, 80),
      dimensions: String(input.dimensions || '').trim().slice(0, 50),
      year,
      kind: input.kind,
      condition: input.condition,
      delivery: input.delivery,
      framed: input.framed,
      negotiable: Boolean(input.negotiable),
      location_text: location,
      country_code: /^[A-Z]{2}$/.test(String(input.location?.countryCode || '')) ? input.location.countryCode : null,
      visibility: input.visibility === 'private' ? 'private' : 'public',
    };
    if (!Number.isSafeInteger(row.price_minor) || row.price_minor < 0) throw failure('VALIDATION');
    return row;
  }

  function profileDTO(row, user) {
    return {
      id: row?.id || user?.id,
      name: row?.display_name && row.display_name !== 'Member' ? row.display_name : '',
      bio: row?.bio || '',
      role: row?.role || 'artist',
      location: row?.location_text ? { text: row.location_text, countryCode: row.country_code || undefined } : undefined,
      region: row?.location_text || '',
      avatarUrl: publicUrl('avatars', row?.avatar_path),
      avatarPath: row?.avatar_path || null,
    };
  }

  async function loadConversations(uid) {
    const { data, error } = await db.from('conversations')
      .select('id, listing_id, buyer_id, seller_id, last_message_at, listing:listings(id, title, price_minor, currency, image_path), ' +
        'messages(id, sender_id, body, created_at, read_at, client_id)')
      .order('last_message_at', { ascending: false })
      .order('created_at', { referencedTable: 'messages', ascending: true })
      .limit(100);
    check(error);
    return (data || []).map((row) => conversationDTO(row, uid));
  }

  function conversationDTO(row, uid) {
    return {
      id: row.id,
      listingId: row.listing_id,
      title: row.listing?.title || '',
      price: row.listing ? toMajor(row.listing.price_minor, row.listing.currency) : 0,
      currency: row.listing?.currency,
      role: row.buyer_id === uid ? 'buyer' : 'seller',
      lastMessageAt: row.last_message_at,
      messages: (row.messages || []).slice(-100).map((m) => ({
        id: m.client_id || m.id,
        serverId: m.id,
        text: m.body,
        createdAt: m.created_at,
        readAt: m.read_at,
        direction: m.sender_id === uid ? 'outgoing' : 'incoming',
        state: 'sent',
      })),
    };
  }

  async function fetchConversation(id, uid) {
    const { data, error } = await db.from('conversations')
      .select('id, listing_id, buyer_id, seller_id, last_message_at, listing:listings(id, title, price_minor, currency, image_path), ' +
        'messages(id, sender_id, body, created_at, read_at, client_id)')
      .eq('id', id)
      .order('created_at', { referencedTable: 'messages', ascending: true })
      .maybeSingle();
    check(error);
    if (!data) throw failure('NOT_FOUND');
    return conversationDTO(data, uid);
  }

  function dataUrlToBlob(dataUrl) {
    const match = /^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/.exec(dataUrl || '');
    if (!match) throw failure('VALIDATION');
    const binary = atob(match[2]);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return { blob: new Blob([bytes], { type: match[1] }), mime: match[1] };
  }
  const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  const newId = () => globalThis.crypto?.randomUUID?.() || Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);

  async function upload(bucket, dataUrl) {
    const uid = requireViewer();
    const { blob, mime } = dataUrlToBlob(dataUrl);
    if (blob.size > (bucket === 'avatars' ? 2 : 3) * 1024 * 1024) throw failure('VALIDATION');
    const path = uid + '/' + newId() + '.' + EXT[mime];
    const { error } = await db.storage.from(bucket).upload(path, blob, { contentType: mime, cacheControl: '31536000', upsert: false });
    check(error, 'UPLOAD');
    return { path, url: publicUrl(bucket, path) };
  }

  const escapeLike = (word) => word.replace(/[\\%_]/g, (c) => '\\' + c);

  const repository = {
    mode: 'supabase',

    async bootstrap() {
      await account.ready;
      const uid = viewerId();
      const feed = await repository.searchListings({});
      const feedIds = feed.map((p) => p.id);
      if (!uid) return { viewer: null, profile: null, listings: feed, feedIds, favorites: [], conversations: [] };

      const [mine, favs, me, conversations] = await Promise.all([
        db.from('listings').select(LISTING).eq('seller_id', uid).is('deleted_at', null).order('created_at', { ascending: false }),
        db.from('favorites').select('listing_id, created_at, listing:listings(' + LISTING + ')').order('created_at', { ascending: false }),
        db.from('profiles').select('id, display_name, bio, role, location_text, country_code, avatar_path').eq('id', uid).maybeSingle(),
        loadConversations(uid),
      ]);
      check(mine.error); check(favs.error); check(me.error);
      const byId = new Map(feed.map((p) => [p.id, p]));
      for (const row of mine.data || []) byId.set(row.id, listingDTO(row));
      for (const fav of favs.data || []) if (fav.listing && !fav.listing.deleted_at) byId.set(fav.listing.id, listingDTO(fav.listing));
      return {
        viewer: { id: uid },
        profile: profileDTO(me.data, account.session?.user),
        listings: [...byId.values()],
        feedIds,
        // Saved pieces that were deleted or made private come back without a listing.
        favorites: (favs.data || []).map((f) => f.listing_id),
        unavailableFavorites: (favs.data || []).filter((f) => !f.listing || f.listing.deleted_at).map((f) => f.listing_id),
        conversations,
      };
    },

    // Explore: filtering, search and sorting run in the database.
    async searchListings(params = {}) {
      let query = db.from('listings').select(LISTING)
        .eq('visibility', 'public').eq('moderation_status', 'active').is('deleted_at', null);
      if (params.category) query = query.eq('category', params.category);
      if (params.kind) query = query.eq('kind', params.kind);
      if (params.delivery) query = query.in('delivery', [params.delivery, 'either']);
      if (params.availableOnly) query = query.eq('status', 'available');
      if (params.sellerId) query = query.eq('seller_id', params.sellerId);
      if (params.currency && Object.hasOwn(MINOR_UNITS, params.currency)) {
        query = query.eq('currency', params.currency);
        if (Number.isFinite(params.min)) query = query.gte('price_minor', toMinor(params.min, params.currency));
        if (Number.isFinite(params.max)) query = query[params.maxInclusive ? 'lte' : 'lt']('price_minor', toMinor(params.max, params.currency));
      }
      const words = String(params.query || '').toLowerCase().split(/\s+/).filter(Boolean).slice(0, 8);
      for (const word of words) query = query.ilike('search_text', '%' + escapeLike(word.slice(0, 40)) + '%');
      if (params.sort === 'price-low' || params.sort === 'price-high') {
        query = query.order('currency', { ascending: true }).order('price_minor', { ascending: params.sort === 'price-low' });
      }
      query = query.order('created_at', { ascending: false }).limit(params.limit || PAGE_SIZE);
      const { data, error } = await query;
      check(error);
      return (data || []).map(listingDTO);
    },

    async loadSeller(sellerId) {
      const [profile, listings] = await Promise.all([
        db.from('profiles').select('id, display_name, bio, role, location_text, country_code, avatar_path').eq('id', sellerId).maybeSingle(),
        repository.searchListings({ sellerId, limit: 60 }),
      ]);
      check(profile.error);
      return { seller: sellerDTO(profile.data), listings };
    },

    async uploadImage(input) {
      return upload('listing-images', input.dataUrl);
    },

    async uploadAvatar(input) {
      return upload('avatars', input.dataUrl);
    },

    async createListing(input) {
      const uid = requireViewer();
      const { data, error } = await db.from('listings').insert(listingRow(input, uid)).select(LISTING).single();
      check(error);
      return listingDTO(data);
    },

    async updateListing(id, input) {
      const uid = requireViewer();
      const { data, error } = await db.from('listings').update(listingRow(input, uid))
        .eq('id', id).eq('seller_id', uid).select(LISTING).maybeSingle();
      check(error);
      if (!data) throw failure('NOT_FOUND');
      return listingDTO(data);
    },

    // Soft delete: the row stays so buyers keep their inquiry history.
    async deleteListing(id) {
      const uid = requireViewer();
      const { error } = await db.from('listings').update({ deleted_at: new Date().toISOString() }).eq('id', id).eq('seller_id', uid);
      check(error);
    },

    async setFavorite(listingId, saved) {
      requireViewer();
      if (saved) {
        const { error } = await db.from('favorites').insert({ listing_id: listingId });
        if (error && error.code !== '23505') check(error);
      } else {
        const { error } = await db.from('favorites').delete().eq('listing_id', listingId);
        check(error);
      }
      return { listingId, saved };
    },

    async openConversation(listingId) {
      const uid = requireViewer();
      const { data, error } = await db.rpc('open_conversation', { p_listing: listingId });
      check(error);
      return fetchConversation(data.id, uid);
    },

    async sendMessage(conversationId, input) {
      const uid = requireViewer();
      const text = String(input.text || '').trim();
      if (!text || text.length > 500) throw failure('VALIDATION');
      const clientId = /^[0-9a-f-]{36}$/i.test(input.clientId || '') ? input.clientId : newId();
      const { error } = await db.from('messages').insert({ conversation_id: conversationId, body: text, client_id: clientId });
      if (error && error.code !== '23505') check(error);
      return fetchConversation(conversationId, uid);
    },

    async markRead(conversationId) {
      if (!viewerId()) return;
      const { error } = await db.rpc('mark_conversation_read', { conv: conversationId });
      if (error) console.warn('[PIECENOA] mark read failed', error.message);
    },

    async updateProfile(value) {
      const uid = requireViewer();
      const row = {
        display_name: String(value.name || '').trim().slice(0, 40),
        bio: String(value.bio || '').trim().slice(0, 240),
        role: value.role,
      };
      const location = String(value.location?.text || '').trim();
      if (location) row.location_text = location.slice(0, 80);
      if (value.avatarPath !== undefined) {
        if (value.avatarPath !== null && !String(value.avatarPath).startsWith(uid + '/')) throw failure('VALIDATION');
        row.avatar_path = value.avatarPath;
      }
      const { data, error } = await db.from('profiles').update(row).eq('id', uid)
        .select('id, display_name, bio, role, location_text, country_code, avatar_path').single();
      check(error);
      return profileDTO(data, account.session?.user);
    },

    async removeFile(bucket, path) {
      const uid = viewerId();
      if (!uid || !path || !path.startsWith(uid + '/')) return;
      const { error } = await db.storage.from(bucket).remove([path]);
      if (error) console.warn('[PIECENOA] file cleanup failed', error.message);
    },

    // Calls back when listings change anywhere, so Explore can refresh.
    subscribe(onChange) {
      const channel = db.channel('public:listings')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'listings' }, () => onChange('listings'))
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, () => onChange('messages'))
        .subscribe();
      return () => db.removeChannel(channel);
    },
  };

  window.PIECENOA_MARKET_REPOSITORY = repository;

  // Reload the market when a different member signs in or out.
  let lastViewer = undefined;
  account.onChange((session) => {
    const id = session?.user?.id || null;
    if (lastViewer === undefined) { lastViewer = id; return; }
    if (id === lastViewer) return;
    lastViewer = id;
    window.dispatchEvent(new CustomEvent('piecenoa:viewer-changed'));
  });
  account.ready.then(() => { if (lastViewer === undefined) lastViewer = viewerId(); });
})();
