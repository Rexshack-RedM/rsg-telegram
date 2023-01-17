local Translations = {
    error = {
        you_dont_have_enough_cash_on_you = "usted no tiene suficiente dinero en efectivo en usted!",
        failed_to_delete_your_message = '¡Error al borrar tu mensaje!',
    },
    success = {
		    var = 'text goes here',
    },
    primary = {
        telegram_sent_to = 'telegrama enviado a: ',
        post_office = 'Oficina de correos',
    },
    menu = {
		    open = 'Abrir ',
            telegram_menu = '| Menú de telegramas |',
            read_messages = '📥 | Leer telegramas',
            send_telegram = '📤 | enviar telegrama',
            close_menu = 'Cerra menú',
    },
    commands = {
		    var = 'text goes here',
    },
    inputs = {
            recipient = 'Destinatario',
            subject = 'asunto: ',
            add_your_message_here = 'agrega tu mensaje aquí',
            telegram =  'Telegrama : ',
            send_for = 'enviar por $',
    },
    progressbar = {
		    var = 'text goes here',
    },
    text = {
        read_your_telegram_messages = 'lee tus mensajes de telegram',
        send_telegram_to_another_player = 'Enviar un telegrama a otra persona',
    },
    showUi = {
        sender = 'Remitente:',
        recipient = 'Destinatario:',
        dateMail = 'Fecha:',
        subject = 'Asunto:',
        message = 'Mensaje:',
        delete = 'Borrar',
        post_office = 'Oficina de correos',
        close_post_office = 'Cerrar Oficina de correos',
    }
}

if GetConvar('rsg_locale', 'en') == 'es' then
    Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true,
    fallbackLang = Lang,
  })
end