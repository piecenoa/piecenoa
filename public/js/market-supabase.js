/* PIECENOA market data on Supabase (piecenoa-2 contract).
 *
 * Implements window.PIECENOA_MARKET_REPOSITORY as documented in js/app.js under
 * "MARKET DATA BOUNDARY". Loaded only when js/account.js created a Supabase client;
 * otherwise app.js keeps its browser-only preview repository.
 *
 * Who may read or change what is decided by row level security in the database
 * (supabase/migrations), not by this file.
 */
(() => {
  'use strict';
  const account = window.PIECENOA_ACCOUNT;
  if (!account?.client) return;
  const db = account.client;
  const storageBase = window.PIECENOA_CONFIG.supabaseUrl.replace(/\/$/, '') + '/storage/v1/object/public/';

  // Must match MARKET_CURRENCIES in app.js and public.currencies in the database.
  const MINOR_UNITS = {
    USD: 2, EUR: 2, JPY: 0, GBP: 2, CNY: 2, CHF: 2, CAD: 2, AUD: 2, KRW: 0, HKD: 2,
    SGD: 2, INR: 2, NZD: 2, TWD: 2, AED: 2, BRL: 2, MXN: 2, THB: 2, VND: 0, RUB: 2,
  };
  const CATEGORIES = ['painting', 'drawing', 'print', 'photography', 'sculpture', 'object', 'jewelry', 'mixed'];
  const KINDS = ['unknown', 'original', 'edition', 'reproduction'];
  const CONDITIONS = ['unknown', 'new', 'good', 'vintage'];
  const DELIVERIES = ['unknown', 'meetup', 'shipping', 'either'];
  const FRAMINGS = ['yes', 'no', 'unknown'];
  const FEED_SIZE = 500;
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  const PROFILE = 'id, display_name, bio, role, location_text, country_code, avatar_path';
  const SELLER = 'seller:profiles!listings_seller_id_fkey(' + PROFILE + ')';
  const LISTING = 'id, seller_id, title, description, price_minor, currency, category, status, image_path, artist, medium, ' +
    'dimensions, year, kind, condition, delivery, framed, negotiable, location_text, country_code, visibility, ' +
    'moderation_status, favorite_count, conversation_count, created_at, updated_at, deleted_at, ' + SELLER;
  const CONVERSATION = 'id, listing_id, buyer_id, seller_id, last_message_at, ' +
    'listing:listings(id, title, price_minor, currency, conversation_count), ' +
    'messages(id, sender_id, body, created_at, read_at, client_id)';

  const failure = (code, cause) => Object.assign(new Error(code), { code, cause });
  function check(error, fallback = 'SERVER') {
    if (!error) return;
    console.warn('[PIECENOA] market request failed', error.code || '', error.message || error);
    const status = Number(error.status || error.statusCode || 0);
    const message = String(error.message || '');
    if (status === 401 || error.code === 'PGRST301' || /jwt|not authenticated|AUTH_REQUIRED/i.test(message)) throw failure('AUTH_REQUIRED', error);
    if (error.code === '42501' || status === 403) throw failure('FORBIDDEN', error);
    if (['23514', '22P02', '23502', '23503'].includes(error.code)) throw failure('VALIDATION', error);
    if (/NOT_FOUND/.test(message)) throw failure('NOT_FOUND', error);
    if (error.code === 'PGRST202' || error.code === '42883') throw failure('CHAT_NOT_READY', error);
    throw failure(fallback, error);
  }
  const viewerId = () => account.session?.user?.id || null;
  function requireViewer() {
    const id = viewerId();
    if (!id) throw failure('AUTH_REQUIRED');
    return id;
  }
  const newId = () => globalThis.crypto?.randomUUID?.() ||
    'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g, () => Math.floor(Math.random() * 16).toString(16));

  const publicUrl = (bucket, path) => (path ? storageBase + bucket + '/' + path.split('/').map(encodeURIComponent).join('/') : '');
  function pathFromUrl(bucket, url) {
    const prefix = storageBase + bucket + '/';
    if (typeof url !== 'string' || !url.startsWith(prefix)) return null;
    return url.slice(prefix.length).split('/').map(decodeURIComponent).join('/');
  }
  const scale = (currency) => 10 ** (MINOR_UNITS[currency] ?? 2);
  const count = (value) => (Number.isSafeInteger(value) && value >= 0 ? value : 0);

  function sellerDTO(row) {
    if (!row) return undefined;
    return {
      id: row.id,
      name: row.display_name && row.display_name !== 'Member' ? row.display_name : '',
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
      price: row.price_minor / scale(row.currency),
      priceMinor: row.price_minor,
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
      favoriteCount: count(row.favorite_count),
      conversationCount: count(row.conversation_count),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      version: row.updated_at,
      seller: sellerDTO(row.seller),
    };
  }

  const oneOf = (value, allowed, fallback) => (allowed.includes(value) ? value : fallback);

  // ListingInput (app shape) -> the columns a member may write.
  function listingRow(input, uid) {
    const currency = String(input.currency || '').toUpperCase();
    if (!Object.hasOwn(MINOR_UNITS, currency)) throw failure('VALIDATION');
    const minor = Number.isSafeInteger(input.priceMinor) ? input.priceMinor : Math.round(Number(input.price) * scale(currency));
    if (!Number.isSafeInteger(minor) || minor < 0) throw failure('VALIDATION');
    const imagePath = pathFromUrl('listing-images', input.image);
    if (!imagePath || !imagePath.startsWith(uid + '/')) throw failure('VALIDATION');
    if (!CATEGORIES.includes(input.category)) throw failure('VALIDATION');
    const year = /^[12][0-9]{3}$/.test(String(input.year || '')) ? Number(input.year) : null;
    const row = {
      title: String(input.title || '').trim(),
      description: String(input.description || '').trim(),
      price_minor: minor,
      currency,
      category: input.category,
      status: oneOf(input.status, ['available', 'reserved', 'sold'], 'available'),
      image_path: imagePath,
      artist: String(input.artist || '').trim().slice(0, 80),
      medium: String(input.medium || '').trim().slice(0, 80),
      dimensions: String(input.dimensions || '').trim().slice(0, 50),
      year,
      kind: oneOf(input.kind, KINDS, 'unknown'),
      condition: oneOf(input.condition, CONDITIONS, 'unknown'),
      delivery: oneOf(input.delivery, DELIVERIES, 'unknown'),
      framed: oneOf(input.framed, FRAMINGS, 'unknown'),
      negotiable: Boolean(input.negotiable),
      location_text: String(input.location?.text || input.region || '').trim().slice(0, 80),
      country_code: /^[A-Z]{2}$/.test(String(input.location?.countryCode || '')) ? input.location.countryCode : null,
    };
    // Only change visibility when the app asks; an edit must not make a private piece public.
    if (input.visibility === 'public' || input.visibility === 'private') row.visibility = input.visibility;
    return row;
  }

  function profileDTO(row) {
    return {
      id: row?.id,
      name: row?.display_name && row.display_name !== 'Member' ? row.display_name : '',
      bio: row?.bio || '',
      role: row?.role || 'artist',
      location: row?.location_text ? { text: row.location_text, countryCode: row.country_code || undefined } : undefined,
      region: row?.location_text || '',
      avatarUrl: publicUrl('avatars', row?.avatar_path),
    };
  }

  function conversationDTO(row, uid) {
    const listing = row.listing;
    return {
      id: row.id,
      listingId: row.listing_id,
      title: listing?.title || '',
      ...(listing ? { price: listing.price_minor / scale(listing.currency), priceMinor: listing.price_minor, currency: listing.currency } : { price: 0 }),
      ...(listing ? { conversationCount: count(listing.conversation_count) } : {}),
      role: row.buyer_id === uid ? 'buyer' : 'seller',
      lastMessageAt: row.last_message_at,
      messages: (row.messages || []).slice(-100).map((m) => {
        const outgoing = m.sender_id === uid;
        return {
          id: m.id,
          clientId: m.client_id || undefined,
          text: m.body,
          createdAt: m.created_at,
          senderId: m.sender_id,
          direction: outgoing ? 'outgoing' : 'incoming',
          state: 'sent',
          // read is about the viewer: an incoming message is read once the viewer saw it.
          read: outgoing || Boolean(m.read_at),
          readAt: m.read_at,
        };
      }),
    };
  }

  async function loadConversations(uid) {
    const { data, error } = await db.from('conversations').select(CONVERSATION)
      .order('last_message_at', { ascending: false })
      .order('created_at', { referencedTable: 'messages', ascending: true })
      .limit(100);
    check(error);
    return (data || []).map((row) => conversationDTO(row, uid)).filter((c) => c.messages.length > 0);
  }

  async function fetchConversation(id, uid) {
    const { data, error } = await db.from('conversations').select(CONVERSATION).eq('id', id)
      .order('created_at', { referencedTable: 'messages', ascending: true }).maybeSingle();
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

  async function removeOwnFile(bucket, path) {
    const uid = viewerId();
    if (!uid || !path || !path.startsWith(uid + '/')) return;
    const { error } = await db.storage.from(bucket).remove([path]);
    if (error) console.warn('[PIECENOA] file cleanup failed', error.message);
  }

  const repository = {
    mode: 'supabase',

    async bootstrap() {
      await account.ready;
      const uid = viewerId();
      const feed = await db.from('listings').select(LISTING)
        .eq('visibility', 'public').eq('moderation_status', 'active').is('deleted_at', null)
        .order('created_at', { ascending: false }).limit(FEED_SIZE);
      check(feed.error);
      const byId = new Map((feed.data || []).map((row) => [row.id, listingDTO(row)]));
      if (!uid) return { viewer: null, profile: null, listings: [...byId.values()], favorites: [], conversations: [] };

      const [mine, favs, me, conversations] = await Promise.all([
        db.from('listings').select(LISTING).eq('seller_id', uid).is('deleted_at', null).order('created_at', { ascending: false }),
        db.from('favorites').select('listing_id, created_at, listing:listings(' + LISTING + ')').order('created_at', { ascending: false }),
        db.from('profiles').select(PROFILE).eq('id', uid).maybeSingle(),
        loadConversations(uid),
      ]);
      check(mine.error); check(favs.error); check(me.error);
      for (const row of mine.data || []) byId.set(row.id, listingDTO(row));
      for (const fav of favs.data || []) if (fav.listing && !fav.listing.deleted_at) byId.set(fav.listing.id, listingDTO(fav.listing));
      return {
        viewer: { id: uid },
        profile: profileDTO(me.data),
        listings: [...byId.values()],
        // Saved pieces that were deleted or made private are left out; the app never sees them.
        favorites: (favs.data || []).filter((f) => f.listing && !f.listing.deleted_at).map((f) => f.listing_id),
        conversations,
      };
    },

    async uploadImage(input) {
      const uid = requireViewer();
      const bucket = input?.purpose === 'avatar' ? 'avatars' : 'listing-images';
      const { blob, mime } = dataUrlToBlob(input?.dataUrl);
      if (blob.size > (bucket === 'avatars' ? 2 : 3) * 1024 * 1024) throw failure('VALIDATION');
      const path = uid + '/' + newId() + '.' + EXT[mime];
      const { error } = await db.storage.from(bucket).upload(path, blob, { contentType: mime, cacheControl: '31536000', upsert: false });
      check(error, 'UPLOAD');
      return { url: publicUrl(bucket, path), id: path };
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

    // Soft delete keeps the row so buyers keep their inquiry history.
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
      const result = { listingId, saved };
      const { data } = await db.from('listings').select('favorite_count').eq('id', listingId).maybeSingle();
      if (data) result.favoriteCount = count(data.favorite_count);
      return result;
    },

    // Creates (or reuses) the conversation and saves its first message in one database transaction.
    async startConversation(listingId, input) {
      const uid = requireViewer();
      const text = String(input?.text || '').trim();
      if (!text || text.length > 500) throw failure('VALIDATION');
      const clientId = UUID.test(input?.clientId || '') ? input.clientId : newId();
      const { data, error } = await db.rpc('start_conversation', { p_listing: listingId, p_body: text, p_client_id: clientId });
      check(error);
      return fetchConversation(data.id, uid);
    },

    async sendMessage(conversationId, input) {
      const uid = requireViewer();
      const text = String(input?.text || '').trim();
      if (!text || text.length > 500) throw failure('VALIDATION');
      const clientId = UUID.test(input?.clientId || '') ? input.clientId : newId();
      const { error } = await db.from('messages').insert({ conversation_id: conversationId, body: text, client_id: clientId });
      if (error && error.code !== '23505') check(error);
      return fetchConversation(conversationId, uid);
    },

    // Legacy and read-only: never creates an empty conversation.
    async openConversation(listingId) {
      const uid = requireViewer();
      const { data, error } = await db.from('conversations').select('id').eq('listing_id', listingId).eq('buyer_id', uid).maybeSingle();
      check(error);
      if (!data) throw failure('NOT_FOUND');
      return fetchConversation(data.id, uid);
    },

    async markConversationRead(conversationId, input = {}) {
      if (!viewerId()) return;
      const ids = (Array.isArray(input.messageIds) ? input.messageIds : []).map(String).filter((id) => UUID.test(id)).slice(0, 100);
      let query = db.from('messages').update({ read_at: new Date().toISOString() })
        .eq('conversation_id', conversationId).is('read_at', null).neq('sender_id', viewerId());
      if (ids.length) query = query.in('id', ids);
      const { error } = await query;
      if (error) console.warn('[PIECENOA] mark read failed', error.message);
    },

    async updateProfile(value) {
      const uid = requireViewer();
      const { data: before } = await db.from('profiles').select('avatar_path').eq('id', uid).maybeSingle();
      const row = {
        display_name: String(value.name || '').trim().slice(0, 40) || 'Member',
        bio: String(value.bio || '').trim().slice(0, 240),
        role: oneOf(value.role, ['artist', 'collector', 'studio'], 'artist'),
      };
      const location = String(value.location?.text || '').trim();
      if (location) row.location_text = location.slice(0, 80);
      if (Object.hasOwn(value, 'avatarUrl')) {
        if (!value.avatarUrl) row.avatar_path = null;
        else {
          const path = pathFromUrl('avatars', value.avatarUrl);
          if (!path || !path.startsWith(uid + '/')) throw failure('VALIDATION');
          row.avatar_path = path;
        }
      }
      const { data, error } = await db.from('profiles').update(row).eq('id', uid).select(PROFILE).single();
      check(error);
      const previous = before?.avatar_path;
      if (previous && previous !== data.avatar_path) removeOwnFile('avatars', previous);
      return profileDTO(data);
    },

    // Pushes conversations to the app when a message arrives or is read.
    subscribe(listener) {
      const uid = viewerId();
      if (!uid) return () => {};
      const pending = new Map();
      const refresh = (conversationId) => {
        if (!conversationId || pending.has(conversationId)) return;
        pending.set(conversationId, setTimeout(async () => {
          pending.delete(conversationId);
          try {
            const conversation = await fetchConversation(conversationId, uid);
            if (conversation.messages.length) listener({ type: 'conversation', conversation });
          } catch (error) {
            console.warn('[PIECENOA] live update failed', error?.code || error);
          }
        }, 250));
      };
      const channel = db.channel('piecenoa:messages:' + uid)
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, (payload) => refresh(payload.new?.conversation_id))
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages' }, (payload) => refresh(payload.new?.conversation_id))
        .subscribe();
      return () => {
        pending.forEach((timer) => clearTimeout(timer));
        db.removeChannel(channel);
      };
    },
  };

  window.PIECENOA_MARKET_REPOSITORY = repository;

  // Reload the market when a different member signs in or out.
  let lastViewer;
  account.onChange((session) => {
    const id = session?.user?.id || null;
    if (lastViewer === undefined) { lastViewer = id; return; }
    if (id === lastViewer) return;
    lastViewer = id;
    window.dispatchEvent(new CustomEvent('piecenoa:viewer-changed'));
  });
  account.ready.then(() => { if (lastViewer === undefined) lastViewer = viewerId(); });
})();
