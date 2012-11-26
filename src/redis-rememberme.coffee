###
# Redis - Remember me
# Copyright(c) 2012 James Sharp <james@ortootech.com>
# MIT Licensed
#
# This uses the algorithm as described here: http://jaspan.com/improved_persistent_login_cookie_best_practice
# To implement it we create a couple of sets per user of the following form
#
#     remme:userid:series  - set containing a list of series tokens in use for the user
#     remme:userid:token   - set containing a list of series:token tokens that are in use for the user
#
# We also set a remme:expires sorted set, whose value is json {key: value} and whose score is the unix time
# the key expires
###
connect = require 'connect'
signature = require 'cookie-signature'
winston = require 'winston'
crypto = require 'crypto'

Cookie = connect.session.Cookie

# utility function to generate a random token
generateRandomToken = (callback) ->
    crypto.randomBytes 48, (err, buf) ->
        if err then return callback err
        callback null, buf.toString 'hex'

decodeRememberMeCookie = (value, secret) ->
    # s:[signed bit of the format j:{json data}]
    unsignedCookie = connect.utils.parseSignedCookie value, secret

    # Now we expect to be able to parse its JSON
    cookieData = connect.utils.parseJSONCookie unsignedCookie

    # If we don't have any data here then something has gone wrong. Just exit
    unless cookieData
        winston.warn 'Problem decoding remember me cookie', {value, unsignedCookie}
        return null

    # Does our cookie data have the correct fields
    unless cookieData.userid and cookieData.series and cookieData.token
        winston.warn 'Remember me cookie doesn\'t have correct data', {cookieData}
        return null

    return cookieData

encodeRememberMeCookie = (data, secret) ->
    # s:[signed bit of the format j:{json data}]
    unsigned = 'j:' + JSON.stringify data
    value = 's:' + signature.sign unsigned, secret
    return value

getRedisKeyVals = (data) ->
    return {
        tokenKey: "remme:#{data.userid}:token"
        tokenVal: "#{data.series}:#{data.token}"
        seriesKey: "remme:#{data.userid}:series"
        seriesVal: "#{data.series}"
        expiresKey: "remme:expires"
    }


class RememberMe

    constructor: (opts) ->

        @opts = opts or {}
        @opts.key = @opts.key or 'connect.rememberme'

        # Get the redis client. 
        @client = opts.redisStore.client 

        # Kick off the scheduled cleanup of expired sessions
        @commenceCleanup()

        return @middleware.bind this

    # Validate the cookie data. We do this by trying to find
    # the series/token combination for the provided user. If that exists then
    # all is good, we can validate the user. However if the token doesn't match 
    # we have two options. Either the token _and_ series don't match in which case
    # just reject the entry _or_ the series matches but the token doesn't in which
    # case someone has been naughty and stolen the cookie. I.e. we've had a security
    # breach.
    validateData: (data, callback) ->

        # Destroy the data first. This will return info on what it managed to delete
        # though...
        @destroy data, (err, [tokenResult, seriesResult]) ->
            if err then return callback err

            # OK now check the results. If the token result isnt 0 then we've successfully
            # removed a token so it's valid. Check that the series also exists. If it doesn't
            # something funny has happened and don't validate
            unless tokenResult is 0
                if seriesResult is 0
                    winston.error 'Found a token with no series!', data
                    callback()
                else
                    callback null, true
            else
                # We don't have a token. If we don't have a series then don't validate but
                # nothing too serious is amiss. However if we do have a series then
                # someone has probably stolen a cookie. Report it.
                if seriesResult is 0
                    callback()
                else
                    winston.warn 'Potentially stolen remember me token', data
                    callback null, false, true

    middleware: (req, res, next) ->

        cookieName = @opts.key or 'connect.rememberme'

        # Monkey patch end() so that we write the cookie
        end = res.end
        res.end = (data, encoding) =>
            res.end = end
            unless res.rememberme and 
                   req.session?.userid and
                   res.rememberme.userid is req.session.userid 
                return res.end data, encoding

            # Start creating our cookie
            cookie = new Cookie @opts.cookie
            proto = (req.headers['x-forwarded-proto'] or '').toLowerCase()
            tls = req.connection.encrypted or (@opts.proxy and 'https' is proto)
            secured = cookie.secure and tls

            # Are we OK to add it?
            if cookie.secure and not secured then return res.end data, encoding

            # Generate the data - we want a new token and the existing userid. If we
            # have been passed a series then use that otherwise create a new one
            @createTokens res.rememberme, (err, tokenData) =>
                unless err
                    value = encodeRememberMeCookie tokenData, @opts.secret
                    cookieVal = cookie.serialize cookieName, value
                    res.setHeader 'Set-Cookie', cookieVal
                else
                    winston.error err.stack, err
                res.end data, encoding

        # Do we have a remember me cookie?
        # if not then just exit
        cookieVal = req.cookies[cookieName]
        unless cookieVal then return next()

        cookieData = decodeRememberMeCookie cookieVal, @opts.secret
        unless cookieData then return next new Error 'Invalid cookie data'

        # No need to actually validate it if we have a userid already (i.e. we're in a session)
        # but we do want to get this far so that we can destroy the cookie if the user logs out
        req.rememberme = { 
            destroy: (callback) =>
                delete res.rememberme
                delete req.rememberme
                @destroy cookieData, callback 
        }
        if req.session.userid then return next()

        # Is the cookie valid
        @validateData cookieData, (err, valid, breach) =>
            # If there was an error then log it but move on
            if err
                winston.error err
                return next()

            # Was the cookie valid? Could there have been a security breach?
            # TODO: Some kind of warning notification for the security breach
            unless valid
                winston.verbose 'Invalid cookie', cookieData
                # If there has been a security breach then invalidate all tokens for the
                # use
                if breach then @invalidateAll cookieData.userid
                return next()

            # So the cookie is valid. Let the user in and record the remember me details. This will
            # mean that we'll get a new cookie when the response is sent
            req.session.userid = cookieData.userid
            res.rememberme = res.rememberme or {}
            res.rememberme.userid = cookieData.userid
            res.rememberme.series = cookieData.series
            return next()

    # Destroy the rememberme data
    destroy: (data, callback) ->
        {seriesKey, seriesVal, tokenKey, tokenVal, expiresKey} = getRedisKeyVals(data)
        expiresObj = @_expiresObj(data)
        expiresVal = JSON.stringify(expiresObj)
        multi = @client.multi()
        multi.srem(tokenKey, tokenVal)
        multi.srem(seriesKey, seriesVal)
        multi.zrem(expiresKey, expiresVal)
        multi.exec callback

    createTokens: (opts, callback) ->
        
        generateRandomToken (err, token) =>
            if err then return callback err
            opts.token = token
            unless opts.series
                generateRandomToken (err, series) =>
                    if err then return callback err
                    opts.series = series
                    @_storeTokens opts, callback
            else
                @_storeTokens opts, callback

    _expiresObj: (data) ->
        {seriesKey, seriesVal, tokenKey, tokenVal} = getRedisKeyVals(data)
        expiresObj = {}
        expiresObj[seriesKey] = seriesVal
        expiresObj[tokenKey] = tokenVal
        return expiresObj

    _storeTokens: (data, callback) ->
        {seriesKey, seriesVal, tokenKey, tokenVal, expiresKey} = getRedisKeyVals(data)

        # Work out when everything should expire. 
        expiresTime = Math.round(new Date().getTime() / 1000) + Math.round(@opts.cookie.maxAge / 1000)
        expiresVal = JSON.stringify @_expiresObj data
        multi = @client.multi()
        multi.sadd(seriesKey, seriesVal)
        multi.sadd(tokenKey, tokenVal)
        multi.zadd(expiresKey, expiresTime, expiresVal)
        multi.exec (err, replies) ->
            if err then callback err
            callback null, data

    invalidateAll: (userid, callback) ->
        {seriesKey, tokenKey} = getRedisKeyVals({userid})
        @client.del seriesKey, tokenKey

    commenceCleanup: ->
        # Run the cleanup every hour
        @cleanup()
        @cleanupId = setInterval @cleanup.bind(this), 24*3600*1000 

    cancelCleanup: ->
        if @cleanupId then clearInterval @cleanupId

    # Find everything in the expires set that should expired by now
    cleanup: (callback) ->
        {expiresKey} = getRedisKeyVals {}
        currentTime = Math.round(new Date().getTime() / 1000)
        multi = @client.multi()
        multi.zrangebyscore(expiresKey, '-inf', currentTime)
        multi.zremrangebyscore(expiresKey, '-inf', currentTime)
        multi.exec (err, [expiredObjs, removed]) =>
            if err
                return callback(err) if callback else winston.error err.stack, err

            multi = @client.multi()
            for objVal in expiredObjs
                expiredObj = JSON.parse objVal
                for key, value of expiredObj
                    multi.srem(key, value)
            multi.exec (err, replies) ->
                if err 
                    return callback(err) if callback else winston.error err.stack, err

module.exports = RememberMe
        
