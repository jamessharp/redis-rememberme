// Generated by CoffeeScript 1.6.2
/*
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
*/


(function() {
  var Cookie, EventEmitter, RememberMe, connect, crypto, decodeRememberMeCookie, encodeRememberMeCookie, generateRandomToken, getRedisKeyVals, signature, winston,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  connect = require('connect');

  signature = require('cookie-signature');

  winston = require('winston');

  crypto = require('crypto');

  EventEmitter = require('events').EventEmitter;

  Cookie = connect.session.Cookie;

  generateRandomToken = function(callback) {
    return crypto.randomBytes(48, function(err, buf) {
      if (err) {
        return callback(err);
      }
      return callback(null, buf.toString('hex'));
    });
  };

  decodeRememberMeCookie = function(value, secret) {
    var cookieData, unsignedCookie;

    unsignedCookie = connect.utils.parseSignedCookie(value, secret);
    if (!unsignedCookie) {
      winston.warn('Invalid remember me cookie signature', {
        value: value,
        unsignedCookie: unsignedCookie
      });
      return null;
    }
    cookieData = connect.utils.parseJSONCookie(unsignedCookie);
    if (!cookieData) {
      winston.warn('Problem decoding remember me cookie', {
        value: value,
        unsignedCookie: unsignedCookie
      });
      return null;
    }
    if (!(cookieData.userid && cookieData.series && cookieData.token)) {
      winston.warn('Remember me cookie doesn\'t have correct data', {
        cookieData: cookieData
      });
      return null;
    }
    return cookieData;
  };

  encodeRememberMeCookie = function(data, secret) {
    var unsigned, value;

    unsigned = 'j:' + JSON.stringify(data);
    value = 's:' + signature.sign(unsigned, secret);
    return value;
  };

  getRedisKeyVals = function(data) {
    return {
      tokenKey: "remme:" + data.userid + ":token",
      tokenVal: "" + data.series + ":" + data.token,
      seriesKey: "remme:" + data.userid + ":series",
      seriesVal: "" + data.series,
      expiresKey: "remme:expires"
    };
  };

  RememberMe = (function(_super) {
    __extends(RememberMe, _super);

    function RememberMe(opts) {
      var mw;

      this.opts = opts || {};
      this.opts.key = this.opts.key || 'connect.rememberme';
      this.client = opts.redisStore.client;
      this.commenceCleanup();
      mw = this.middleware.bind(this);
      mw.worker = this;
      return mw;
    }

    RememberMe.prototype.validateData = function(data, callback) {
      return this.destroy(data, function(err, _arg) {
        var seriesResult, tokenResult;

        tokenResult = _arg[0], seriesResult = _arg[1];
        if (err) {
          return callback(err);
        }
        if (tokenResult !== 0) {
          if (seriesResult === 0) {
            winston.error('Found a token with no series!', data);
            return callback();
          } else {
            return callback(null, true);
          }
        } else {
          if (seriesResult === 0) {
            return callback();
          } else {
            winston.warn('Potentially stolen remember me token', data);
            return callback(null, false, true);
          }
        }
      });
    };

    RememberMe.prototype.middleware = function(req, res, next) {
      var cookieData, cookieName, cookieVal, end,
        _this = this;

      cookieName = this.opts.key || 'connect.rememberme';
      end = res.end;
      res.end = function(data, encoding) {
        var cookie, proto, secured, tls, _ref;

        res.end = end;
        if (!(res.rememberme && ((_ref = req.session) != null ? _ref.userid : void 0) && res.rememberme.userid === req.session.userid)) {
          return res.end(data, encoding);
        }
        cookie = new Cookie(_this.opts.cookie);
        proto = (req.headers['x-forwarded-proto'] || '').toLowerCase();
        tls = req.connection.encrypted || (_this.opts.proxy && 'https' === proto);
        secured = cookie.secure && tls;
        if (cookie.secure && !secured) {
          return res.end(data, encoding);
        }
        return _this.createTokens(res.rememberme, function(err, tokenData) {
          var cookieVal, value;

          if (!err) {
            value = encodeRememberMeCookie(tokenData, _this.opts.secret);
            cookieVal = cookie.serialize(cookieName, value);
            res.setHeader('Set-Cookie', cookieVal);
          } else {
            winston.error(err.stack, err);
          }
          return res.end(data, encoding);
        });
      };
      cookieVal = req.cookies[cookieName];
      if (!cookieVal) {
        return next();
      }
      cookieData = decodeRememberMeCookie(cookieVal, this.opts.secret);
      if (!cookieData) {
        return next();
      }
      req.rememberme = {
        destroy: function(callback) {
          delete res.rememberme;
          delete req.rememberme;
          return _this.destroy(cookieData, callback);
        }
      };
      if (req.session.userid) {
        return next();
      }
      return this.validateData(cookieData, function(err, valid, breach) {
        if (err) {
          winston.error(err.stack, err);
          return next();
        }
        if (!valid) {
          winston.verbose('Invalid cookie', cookieData);
          if (breach) {
            _this.invalidateAll(cookieData.userid);
            req.rememberme.stolen = true;
          }
          return next();
        }
        req.session.userid = cookieData.userid;
        req.session.rememberme = true;
        res.rememberme = res.rememberme || {};
        res.rememberme.userid = cookieData.userid;
        res.rememberme.series = cookieData.series;
        return next();
      });
    };

    RememberMe.prototype.destroy = function(data, callback) {
      var expiresKey, expiresObj, expiresVal, multi, seriesKey, seriesVal, tokenKey, tokenVal, _ref;

      _ref = getRedisKeyVals(data), seriesKey = _ref.seriesKey, seriesVal = _ref.seriesVal, tokenKey = _ref.tokenKey, tokenVal = _ref.tokenVal, expiresKey = _ref.expiresKey;
      expiresObj = this._expiresObj(data);
      expiresVal = JSON.stringify(expiresObj);
      multi = this.client.multi();
      multi.srem(tokenKey, tokenVal);
      multi.srem(seriesKey, seriesVal);
      multi.zrem(expiresKey, expiresVal);
      return multi.exec(callback);
    };

    RememberMe.prototype.createTokens = function(opts, callback) {
      var _this = this;

      return generateRandomToken(function(err, token) {
        if (err) {
          return callback(err);
        }
        opts.token = token;
        if (!opts.series) {
          return generateRandomToken(function(err, series) {
            if (err) {
              return callback(err);
            }
            opts.series = series;
            return _this._storeTokens(opts, callback);
          });
        } else {
          return _this._storeTokens(opts, callback);
        }
      });
    };

    RememberMe.prototype._expiresObj = function(data) {
      var expiresObj, seriesKey, seriesVal, tokenKey, tokenVal, _ref;

      _ref = getRedisKeyVals(data), seriesKey = _ref.seriesKey, seriesVal = _ref.seriesVal, tokenKey = _ref.tokenKey, tokenVal = _ref.tokenVal;
      expiresObj = {};
      expiresObj[seriesKey] = seriesVal;
      expiresObj[tokenKey] = tokenVal;
      return expiresObj;
    };

    RememberMe.prototype._storeTokens = function(data, callback) {
      var expiresKey, expiresTime, expiresVal, multi, seriesKey, seriesVal, tokenKey, tokenVal, _ref;

      _ref = getRedisKeyVals(data), seriesKey = _ref.seriesKey, seriesVal = _ref.seriesVal, tokenKey = _ref.tokenKey, tokenVal = _ref.tokenVal, expiresKey = _ref.expiresKey;
      expiresTime = Math.round(new Date().getTime() / 1000) + Math.round(this.opts.cookie.maxAge / 1000);
      expiresVal = JSON.stringify(this._expiresObj(data));
      multi = this.client.multi();
      multi.sadd(seriesKey, seriesVal);
      multi.sadd(tokenKey, tokenVal);
      multi.zadd(expiresKey, expiresTime, expiresVal);
      return multi.exec(function(err, replies) {
        if (err) {
          callback(err);
        }
        return callback(null, data);
      });
    };

    RememberMe.prototype.invalidateAll = function(userid, callback) {
      var seriesKey, tokenKey, _ref;

      _ref = getRedisKeyVals({
        userid: userid
      }), seriesKey = _ref.seriesKey, tokenKey = _ref.tokenKey;
      return this.client.del(seriesKey, tokenKey);
    };

    RememberMe.prototype.commenceCleanup = function() {
      this.cleanup();
      return this.cleanupId = setInterval(this.cleanup.bind(this), 3600 * 1000);
    };

    RememberMe.prototype.cancelCleanup = function() {
      if (this.cleanupId) {
        return clearInterval(this.cleanupId);
      }
    };

    RememberMe.prototype.cleanup = function(callback) {
      var currentTime, expiresKey, multi,
        _this = this;

      this.emit('cleanup');
      expiresKey = getRedisKeyVals({}).expiresKey;
      currentTime = Math.round(new Date().getTime() / 1000);
      multi = this.client.multi();
      multi.zrangebyscore(expiresKey, '-inf', currentTime);
      multi.zremrangebyscore(expiresKey, '-inf', currentTime);
      return multi.exec(function(err, _arg) {
        var expiredObj, expiredObjs, key, objVal, removed, sets, setsObj, val, value, _i, _len;

        expiredObjs = _arg[0], removed = _arg[1];
        if (err) {
          return callback(err)(callback ? void 0 : winston.error(err.stack, err));
        }
        multi = _this.client.multi();
        setsObj = {};
        for (_i = 0, _len = expiredObjs.length; _i < _len; _i++) {
          objVal = expiredObjs[_i];
          expiredObj = JSON.parse(objVal);
          for (key in expiredObj) {
            value = expiredObj[key];
            multi.srem(key, value);
            setsObj[key] = true;
          }
        }
        sets = [];
        for (key in setsObj) {
          val = setsObj[key];
          multi.scard(key);
          sets.push(key);
        }
        return multi.exec(function(err, replies) {
          var start, _j, _len1;

          if (err) {
            return callback(err)(callback ? void 0 : winston.error(err.stack, err));
          }
          start = replies.length - sets.length;
          _i = 0;
          multi = _this.client.multi();
          for (_j = 0, _len1 = sets.length; _j < _len1; _j++) {
            key = sets[_j];
            if (replies[start + _i] === 0) {
              multi.del(key);
            }
            _i++;
          }
          return multi.exec(function(err, replies) {
            if (err) {
              return callback(err)(callback ? void 0 : winston.error(err.stack, err));
            }
            _this.emit('cleaned');
            if (callback) {
              callback();
            }
          });
        });
      });
    };

    return RememberMe;

  })(EventEmitter);

  module.exports = RememberMe;

}).call(this);
