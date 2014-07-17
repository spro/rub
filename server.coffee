redis = require 'redis'
socketio = require 'socket.io'
polar = require 'polar'
express = require 'express'
http = require 'http'
fs = require 'fs'
styl = require 'styl'
variant = require 'rework-variant'
shade = require 'rework-shade'
util = require 'util'

# Create three Redis clients,
# one for Publishing,
# one for Subscribing,
# one for Getting
rp = redis.createClient()
rs = redis.createClient()
rg = redis.createClient()

# Send a message
send_message = (message) ->

    # Serialize the message into JSON
    message_json = JSON.stringify message

    # Get the next message ID for this room
    rp.incr "chat:#{ message.room }:last_message_id", (err, next_message_id) ->

        # Set the message JSON
        rp.set "chat:#{ message.room }:messages:#{ next_message_id }", message_json, ->

            # Publish the event
            rp.publish "chat:#{ message.room }:messages", next_message_id, ->

                # Message has been sent

# Subscribe to all chat events
rs.psubscribe 'chat:*'

# When a chat event is matched
rs.on 'pmessage', (pattern, channel, message_id) ->

    # Get the message JSON by the ID
    rg.get "#{ channel }:#{ message_id }", (err, message_json) ->

        # Parse the message from JSON
        message = JSON.parse message_json

        # Send the message to all relevant IO clients
        send_message_to_subscribers message

        # Debug output
        console.log "@#{ message.sender.username }: #{ message.body }"

# Gets a list of message objects from a list of message ids
get_messages_by_ids = (room, message_ids, cb) ->
    message_keys = for message_id in message_ids
        "chat:#{ room }:messages:#{ message_id }"
    rp.mget message_keys, (err, message_jsons) ->
        cb err, (for message_json in message_jsons
            JSON.parse message_json)

# Gets the last 10 messages sent in a room, or less if there aren't 10
get_latest_messages = (room, cb) ->
    rp.get "chat:#{ room }:last_message_id", (err, last_message_id) ->
        first_message_id = Math.max 1, last_message_id - 10
        get_messages_by_ids room, [first_message_id..last_message_id], cb

# Get a list of connected peers in a room
get_connected_peers = (room, cb) ->
    socket_ids = io.sockets.manager.rooms['/'+room]
    return if !socket_ids
    peers = (users[socket_id] for socket_id in socket_ids)
    cb null, peers

# Keep track of user data by socket ids
users = {}

send_message_to_subscribers = (message) ->
    io.sockets.in(message.room).emit 'chat', message

peer_joined = (room, peer) ->
    io.sockets.in(room).emit 'peer_joined', peer

peer_left = (room, peer) ->
    io.sockets.in(room).emit 'peer_left', peer

# Create a base express server for Socket.IO to attach to
base_app = express()
http_server = http.createServer base_app
http_server.listen 5888, -> console.log "Listening on 5888"
io = socketio.listen(http_server)

# Set up Polar for serving pages and scripts, using the
# base express server that Socket.IO is now attached to
app = polar.setup_app
    app: base_app

app.get '/', (req, res) -> res.redirect '/room/testing'

# Render the stylesheet with Style and Rework
app.get '/chat.css', (req, res) ->
    sass_str = fs.readFileSync('static/chat.sass').toString()
    rendered_css = styl(sass_str, {whitespace: true})
        .use(variant())
        .use(shade())
        .toString()
    res.end rendered_css

# Use the base url as the room
app.get '/room/:room', (req, res) ->
    res.render 'page',
        room: req.params.room
        username: 'spro'

# Handle new client socket connections
io.on 'connection', (socket) ->
    console.log 'connected'

    # When a client sends a subscribe message, add their
    # information to the users hash and send them the
    # latest messages and connected peers
    socket.on 'subscribe', (user) ->
        # Add socket id to user
        user.socket_id = socket.id
        users[socket.id] = user
        socket.join user.room

        # Send them a list of latest messages
        get_latest_messages user.room, (err, latest_messages) ->
            socket.emit 'chats', latest_messages

        # Send them a list of connected peers
        get_connected_peers user.room, (err, connected_peers) ->
            socket.emit 'peers', connected_peers

        # Tell other peers in this room a new peer has joined
        io.sockets.in(user.room).emit '+peer', users[socket.id]

    # When a client sends a chat message, send it to peers
    socket.on 'chat', (message) ->
        console.log 'received'
        send_message message

    # When a client disconnects, notify all peers in the room
    socket.on 'disconnect', ->
        user = users[socket.id]
        io.sockets.in(user.room).emit '-peer', user

