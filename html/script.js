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

// Listen for the 'Esc' key press to close ui
$(document).ready(function () {
    $(document).keydown(function (event) {
        if (event.keyCode === 27) {
            $.post('https://rsg-telegram/NUIFocusOff', JSON.stringify({}));
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

$(document).ready(function () {
    $("#searchInput").on("keyup", function () {
        var value = $(this).val().toLowerCase();
        $("#inboxList li").filter(function () {
            $(this).toggle($(this).text().toLowerCase().indexOf(value) > -1)
        });
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


document.addEventListener('DOMContentLoaded', (event) => {
    const getRandomText = (array) => array[Math.floor(Math.random() * array.length)];

    document.querySelector('.header-left h1').textContent = getRandomText(headerTexts.title);
    document.querySelector('.header-left p').textContent = getRandomText(headerTexts.description);
    document.querySelector('.header-center div:nth-of-type(1) p').textContent = getRandomText(headerTexts.centerText);
    document.querySelector('.header-center div:nth-of-type(3) h1').textContent = getRandomText(headerTexts.postalTitle);
    document.querySelector('.header-center div:nth-of-type(4) p').textContent = getRandomText(headerTexts.postalDescription);
    document.querySelector('.header-rigth p').textContent = getRandomText(headerTexts.commitmentText);
});

const headerTexts = {
    title: [
        'Global Connection',
        'Universal Link',
        'Worldwide Network',
        'Global Bridge'
    ],
    description: [
        'We are the bridge that connects hearts across distance. Every letter, every word, is a bond that unites stories and people, keeping relationships alive. In this fast-paced world, taking the time to send a written message is a gesture of care and dedication that transcends borders.',
        'Connecting hearts and minds, one message at a time. Every word carries a piece of our soul, bridging distances and uniting lives. In our fast-moving world, a handwritten note is a cherished gesture of love and dedication.',
        'Bridging distances with every message. Each letter carries a story, connecting lives across the globe. In a world where speed is everything, taking the time to send a personal note shows true commitment.',
        'We link people through written words, preserving stories and connections. In a world that moves too fast, we take the time to deliver messages that matter, fostering relationships across any distance.',
        'We function as the bridge that links hearts over long distances. Each message, every word, forges a connection that unites lives and tales, maintaining relationships. In this fast-paced age, sending a personal note is a gesture of care and dedication that spans across borders.',
        'We serve as a link connecting hearts over vast distances. Each letter, each word, forms a connection that ties stories and individuals, sustaining relationships. In today’s quick-moving world, taking time to send a personal message is a sign of care and devotion that bridges gaps.',
        'We act as a conduit that brings people together across distances. Every note, every word, creates a link that joins lives and narratives, preserving bonds. In this rapidly moving era, sending a handwritten message is a meaningful act of commitment that crosses boundaries.',
    ],
    centerText: [
        'Your voice, anywhere',
        'Speak to the world',
        'Voice of the Globe',
        'Echoes Everywhere'
    ],
    postalTitle: [
        'Postal Telegrah',
        'Global Postal',
        'Universal Mail'
    ],
    postalDescription: [
        'We deliver your message where you need it',
        'Your message reaches its destination',
        'Bringing your words to every corner',
        'Delivering messages worldwide'
    ],
    commitmentText: [
        'Committed to bringing your message to every corner. Trusted postal service for over 100 years, Safe Delivery',
        'Dedicated to reaching every destination. Over a century of trusted postal service, ensuring safe delivery',
        'Bringing your messages everywhere with care. A century of reliable service, committed to safe delivery',
        'Ensuring your messages reach their destination. Over 100 years of trusted postal service, delivering safely'
    ]
};
