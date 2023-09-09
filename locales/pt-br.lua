local Translations =
{
desc =
{
    ["prompt_desc"] = "Correio de Pássaros",
    ["prompt_button"] = "Recuperar Carta",
    ["blip_name"] = "Correio de Pássaros",
    ["send_button_free"] = "Enviar Carta",
    ["send_button_paid"] = "Enviar Carta por $%{lPrice}",
    ["send_message_header"] = "Enviar uma Carta",
    ["recipient"] = "Destinatário",
    ["subject"] = "Assunto",
    ["message"] = "Escreva sua mensagem aqui!",
    ["message_prefix"] = "Correio de Pássaros"
},
info =
{
    ["bird_approaching"] = "Um Correio de Pássaros está se aproximando de você!",
    ["wait_for_bird"] = "Aguarde o Correio de Pássaros se aproximar de você, por favor!",
    ["inside_building"] = "Por favor, saia do prédio, o pássaro não pode alcançar você!"
},
error =
{
    ["send_to_self"] = "Você não pode enviar uma carta para si mesmo!",
    ["player_unavailable"] = "A pessoa alvo está longe da área!",
    ["player_on_horse"] = "Por favor, desça do cavalo primeiro!",
    ["cancel_send"] = "Envio de carta cancelado!",
    ["insufficient_balance"] = "Você não possui dinheiro suficiente!",
    ["no_message"] = "Não há mensagens disponíveis para você!",
    ["delete_fail"] = "Falha ao excluir a mensagem!",
    ["delivery_fail1"] = "Você decidiu não pegar a carta!",
    ["delivery_fail2"] = "O pássaro ficou cansado e decidiu ir embora!",
    ["delivery_fail3"] = "Você pode recuperar a carta no Correio local!",
    ["send_receiving"] = "Você não pode escrever uma carta enquanto aguarda o Correio de Pássaros chegar!",
    ["wait_between_send"] = "Aguarde %{tDelay} segundos antes de enviar outra carta!"
},
success =
{
    ["letter_delivered"] = "Carta enviada para %{pName} com sucesso!",
    ["delete_success"] = "Mensagem excluída com sucesso!"
}

}

if GetConvar('rsg_locale', 'en') == 'pt-br' then
    Lang = Locale:new({
        phrases = Translations,
        warnOnMissing = true,
        fallbackLang = Lang,
    })
end
