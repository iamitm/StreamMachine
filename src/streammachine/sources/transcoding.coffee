_               = require "underscore"
FFmpeg          = require "fluent-ffmpeg"
PassThrough     = require("stream").PassThrough

module.exports = class TranscodingSource extends require("./base")
    TYPE: -> "Transcoding (#{if @connected then "Connected" else "Waiting"})"

    constructor: (@opts) ->
        super skipParser:true

        @_queue = []

        @o_stream = @opts.stream

        # we start up an ffmpeg transcoder and then listen for data events
        # from our source. Each time we get a chunk of audio data, we feed
        # it into ffmpeg.  We then run the stream of transcoded data that
        # comes back through our parser to re-chunk it. We count chunks to
        # attach the right timing information to the chunks that come out

        @_buf = new PassThrough
        @ffmpeg = new FFmpeg( source:@_buf ).addOptions @opts.ffmpeg_args.split("|")

        @ffmpeg.on "start", (cmd) =>
            @log?.info "ffmpeg started with #{ cmd }"

        @ffmpeg.on "error", (err) =>
            @log?.error "ffmpeg transcoding error: #{ err }"
            # FIXME: What do we do to restart the transcoder?

        @ffmpeg.writeToStream @parser

        # -- watch for discontinuities -- #

        @_pingData = _.debounce =>
            # data has stopped flowing. mark a discontinuity in the chunker.
            @log?.info "Transcoder data interupted. Marking discontinuity."

            @o_stream.once "data", (chunk) =>
                @log?.info "Transcoder data resumed. Reseting time to #{chunk.ts}."
                @chunker.resetTime chunk.ts

        , 30*1000

        # -- chunking -- #

        @o_stream.once "data", (first_chunk) =>
            @emit "connected"

            @chunker = new TranscodingSource.FrameChunker @emitDuration * 1000, first_chunk.ts

            @parser.on "frame", (frame,header) =>
                # we need to re-apply our chunking logic to the output
                @chunker.write frame:frame, header:header

            @chunker.on "readable", =>
                while c = @chunker.read()
                    @emit "data", c

            @o_stream.on "data", (chunk) =>
                @_pingData()
                @_buf.write chunk.data

            @_buf.write first_chunk.data

        # -- watch for vitals -- #

        @parser.once "header", (header) =>
            # -- compute frames per second and stream key -- #

            @framesPerSec   = header.frames_per_sec
            @streamKey      = header.stream_key

            @log?.debug "setting framesPerSec to ", frames:@framesPerSec
            @log?.debug "first header is ", header

            # -- send out our stream vitals -- #

            @_setVitals
                streamKey:          @streamKey
                framesPerSec:       @framesPerSec
                emitDuration:       @emitDuration

    #----------

    info: ->
        source:     @TYPE?() ? @TYPE
        connected:  @connected
        url:        "N/A"
        streamKey:  @streamKey
        uuid:       @uuid
