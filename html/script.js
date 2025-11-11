// RSG Telegram - Custom UI Script
let currentTab = 'inbox';
let currentMessageId = null;
let messages = [];
let contacts = [];
let players = [];

// Open/Close UI
function openTelegramUI(defaultTab) {
    $('#telegramContainer').fadeIn(300).css('display', 'block');
    $('#telegramContainer').addClass('opening');
    setTimeout(() => {
        $('#telegramContainer').removeClass('opening');
    }, 300);
    
    // Switch to default tab if specified, otherwise inbox
    if (defaultTab && (defaultTab === 'inbox' || defaultTab === 'new-message' || defaultTab === 'addressbook')) {
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
    
    // Update tab buttons
    $('.telegram-tab').removeClass('active');
    $(`.telegram-tab[data-tab="${tabName}"]`).addClass('active');
    
    // Update tab panels
    $('.tab-panel').removeClass('active');
    $(`#${tabName}`).addClass('active');
    
    // Load data for the tab
    if (tabName === 'inbox') {
        loadInbox();
    } else if (tabName === 'addressbook') {
        loadAddressbook();
    } else if (tabName === 'new-message') {
        loadRecipients();
    }
}

// Load Inbox
function loadInbox() {
    $.post('https://rsg-telegram/getInbox', JSON.stringify({}), function(messageList) {
        displayMessages(messageList);
    });
}

function displayMessages(messageList) {
    messages = messageList;
    const $inboxList = $('#inboxList');
    $inboxList.empty();
    
    if (!messageList || messageList.length === 0) {
        $inboxList.append(`
            <div class="empty-state">
                <i class="fas fa-inbox"></i>
                <p>No messages in your inbox</p>
            </div>
        `);
        updateUnreadBadge(0);
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
        const pickupBadge = notPickedUp ? '<span class="pickup-badge">At Post Office</span>' : '';
        
        $inboxList.append(`
            <div class="message-item ${unreadClass}" data-id="${message.id}">
                <div class="message-info-left">
                    <div class="message-subject">
                        <i class="fas ${icon}"></i> ${escapeHtml(message.subject)} ${pickupBadge}
                    </div>
                    <div class="message-sender">From: ${escapeHtml(message.sendername)}</div>
                </div>
                <div class="message-date">${escapeHtml(message.sentDate)}</div>
            </div>
        `);
    });
    
    updateUnreadBadge(unreadCount);
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
                <p>No contacts in your addressbook</p>
            </div>
        `);
        return;
    }
    
    contactList.forEach(contact => {
        $addressbookList.append(`
            <div class="contact-item">
                <div class="contact-info">
                    <div class="contact-name">${escapeHtml(contact.name)}</div>
                    <div class="contact-id">Citizen ID: ${escapeHtml(contact.citizenid)}</div>
                </div>
                <div class="contact-actions">
                    <button class="contact-btn compose-to" data-citizenid="${escapeHtml(contact.citizenid)}" data-name="${escapeHtml(contact.name)}" title="Send Message">
                        <i class="fas fa-paper-plane"></i>
                    </button>
                    <button class="contact-btn delete" data-citizenid="${escapeHtml(contact.citizenid)}" title="Remove Contact">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        `);
    });
}

// Load Recipients for New Message
function loadRecipients() {
    $.post('https://rsg-telegram/getPlayers', JSON.stringify({}), function(playerList) {
        displayRecipients(playerList);
    });
}

function displayRecipients(playerList) {
    players = playerList;
    const $recipientSelect = $('#recipientSelect');
    $recipientSelect.empty();
    $recipientSelect.append('<option value="">Select Recipient...</option>');
    
    if (playerList && playerList.length > 0) {
        playerList.forEach(player => {
            $recipientSelect.append(`
                <option value="${escapeHtml(player.citizenid)}">
                    ${escapeHtml(player.name)} (${escapeHtml(player.citizenid)})
                </option>
            `);
        });
    }
}

// Show Message Modal
function showMessage(messageId) {
    const message = messages.find(m => m.id == messageId);
    if (!message) return;
    
    currentMessageId = messageId;
    
    $('#modalSender').text(message.sendername);
    $('#modalRecipient').text(message.recipient);
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
    loadInbox(); // Refresh inbox
}

// Send Message
function sendMessage() {
    const recipient = $('#recipientSelect').val();
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
    $('#recipientSelect').val('');
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
    // For now, just placeholder - can be implemented later
    console.log('Delete selected not yet implemented');
}

// Update Unread Badge
function updateUnreadBadge(count) {
    const $badge = $('#unreadBadge');
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
    
    // Send message
    $('#sendMessageBtn').on('click', function() {
        sendMessage();
    });
    
    // Clear form
    $('#clearFormBtn').on('click', function() {
        clearMessageForm();
    });
    
    // Search
    $('#searchInput').on('input', function() {
        const query = $(this).val();
        searchMessages(query);
    });
    
    // Clear search input
    $('#clearSearchBtn').on('click', function() {
        $('#searchInput').val('');
        $('#searchInput').trigger('input'); // Trigger search to show all messages
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
            openTelegramUI(data.defaultTab);
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
