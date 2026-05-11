// RSG Telegram - Custom UI Script
let currentTab = 'inbox';
let currentMessageId = null;
let currentMessageMailbox = 'personal';
let currentViewedMessage = null;
let messages = [];
let contacts = [];
let players = [];
let jobSenders = [];
let enableJobMailboxes = true;
let pendingReplyDefaults = null;
let personalSenderDisplay = 'name';
let jobAliases = {};
let jobSendersLoaded = false;
let recipientChoices = [];
let uiLocales = {};

function t(key, replacements = {}) {
    let value = uiLocales[key] || key;

    Object.keys(replacements).forEach(name => {
        value = value.replace(new RegExp(`{${name}}`, 'g'), replacements[name]);
    });

    return value;
}

function applyLocales() {
    $('[data-i18n]').each(function() {
        $(this).text(t($(this).data('i18n')));
    });

    $('[data-i18n-placeholder]').each(function() {
        $(this).attr('placeholder', t($(this).data('i18n-placeholder')));
    });

    $('[data-i18n-title]').each(function() {
        $(this).attr('title', t($(this).data('i18n-title')));
    });

    const pageTitle = $('[data-i18n="ui_page_title"]').first().text();
    if (pageTitle) {
        document.title = pageTitle;
    }
}

// Open/Close UI
function openTelegramUI(defaultTab, jobEnabled, senderDisplay, configuredJobAliases, labels) {
    enableJobMailboxes = jobEnabled !== false;
    personalSenderDisplay = senderDisplay === 'citizenid' ? 'citizenid' : 'name';
    jobAliases = configuredJobAliases || {};
    uiLocales = labels || {};
    applyLocales();

    // Hide the job tab when the server config disables job mailboxes.
    $('.telegram-tab[data-tab="job-inbox"]').toggle(enableJobMailboxes);

    if (!enableJobMailboxes && defaultTab === 'job-inbox') {
        defaultTab = 'inbox';
    }

    $('#telegramContainer').fadeIn(300).css('display', 'block');
    $('#telegramContainer').addClass('opening');
    setTimeout(() => {
        $('#telegramContainer').removeClass('opening');
    }, 300);
    
    // Switch to default tab if specified, otherwise inbox
    if (defaultTab && (defaultTab === 'inbox' || (enableJobMailboxes && defaultTab === 'job-inbox') || defaultTab === 'new-message' || defaultTab === 'addressbook')) {
        switchTab(defaultTab);
    } else {
        switchTab('inbox');
    }
}

function closeTelegramUI() {
    $('#telegramContainer').addClass('closing');
    setTimeout(() => {
        $('#telegramContainer').fadeOut(300).css('display', 'none');
        $('#telegramContainer').removeClass('closing');
        $.post('https://rsg-telegram/closeUI', JSON.stringify({}));
    }, 300);
}

// Tab Switching
function switchTab(tabName) {
    currentTab = tabName;
    $('#telegramContainer').toggleClass('compose-mode', tabName === 'new-message');
    
    // Update tab buttons
    $('.telegram-tab').removeClass('active');
    $(`.telegram-tab[data-tab="${tabName}"]`).addClass('active');
    
    // Update tab panels
    $('.tab-panel').removeClass('active');
    $(`#${tabName}`).addClass('active');
    
    // Load data for the tab
    if (tabName === 'inbox') {
        loadInbox();
    } else if (enableJobMailboxes && tabName === 'job-inbox') {
        loadJobInbox();
    } else if (tabName === 'addressbook') {
        loadAddressbook();
    } else if (tabName === 'new-message') {
        loadRecipients();
    }
}

// Load Inbox
function loadInbox() {
    $.post('https://rsg-telegram/getAddressbook', JSON.stringify({}), function(contactList) {
        contacts = contactList || [];
        $.post('https://rsg-telegram/getInbox', JSON.stringify({}), function(messageList) {
            displayMessages(messageList, 'personal');
        });
    });
}

// Job inbox uses the same message renderer but writes to a separate list and badge.
function loadJobInbox() {
    $.post('https://rsg-telegram/getAddressbook', JSON.stringify({}), function(contactList) {
        contacts = contactList || [];
        $.post('https://rsg-telegram/getJobInbox', JSON.stringify({}), function(messageList) {
            displayMessages(messageList, 'job');
        });
    });
}

function displayMessages(messageList, mailbox = 'personal') {
    messages = messageList;
    const $inboxList = mailbox === 'job' ? $('#jobInboxList') : $('#inboxList');
    $inboxList.empty();
    
    if (!messageList || messageList.length === 0) {
        $inboxList.append(`
            <div class="empty-state">
                <i class="fas fa-inbox"></i>
                <p>${t(mailbox === 'job' ? 'ui_empty_job_inbox' : 'ui_empty_inbox')}</p>
            </div>
        `);
        updateUnreadBadge(0, mailbox);
        return;
    }
    
    let unreadCount = 0;
    
    messageList.forEach(message => {
        const isUnread = message.status === 0 || message.birdstatus === 0;
        const notPickedUp = message.pickedUp === 0;
        if (isUnread) unreadCount++;
        
        const unreadClass = isUnread ? 'unread' : '';
        const icon = isUnread ? 'fa-envelope' : 'fa-envelope-open';
        
        // Show badge if message is not picked up yet
        const pickupBadge = notPickedUp ? `<span class="pickup-badge">${t('ui_at_post_office')}</span>` : '';
        const jobBadge = mailbox === 'job' ? `<span class="pickup-badge">${t('ui_job_badge')}</span>` : '';
        
        $inboxList.append(`
            <div class="message-item ${unreadClass}" data-id="${message.id}" data-mailbox="${mailbox}">
                <div class="message-info-left">
                    <div class="message-subject">
                        <i class="fas ${icon}"></i> ${escapeHtml(message.subject)} ${pickupBadge} ${jobBadge}
                    </div>
                    <div class="message-sender">${t('ui_from_label')} ${escapeHtml(getSenderDisplayName(message))}</div>
                </div>
                <div class="message-date">${escapeHtml(message.sentDate)}</div>
            </div>
        `);
    });
    
    updateUnreadBadge(unreadCount, mailbox);
}

// Load Addressbook
function loadAddressbook() {
    $.post('https://rsg-telegram/getAddressbook', JSON.stringify({}), function(contactList) {
        displayContacts(contactList);
    });
}

function displayContacts(contactList) {
    contacts = contactList;
    const $addressbookList = $('#addressbookList');
    $addressbookList.empty();
    
    if (!contactList || contactList.length === 0) {
        $addressbookList.append(`
            <div class="empty-state">
                <i class="fas fa-address-book"></i>
                <p>${t('ui_empty_addressbook')}</p>
            </div>
        `);
        return;
    }
    
    contactList.forEach(contact => {
        $addressbookList.append(`
            <div class="contact-item">
                <div class="contact-info">
                    <div class="contact-name">${escapeHtml(contact.name)}</div>
                    <div class="contact-id">${t('ui_citizenid_display', {citizenid: escapeHtml(contact.citizenid)})}</div>
                </div>
                <div class="contact-actions">
                    <button class="contact-btn compose-to" data-citizenid="${escapeHtml(contact.citizenid)}" data-name="${escapeHtml(contact.name)}" title="${t('ui_send_message')}">
                        <i class="fas fa-paper-plane"></i>
                    </button>
                    <button class="contact-btn delete" data-citizenid="${escapeHtml(contact.citizenid)}" title="${t('ui_remove_contact')}">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        `);
    });
}

// Load Recipients for New Message
function loadRecipients() {
    jobSendersLoaded = false;

    $.post('https://rsg-telegram/getPlayers', JSON.stringify({}), function(playerList) {
        displayRecipients(playerList);
    });

    if (enableJobMailboxes) {
        $.post('https://rsg-telegram/getJobSenders', JSON.stringify({}), function(senderList) {
            displayJobSenders(senderList);
        });
    } else {
        displayJobSenders([]);
    }
}

function displayRecipients(playerList) {
    players = playerList;
    const $recipientOptions = $('#recipientOptions');
    $recipientOptions.empty();
    recipientChoices = [];
    
    if (playerList && playerList.length > 0) {
        playerList.forEach(player => {
            const rawRecipientLabel = player.job ? player.name : `${player.name} (${player.citizenid})`;
            const recipientLabel = escapeHtml(rawRecipientLabel);
            recipientChoices.push({
                value: player.citizenid,
                label: rawRecipientLabel
            });

            $recipientOptions.append(`
                <option value="${escapeHtml(player.citizenid)}">
                    ${recipientLabel}
                </option>
            `);
        });
    }

    $('#recipientDropdown').hide();
    applyPendingReplyDefaults();
}

function displayJobSenders(senderList) {
    jobSenders = senderList || [];
    jobSendersLoaded = true;
    const $senderSelect = $('#senderSelect');
    $senderSelect.empty();
    $senderSelect.append(`<option value="">${t('ui_personal_sender')}</option>`);

    if (jobSenders.length === 0) {
        $('#senderGroup').hide();
        applyPendingReplyDefaults();
        return;
    }

    // Job sender options let eligible workers send telegrams as their job identity.
    jobSenders.forEach(sender => {
        $senderSelect.append(`
            <option value="${escapeHtml(sender.alias)}">
                ${escapeHtml(sender.label)}
            </option>
        `);
    });

    $('#senderGroup').show();
    applyPendingReplyDefaults();
}

// Show Message Modal
function showMessage(messageId) {
    const message = messages.find(m => m.id == messageId);
    if (!message) return;
    
    currentMessageId = messageId;
    currentMessageMailbox = message.mailbox === 'job' ? 'job' : 'personal';
    currentViewedMessage = message;
    
    $('#modalSender').text(getSenderDisplayName(message));
    $('#modalRecipient').text(currentMessageMailbox === 'job' ? message.recipient : getContactName(message.citizenid));
    $('#modalDate').text(message.sentDate);
    $('#modalSubject').text(message.subject);
    $('#modalMessage').text(message.message);
    
    $('#messageModal').addClass('active');
    
    // Mark as read
    $.post('https://rsg-telegram/markAsRead', JSON.stringify({ id: messageId }));
}

function closeMessageModal() {
    $('#messageModal').removeClass('active');
    currentMessageId = null;
    currentViewedMessage = null;
    // Refresh the mailbox that opened the message.
    if (currentTab === 'job-inbox' || currentMessageMailbox === 'job') {
        loadJobInbox();
    } else {
        loadInbox();
    }
}

function replyToCurrentMessage() {
    if (!currentViewedMessage) return;

    const message = currentViewedMessage;
    const replyPrefix = t('ui_reply_subject_prefix');
    const replySubject = message.subject && message.subject.toLowerCase().indexOf(replyPrefix.toLowerCase()) === 0 ? message.subject : `${replyPrefix} ${message.subject || ''}`;
    const jobReplySender = message.mailbox === 'job' ? message.jobTarget : '';
    pendingReplyDefaults = {
        recipient: message.sender,
        recipientLabel: getSenderDisplayName(message),
        subject: replySubject,
        jobSender: jobReplySender
    };

    $('#messageModal').removeClass('active');
    currentMessageId = null;
    currentViewedMessage = null;

    switchTab('new-message');
}

function applyPendingReplyDefaults() {
    if (!pendingReplyDefaults || currentTab !== 'new-message') return;
    if (pendingReplyDefaults.jobSender && enableJobMailboxes && !jobSendersLoaded) return;

    // Reply targets may not be in the addressbook or visible job-recipient list, so add a temporary suggestion when needed.
    if ($('#recipientOptions option[value="' + pendingReplyDefaults.recipient + '"]').length === 0) {
        $('#recipientOptions').append(`
            <option value="${escapeHtml(pendingReplyDefaults.recipient)}">
                ${escapeHtml(pendingReplyDefaults.recipientLabel || pendingReplyDefaults.recipient)}
            </option>
        `);
    }

    $('#recipientSelect').val(pendingReplyDefaults.recipient);
    $('#subjectInput').val(pendingReplyDefaults.subject);
    $('#messageInput').val('').focus();

    if (pendingReplyDefaults.jobSender && $('#senderSelect option[value="' + pendingReplyDefaults.jobSender + '"]').length > 0) {
        $('#senderSelect').val(pendingReplyDefaults.jobSender);
    } else {
        $('#senderSelect').val('');
    }

    pendingReplyDefaults = null;
}

// Send Message
function sendMessage() {
    const jobSender = $('#senderSelect').val();
    const recipient = $('#recipientSelect').val().trim();
    const subject = $('#subjectInput').val().trim();
    const message = $('#messageInput').val().trim();
    
    if (!recipient) {
        return;
    }
    
    if (!subject) {
        return;
    }
    
    if (!message) {
        return;
    }
    
    // Store message data for confirmation
    window.pendingSendData = {
        jobSender: jobSender,
        recipient: recipient,
        subject: subject,
        message: message
    };
    
    // Check location and get cost info
    $.post('https://rsg-telegram/checkLocation', JSON.stringify({}), function(response) {
        if (response.atPostOffice) {
            $('#birdPostWarning').hide();
            
            // Show cost warning if charging is enabled
            if (response.chargePlayer) {
                $('#letterCost').text(response.cost.toFixed(2));
                $('#costWarning').show();
            } else {
                $('#costWarning').hide();
            }
        } else {
            $('#birdPostWarning').show();
            $('#costWarning').hide();
        }
    });
    
    // Show confirmation dialog
    $('#confirmSendDialog').addClass('active');
}

function renderRecipientDropdown() {
    const query = ($('#recipientSelect').val() || '').toLowerCase();
    const $dropdown = $('#recipientDropdown');
    $dropdown.empty();

    const filteredChoices = recipientChoices.filter(choice => {
        return !query || choice.value.toLowerCase().includes(query) || choice.label.toLowerCase().includes(query);
    }).slice(0, 8);

    if (filteredChoices.length === 0) {
        $dropdown.hide();
        return;
    }

    filteredChoices.forEach(choice => {
        $dropdown.append(`
            <button type="button" class="recipient-option" data-value="${escapeHtml(choice.value)}">
                <span>${escapeHtml(choice.label)}</span>
            </button>
        `);
    });

    $dropdown.show();
}

function confirmSend() {
    if (!window.pendingSendData) return;
    
    $.post('https://rsg-telegram/sendMessage', JSON.stringify(window.pendingSendData));
    
    // Close confirmation dialog
    $('#confirmSendDialog').removeClass('active');
    
    // Clear form
    clearMessageForm();
    
    // Clear pending data
    window.pendingSendData = null;
}

function cancelSend() {
    $('#confirmSendDialog').removeClass('active');
    window.pendingSendData = null;
}

function clearMessageForm() {
    pendingReplyDefaults = null;
    $('#senderSelect').val('');
    $('#recipientSelect').val('');
    $('#recipientDropdown').hide();
    $('#subjectInput').val('');
    $('#messageInput').val('');
}

// Delete Message
function deleteMessage(messageId) {
    $.post('https://rsg-telegram/deleteMessage', JSON.stringify({ id: messageId }));
    closeMessageModal();
}

// Add Contact
function openAddContactModal() {
    $('#addContactModal').addClass('active');
    $('#contactName').val('').focus();
    $('#contactCitizenId').val('');
}

function closeAddContactModal() {
    $('#addContactModal').removeClass('active');
    $('#contactName').val('');
    $('#contactCitizenId').val('');
}

function addContact() {
    const name = $('#contactName').val().trim();
    const citizenid = $('#contactCitizenId').val().trim();
    
    if (!name || !citizenid) {
        return;
    }
    
    $.post('https://rsg-telegram/addContact', JSON.stringify({
        name: name,
        citizenid: citizenid
    }));
    
    closeAddContactModal();
    
    // Reload addressbook after a short delay
    setTimeout(() => {
        loadAddressbook();
    }, 500);
}

// Remove Contact
function removeContact(citizenid) {
    $.post('https://rsg-telegram/removeContact', JSON.stringify({ citizenid: citizenid }));
    
    // Reload addressbook after a short delay
    setTimeout(() => {
        loadAddressbook();
    }, 500);
}

// Delete Selected Messages
function deleteSelectedMessages() {
    return;
}

// Update Unread Badge
function updateUnreadBadge(count, mailbox = 'personal') {
    const $badge = mailbox === 'job' ? $('#jobUnreadBadge') : $('#unreadBadge');
    if (count > 0) {
        $badge.text(count).show();
    } else {
        $badge.hide();
    }
}

// Search Messages
function searchMessages(query) {
    query = query.toLowerCase();
    
    if (!query) {
        $('.message-item').show();
        return;
    }
    
    $('.message-item').each(function() {
        const subject = $(this).find('.message-subject').text().toLowerCase();
        const sender = $(this).find('.message-sender').text().toLowerCase();
        
        if (subject.includes(query) || sender.includes(query)) {
            $(this).show();
        } else {
            $(this).hide();
        }
    });
}

// Get contact name from addressbook, fallback to citizenid
function getContactName(citizenid) {
    if (!citizenid) return '';
    const contact = contacts.find(c => c.citizenid === citizenid);
    return contact ? contact.name : citizenid;
}

function getSenderDisplayName(message) {
    if (!message || !message.sender) return '';

    if (jobAliases && jobAliases[message.sender]) {
        return message.sendername || jobAliases[message.sender].label || message.sender;
    }

    if (personalSenderDisplay === 'citizenid') {
        return message.sender;
    }

    const contactName = getContactName(message.sender);

    // Keep addressbook display names first, then fall back to sendername for job mailbox identities.
    if (contactName !== message.sender) {
        return contactName;
    }

    return message.sendername || message.sender;
}

// Utility Functions
function escapeHtml(text) {
    if (!text) return '';
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.toString().replace(/[&<>"']/g, m => map[m]);
}

// Event Listeners
$(document).ready(function() {
    // Tab switching
    $('.telegram-tab').on('click', function() {
        const tabName = $(this).data('tab');
        switchTab(tabName);
    });
    
    // Close UI
    $('#closeBtn').on('click', function() {
        closeTelegramUI();
    });
    
    // Message item click
    $(document).on('click', '.message-item', function() {
        const messageId = $(this).data('id');
        showMessage(messageId);
    });
    
    // Modal close
    $('#closeModal, #closeModalBtn').on('click', function() {
        closeMessageModal();
    });
    
    // Delete message from modal
    $('#deleteMessageBtn').on('click', function() {
        if (currentMessageId) {
            deleteMessage(currentMessageId);
        }
    });

    // Reply to message from modal
    $('#replyMessageBtn').on('click', function() {
        replyToCurrentMessage();
    });
    
    // Send message
    $('#sendMessageBtn').on('click', function() {
        sendMessage();
    });
    
    // Clear form
    $('#clearFormBtn').on('click', function() {
        clearMessageForm();
    });

    // Custom recipient combobox keeps one field while supporting free typing and clickable suggestions.
    $('#recipientSelect').on('focus input', function() {
        renderRecipientDropdown();
    });

    $(document).on('mousedown', '.recipient-option', function(e) {
        e.preventDefault();
        $('#recipientSelect').val($(this).data('value'));
        $('#recipientDropdown').hide();
    });

    $('#recipientSelect').on('blur', function() {
        setTimeout(() => {
            $('#recipientDropdown').hide();
        }, 150);
    });
    
    // Search
    $('#searchInput').on('input', function() {
        const query = $(this).val();
        searchMessages(query);
    });

    // Job inbox search uses the same filtering logic on the visible job list.
    $('#jobSearchInput').on('input', function() {
        const query = $(this).val();
        searchMessages(query);
    });
    
    // Clear search input
    $('#clearSearchBtn').on('click', function() {
        $('#searchInput').val('');
        $('#searchInput').trigger('input'); // Trigger search to show all messages
    });

    $('#clearJobSearchBtn').on('click', function() {
        $('#jobSearchInput').val('');
        $('#jobSearchInput').trigger('input');
    });
    
    // Add contact
    $('#addContactBtn').on('click', function() {
        openAddContactModal();
    });
    
    // Save contact from modal
    $('#saveContactBtn').on('click', function() {
        addContact();
    });
    
    // Close add contact modal
    $('#closeAddContactModal, #cancelAddContactBtn').on('click', function() {
        closeAddContactModal();
    });
    
    // Confirm send buttons
    $('#confirmSendBtn').on('click', function() {
        confirmSend();
    });
    
    $('#cancelSendBtn, #closeConfirmSendDialog').on('click', function() {
        cancelSend();
    });
    
    // Submit contact on Enter key
    $('#contactName, #contactCitizenId').on('keypress', function(e) {
        if (e.key === 'Enter' || e.keyCode === 13) {
            addContact();
        }
    });
    
    // Remove contact
    $(document).on('click', '.contact-btn.delete', function() {
        const citizenid = $(this).data('citizenid');
        removeContact(citizenid);
    });
    
    // Compose to contact
    $(document).on('click', '.contact-btn.compose-to', function() {
        const citizenid = $(this).data('citizenid');
        const name = $(this).data('name');
        
        switchTab('new-message');
        setTimeout(() => {
            $('#recipientSelect').val(citizenid);
            $('#recipientDropdown').hide();
        }, 100);
    });
    
    // ESC key to close
    $(document).on('keyup', function(e) {
        if (e.key === 'Escape' || e.keyCode === 27) {
            if ($('#addContactModal').hasClass('active')) {
                closeAddContactModal();
            } else if ($('#messageModal').hasClass('active')) {
                closeMessageModal();
            } else if ($('#telegramContainer').is(':visible')) {
                closeTelegramUI();
            }
        }
    });
    
    // Click outside modal to close
    $('#messageModal').on('click', function(e) {
        if (e.target === this) {
            closeMessageModal();
        }
    });
    
    $('#addContactModal').on('click', function(e) {
        if (e.target === this) {
            closeAddContactModal();
        }
    });
});

// NUI Message Handler
window.addEventListener('message', function(event) {
    const data = event.data;
    
    switch(data.action) {
        case 'openUI':
            openTelegramUI(data.defaultTab, data.enableJobMailboxes, data.personalSenderDisplay, data.jobAliases, data.labels);
            break;
            
        case 'closeUI':
            closeTelegramUI();
            break;
            
        case 'updateInbox':
            displayMessages(data.messages);
            break;
            
        case 'updateAddressbook':
            displayContacts(data.contacts);
            break;
            
        case 'updatePlayers':
            displayRecipients(data.players);
            break;
            
        case 'updateUnreadCount':
            updateUnreadBadge(data.count);
            break;
            
        case 'messageSent':
            clearMessageForm();
            switchTab('inbox');
            break;
            
        case 'contactAdded':
            if (currentTab === 'addressbook') {
                loadAddressbook();
            }
            break;
            
        case 'contactRemoved':
            if (currentTab === 'addressbook') {
                loadAddressbook();
            }
            break;
    }
});
