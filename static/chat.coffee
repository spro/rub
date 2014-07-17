LMIN = 40.0
LMAX = 150.0
RSCALE = 0.7
GSCALE = 1.3
BSCALE = 1.0
randcolor = ->
    r = Math.floor Math.random()*(LMAX-LMIN)+LMIN*RSCALE
    g = Math.floor Math.random()*(LMAX-LMIN)+LMIN*GSCALE
    b = Math.floor Math.random()*(LMAX-LMIN)+LMIN*BSCALE
    return "rgb(#{ r }, #{ g }, #{ b })"

# Keep track of colors for peer names
peer_colors = {}
peer_color = (identifier) ->
    if !peer_colors[identifier]
        peer_colors[identifier] = randcolor()
    return peer_colors[identifier]

# Creating and adding views for incoming messages
message_view = (message) ->
    $message = $($('#message-template').html())
    $message.find('.username').text message.sender.username
    $message.find('.username').css 'background', peer_color message.sender.username
    $message.find('.body').text message.body
    $message
add_message = (message) ->
    $('#messages').append message_view message
    updateMessages()

# Add a notice, a message that is just a line of text
notice_view = (notice) ->
    $notice = $($('#notice-template').html())
    $notice.find('.body').text notice
    $notice
add_notice = (notice) ->
    $('#messages').append notice_view notice
    console.log notice
    updateMessages()

# Creating and adding views for joined peers
all_peers = {}
set_peers = (peers) ->
    for peer in peers
        all_peers[peer.socket_id] = peer
    show_peers()

show_peers = ->
    peer_usernames = (peer.username for socket_id, peer of all_peers)
    $("#peers").text 'Online: ' + peer_usernames.join ', '
    positionView()

peer_joined = (peer) ->
    all_peers[peer.socket_id] = peer
    add_notice "#{ peer.username } joined."
    show_peers()

peer_left = (peer) ->
    add_notice "#{ peer.username } left."
    delete all_peers[peer.socket_id]
    show_peers()

# Connect to the Socket.io server
window.username = prompt("Username: ")
socket = io.connect()

# Listen for messages and add them
socket.on 'chat', add_message
socket.on 'chats', (messages) ->
    for message in messages
        add_message message

# Listen for peers joining and add them
socket.on 'peers', set_peers
socket.on '+peer', peer_joined
socket.on '-peer', peer_left

# Show status and send subscription message when connected
socket.on 'connect', ->
    $('#messages').empty()
    socket.emit 'subscribe',
        username: username
        room: room
    showConnected()
    $('#message').focus()

# Change the status indicator when disconnected
socket.on 'disconnect', ->
    all_peers = []
    showDisonnected()

# Sending a message
send_message = (message) ->
    socket.emit 'chat', message

# Send a message upon pressing enter
$('#message').on 'keydown', (e) ->
    if e.keyCode == 13
        send_message
            room: room
            sender:
                username: username
            body: $('#message').val()
        $('#message').val ''

# Set up the view
showConnected = ->
    $status_inner = $($('#status-template').html())
    $status_inner.find('.username').text username
    $status_inner.find('.room').text room
    $('#status').html $status_inner

showDisonnected = ->
    $('#status').text 'Not connected.'

positionView = ->
    $('#messages').css 'margin-top', $('#status').outerHeight()
    $('#messages').css 'margin-bottom', $('#message').outerHeight() + 5

updateMessages = ->
    $('body').animate { scrollTop: $('#messages').outerHeight() }

