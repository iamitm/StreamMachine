Stream          = $src "master/stream"
FileSource      = $src "sources/file"
DumpRestore     = $src "rewind/dump_restore"
Logger          = $src "logger"

nconf = require "nconf"

uuid = require "node-uuid"
fs = require "fs"
_ = require "underscore"

mp3_a = $file "mp3/mp3-44100-64-s.mp3"

STREAM1 =
    key:                "test1"
    source_password:    "abc123"
    root_route:         true
    seconds:            120
    burst:              30
    format:             "mp3"

class FakeMaster extends require("events").EventEmitter
    constructor: (@log,mstreams...) ->
        @streams = {}
        for obj in mstreams
            @streams[ obj.key ] = obj

describe "Rewind Buffer Dump and Restore", ->
    master          = null
    stream          = null
    dump_restore    = null
    source_a        = null

    logger = new Logger stdout:false

    run_id = uuid.v4()

    nconf.set "rewind_dump:dir", "/tmp"
    nconf.set "rewind_dump:frequency", -1

    dump_filepath = null

    after (done) ->
        # make sure our file gets removed
        if dump_filepath
            fs.unlink dump_filepath, (err) ->
                throw err if err && err.code != "ENOENT"
                done()

    describe "Empty RewindBuffer", ->
        before (done) ->

            stream = new Stream null, "test__#{run_id}", logger, STREAM1
            master = new FakeMaster logger, stream
            dump_restore = new DumpRestore master, nconf.get("rewind_dump")

            done()

        it "can 'dump' an empty buffer", (done) ->
            dump_restore.once "debug", (event,s_key,err,info) ->
                throw err if err

                expect(event).to.eql "dump"
                expect(s_key).to.eql stream.key
                expect(info.file).to.be.null
                done()

            dump_restore._triggerDumps()

    describe "When dumping", ->
        before (done) ->
            stream = new Stream null, "test__#{run_id}", logger, STREAM1
            master = new FakeMaster logger, stream
            dump_restore = new DumpRestore master, nconf.get("rewind_dump")

            done()

        before (done) ->
            source = new FileSource format:"mp3", filePath:mp3_a, do_not_emit:true
            stream.addSource source, ->
                process.nextTick ->
                    ts = Number(new Date)
                    # push two minutes of data (240 samples)
                    for i in [0..239]
                        c_ts = new Date(ts+source.emitDuration*1000*i)
                        source._emitOnce(c_ts)

                    done()

        it "should have 120 seconds in the buffer", (done) ->
            expect( stream.rewind.bufferedSecs() ).to.be.within 119, 121
            done()

        it "should be able to dump its buffer", (done) ->
            dump_restore.once "debug", (event,s_key,err,info) ->
                throw err if err

                expect(event).to.eql "dump"
                expect(s_key).to.eql stream.key

                dump_filepath = info.file

                stat = fs.statSync(dump_filepath)
                expect(stat.size).to.be.gt 7000

                done()

            dump_restore._triggerDumps()

    describe "When restoring", ->
        before (done) ->
            stream = new Stream null, "test__#{run_id}", logger, STREAM1
            master = new FakeMaster logger, stream
            dump_restore = new DumpRestore master, nconf.get("rewind_dump")

            done()

        it "should load with a status of true", (done) ->
            dump_restore.load (err,stats) ->
                throw err if err
                expect(stats.success).to.eql 1
                done()

        it "should have 120 seconds in the buffer", (done) ->
            expect( stream.rewind.bufferedSecs() ).to.be.within 119, 121
            done()

    describe "When reset", ->
        beforeEach (done) ->
            stream = new Stream null, "test__#{run_id}", logger, STREAM1
            master = new FakeMaster logger, stream
            dump_restore = new DumpRestore master, nconf.get("rewind_dump")

            dump_restore.load (err,stats) ->
                throw err if err
                done()

        it "should unlink the dump file when the stream rewind buffer resets", (done) ->
            stream.rewind.resetRewind()
            dump_restore._triggerDumps ->
                fs.stat dump_restore._streams[ stream.key ]._filepath, (err,stats) ->
                    expect(err).to.not.be.null
                    expect(err.code).to.eql "ENOENT"
                    done()

