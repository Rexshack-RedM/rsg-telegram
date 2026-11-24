const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg-telegram';
const $ = (id) => document.getElementById(id);

const state = {
    contacts: [], pendingContact: null, inbox: [], sent: [], blocked: [], current: null, recipient: null,
    cost: 0, maxSubject: 50, maxMessage: 1000, minSearch: 2, busy: false,
    tab: 'inbox', view: 'inbox', readMode: 'inbox', offices: [], attach: { enabled: false }, receipts: true,
    attachables: null, attachSel: {}, modalAction: null,
    inboxQuery: '', inboxMore: false, pageSize: 25, unreadTotal: null,
    anon: { enabled: false, fee: 0 }, anonymous: false, showIds: true, directory: false, unlisted: false, appOpen: false,
};
const DRAFT_KEY = 'rsg-telegram:draft';
let draftOwner = null; // citizen id the stored draft belongs to (localStorage is shared by every character on this PC)
const timers = { recipient: null, contact: null, inbox: null };
let L = {};
const SYSTEM_SENDER = 'SYSTEM'; // sender id used for telegrams sent by scripts through the server API
const ANON_SENDER = 'ANON';     // what the server sends instead of an anonymous sender's citizen id
function idTag(cid) { return state.showIds ? (cid || '') : ''; }

/* ---------- locales ---------- */
function t(key, ...args) {
    let str = L[key] ?? key;
    args.forEach(a => { str = str.replace('%s', () => String(a)); });
    return str;
}

function applyLocales() {
    document.querySelectorAll('[data-i18n]').forEach(el => { if (L[el.dataset.i18n]) el.textContent = L[el.dataset.i18n]; });
    document.querySelectorAll('[data-i18n-ph]').forEach(el => { if (L[el.dataset.i18nPh]) el.placeholder = L[el.dataset.i18nPh]; });
    document.querySelectorAll('[data-i18n-title]').forEach(el => { if (L[el.dataset.i18nTitle]) el.title = L[el.dataset.i18nTitle]; });
}

async function post(name, data = {}) {
    try {
        const res = await fetch(`https://${RES}/${name}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
        });
        return await res.json();
    } catch (e) { return null; }
}

function esc(str) {
    const d = document.createElement('div');
    d.textContent = str == null ? '' : String(str);
    return d.innerHTML;
}

function fmtDate(ts) {
    if (!ts) return '';
    const d = new Date(ts * 1000);
    try {
        const loc = t('ui_date_locale');
        return d.toLocaleDateString(loc, { day: '2-digit', month: 'short' }) + ' ' +
               d.toLocaleTimeString(loc, { hour: '2-digit', minute: '2-digit' });
    } catch (e) {
        return d.toLocaleString();
    }
}

function toast(msg, type = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<div class="t-label">${esc(t('ui_toast_' + type))}</div>${esc(msg)}`;
    $('toasts').appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3000);
}

function showView(name) {
    state.view = name;
    ['inbox', 'read', 'compose', 'contacts', 'blocked'].forEach(v => $(`view-${v}`).classList.toggle('hidden', v !== name));
    $('btn-back').classList.toggle('hidden', name === 'inbox');
}

function money(n) { return '$' + Number(n || 0).toFixed(2); }

/* ---------- confirm modal ---------- */
function askConfirm(titleKey, textKey, yesKey, action, ...args) {
    $('modal-title').textContent = t(titleKey);
    $('modal-text').textContent = t(textKey, ...args);
    $('modal-yes').textContent = t(yesKey);
    state.modalAction = action;
    $('modal').classList.remove('hidden');
}

/* ---------- tabs ---------- */
function renderList() { state.tab === 'sent' ? renderSent() : renderInbox(); }

async function setTab(tab) {
    state.tab = tab;
    $('tab-inbox').classList.toggle('active', tab === 'inbox');
    $('tab-sent').classList.toggle('active', tab === 'sent');
    $('bulk-bar').classList.toggle('hidden', tab !== 'inbox');
    $('search-row').classList.toggle('hidden', tab !== 'inbox');
    renderList();
    if (tab === 'sent') await refreshSent(); else await refreshInbox();
}

/* ---------- inbox ---------- */
function renderInbox() {
    const list = $('inbox-list');
    const loadedUnread = state.inbox.filter(m => !m.is_read).length;
    const unread = state.inboxMore && state.unreadTotal != null ? Math.max(loadedUnread, state.unreadTotal) : loadedUnread;
    $('unread-count').textContent = unread ? t('ui_new_count', unread) : '';
    if (!state.inbox.length) {
        list.innerHTML = `<div class="empty">${esc(t(state.inboxQuery ? 'ui_no_results' : 'ui_no_telegrams'))}</div>`;
        return;
    }
    list.innerHTML = state.inbox.map(m => `
        <div class="row ${m.is_read ? 'read' : ''}" data-id="${m.id}">
            <div class="badge-icon">&#9993;</div>
            <div class="row-main">
                <div class="row-title">${esc(m.subject)}</div>
                <div class="row-sub">${esc(t('ui_from_line', m.sender_name))} &middot; ${fmtDate(m.sent_at)}</div>
            </div>
            <div class="row-pills">
                ${m.kind ? `<span class="pill notice">${esc(t(m.kind === 'notice' ? 'ui_kind_notice' : 'ui_kind_broadcast'))}</span>` : ''}
                ${m.is_read ? '' : `<span class="pill">${esc(t('ui_new'))}</span>`}
                ${m.attachment ? `<span class="pill ok">${esc(t('ui_attachment'))}</span>` : ''}
            </div>
        </div>`).join('') + (state.inboxMore ? `<div class="load-more"><button class="wood-btn muted mini-btn" id="btn-more">${esc(t('ui_load_more'))}</button></div>` : '');
    list.querySelectorAll('.row').forEach(r => r.addEventListener('click', () => openTelegram(Number(r.dataset.id))));
    const more = $('btn-more');
    if (more) more.addEventListener('click', async () => { more.disabled = true; await refreshInbox(true); });
}

/* ---------- sent ---------- */
function sentStatus(m) {
    if (!m.delivered) return { cls: 'dim', text: t('ui_status_transit') };
    if (state.receipts && m.recipients > 0) {
        if (m.read_count >= m.recipients) return { cls: 'ok', text: t('ui_status_read') };
        if (m.read_count > 0) return { cls: 'ok', text: t('ui_status_read_n', m.read_count, m.recipients) };
    }
    return { cls: '', text: t('ui_status_delivered') };
}

function renderSent() {
    const list = $('inbox-list');
    $('unread-count').textContent = state.inbox.some(m => !m.is_read) ? t('ui_new_count', state.inbox.filter(m => !m.is_read).length) : '';
    if (!state.sent.length) {
        list.innerHTML = `<div class="empty">${esc(t('ui_sent_empty'))}</div>`;
        return;
    }
    list.innerHTML = state.sent.map(m => {
        const st = sentStatus(m);
        return `
        <div class="row read" data-id="${m.id}">
            <div class="badge-icon">&#10148;</div>
            <div class="row-main">
                <div class="row-title">${esc(m.subject)}</div>
                <div class="row-sub">${esc(t('ui_to_line', m.recipient_name || ''))}${m.recipients > 1 ? ' +' + (m.recipients - 1) : ''} &middot; ${fmtDate(m.sent_at)}</div>
            </div>
            <div class="row-pills">
                <span class="pill ${st.cls}">${esc(st.text)}</span>
                ${m.has_attachment ? `<span class="pill ${m.unclaimed ? '' : 'ok'}">${esc(t(m.unclaimed ? 'ui_unclaimed' : 'ui_claimed'))}</span>` : ''}
            </div>
        </div>`;
    }).join('');
    list.querySelectorAll('.row').forEach(r => r.addEventListener('click', () => openSent(Number(r.dataset.id))));
}

async function refreshSent() {
    const data = await post('getSent');
    if (data === false) return;
    state.sent = Array.isArray(data) ? data : [];
    if (state.tab === 'sent') renderSent();
}

// append = load the next page; otherwise (re)load the first page for the current search
async function refreshInbox(append = false) {
    const data = await post('refresh', { offset: append ? state.inbox.length : 0, query: state.inboxQuery });
    if (data === false) { if (append) renderInbox(); return; } // throttled, keep what is shown
    const rows = Array.isArray(data) ? data : [];
    const known = new Set(state.inbox.map(m => m.id));
    state.inbox = append ? state.inbox.concat(rows.filter(m => !known.has(m.id))) : rows;
    state.inboxMore = rows.length >= state.pageSize;
    if (state.tab === 'inbox') renderInbox();
}

/* ---------- read ---------- */
function renderAttachBox(m) {
    const box = $('read-attach');
    const att = m.attachment;
    const had = !!m.has_attachment;
    const mine = state.readMode === 'inbox';
    if (!had && !att) { box.classList.add('hidden'); return; }
    box.classList.remove('hidden');
    const lines = [];
    if (att && att.cash > 0) lines.push(`<span>${esc(t('ui_attach_cash'))}: ${esc(money(att.cash))}</span>`);
    if (att) (att.items || []).forEach(it => lines.push(`<span>${esc(it.amount)}x ${esc(it.label || it.name)}</span>`));
    $('read-attach-lines').innerHTML = lines.join('');
    $('btn-collect').classList.toggle('hidden', !(mine && att));
    $('btn-collect').disabled = false;
    const st = $('read-attach-state');
    st.classList.toggle('hidden', !!(mine && att));
    st.textContent = t(att ? 'ui_unclaimed' : 'ui_claimed');
}

function setReadMode(mode) {
    state.readMode = mode;
    const inbox = mode === 'inbox';
    $('read-from-label').textContent = t(inbox ? 'ui_from' : 'ui_to');
    ['btn-reply', 'btn-save-sender', 'btn-block', 'btn-delete'].forEach(id => $(id).classList.toggle('hidden', !inbox));
}

function openSent(id) {
    const m = state.sent.find(x => x.id === id);
    if (!m) return;
    state.current = m;
    setReadMode('sent');
    $('read-from').textContent = m.recipient_name + (m.recipients > 1 ? ` (+${m.recipients - 1})` : '');
    $('read-date').textContent = fmtDate(m.sent_at);
    $('read-subject').textContent = m.subject;
    $('read-body').textContent = m.message;
    $('read-body').parentElement.scrollTop = 0;
    renderAttachBox(m);
    showView('read');
}

function openTelegram(id) {
    const m = state.inbox.find(x => x.id === id);
    if (!m) return;
    state.current = m;
    setReadMode('inbox');
    renderAttachBox(m);
    $('read-from').textContent = m.sender_name;
    $('read-date').textContent = fmtDate(m.sent_at);
    $('read-subject').textContent = m.subject;
    $('read-body').textContent = m.message;
    $('read-body').parentElement.scrollTop = 0;
    const fromSystem = m.sender_citizenid === SYSTEM_SENDER;
    const anon = m.sender_citizenid === ANON_SENDER;
    $('btn-reply').classList.toggle('hidden', fromSystem || anon);
    $('btn-save-sender').classList.toggle('hidden', fromSystem || anon);
    $('btn-block').classList.toggle('hidden', fromSystem);
    if (!m.is_read) { m.is_read = 1; if (state.unreadTotal) state.unreadTotal -= 1; post('read', { id }); }
    showView('read');
}

/* ---------- compose ---------- */
function resetCompose() {
    state.recipient = null;
    resetAttach();
    setAnonymous(false);
    $('in-recipient').value = '';
    $('in-subject').value = '';
    $('in-message').value = '';
    $('search-results').classList.add('hidden');
    renderChosen();
    updateCounter();
}

function renderChosen() {
    const c = $('chosen');
    if (!state.recipient) { c.classList.add('hidden'); $('in-recipient').classList.remove('hidden'); syncAnonymous(); return; }
    c.innerHTML = `<span>${esc(state.recipient.name)} <small>${esc(state.recipient.job ? t('ui_office_tag') : idTag(state.recipient.citizenid))}</small></span><button id="clear-recipient">&#10005;</button>`;
    c.classList.remove('hidden');
    $('in-recipient').classList.add('hidden');
    $('clear-recipient').onclick = () => { state.recipient = null; $('in-recipient').value = ''; renderChosen(); saveDraftSoon(); $('in-recipient').focus(); };
    syncAttachPanel();
    syncAnonymous();
}

function updateCounter() {
    $('msg-counter').textContent = `${$('in-message').value.length}/${state.maxMessage}`;
    $('subj-counter').textContent = `${$('in-subject').value.length}/${state.maxSubject}`;
}

function contactLabel(c) { return c.nickname ? `${c.nickname} (${c.name})` : c.name; }

function pickRecipient(r) {
    state.recipient = r.job ? { job: r.job, name: r.label } : { citizenid: r.citizenid, name: contactLabel(r) };
    $('search-results').classList.add('hidden');
    renderChosen();
    saveDraftSoon();
}

function renderRecipientResults(query, remote) {
    const box = $('search-results');
    const q = query.toLowerCase();
    const book = state.contacts.filter(c => !q || contactLabel(c).toLowerCase().includes(q) || c.citizenid.toLowerCase().includes(q));
    const bookIds = new Set(book.map(c => c.citizenid));
    const others = (remote || []).filter(r => !bookIds.has(r.citizenid));
    const items = [];
    let html = '';
    const offices = (state.offices || []).filter(o => !q || o.label.toLowerCase().includes(q));
    if (offices.length) {
        html += `<div class="result-group">${esc(t('ui_offices'))}</div>`;
        offices.forEach(o => { items.push(o); html += `<div class="result" data-i="${items.length - 1}"><span>${esc(o.label)}</span><small>${esc(t('ui_office_tag'))}</small></div>`; });
    }
    if (book.length) {
        html += `<div class="result-group">${esc(t('ui_address_book'))}</div>`;
        book.forEach(c => { items.push(c); html += `<div class="result" data-i="${items.length - 1}"><span><span class="book">&#9733;</span>${esc(contactLabel(c))}</span><small>${esc(idTag(c.citizenid))}</small></div>`; });
    }
    if (others.length) {
        html += `<div class="result-group">${esc(t('ui_directory'))}</div>`;
        others.forEach(r => { items.push(r); html += `<div class="result" data-i="${items.length - 1}"><span>${esc(r.name)}</span><small>${esc(idTag(r.citizenid))}</small></div>`; });
    }
    if (!items.length) {
        if (!q) { box.classList.add('hidden'); return; }
        html = `<div class="result"><small>${esc(t('ui_no_results'))}</small></div>`;
    }
    box.innerHTML = html;
    box.querySelectorAll('.result[data-i]').forEach(el => el.addEventListener('click', () => pickRecipient(items[Number(el.dataset.i)])));
    box.classList.remove('hidden');
}

$('in-recipient').addEventListener('focus', (e) => {
    if (!e.target.value.trim()) renderRecipientResults('', []);
});

$('in-recipient').addEventListener('input', (e) => {
    clearTimeout(timers.recipient);
    const q = e.target.value.trim();
    renderRecipientResults(q, []);
    if (q.length < state.minSearch) return;
    timers.recipient = setTimeout(async () => {
        const results = await post('search', { query: q });
        if (results === false) return; // throttled
        if ($('in-recipient').value.trim() === q) renderRecipientResults(q, Array.isArray(results) ? results : []);
    }, 300);
});

document.addEventListener('mousedown', (e) => {
    if (!e.target.closest('.recipient-wrap')) {
        $('search-results').classList.add('hidden');
        $('contact-results').classList.add('hidden');
    }
});

/* ---------- attachments (compose) ---------- */
function resetAttach() {
    state.attachSel = {};
    state.attachables = null;
    $('in-cash').value = '';
    $('attach-body').classList.add('hidden');
    $('btn-attach-toggle').textContent = t('ui_attach_add');
    updateAttachSummary();
}

// the anonymous option is for telegrams to a person (not to an office)
function syncAnonymous() {
    const ok = state.anon.enabled && state.recipient && !state.recipient.job;
    $('anon-row').classList.toggle('hidden', !ok);
    if (!ok && state.anonymous) setAnonymous(false);
}

function setAnonymous(on) {
    state.anonymous = !!on;
    $('btn-anon').classList.toggle('active', state.anonymous);
    updateFee();
}

$('btn-anon').addEventListener('click', () => setAnonymous(!state.anonymous));

function syncAttachPanel() {
    const ok = state.attach.enabled && state.recipient && !state.recipient.job;
    $('attach-panel').classList.toggle('hidden', !ok);
    if (!ok && state.attach.enabled) {
        state.attachSel = {};
        $('in-cash').value = '';
        $('attach-body').classList.add('hidden');
        updateAttachSummary();
    }
}

function cashValue() {
    const v = parseFloat(($('in-cash').value || '').replace(',', '.'));
    return Number.isFinite(v) && v > 0 ? Math.round(v * 100) / 100 : 0;
}

function buildAttachment() {
    if (!state.attach.enabled || !state.recipient || state.recipient.job) return null;
    const att = {};
    const cash = cashValue();
    if (cash > 0) att.cash = cash;
    const items = Object.keys(state.attachSel).filter(n => state.attachSel[n] > 0).map(n => ({ name: n, amount: state.attachSel[n] }));
    if (items.length) att.items = items;
    return att.cash || att.items ? att : null;
}

function updateAttachSummary() {
    const att = buildAttachment();
    const kinds = Object.keys(state.attachSel).filter(n => state.attachSel[n] > 0).length;
    $('attach-items-count').textContent = kinds ? t('ui_items_count', kinds) : '';
    const parts = [];
    if (att && att.cash) parts.push(`${t('ui_attach_cash')}: ${money(att.cash)}`);
    (att && att.items || []).forEach(i => {
        const def = (state.attachables && state.attachables.items || []).find(x => x.name === i.name);
        parts.push(`${i.amount}x ${def ? def.label : i.name}`);
    });
    $('attach-summary').textContent = parts.join(' · ');
    updateFee();
}

function updateFee() {
    const total = state.cost + (buildAttachment() ? (state.attach.fee || 0) : 0) + (state.anonymous ? (state.anon.fee || 0) : 0);
    $('send-cost').textContent = total > 0 ? money(total) : t('ui_free');
}

function renderAttachItems() {
    const box = $('attach-items');
    const data = state.attachables;
    if (!data || !data.items.length) { box.innerHTML = `<div class="empty">${esc(t('ui_attach_none_items'))}</div>`; return; }
    const kinds = Object.keys(state.attachSel).filter(n => state.attachSel[n] > 0).length;
    box.innerHTML = data.items.map((it, i) => {
        const n = state.attachSel[it.name] || 0;
        const cap = Math.min(state.attach.maxItemAmount || it.amount, it.amount);
        const canAdd = n < cap && (n > 0 || kinds < (state.attach.maxItems || 1));
        return `<div class="attach-item" data-i="${i}">
            <span>${esc(it.label)}<small>${esc(t('ui_have', it.amount))}</small></span>
            <span class="stepper"><button data-d="-1" ${n <= 0 ? 'disabled' : ''}>&minus;</button><span>${n}</span><button data-d="1" ${canAdd ? '' : 'disabled'}>+</button></span>
        </div>`;
    }).join('');
    box.querySelectorAll('.attach-item').forEach(row => {
        const it = data.items[Number(row.dataset.i)];
        row.querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
            const cap = Math.min(state.attach.maxItemAmount || it.amount, it.amount);
            const n = Math.min(cap, Math.max(0, (state.attachSel[it.name] || 0) + Number(b.dataset.d)));
            if (n > 0) state.attachSel[it.name] = n; else delete state.attachSel[it.name];
            renderAttachItems();
            updateAttachSummary();
        }));
    });
}

$('btn-attach-toggle').addEventListener('click', async () => {
    const body = $('attach-body');
    const open = body.classList.contains('hidden');
    body.classList.toggle('hidden', !open);
    if (!open) return;
    $('attach-hint').textContent = t('ui_attach_hint') + ' ' + t('ui_attach_limits', money(state.attach.maxCash), state.attach.maxItems, state.attach.maxItemAmount);
    if (!state.attachables) {
        const data = await post('getAttachables');
        if (data && Array.isArray(data.items)) state.attachables = data; else if (data === false) { body.classList.add('hidden'); return; }
    }
    if (state.attachables) $('attach-hint').textContent += ' ' + t('ui_have', money(state.attachables.cash));
    renderAttachItems();
});

$('in-cash').addEventListener('input', (e) => {
    let v = e.target.value.replace(',', '.').replace(/[^0-9.]/g, '');
    const dot = v.indexOf('.');
    if (dot >= 0) v = v.slice(0, dot + 1) + v.slice(dot + 1).replace(/\./g, '').slice(0, 2);
    let n = parseFloat(v);
    const cap = Math.min(state.attach.maxCash || Infinity, state.attachables ? state.attachables.cash : Infinity);
    if (Number.isFinite(n) && n > cap) v = String(cap);
    e.target.value = v;
    updateAttachSummary();
});

/* ---------- draft autosave ---------- */
let draftTimer = null;
function saveDraft() {
    const subject = $('in-subject').value, message = $('in-message').value;
    if (!draftOwner) return;
    try {
        if (!subject.trim() && !message.trim()) { localStorage.removeItem(DRAFT_KEY); return; }
        localStorage.setItem(DRAFT_KEY, JSON.stringify({ owner: draftOwner, subject, message, recipient: state.recipient || null }));
    } catch (e) {}
}
function saveDraftSoon() { clearTimeout(draftTimer); draftTimer = setTimeout(saveDraft, 400); }
function clearDraft() { clearTimeout(draftTimer); try { localStorage.removeItem(DRAFT_KEY); } catch (e) {} }
function loadDraft() {
    let d = null;
    try { d = JSON.parse(localStorage.getItem(DRAFT_KEY)); } catch (e) {}
    if (!d || typeof d !== 'object' || !draftOwner || d.owner !== draftOwner) return; // never show another character's draft
    $('in-subject').value = String(d.subject || '').slice(0, state.maxSubject);
    $('in-message').value = String(d.message || '').slice(0, state.maxMessage);
    const r = d.recipient;
    if (r && typeof r === 'object' && (r.job || r.citizenid) && typeof r.name === 'string') {
        // a draft addressed to an office is only restored while that office still exists
        if (!r.job || (state.offices || []).some(o => o.job === r.job)) { state.recipient = r; renderChosen(); }
    }
    updateCounter();
}

/* ---------- address book ---------- */
async function loadContacts() {
    const data = await post('getContacts');
    if (data === false) return; // throttled, keep what is shown
    state.contacts = Array.isArray(data) ? data : [];
    renderContacts();
}

function renderContacts() {
    const list = $('contact-list');
    $('contact-count').textContent = state.contacts.length ? `(${state.contacts.length})` : '';
    if (!state.contacts.length) {
        list.innerHTML = `<div class="empty">${esc(t('ui_book_empty'))}</div>`;
        return;
    }
    list.innerHTML = state.contacts.map((c, i) => `
        <div class="row" data-i="${i}">
            <div class="badge-icon">&#9733;</div>
            <div class="row-main">
                <div class="row-title">${esc(c.nickname || c.name)}</div>
                <div class="row-sub">${c.nickname ? esc(c.name) + (state.showIds ? ' &middot; ' : '') : ''}${esc(idTag(c.citizenid))}</div>
            </div>
            <div class="row-actions">
                <button class="wood-btn mini-btn" data-act="write">${esc(t('ui_write_short'))}</button>
                <button class="wood-btn muted mini-btn" data-act="remove">&#10005;</button>
            </div>
        </div>`).join('');
    list.querySelectorAll('.row').forEach(row => {
        const c = state.contacts[Number(row.dataset.i)];
        row.querySelector('[data-act="write"]').addEventListener('click', (e) => {
            e.stopPropagation();
            resetCompose();
            pickRecipient(c);
            showView('compose');
            $('in-subject').focus();
        });
        row.querySelector('[data-act="remove"]').addEventListener('click', async (e) => {
            e.stopPropagation();
            const btn = e.currentTarget;
            btn.disabled = true;
            const ok = await post('removeContact', { citizenid: c.citizenid });
            if (!ok) { btn.disabled = false; return; }
            state.contacts = state.contacts.filter(x => x.citizenid !== c.citizenid);
            renderContacts();
        });
    });
}

function setPendingContact(r) {
    state.pendingContact = r;
    $('contact-results').classList.add('hidden');
    if (!r) {
        $('add-contact').classList.add('hidden');
        $('in-contact-search').classList.remove('hidden');
        return;
    }
    $('contact-chosen').innerHTML = `<span>${esc(r.name)} <small>${esc(idTag(r.citizenid))}</small></span><button id="clear-contact">&#10005;</button>`;
    $('clear-contact').onclick = () => { setPendingContact(null); $('in-contact-search').value = ''; };
    $('in-nickname').value = '';
    $('add-contact').classList.remove('hidden');
    $('in-contact-search').classList.add('hidden');
    $('in-nickname').focus();
}

$('in-contact-search').addEventListener('input', (e) => {
    clearTimeout(timers.contact);
    const q = e.target.value.trim();
    const box = $('contact-results');
    if (q.length < state.minSearch) { box.classList.add('hidden'); return; }
    timers.contact = setTimeout(async () => {
        const results = await post('search', { query: q });
        if (results === false || $('in-contact-search').value.trim() !== q) return;
        const list = Array.isArray(results) ? results : [];
        box.innerHTML = list.length
            ? list.map((r, i) => `<div class="result" data-i="${i}"><span>${esc(r.name)}</span><small>${esc(idTag(r.citizenid))}</small></div>`).join('')
            : `<div class="result"><small>${esc(t('ui_no_results'))}</small></div>`;
        box.querySelectorAll('.result[data-i]').forEach(el => el.addEventListener('click', () => setPendingContact(list[Number(el.dataset.i)])));
        box.classList.remove('hidden');
    }, 300);
});

$('btn-add-contact').addEventListener('click', async () => {
    const r = state.pendingContact;
    const btn = $('btn-add-contact');
    if (!r || btn.disabled) return;
    btn.disabled = true;
    const ok = await post('addContact', { citizenid: r.citizenid, nickname: $('in-nickname').value.trim() || null });
    btn.disabled = false;
    if (ok) {
        setPendingContact(null);
        $('in-contact-search').value = '';
        await loadContacts();
    }
});

function renderListed() {
    const btn = $('btn-listed');
    btn.classList.toggle('hidden', !state.directory);
    btn.textContent = t(state.unlisted ? 'ui_dir_unlisted' : 'ui_dir_listed');
}

$('btn-listed').addEventListener('click', async () => {
    const btn = $('btn-listed');
    btn.disabled = true;
    const res = await post('toggleListed');
    btn.disabled = false;
    if (res && typeof res === 'object') { state.unlisted = !!res.unlisted; renderListed(); }
});

$('btn-contacts').addEventListener('click', async () => {
    setPendingContact(null);
    $('in-contact-search').value = '';
    showView('contacts');
    renderListed();
    const settings = state.directory ? await post('getSettings') : null;
    if (settings && typeof settings === 'object') { state.unlisted = !!settings.unlisted; renderListed(); }
    await loadContacts();
});

$('btn-save-sender').addEventListener('click', async () => {
    const m = state.current;
    if (!m) return;
    if (state.contacts.some(c => c.citizenid === m.sender_citizenid)) return toast(t('ui_already_saved'), 'info');
    const ok = await post('addContact', { citizenid: m.sender_citizenid });
    if (ok) await loadContacts();
});

$('in-message').addEventListener('input', () => { updateCounter(); saveDraftSoon(); });
$('in-message').addEventListener('keydown', (e) => { if (e.ctrlKey && e.key === 'Enter') $('btn-send').click(); });
$('in-subject').addEventListener('input', () => { updateCounter(); saveDraftSoon(); });

$('btn-send').addEventListener('click', async () => {
    if (state.busy) return;
    const subject = $('in-subject').value.trim();
    const message = $('in-message').value.trim();
    if (!state.recipient) return toast(t('ui_need_recipient'), 'error');
    if (!subject) return toast(t('ui_need_subject'), 'error');
    if (!message) return toast(t('ui_need_message'), 'error');

    const btn = $('btn-send');
    state.busy = true;
    btn.disabled = true;
    btn.textContent = t('ui_sending');
    const ok = await post('send', {
        citizenid: state.recipient.citizenid, job: state.recipient.job, subject, message, attachment: buildAttachment(), anonymous: state.anonymous,
    });
    state.busy = false;
    btn.disabled = false;
    btn.textContent = t('ui_send');
    if (ok) {
        clearDraft();
        resetCompose();
        showView('inbox');
        setTab(state.tab);
    }
});

/* ---------- buttons ---------- */
$('btn-compose').addEventListener('click', () => { resetCompose(); loadDraft(); showView('compose'); });
$('btn-back').addEventListener('click', () => {
    if (state.view === 'blocked') return showView('contacts');
    showView('inbox');
    renderList();
});
$('in-inbox-search').addEventListener('input', (e) => {
    clearTimeout(timers.inbox);
    timers.inbox = setTimeout(() => { state.inboxQuery = e.target.value.trim(); refreshInbox(false); }, 350);
});
$('tab-inbox').addEventListener('click', () => { if (state.tab !== 'inbox') setTab('inbox'); });
$('tab-sent').addEventListener('click', () => { if (state.tab !== 'sent') setTab('sent'); });

/* ---------- bulk actions ---------- */
$('btn-mark-all').addEventListener('click', async () => {
    const btn = $('btn-mark-all');
    if (btn.disabled || !state.inbox.some(m => !m.is_read)) return;
    btn.disabled = true;
    const ok = await post('markAllRead');
    btn.disabled = false;
    if (!ok) return;
    state.inbox.forEach(m => { m.is_read = 1; });
    renderInbox();
});

$('btn-destroy-read').addEventListener('click', () => {
    if (!state.inbox.some(m => m.is_read && !m.attachment)) return toast(t('ui_nothing_read'), 'info');
    askConfirm('ui_confirm_read_title', 'ui_confirm_read_text', 'ui_destroy', async () => {
        const ok = await post('deleteRead');
        if (!ok) return;
        // telegrams that still hold an attachment are kept by the server
        state.inbox = state.inbox.filter(m => !m.is_read || m.attachment);
        renderInbox();
    });
});

/* ---------- attachment collect ---------- */
$('btn-collect').addEventListener('click', async () => {
    const m = state.current, btn = $('btn-collect');
    if (!m || state.readMode !== 'inbox' || btn.disabled) return;
    btn.disabled = true;
    const res = await post('collect', { id: m.id });
    if (res && res.ok) {
        m.attachment = res.attachment || null; // anything that did not fit stays on the telegram
        renderAttachBox(m);
    } else {
        btn.disabled = false;
    }
});

/* ---------- blocked senders ---------- */
function renderBlocked() {
    const list = $('blocked-list');
    $('blocked-count').textContent = state.blocked.length ? `(${state.blocked.length})` : '';
    if (!state.blocked.length) { list.innerHTML = `<div class="empty">${esc(t('ui_blocked_empty'))}</div>`; return; }
    list.innerHTML = state.blocked.map((b, i) => `
        <div class="row" data-i="${i}">
            <div class="badge-icon">&#10006;</div>
            <div class="row-main">
                <div class="row-title">${esc(b.name || b.citizenid)}</div>
                <div class="row-sub">${esc(idTag(b.citizenid))}</div>
            </div>
            <div class="row-actions"><button class="wood-btn muted mini-btn">${esc(t('ui_unblock'))}</button></div>
        </div>`).join('');
    list.querySelectorAll('.row').forEach(row => {
        const b = state.blocked[Number(row.dataset.i)];
        row.querySelector('button').addEventListener('click', async (e) => {
            const btn = e.currentTarget;
            btn.disabled = true;
            const ok = await post('unblock', b.citizenid ? { citizenid: b.citizenid } : { id: b.id });
            if (!ok) { btn.disabled = false; return; }
            state.blocked = state.blocked.filter(x => x.id !== b.id);
            renderBlocked();
        });
    });
}

async function loadBlocked() {
    const data = await post('getBlocked');
    if (data === false) return;
    state.blocked = Array.isArray(data) ? data : [];
    renderBlocked();
}

$('btn-blocked').addEventListener('click', async () => { showView('blocked'); renderBlocked(); await loadBlocked(); });

$('btn-block').addEventListener('click', () => {
    const m = state.current;
    if (!m || state.readMode !== 'inbox' || m.sender_citizenid === SYSTEM_SENDER) return;
    askConfirm('ui_confirm_block_title', 'ui_confirm_block_text', 'ui_block', async () => {
        // an anonymous sender is blocked through the telegram, the client never learns who it is
        const ok = await post('block', m.sender_citizenid === ANON_SENDER ? { id: m.id } : { citizenid: m.sender_citizenid });
        if (ok) loadBlocked();
    }, m.sender_name);
});
$('btn-close').addEventListener('click', () => post('close'));

$('btn-reply').addEventListener('click', () => {
    const m = state.current;
    if (!m) return;
    resetCompose();
    state.recipient = { citizenid: m.sender_citizenid, name: m.sender_name };
    renderChosen();
    const prefix = t('ui_reply_prefix');
    const subj = m.subject.startsWith(prefix) ? m.subject : prefix + m.subject;
    $('in-subject').value = subj.substring(0, state.maxSubject);
    updateCounter();
    showView('compose');
    $('in-message').focus();
});

async function deleteCurrent() {
    if (!state.current || state.readMode !== 'inbox') return;
    const id = state.current.id;
    const ok = await post('delete', { id });
    if (ok) {
        state.inbox = state.inbox.filter(m => m.id !== id);
        state.current = null;
        renderInbox();
        showView('inbox');
    }
}

$('btn-delete').addEventListener('click', () => askConfirm('ui_confirm_title', 'ui_confirm_text', 'ui_destroy', deleteCurrent));
$('modal-no').addEventListener('click', () => { state.modalAction = null; $('modal').classList.add('hidden'); });
$('modal-yes').addEventListener('click', async () => {
    const action = state.modalAction;
    state.modalAction = null;
    $('modal').classList.add('hidden');
    if (action) await action();
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('app').classList.contains('hidden')) return;
    if (!$('modal').classList.contains('hidden')) { state.modalAction = null; return $('modal').classList.add('hidden'); }
    const openResults = document.querySelector('.results:not(.hidden)');
    if (openResults) return openResults.classList.add('hidden');
    post('close');
});

/* ---------- unread badge (outside the panel, hidden while the panel is open) ---------- */
function updateBadge() {
    const n = state.unreadTotal || 0;
    $('mail-count').textContent = n;
    $('mail-badge').classList.toggle('hidden', n < 1 || state.appOpen);
}

/* ---------- lua messages ---------- */
window.addEventListener('message', (e) => {
    const d = e.data;
    if (d.action === 'open') {
        if (d.locales) { L = d.locales; applyLocales(); applyTextSize(); }
        draftOwner = typeof d.owner === 'string' ? d.owner : null;
        state.inbox = Array.isArray(d.inbox) ? d.inbox : [];
        state.cost = d.cost || 0;
        state.maxSubject = d.maxSubject || 50;
        state.maxMessage = d.maxMessage || 1000;
        state.minSearch = d.minSearch || 2;
        state.offices = Array.isArray(d.offices) ? d.offices : [];
        state.attach = d.attachments && d.attachments.enabled ? d.attachments : { enabled: false };
        state.receipts = d.receipts !== false;
        state.anon = d.anonymous && d.anonymous.enabled ? d.anonymous : { enabled: false, fee: 0 };
        state.pageSize = d.pageSize || 25;
        state.showIds = d.showIds !== false;
        state.directory = d.directory === true;
        state.inboxQuery = '';
        $('in-inbox-search').value = '';
        state.inboxMore = state.inbox.length >= state.pageSize;
        state.appOpen = true;
        updateBadge();
        state.tab = 'inbox';
        state.sent = [];
        state.current = null;
        $('tab-inbox').classList.add('active');
        $('tab-sent').classList.remove('active');
        $('bulk-bar').classList.remove('hidden');
        $('search-row').classList.remove('hidden');
        setAnonymous(false);
        resetAttach();
        syncAttachPanel();
        $('office-name').textContent = d.office || t('ui_post_office');
        updateFee();
        $('in-subject').maxLength = state.maxSubject;
        $('in-message').maxLength = state.maxMessage;
        $('modal').classList.add('hidden');
        showView('inbox');
        renderInbox();
        $('app').classList.remove('hidden');
        loadContacts();
    } else if (d.action === 'badge') {
        state.unreadTotal = Number(d.count) || 0;
        const el = $('mail-badge');
        el.classList.remove('top-right', 'top-left', 'bottom-right', 'bottom-left');
        el.classList.add(['top-left', 'bottom-right', 'bottom-left'].includes(d.corner) ? d.corner : 'top-right');
        updateBadge();
        if (state.appOpen && state.tab === 'inbox' && state.view === 'inbox') renderInbox();
    } else if (d.action === 'close') {
        state.appOpen = false;
        updateBadge();
        saveDraft();
        $('app').classList.add('hidden');
        state.modalAction = null;
        $('modal').classList.add('hidden');
        document.querySelectorAll('.results').forEach(r => r.classList.add('hidden'));
    }
});

/* ---------- message text size ---------- */
const SIZE_KEY = 'rsg-telegram:textsize';
const SIZE_MIN = 11, SIZE_MAX = 26, SIZE_DEFAULT = 14;
let msgSize = SIZE_DEFAULT;

function applyTextSize() {
    document.documentElement.style.setProperty('--msg-size', msgSize + 'px');
    $('size-val').textContent = msgSize;
    document.querySelectorAll('.size-btn').forEach(b => {
        const step = Number(b.dataset.size);
        b.disabled = (step < 0 && msgSize <= SIZE_MIN) || (step > 0 && msgSize >= SIZE_MAX);
    });
}

try {
    const saved = Number(localStorage.getItem(SIZE_KEY));
    if (saved >= SIZE_MIN && saved <= SIZE_MAX) msgSize = saved;
} catch (e) {}
applyTextSize();

document.querySelectorAll('.size-btn').forEach(b => b.addEventListener('click', () => {
    msgSize = Math.min(SIZE_MAX, Math.max(SIZE_MIN, msgSize + Number(b.dataset.size)));
    applyTextSize();
    try { localStorage.setItem(SIZE_KEY, String(msgSize)); } catch (e) {}
}));
