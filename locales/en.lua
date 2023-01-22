local Translations = {
    error = {
        you_dont_have_enough_cash_on_you = "you don\'t have enough cash on you!",
        failed_to_delete_your_message = 'failed to delete your message!',
    },
    success = {
		    var = 'text goes here',
    },
    primary = {
        telegram_sent_to = 'Telegram sent to : ',
        post_office = 'Post Office',
    },
    menu = {
		    open = 'Open ',
            telegram_menu = '| Telegram Menu |',
            read_messages = '📥 | Read Telegrams',
            send_telegram = '📤 | Send Telegrams',
            close_menu = 'Close Menu',
    },
    commands = {
		    var = 'text goes here',
    },
    inputs = {
            recipient = 'Recipient',
            subject = 'Subject',
            add_your_message_here = 'add your message here',
            telegram =  'Telegram : ',
            send_for = 'Send for $',
    },
    progressbar = {
		    var = 'text goes here',
    },
    text = {
        read_your_telegram_messages = '',
        send_telegram_to_another_player = '',
    },
    showUi = {
        sender = 'Sender:',
        recipient = 'Recipient:',
        dateMail = 'Date:',
        subject = 'Subject:',
        message = 'Message:',
        delete = 'Delete',
        post_office = 'Post Office',
        close_post_office = 'Close Post Office',
    }
}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
