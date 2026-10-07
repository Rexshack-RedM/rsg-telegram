const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg-telegram';
const $ = (id) => document.getElementById(id);

const state = { contacts: [], pendingContact: null, inbox: [], current: null, recipient: null, cost: 0, maxSubject: 50, maxMessage: 1000, minSearch: 2, busy: false };
const timers = { recipient: null, contact: null };
let L = {};

/* ---------- locales ---------- */
function t(key, ...args) {
    let str = L[key] ?? key;
    args.forEach(a => { str = str.replace('%s', a); });
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
    return d.toLocaleDateString(t('ui_date_locale'), { day: '2-digit', month: 'short' }) + ' ' +
           d.toLocaleTimeString(t('ui_date_locale'), { hour: '2-digit', minute: '2-digit' });
}

function toast(msg, type = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<div class="t-label">${esc(t('ui_toast_' + type))}</div>${esc(msg)}`;
    $('toasts').appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3000);
}

function showView(name) {
    ['inbox', 'read', 'compose', 'contacts'].forEach(v => $(`view-${v}`).classList.toggle('hidden', v !== name));
    $('btn-back').classList.toggle('hidden', name === 'inbox');
}

/* ---------- inbox ---------- */
function renderInbox() {
    const list = $('inbox-list');
    const unread = state.inbox.filter(m => !m.is_read).length;
    $('unread-count').textContent = unread ? t('ui_new_count', unread) : '';
    if (!state.inbox.length) {
        list.innerHTML = `<div class="empty">${esc(t('ui_no_telegrams'))}</div>`;
        return;
    }
    list.innerHTML = state.inbox.map(m => `
        <div class="row ${m.is_read ? 'read' : ''}" data-id="${m.id}">
            <div class="badge-icon">&#9993;</div>
            <div class="row-main">
                <div class="row-title">${esc(m.subject)}</div>
                <div class="row-sub">${esc(t('ui_from_line', m.sender_name))} &middot; ${fmtDate(m.sent_at)}</div>
            </div>
            ${m.is_read ? '' : `<span class="pill">${esc(t('ui_new'))}</span>`}
        </div>`).join('');
    list.querySelectorAll('.row').forEach(r => r.addEventListener('click', () => openTelegram(Number(r.dataset.id))));
}

async function refreshInbox() {
    const data = await post('refresh');
    state.inbox = Array.isArray(data) ? data : [];
    renderInbox();
}

/* ---------- read ---------- */
function openTelegram(id) {
    const m = state.inbox.find(x => x.id === id);
    if (!m) return;
    state.current = m;
    $('read-from').textContent = m.sender_name;
    $('read-date').textContent = fmtDate(m.sent_at);
    $('read-subject').textContent = m.subject;
    $('read-body').textContent = m.message;
    $('read-body').parentElement.scrollTop = 0;
    if (!m.is_read) { m.is_read = 1; post('read', { id }); }
    showView('read');
}

/* ---------- compose ---------- */
function resetCompose() {
    state.recipient = null;
    $('in-recipient').value = '';
    $('in-subject').value = '';
    $('in-message').value = '';
    $('search-results').classList.add('hidden');
    renderChosen();
    updateCounter();
}

function renderChosen() {
    const c = $('chosen');
    if (!state.recipient) { c.classList.add('hidden'); $('in-recipient').classList.remove('hidden'); return; }
    c.innerHTML = `<span>${esc(state.recipient.name)} <small>${esc(state.recipient.citizenid)}</small></span><button id="clear-recipient">&#10005;</button>`;
    c.classList.remove('hidden');
    $('in-recipient').classList.add('hidden');
    $('clear-recipient').onclick = () => { state.recipient = null; $('in-recipient').value = ''; renderChosen(); $('in-recipient').focus(); };
}

function updateCounter() {
    $('msg-counter').textContent = `${$('in-message').value.length}/${state.maxMessage}`;
    $('subj-counter').textContent = `${$('in-subject').value.length}/${state.maxSubject}`;
}

function contactLabel(c) { return c.nickname ? `${c.nickname} (${c.name})` : c.name; }

function pickRecipient(r) {
    state.recipient = { citizenid: r.citizenid, name: contactLabel(r) };
    $('search-results').classList.add('hidden');
    renderChosen();
}

function renderRecipientResults(query, remote) {
    const box = $('search-results');
    const q = query.toLowerCase();
    const book = state.contacts.filter(c => !q || contactLabel(c).toLowerCase().includes(q) || c.citizenid.toLowerCase().includes(q));
    const bookIds = new Set(book.map(c => c.citizenid));
    const others = (remote || []).filter(r => !bookIds.has(r.citizenid));
    const items = [];
    let html = '';
    if (book.length) {
        html += `<div class="result-group">${esc(t('ui_address_book'))}</div>`;
        book.forEach(c => { items.push(c); html += `<div class="result" data-i="${items.length - 1}"><span><span class="book">&#9733;</span>${esc(contactLabel(c))}</span><small>${esc(c.citizenid)}</small></div>`; });
    }
    if (others.length) {
        html += `<div class="result-group">${esc(t('ui_directory'))}</div>`;
        others.forEach(r => { items.push(r); html += `<div class="result" data-i="${items.length - 1}"><span>${esc(r.name)}</span><small>${esc(r.citizenid)}</small></div>`; });
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
        if ($('in-recipient').value.trim() === q) renderRecipientResults(q, Array.isArray(results) ? results : []);
    }, 300);
});

document.addEventListener('mousedown', (e) => {
    if (!e.target.closest('.recipient-wrap')) {
        $('search-results').classList.add('hidden');
        $('contact-results').classList.add('hidden');
    }
});

/* ---------- address book ---------- */
async function loadContacts() {
    const data = await post('getContacts');
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
                <div class="row-sub">${c.nickname ? esc(c.name) + ' &middot; ' : ''}${esc(c.citizenid)}</div>
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
            const ok = await post('removeContact', { citizenid: c.citizenid });
            if (ok) { state.contacts = state.contacts.filter(x => x.citizenid !== c.citizenid); renderContacts(); }
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
    $('contact-chosen').innerHTML = `<span>${esc(r.name)} <small>${esc(r.citizenid)}</small></span><button id="clear-contact">&#10005;</button>`;
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
        if ($('in-contact-search').value.trim() !== q) return;
        const list = Array.isArray(results) ? results : [];
        box.innerHTML = list.length
            ? list.map((r, i) => `<div class="result" data-i="${i}"><span>${esc(r.name)}</span><small>${esc(r.citizenid)}</small></div>`).join('')
            : `<div class="result"><small>${esc(t('ui_no_results'))}</small></div>`;
        box.querySelectorAll('.result[data-i]').forEach(el => el.addEventListener('click', () => setPendingContact(list[Number(el.dataset.i)])));
        box.classList.remove('hidden');
    }, 300);
});

$('btn-add-contact').addEventListener('click', async () => {
    const r = state.pendingContact;
    if (!r) return;
    const ok = await post('addContact', { citizenid: r.citizenid, nickname: $('in-nickname').value.trim() || null });
    if (ok) {
        setPendingContact(null);
        $('in-contact-search').value = '';
        await loadContacts();
    }
});

$('btn-contacts').addEventListener('click', async () => {
    setPendingContact(null);
    $('in-contact-search').value = '';
    showView('contacts');
    await loadContacts();
});

$('btn-save-sender').addEventListener('click', async () => {
    const m = state.current;
    if (!m) return;
    if (state.contacts.some(c => c.citizenid === m.sender_citizenid)) return toast(t('ui_already_saved'), 'info');
    const ok = await post('addContact', { citizenid: m.sender_citizenid });
    if (ok) await loadContacts();
});

$('in-message').addEventListener('input', updateCounter);
$('in-subject').addEventListener('input', updateCounter);

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
    const ok = await post('send', { citizenid: state.recipient.citizenid, subject, message });
    state.busy = false;
    btn.disabled = false;
    btn.textContent = t('ui_send');
    if (ok) {
        resetCompose();
        showView('inbox');
        refreshInbox();
    }
});

/* ---------- buttons ---------- */
$('btn-compose').addEventListener('click', () => { resetCompose(); showView('compose'); });
$('btn-back').addEventListener('click', () => { showView('inbox'); renderInbox(); });
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

$('btn-delete').addEventListener('click', () => $('modal').classList.remove('hidden'));
$('modal-no').addEventListener('click', () => $('modal').classList.add('hidden'));
$('modal-yes').addEventListener('click', async () => {
    $('modal').classList.add('hidden');
    if (!state.current) return;
    const id = state.current.id;
    const ok = await post('delete', { id });
    if (ok) {
        state.inbox = state.inbox.filter(m => m.id !== id);
        state.current = null;
        renderInbox();
        showView('inbox');
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('app').classList.contains('hidden')) return;
    if (!$('modal').classList.contains('hidden')) return $('modal').classList.add('hidden');
    const openResults = document.querySelector('.results:not(.hidden)');
    if (openResults) return openResults.classList.add('hidden');
    post('close');
});

/* ---------- lua messages ---------- */
window.addEventListener('message', (e) => {
    const d = e.data;
    if (d.action === 'open') {
        if (d.locales) { L = d.locales; applyLocales(); applyTextSize(); }
        state.inbox = Array.isArray(d.inbox) ? d.inbox : [];
        state.cost = d.cost || 0;
        state.maxSubject = d.maxSubject || 50;
        state.maxMessage = d.maxMessage || 1000;
        state.minSearch = d.minSearch || 2;
        $('office-name').textContent = d.office || t('ui_post_office');
        $('send-cost').textContent = state.cost > 0 ? `$${Number(state.cost).toFixed(2)}` : t('ui_free');
        $('in-subject').maxLength = state.maxSubject;
        $('in-message').maxLength = state.maxMessage;
        $('modal').classList.add('hidden');
        showView('inbox');
        renderInbox();
        $('app').classList.remove('hidden');
        loadLayout();
        loadContacts();
    } else if (d.action === 'close') {
        $('app').classList.add('hidden');
        $('modal').classList.add('hidden');
        document.querySelectorAll('.results').forEach(r => r.classList.add('hidden'));
    }
});

/* ---------- move & resize ---------- */
const LAYOUT_KEY = 'rsg-telegram:layout';
const panel = $('panel');

function clampLayout() {
    const r = panel.getBoundingClientRect();
    const maxX = window.innerWidth - r.width, maxY = window.innerHeight - r.height;
    panel.style.left = Math.min(Math.max(0, r.left), Math.max(0, maxX)) + 'px';
    panel.style.top  = Math.min(Math.max(0, r.top),  Math.max(0, maxY)) + 'px';
}

function saveLayout() {
    try {
        localStorage.setItem(LAYOUT_KEY, JSON.stringify({
            left: panel.offsetLeft, top: panel.offsetTop, width: panel.offsetWidth, height: panel.offsetHeight,
        }));
    } catch (e) {}
}

function centerPanel() {
    panel.style.left = Math.round((window.innerWidth - panel.offsetWidth) / 2) + 'px';
    panel.style.top  = Math.round((window.innerHeight - panel.offsetHeight) / 2) + 'px';
}

function loadLayout() {
    let l = null;
    try { l = JSON.parse(localStorage.getItem(LAYOUT_KEY)); } catch (e) {}
    if (l && l.width && l.height) {
        panel.style.width = l.width + 'px';
        panel.style.height = l.height + 'px';
        panel.style.left = l.left + 'px';
        panel.style.top = l.top + 'px';
        clampLayout();
    } else {
        centerPanel();
    }
}

function resetLayout() {
    panel.style.width = '';
    panel.style.height = '';
    centerPanel();
    try { localStorage.removeItem(LAYOUT_KEY); } catch (e) {}
}

// drag by the header (ignoring its buttons)
document.querySelector('.header').addEventListener('mousedown', (e) => {
    if (e.button !== 0 || e.target.closest('button')) return;
    e.preventDefault();
    const startX = e.clientX, startY = e.clientY, startL = panel.offsetLeft, startT = panel.offsetTop;
    document.body.classList.add('dragging');
    const move = (ev) => {
        panel.style.left = (startL + ev.clientX - startX) + 'px';
        panel.style.top  = (startT + ev.clientY - startY) + 'px';
        clampLayout();
    };
    const up = () => {
        document.removeEventListener('mousemove', move);
        document.removeEventListener('mouseup', up);
        document.body.classList.remove('dragging');
        saveLayout();
    };
    document.addEventListener('mousemove', move);
    document.addEventListener('mouseup', up);
});

// double-click header to reset size & position
document.querySelector('.header').addEventListener('dblclick', (e) => {
    if (!e.target.closest('button')) { resetLayout(); }
});

// resize from bottom-right corner
$('resize-handle').addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    const startX = e.clientX, startY = e.clientY, startW = panel.offsetWidth, startH = panel.offsetHeight;
    document.body.classList.add('resizing');
    const move = (ev) => {
        const maxW = window.innerWidth - panel.offsetLeft, maxH = window.innerHeight - panel.offsetTop;
        panel.style.width  = Math.min(maxW, Math.max(360, startW + ev.clientX - startX)) + 'px';
        panel.style.height = Math.min(maxH, Math.max(380, startH + ev.clientY - startY)) + 'px';
    };
    const up = () => {
        document.removeEventListener('mousemove', move);
        document.removeEventListener('mouseup', up);
        document.body.classList.remove('resizing');
        saveLayout();
    };
    document.addEventListener('mousemove', move);
    document.addEventListener('mouseup', up);
});

window.addEventListener('resize', () => { if (!$('app').classList.contains('hidden')) clampLayout(); });

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
