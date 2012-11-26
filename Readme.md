# Redis Rememberme

This is connect middleware creating remember me functionality to sit alongside [connect_redis](https://github.com/visionmedia/connect-redis).

## Installation
    $ npm install redis-rememberme

You will also need to have connect-redis installed and configured (this piggy backs of its client connection)

## Options
Are almost the same as the connect session middleware with the added `redisStore`
    - `key` cookie name defaulting to connect.sid
    - `redisStore` connect-redis instance
    - `secret` session cookie is signed with this secret to prevent tampering
    - `cookie` session cookie settings, defaulting to { path: '/', httpOnly: true, maxAge: null }
    - `proxy` trust the reverse proxy when setting secure cookies (via "x-forwarded-proto")

## Usage (with an express app)

    var RedisStore = require('connect-redis')(express)
      , RememberMe = require('redis-rememberme');

    // Do some setup for the RedisStore to give you redisStore
    var rememberMeSettings = {
        cookie: {
          maxAge: 24*3600*1000 * 30 // 30 Days in ms
        },
        secret: 'secret,
        redisStore: redisStore,
        key: 'cookie-name'
    };
    app.use(new RememberMe(rememberMeSettings));

## Licence
MIT
