local Translations = {
    error = {
        you_dont_have_enough_cash_on_you = "Non hai abbastanza soldi con te!",
        failed_to_delete_your_message = 'Impossibile eliminare il messaggio!',
    },
    success = {
		    var = 'text goes here',
    },
    primary = {
        telegram_sent_to = 'Telegramma inviato a : ',
        post_office = 'Ufficio postale',
    },
    menu = {
		    open = 'Apri ',
            telegram_menu = '| Menù telegramma |',
            read_messages = '📥 | Leggi Telegrammi',
            send_telegram = '📤 | Scrivi Telegrammi',
            close_menu = 'Chiudi Menu',
    },
    commands = {
		    var = 'text goes here',
    },
    inputs = {
            recipient = 'Destinatario',
            subject = 'Oggetto',
            add_your_message_here = 'Scrivi il messaggio qui',
            telegram =  'Telegramma : ',
            send_for = 'Invia per $',
    },
    progressbar = {
		    var = 'text goes here',
    },
    text = {
        read_your_telegram_messages = '',
        send_telegram_to_another_player = '',
    },
    showUi = {
        sender = 'Mittente:',
        recipient = 'Destinatario:',
        dateMail = 'Data:',
        subject = 'Oggetto:',
        message = 'Messaggio:',
        delete = 'Cancella',
        post_office = 'Ufficio Postale',
        close_post_office = 'Chiudi Ufficio Postale',
    }
}

if GetConvar('rsg_locale', 'en') == 'it' then
  Lang = Locale:new({
      phrases = Translations,
      warnOnMissing = true,
      fallbackLang = Lang,
  })
end
