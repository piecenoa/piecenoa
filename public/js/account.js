/* PIECENOA accounts: Supabase Auth behind the existing auth dialog.
 *
 * Runs only when js/config.js provides a Supabase URL and publishable key and the
 * supabase-js script has loaded. Without them it does nothing and the site stays the
 * local preview it was before. Only the publishable (public) key belongs in the browser;
 * row level security on the database decides what each user may read or change.
 *
 * Exposes window.PIECENOA_ACCOUNT = { client, ready, session, profile, onChange, setup }.
 */
(() => {
  'use strict';
  const config = window.PIECENOA_CONFIG;
  if (!config?.supabaseUrl || !config?.supabaseKey || typeof window.supabase?.createClient !== 'function') return;

  // Email confirmation, password reset and Google sign-in come back with their result in
  // the URL. Take it out before the app reads its own #community route.
  const AUTH_KEYS = ['access_token', 'refresh_token', 'expires_at', 'expires_in', 'token_type', 'type',
    'provider_token', 'provider_refresh_token', 'error', 'error_code', 'error_description'];
  const redirect = (() => {
    const hash = new URLSearchParams(location.hash.slice(1));
    const query = new URLSearchParams(location.search);
    if (!hash.has('access_token') && !hash.has('error_description') && !query.has('error_description')) return null;
    const result = {};
    for (const key of AUTH_KEYS) {
      const value = hash.get(key) ?? query.get(key);
      if (value != null) result[key] = value;
      query.delete(key);
    }
    const rest = query.toString();
    history.replaceState(history.state, '', location.pathname + (rest ? '?' + rest : ''));
    return result;
  })();

  const client = window.supabase.createClient(config.supabaseUrl, config.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'piecenoa.auth.v1' },
  });
  const siteURL = new URL('./', location.href).href;

  let session = null, profile = null, pending = null, googleEnabled = false, ui = null;
  const listeners = new Set();
  const emit = () => listeners.forEach((fn) => {
    try { fn(session, profile); } catch (error) { console.error('[PIECENOA] account listener failed', error); }
  });

  async function loadProfile() {
    const uid = session?.user?.id;
    if (!uid) { profile = null; return; }
    const { data, error } = await client.from('profiles').select('id, display_name').eq('id', uid).maybeSingle();
    if (error) console.warn('[PIECENOA] profile load failed', error.message);
    if (session?.user?.id === uid) profile = data || null;
  }

  function friendly(error) {
    const status = error?.status, code = String(error?.code || ''), message = String(error?.message || '');
    if (status === 429 || /rate limit|too many/i.test(message)) return 'Too many attempts. Please wait a minute and try again.';
    if (code === 'invalid_credentials' || /invalid login credentials/i.test(message)) return 'The email or password is incorrect.';
    if (code === 'email_not_confirmed' || /email not confirmed/i.test(message)) return 'Please confirm your email first. Check your inbox for the link.';
    if (code === 'weak_password' || /password should|weak password|pwned/i.test(message)) return 'Please choose a stronger password: at least 8 characters, and not a common one.';
    if (code === 'same_password') return 'Your new password must be different from the current one.';
    if (/provider is not enabled|unsupported provider/i.test(message)) return 'Google sign-in is not available yet. Please use email for now.';
    if (code === 'signup_disabled') return 'New accounts are paused right now. Please try again later.';
    if (code === 'email_address_invalid' || /email.*invalid|invalid.*email/i.test(message)) return 'Please enter a valid email address.';
    if (/failed to fetch|network/i.test(message)) return 'We could not reach the server. Check your connection and try again.';
    return 'Something went wrong. Please try again.';
  }
  const isUnconfirmed = (error) => error?.code === 'email_not_confirmed' || /email not confirmed/i.test(String(error?.message || ''));

  const ready = (async () => {
    try {
      if (redirect?.access_token && redirect.refresh_token) {
        const { error } = await client.auth.setSession({ access_token: redirect.access_token, refresh_token: redirect.refresh_token });
        if (error) pending = { mode: 'login', message: 'That link has expired or was already used. Please request a new one.', error: true };
        else if (redirect.type === 'recovery') pending = { mode: 'new-password', message: 'Choose a new password for your account.' };
        else if (redirect.type === 'signup' || redirect.type === 'email_change') pending = { mode: 'account', message: 'Your email is confirmed. Welcome to PIECENOA.' };
      } else if (redirect?.error_description) {
        pending = {
          mode: 'login', error: true,
          message: redirect.error_code === 'otp_expired'
            ? 'That link has expired or was already used. Please request a new one.'
            : 'We could not complete that sign-in. Please try again.',
        };
      }
      const { data } = await client.auth.getSession();
      session = data.session;
      await loadProfile();
    } catch (error) {
      console.error('[PIECENOA] account start failed', error);
    }
    try {
      const response = await fetch(config.supabaseUrl + '/auth/v1/settings', { headers: { apikey: config.supabaseKey } });
      if (response.ok) googleEnabled = Boolean((await response.json())?.external?.google);
    } catch {}
    emit();
  })();

  client.auth.onAuthStateChange((event, next) => {
    session = next;
    // Supabase advises not to await other auth calls inside this callback.
    setTimeout(async () => {
      if (event === 'PASSWORD_RECOVERY') {
        pending = { mode: 'new-password', message: 'Choose a new password for your account.' };
        ui?.showPending();
      }
      await loadProfile();
      emit();
    }, 0);
  });

  function setup({ showDialog }) {
    const $ = (selector) => document.querySelector(selector);
    const dialog = $('#auth-dialog'), form = $('#auth-form');
    const tabsRow = dialog.querySelector('.auth-tabs'), tabs = [...dialog.querySelectorAll('[data-auth-mode]')];
    const el = {
      title: $('#auth-title'), intro: $('#auth-intro'), panel: $('#auth-panel'), social: $('#auth-social'), google: $('#auth-google'),
      nameField: $('#auth-name-field'), name: $('#auth-name'), emailField: $('#auth-email-field'), email: $('#auth-email'),
      passwordField: $('#auth-password-field'), password: $('#auth-password'), show: $('#auth-show-password'),
      confirmField: $('#auth-confirm-field'), confirm: $('#auth-confirm'), forgotRow: $('#auth-forgot-row'), forgot: $('#auth-forgot'),
      resendRow: $('#auth-resend-row'), resend: $('#auth-resend'), status: $('#auth-status'), submit: $('#auth-submit'),
      account: $('#auth-account'), accountEmail: $('#auth-account-email'), accountStatus: $('#auth-account-status'),
      goStudio: $('#auth-go-studio'), changePassword: $('#auth-change-password'), signout: $('#auth-signout'),
      danger: $('#auth-danger'), deleteConfirm: $('#auth-delete-confirm'), deleteButton: $('#auth-delete'),
      switchRow: $('#auth-switch-row'), switchNote: $('#auth-switch-note'), switchButton: $('#auth-switch'), note: $('#auth-note'),
      homeLabel: $('.home-login span'), marketButton: $('#header-auth') || $('#market-account'),
    };
    const ARROW = '<svg aria-hidden="true"><use href="#i-arrow"/></svg>';
    const MODES = {
      login: { title: 'Welcome back.', intro: 'Your own space, connected through art.', submit: 'Log in', tabs: true, social: true,
        email: true, password: true, forgot: true, switchNote: 'Don’t have an account?', switchLabel: 'Sign up', switchTo: 'signup' },
      signup: { title: 'Discover your art.', intro: 'Where new art and people meet.', submit: 'Sign up', tabs: true, social: true,
        name: true, email: true, password: true, confirm: true, switchNote: 'Already have an account?', switchLabel: 'Log in', switchTo: 'login' },
      reset: { title: 'Reset your password.', intro: 'Enter your email and we will send you a link to choose a new password.',
        submit: 'Send reset link', email: true, switchNote: 'Remembered it?', switchLabel: 'Log in', switchTo: 'login' },
      'new-password': { title: 'Choose a new password.', intro: 'Use at least 8 characters.', submit: 'Save password', password: true, confirm: true },
      account: { title: 'Your account.', intro: 'You are signed in to PIECENOA.', account: true },
    };
    let mode = 'login', busy = false, lastEmail = '';

    el.note.textContent = 'Your email stays private. It is never shown on your studio.';

    function setStatus(target, message, error) {
      target.textContent = message || '';
      target.hidden = !message;
      target.classList.toggle('is-error', Boolean(error));
    }
    function toggleField(field, input, on) { field.hidden = !on; input.disabled = !on; input.required = on; }

    function setMode(next, notice = {}) {
      if ((next === 'account' || next === 'new-password') && !session) next = 'login';
      mode = MODES[next] ? next : 'login';
      const m = MODES[mode];
      tabs.forEach((tab) => {
        const active = tab.dataset.authMode === mode;
        tab.classList.toggle('active', active);
        tab.setAttribute('aria-selected', String(active));
        tab.tabIndex = active ? 0 : -1;
      });
      tabsRow.hidden = !m.tabs;
      if (m.tabs) {
        el.panel.setAttribute('role', 'tabpanel');
        el.panel.setAttribute('aria-labelledby', mode === 'signup' ? 'auth-signup-tab' : 'auth-login-tab');
      } else {
        el.panel.removeAttribute('role');
        el.panel.removeAttribute('aria-labelledby');
      }
      el.title.textContent = m.title;
      el.intro.textContent = m.intro;
      el.social.hidden = !(m.social && googleEnabled);
      form.hidden = Boolean(m.account);
      el.account.hidden = !m.account;
      toggleField(el.nameField, el.name, Boolean(m.name));
      toggleField(el.emailField, el.email, Boolean(m.email));
      toggleField(el.passwordField, el.password, Boolean(m.password));
      toggleField(el.confirmField, el.confirm, Boolean(m.confirm));
      const choosing = mode === 'signup' || mode === 'new-password';
      el.password.autocomplete = choosing ? 'new-password' : 'current-password';
      el.password.minLength = choosing ? 8 : 1;
      el.password.placeholder = choosing ? 'Enter at least 8 characters' : 'Enter your password';
      el.password.value = '';
      el.confirm.value = '';
      el.confirm.setCustomValidity?.('');
      el.password.type = 'password';
      el.show.setAttribute('aria-pressed', 'false');
      el.show.setAttribute('aria-label', 'Show password');
      el.forgotRow.hidden = !m.forgot;
      el.resendRow.hidden = true;
      el.submit.textContent = m.submit || '';
      el.submit.insertAdjacentHTML('beforeend', ARROW);
      el.switchRow.hidden = !m.switchTo;
      el.switchNote.textContent = m.switchNote || '';
      el.switchButton.textContent = m.switchLabel || '';
      el.deleteConfirm.value = '';
      el.deleteButton.disabled = true;
      el.danger.open = false;
      if (m.account) {
        el.accountEmail.textContent = session?.user?.email ? 'Signed in as ' + session.user.email : '';
        setStatus(el.accountStatus, notice.message, notice.error);
        setStatus(el.status, '');
      } else {
        setStatus(el.status, notice.message, notice.error);
      }
    }

    async function run(button, task) {
      if (busy) return;
      busy = true;
      button.setAttribute('aria-busy', 'true');
      button.disabled = true;
      try {
        await task();
      } catch (error) {
        console.error('[PIECENOA] account action failed', error);
        setStatus(mode === 'account' ? el.accountStatus : el.status, friendly(error), true);
      } finally {
        busy = false;
        button.removeAttribute('aria-busy');
        button.disabled = button === el.deleteButton ? el.deleteConfirm.value.trim().toUpperCase() !== 'DELETE' : false;
      }
    }

    function open(next, notice) {
      form.reset();
      setMode(next || (session ? 'account' : 'login'), notice);
      if (!dialog.open) showDialog(dialog);
    }

    function showPending() {
      if (!pending) return;
      const { mode: next, ...notice } = pending;
      pending = null;
      open(next, notice);
    }

    function renderSignedIn() {
      const signedIn = Boolean(session);
      const user = session?.user;
      const named = profile?.display_name && profile.display_name !== 'Member' ? profile.display_name : '';
      const name = named || String(user?.user_metadata?.name || user?.email?.split('@')[0] || '');
      if (el.homeLabel) el.homeLabel.textContent = signedIn ? (name.length > 18 ? name.slice(0, 17) + '…' : name || 'My account') : 'Log in';
      if (el.marketButton) {
        el.marketButton.classList.toggle('is-signed-in', signedIn);
        el.marketButton.setAttribute('aria-label', signedIn ? 'Your account' : 'Log in');
      }
      document.body.dataset.auth = signedIn ? 'signed-in' : 'signed-out';
      if (!signedIn && dialog.open && (mode === 'account' || mode === 'new-password')) setMode('login');
    }

    document.querySelectorAll('[data-auth-open]').forEach((button) => button.addEventListener('click', () => open()));
    tabs.forEach((tab) => {
      tab.addEventListener('click', () => setMode(tab.dataset.authMode));
      tab.addEventListener('keydown', (event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const next = event.key === 'Home' ? 'login' : event.key === 'End' ? 'signup' : mode === 'login' ? 'signup' : 'login';
        setMode(next);
        tabs.find((x) => x.dataset.authMode === next).focus();
      });
    });
    el.switchButton.addEventListener('click', () => {
      const target = MODES[mode].switchTo;
      if (!target) return;
      setMode(target);
      el.email.focus();
    });
    el.forgot.addEventListener('click', () => { setMode('reset'); el.email.focus(); });
    el.show.addEventListener('click', () => {
      const visible = el.password.type === 'password';
      el.password.type = visible ? 'text' : 'password';
      el.show.setAttribute('aria-pressed', String(visible));
      el.show.setAttribute('aria-label', visible ? 'Hide password' : 'Show password');
    });
    el.confirm.addEventListener('input', () => el.confirm.setCustomValidity?.(''));

    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const email = el.email.value.trim(), password = el.password.value;
      if (el.confirm.required && password !== el.confirm.value) {
        el.confirm.setCustomValidity?.('Passwords do not match.');
        el.confirm.reportValidity?.();
        setStatus(el.status, 'Passwords do not match.', true);
        el.confirm.focus();
        return;
      }
      run(el.submit, async () => {
        setStatus(el.status, '');
        el.resendRow.hidden = true;
        if (mode === 'login') {
          const { error } = await client.auth.signInWithPassword({ email, password });
          if (error) {
            setStatus(el.status, friendly(error), true);
            if (isUnconfirmed(error)) { lastEmail = email; el.resendRow.hidden = false; }
            return;
          }
          dialog.close();
        } else if (mode === 'signup') {
          const name = el.name.value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 40);
          if (!name) { setStatus(el.status, 'Please enter your name.', true); el.name.focus(); return; }
          const { data, error } = await client.auth.signUp({ email, password, options: { data: { name }, emailRedirectTo: siteURL } });
          if (error) { setStatus(el.status, friendly(error), true); return; }
          if (data.session) { dialog.close(); return; }
          // The same reply is shown whether or not the email was already registered.
          lastEmail = email;
          el.password.value = '';
          el.confirm.value = '';
          setStatus(el.status, 'Almost there. We sent a confirmation link to ' + email + '. Open it to finish creating your account.');
          el.resendRow.hidden = false;
        } else if (mode === 'reset') {
          const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo: siteURL });
          if (error?.status === 429) { setStatus(el.status, friendly(error), true); return; }
          setStatus(el.status, 'If an account exists for ' + email + ', a reset link is on its way. Check your inbox.');
        } else if (mode === 'new-password') {
          const { error } = await client.auth.updateUser({ password });
          if (error) { setStatus(el.status, friendly(error), true); return; }
          setMode('account', { message: 'Your password has been updated.' });
        }
      });
    });

    el.resend.addEventListener('click', () => run(el.resend, async () => {
      const email = el.email.value.trim() || lastEmail;
      if (!email) { el.email.focus(); return; }
      const { error } = await client.auth.resend({ type: 'signup', email, options: { emailRedirectTo: siteURL } });
      if (error) { setStatus(el.status, friendly(error), true); return; }
      setStatus(el.status, 'We sent the confirmation link again to ' + email + '.');
    }));

    el.google.addEventListener('click', () => run(el.google, async () => {
      const { error } = await client.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: siteURL } });
      if (error) setStatus(el.status, friendly(error), true);
    }));

    el.goStudio.addEventListener('click', () => {
      dialog.close();
      const goMine = () => document.querySelector('.market-nav [data-mode="mine"]')?.click();
      if (['#community', '#market'].includes(location.hash)) { goMine(); return; }
      window.addEventListener('hashchange', () => setTimeout(goMine, 0), { once: true });
      location.hash = 'community';
    });
    el.changePassword.addEventListener('click', () => setMode('new-password'));
    el.signout.addEventListener('click', () => run(el.signout, async () => {
      const { error } = await client.auth.signOut({ scope: 'local' });
      if (error) { setStatus(el.accountStatus, friendly(error), true); return; }
      dialog.close();
    }));
    el.deleteConfirm.addEventListener('input', () => {
      el.deleteButton.disabled = el.deleteConfirm.value.trim().toUpperCase() !== 'DELETE';
    });
    el.deleteButton.addEventListener('click', () => run(el.deleteButton, async () => {
      const { error } = await client.functions.invoke('delete-account', { method: 'POST' });
      if (error) {
        setStatus(el.accountStatus, 'We could not delete your account right now. Please try again later.', true);
        return;
      }
      await client.auth.signOut({ scope: 'local' }).catch(() => {});
      setMode('login', { message: 'Your account has been deleted.' });
    }));

    dialog.addEventListener('close', () => {
      form.reset();
      el.password.value = '';
      el.confirm.value = '';
      setMode(session ? 'account' : 'login');
    });

    listeners.add(renderSignedIn);
    ui = { showPending };
    setMode('login');
    renderSignedIn();
    // setup() can run before or after the session finishes loading; this runs once either way.
    ready.then(() => {
      el.social.hidden = !(MODES[mode].social && googleEnabled);
      renderSignedIn();
      showPending();
    });
  }

  window.PIECENOA_ACCOUNT = Object.freeze({
    client,
    ready,
    get session() { return session; },
    get profile() { return profile; },
    onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    setup,
  });
})();
