module.exports = process.env.ORTOO_COV
  ? require('./lib-cov/redis-rememberme')
  : require('./lib/redis-rememberme');