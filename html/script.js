// start list
function loadInbox(list)
{
    $('#inboxList').empty();

    if (list.length > 0)
    {
        list.forEach(function(letter)
        {
            if (letter.status == 1)
            {
                $("#inboxList").append(`
                    <li class="inbox_row" data-id="`+letter.id+`">
                    <div class="inbox_checkbox"><input type="checkbox" class="messageCheckbox" data-id="${letter.id}"></div>
                    <div class="inbox_subject"><i class="fa fa-envelope-open"></i> `+letter.subject+`</div>
                    <div class="inbox_sendername">`+letter.sendername+`</div>
                    <div class="inbox_date">`+letter.sentDate+`</div>
                    <a href="#"><i class="fas fa-angle-double-right"></i></a>
                    </li>`
                );
            }
            else
            {
                $("#inboxList").append(`
                    <li class="inbox_row" data-id="`+letter.id+`">
                    <div class="inbox_checkbox"><input type="checkbox" class="messageCheckbox" data-id="${letter.id}"></div>
                    <div class="inbox_subject"><i class="fa fa-envelope"></i> <b>`+letter.subject+`</b></div>
                    <div class="inbox_sendername">`+letter.sendername+`</div>
                    <div class="inbox_date">`+letter.sentDate+`</div>
                    <a href="#"><i class="fas fa-angle-double-right"></i></a>
                    </li>`
                );
            }
        });
    }
    else
    {
        $(".inboxList").text("No messages!")
    }
}

// view msg or telegram
$(function ()
{
    window.addEventListener('message', function (event)
    {
        if (event.data.type === "openGeneral")
        {
            $('.inbox').css('display', 'block');
            let today = new Date().toLocaleDateString();
            $('#today').text(today);
        }

        if (event.data.type === "view")
        {
            $("#view_id").text(event.data.telegram.id)
            $("#view_recipient").text(event.data.telegram.recipient)
            $("#view_sender").text(event.data.telegram.sender)
            $("#view_sendername").text(event.data.telegram.sendername)
            $("#view_date").text(event.data.telegram.sentDate)
            $("#view_subject").text(event.data.telegram.subject)
            $("#view_message").text(event.data.telegram.message)
        }

        if (event.data.type === "inboxlist")
        {
            var msglist = event.data.response.list
            box = event.data.response.box
            loadInbox(msglist);
            $('#firstname').text(event.data.response.firstname);
        }

        if (event.data.type === "closeAll")
        {
            $('.inbox').css('display', 'none')
            $('.view').css('display', 'none')
        }
    });
});

// clicks
$(document).ready(function() {
    $("#inboxList").on("click", 'li', function(event) {
        itemToDel = $(this).data('id');
        $.post('https://rsg-telegram/getview', JSON.stringify({ id: $(this).data('id') }));
        $(".inbox").fadeOut().hide();
        $(".view").fadeIn().show();
    });

    // copy message
    // $(".telegram_copy_button").click(function(event)
    // {
    //     $.post('https://rsg-telegram/copymsg', JSON.stringify({id: itemToDel, }));
    //     $.post('https://rsg-telegram/NUIFocusOff', JSON.stringify({}));
    // });

    // delete message
    $(".telegram_delete_button").click(function(event)
    {
        $.post('https://rsg-telegram/delete', JSON.stringify({id: itemToDel}));
        $.post('https://rsg-telegram/NUIFocusOff', JSON.stringify({}));
    });
});

$(document).ready(function() {
    $('#selectAll').on('change', function() {
        let checked = $(this).prop('checked');
        $('.messageCheckbox').prop('checked', checked);
    });

    $('#inboxList').on('change', '.messageCheckbox', function() {
        let totalCheckboxes = $('.messageCheckbox').length;
        let checkedCheckboxes = $('.messageCheckbox:checked').length;
        $('#selectAll').prop('checked', totalCheckboxes === checkedCheckboxes);
    });

    $('#inboxList').on('click', '.messageCheckbox', function(event) {
        event.stopPropagation();  // Esto evita que el clic en el checkbox active el evento en el <li>
    });

    // filter
    let sortOrder = {
        alphabetical: 'asc',
        subject: 'asc',
        sender: 'asc',
        date: 'asc'
    };

    $('#filterBtn').click(function() {
        $('#filterOptions').toggle();
    });

    $('.sortBtn').click(function() {
        const sortType = $(this).data('sort');
        let rows = $('.inbox_row').get();

        rows.sort(function(a, b) {
            let keyA, keyB;

            if (sortType === 'alphabetical' || sortType === 'subject') {
                keyA = $(a).find('.inbox_subject').text().toUpperCase();
                keyB = $(b).find('.inbox_subject').text().toUpperCase();
            } else if (sortType === 'sender') {
                keyA = $(a).find('.inbox_sendername').text().toUpperCase();
                keyB = $(b).find('.inbox_sendername').text().toUpperCase();
            } else if (sortType === 'date') {
                keyA = new Date($(a).find('.inbox_date').text());
                keyB = new Date($(b).find('.inbox_date').text());
            } else if (sortType === 'readStatus') {
                keyA = $(a).find('.inbox_subject i').hasClass('fa-envelope-open') ? 1 : 0;
                keyB = $(b).find('.inbox_subject i').hasClass('fa-envelope-open') ? 1 : 0;
            }

            if (sortOrder[sortType] === 'asc') {
                if (keyA < keyB) return -1;
                if (keyA > keyB) return 1;
            } else {
                if (keyA > keyB) return -1;
                if (keyA < keyB) return 1;
            }
            return 0;
        });

        sortOrder[sortType] = sortOrder[sortType] === 'asc' ? 'desc' : 'asc';

        $.each(rows, function(index, row) {
            $('#inboxList').append(row);
        });
    });
});

$(document).ready(function() {
    const searchOptions = [
        'Sender 1',
        'Subject 2',
        'Date: 01/01/2024',
        'Sender 3',
        'Subject 4',
        // Agrega más opciones de búsqueda según lo necesario
    ];

    $('#searchInput').on('input', function() {
        const searchTerm = $(this).val().toLowerCase();
        const filteredOptions = searchOptions.filter(option =>
            option.toLowerCase().includes(searchTerm)
        );

        $('#searchOptions').empty(); // Limpia las opciones anteriores

        if (filteredOptions.length > 0) {
            filteredOptions.forEach(option => {
                $('#searchOptions').append(`<div class="search-option">${option}</div>`);
            });
            $('#searchOptions').show();
        } else {
            $('#searchOptions').hide(); // Oculta si no hay resultados
        }
    });

    // Ocultar las opciones si se hace clic fuera del input
    $(document).on('click', function(event) {
        if (!$(event.target).closest('#searchInput, #searchOptions').length) {
            $('#searchOptions').hide();
        }
    });

    // Manejo de la selección de una opción
    $('#searchOptions').on('click', '.search-option', function() {
        $('#searchInput').val($(this).text());
        $('#searchOptions').hide();
    });
});

$(document).ready(function() {
    // search + mark Read select + delete select
    $('#searchBtn').click(function() {
        const searchTerm = $('#searchInput').val().toLowerCase();
        $('.inbox_row').each(function() {
            const subject = $(this).find('.inbox_subject').text().toLowerCase();
            const sender = $(this).find('.inbox_sendername').text().toLowerCase();
            const date = $(this).find('.inbox_date').text().toLowerCase();

            if (subject.includes(searchTerm) || sender.includes(searchTerm) || date.includes(searchTerm)) {
                $(this).show();
            } else {
                $(this).hide();
            }
        });
    });

    $('#markReadBtn').click(function() {
        let messagesToMarkRead = [];
    
        $('.messageCheckbox:checked').each(function() {
            const row = $(this).closest('.inbox_row');
            const messageId = $(this).data('id');
            row.find('.inbox_subject i').removeClass('fa-envelope').addClass('fa-envelope-open');
            row.find('.inbox_subject b').contents().unwrap();
            messagesToMarkRead.push(messageId);
            $(this).prop('checked', false);
        });
    
        if (messagesToMarkRead.length > 0) {
            $.post('https://rsg-telegram/getviewall', JSON.stringify({ ids: messagesToMarkRead }));
        }
    });
 
    $("#deleteSelectedBtn").click(function(event) {
        let messagesToDelete = [];

    $('.messageCheckbox:checked').each(function() {
        const row = $(this).closest('.inbox_row');
        const messageId = $(this).data('id');
        messagesToDelete.push(messageId);
        row.remove();
    });

    if (messagesToDelete.length > 0) {
        $.post('https://rsg-telegram/deleteall', JSON.stringify({ ids: messagesToDelete }));
    }

    });
});

//Close view
$(".close_view").on("click", function ()
{
    $(".view").fadeOut().hide();
    $(".inbox").fadeIn().show();
});

//Close post office
$(".closePostoffice").on("click",function()
{
    $.post('https://rsg-telegram/NUIFocusOff', JSON.stringify({}));
});

// NEW PART MOVE TELEGRAM
$(function () {
    let mouseX = 0,
        mouseY = 0,
        isMouseDown = false;
    const viewContainer = document.querySelector(".view");

    document.addEventListener("mousedown", function () {
        isMouseDown = true;
    });

    document.addEventListener("mouseup", function () {
        isMouseDown = false;
    });

    document.addEventListener("mousemove", function (e) {
        if (isMouseDown) {
            mouseX += e.movementX;
            mouseY += e.movementY;
            viewContainer.style.transform = `rotateY(${mouseX / 5}deg) rotateX(${ -mouseY / 5 }deg)`;
        }
    });
    
    window.addEventListener('message', function (event) {
        if (event.data.type === "view") {
            // Resetear la rotación al abrir un mensaje
            mouseX = 0;
            mouseY = 0;
            viewContainer.style.transform = "rotateY(0deg) rotateX(0deg)";
        }
    });
});

$('.inbox').addClass('no-select');
$('.view').addClass('no-select');
$('#inboxList').addClass('no-select');
$('.messageCheckbox').addClass('no-select');