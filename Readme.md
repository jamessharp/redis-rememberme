# Redis Rememberme

This is connect middleware creating remember me functionality to sit alongside [connect_redis](https://github.com/visionmedia/connect-redis). It uses the remember me method [described here ](http://jaspan.com/improved_persistent_login_cookie_best_practice) and detects whether the cookie has been stolen or not.

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

This will create some extra properties on the req and res object. To destroy the rememberme session simply call `req.rememberme.destroy()`. To check whether a cookie has been stolen test `req.rememberme.stolen`. To set a remember me cookie for a user simply add `res.rememberme = {userid: '1234'}` or whatever in your routes.

You can also listen to `rememberMe.worker` for the `cleanup` and `cleaned` events to determine when cleanup is about to and has happened.

For more details have a look at the tests...

## Licence
MIT
