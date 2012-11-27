should = require 'should'
connect = require 'connect'
RedisStore = require('connect-redis')(connect)
RememberMe = require '../'
winston = require 'winston'
sinon = require 'sinon'

# Setup fake timers
clock = sinon.useFakeTimers('setInterval', 'Date')

# Remove the logging
winston.remove winston.transports.Console

# Get the cookie parser middleware
cookieParser = connect.middleware.cookieParser()

redisStore = new RedisStore {
    db: 15
}

rememberMe = new RememberMe {
    cookie: {
        maxAge: 40 * 60 * 1000 # 40 mins
    }
    redisStore: redisStore
    key: 'rememberme'
    secret: 'secret'
}

describe 'Remember me tests', ->

    req = {}
    res = {}
    resetMocks = ->
         # Basic mock req, res
        req = {
            cookies: {}
            headers: {}
            connection: {}
            session: {}
        }

        res = {
            headers: {}
            setHeader: (header, val) ->
                this.headers[header] = val
        }

    before (done) ->
        redisStore.client.flushall done
    after ->
        clock.restore()

    beforeEach ->
       resetMocks()

    describe 'requests with no cookie', ->

        it 'should not be given a user if no user is on the session', (done) ->
            rememberMe req, res, ->
                should.not.exist req.session.userid
                done()

        it 'should not remove the user if a user is on the session', (done) ->
            req.session = {userid: '1234'}
            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                done()

        it 'should not set a cookie', (done) ->
            req.session = {userid: '1234'}
            res.end = ->
                should.not.exist res.headers['Set-Cookie']
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.end()        

    describe 'requests with bad cookie', ->

        before ->
            req.cookies.rememberme = 'stupidvalue'
            req.session = {}

        it 'should not be given a user if no user is on the session', (done) ->
            rememberMe req, res, ->
                should.not.exist req.session.userid
                done()

        it 'should not remove the user if a user is on the session', (done) ->
            req.session = {userid: '1234'}
            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                done()

        it 'should not set a cookie', (done) ->
            req.session = {userid: '1234'}
            res.end = ->
                should.not.exist res.headers['Set-Cookie']
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.end()        

    describe 'setting the cookie', ->

        it 'should set the cookie when res.rememberme is set', (done) ->
            req.session = {userid: '1234'}
            res.headers = {}

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

        it 'should not set the cookie when res.remember me is set to a different userid than the session', (done) ->
            req.session = {userid: '1234'}

            res.end = ->
                should.not.exist res.headers['Set-Cookie']
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '4567'}
                res.end()        

    describe 'requests with correct cookie', ->

        cookie = null
        beforeEach (done) ->
            # Set a remember me cookie
            req.session = {userid: '1234'}
            res.headers = {}

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                cookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                resetMocks()
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

        it 'should put a userid on the session if the correct cookie is present', (done) ->
            req.headers.cookie = cookie

            req.session = {}
            req.cookies = null
            res.end = ->
                # Should get a new cookie
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                newcookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                newcookie.should.not.equal cookie
                done()

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.exist req.session.userid
                    req.session.userid.should.equal '1234'
                    res.end()

        it 'shouldn\'t set a cookie if there is already a user on the session', (done) ->
            req.headers.cookie = cookie
            res.headers = {}
            req.session = { userid: '1234' }
            req.cookies = null
            res.end = ->
                # Should get a new cookie
                should.not.exist res.headers['Set-Cookie']
                done()
            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.exist req.session.userid
                    req.session.userid.should.equal '1234'
                    res.end()

        it 'should authenticate after there has been a user on the session', (done) ->
            this.timeout(0)
            req.headers.cookie = cookie
            res.headers = {}
            req.session = { userid: '1234' }
            req.cookies = null
            res.end = ->
                # Should get a new cookie
                should.not.exist res.headers['Set-Cookie']
                
                # Now log in with no session but a rememberme cookie
                resetMocks()
                req.headers.cookie = cookie
                req.cookies = null
                res.end = ->
                    # Should get a new cookie
                    should.exist res.headers['Set-Cookie']
                    res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                    newcookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                    newcookie.should.not.equal cookie
                    done()

                cookieParser req, res, ->
                    rememberMe req, res, ->
                        should.exist req.session.userid
                        req.session.userid.should.equal '1234'
                        res.end()

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.exist req.session.userid
                    req.session.userid.should.equal '1234'
                    res.end()

    describe 'request with stolen cookie', ->

        stolenCookie = null
        newcookie = null
        before (done) ->
            # Set a remember me cookie
            req.session = {userid: '1234'}
            res.headers = {}

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                stolenCookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                req.headers.cookie = stolenCookie
                req.session = {}
                req.cookies = null
                res.end = ->
                    # Should get a new cookie
                    should.exist res.headers['Set-Cookie']
                    res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                    newcookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                    newcookie.should.not.equal stolenCookie
                    done()

                cookieParser req, res, ->
                    rememberMe req, res, ->
                        should.exist req.session.userid
                        req.session.userid.should.equal '1234'
                        res.end()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

        it 'should not be possible to use a cookie twice', (done) ->
            req.headers.cookie = stolenCookie
            req.session = {}
            req.cookies = null
            res.headers = {}
            res.end = ->
                # Should not get a new cookie
                should.not.exist res.headers['Set-Cookie']
                done()

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.not.exist req.session.userid
                    req.rememberme.stolen.should.be.true
                    res.end()   

        it 'should now have invalidated the use of all other remember me cookies as well', (done) ->
            req.headers.cookie = newcookie
            req.session = {}
            req.cookies = null
            res.headers = {}
            res.end = ->
                # Should not get a new cookie
                should.not.exist res.headers['Set-Cookie']
                done()

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.not.exist req.session.userid
                    res.end()   

    describe 'destroying the cookie', ->
        cookie1 = null
        cookie2 = null
        before (done) ->
            # Create two remember me cookies
            req.session = {userid: '1234'}
            res.headers = {}

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                cookie1 = res.headers['Set-Cookie'].split(';')[0] + ';'

                req.session = {userid: '1234'}
                res.headers = {}

                rememberMe req, res, ->
                    req.session.userid.should.equal '1234'
                    res.rememberme = {userid: '1234'}
                    res.end()

                res.end = ->
                    should.exist res.headers['Set-Cookie']
                    res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                    cookie2 = res.headers['Set-Cookie'].split(';')[0] + ';'
                    cookie2.should.not.equal cookie1
                    done()

        it 'should not set a new cookie once destroyed', (done) ->
            req.headers.cookie = cookie1
            req.session = {}
            req.cookies = null
            res.headers = {}
            res.end = ->
                # Should not get a new cookie
                should.not.exist res.headers['Set-Cookie']
                done()

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.exist req.session.userid
                    req.session.userid.should.equal '1234'
                    req.rememberme.destroy()
                    res.end()

        it 'should not be possible to log in with cookie1', (done) ->
            req.headers.cookie = cookie1
            req.session = {}
            req.cookies = null
            res.headers = {}

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.not.exist req.session.userid
                    done()

        it 'should still be possible to log in with cookie2', (done) ->
            req.headers.cookie = cookie2
            req.session = {}
            req.cookies = null
            res.headers = {}

            cookieParser req, res, ->
                rememberMe req, res, ->
                    should.exist req.session.userid
                    req.session.userid.should.equal '1234'
                    done()

    describe 'expiry', ->

        beforeEach (done) ->
            # Create a cookie
            req.session = {userid: '1234'}
            res.headers = {}

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                cookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                resetMocks()
                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

        it 'should expire everything after an hour (thats the runtime of the scheduled task)', (done) ->
            clock.tick(3601 * 1000)

            # Wait for the cleaned event and check that its all worked
            rememberMe.worker.once 'cleaned', ->
                # Now check the database and make sure everything has gone
                redisStore.client.keys 'remme*', (err, replies) ->
                    should.not.exist err
                    replies.should.have.length 0
                    done()

        it 'should not remove unexpired details though', (done) ->

            # Tick the clock on 30 mins then create a new cookie
            clock.tick(30 * 60 * 1000)

            resetMocks()
            req.session = {userid: '1234'}
            res.headers = {}

            res.end = ->
                should.exist res.headers['Set-Cookie']
                res.headers['Set-Cookie'].indexOf('rememberme=').should.equal 0
                cookie = res.headers['Set-Cookie'].split(';')[0] + ';'
                resetMocks()
                
                # Tick the clock over the hour (forcing the cleanup to happen)
                clock.tick 31 * 60 * 1000

                rememberMe.worker.once 'cleaned', ->
                    # There should be one series and token left in the sets
                    multi = redisStore.client.multi()
                    multi.scard 'remme:1234:token'
                    multi.scard 'remme:1234:series'
                    multi.exec (err, replies) ->
                        should.not.exist err
                        replies[0].should.equal 1
                        replies[1].should.equal 1

                        # Now tick the clock on another hour (causing a fresh clean up)
                        # There should then be nothing left
                        clock.tick 60 * 60 * 1000

                        rememberMe.worker.once 'cleaned', ->
                            # Now check the database and make sure everything has gone
                            redisStore.client.keys 'remme*', (err, replies) ->
                                should.not.exist err
                                replies.should.have.length 0
                                done()

            rememberMe req, res, ->
                req.session.userid.should.equal '1234'
                res.rememberme = {userid: '1234'}
                res.end()

            






