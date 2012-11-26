fs            = require 'fs'
{print}       = require 'sys'
{spawn, exec} = require 'child_process'
glob          = require 'glob'
wrench        = require 'wrench'

coverageReport = 'coverage.html'

build = (watch, callback) ->
  if typeof watch is 'function'
    callback = watch
    watch = false
  options = ['-c', '-o', 'lib', 'src']
  options.unshift '-w' if watch

  coffee = spawn 'coffee', options
  coffee.stdout.on 'data', (data) -> print data.toString()
  coffee.stderr.on 'data', (data) -> print data.toString()
  coffee.on 'exit', (status) -> callback?() if status is 0

getTests = ->
  testDir = __dirname + '/test'
  # We look for all files ending in -test.coffee
  tests = glob.sync testDir + '/**/*-test.coffee'
  return tests

coverage = (callback) ->
  if fs.existsSync 'lib-cov'
    wrench.rmdirSyncRecursive 'lib-cov'

  options = ['lib', 'lib-cov']
  jscov = spawn 'jscoverage', options
  jscov.stdout.on 'data', (data) -> print data.toString()
  jscov.stderr.on 'data', (data) -> print data.toString()
  jscov.on 'exit', (status) -> callback?() if status is 0

buildCoverage = (callback) ->
  build ->
    coverage callback

runTests = (coverage, opts) ->

  # Set the environment
  process.env.ORTOO_ENV = 'test'

  opts = opts || {}
  options = [
    '--compilers', 'coffee:coffee-script', 
    '-r', 'should',
  ]

  if opts.debug
    options.push '--debug-brk'
  if opts.grep
    options.push '--grep'
    options.push opts.grep

  if coverage
    options.push '--reporter'
    options.push 'html-cov'
    if fs.existsSync coverageReport
      fs.unlinkSync coverageReport

  # Get our tests
  tests = getTests()
  options = options.concat(tests)
  mocha = spawn 'mocha', options

  if coverage
    # If we are doing coverage then write the data to a file
    mocha.stdout.on 'data', (data) -> fs.appendFile coverageReport, data
    mocha.stderr.on 'data', (data) -> fs.appendFile coverageReport, data

  else
    # Otherwise write to the terminal
    mocha.stdout.on 'data', (data) -> print data.toString()
    mocha.stderr.on 'data', (data) -> print data.toString()

task 'docs', 'Generate annotated source code with Docco', ->
  fs.readdir 'src', (err, contents) ->
    files = ("src/#{file}" for file in contents when /\.coffee$/.test file)
    docco = spawn 'docco', files
    docco.stdout.on 'data', (data) -> print data.toString()
    docco.stderr.on 'data', (data) -> print data.toString()
    docco.on 'exit', (status) -> callback?() if status is 0

task 'build', 'Compile CoffeeScript source files', ->
  build()

task 'watch', 'Recompile CoffeeScript source files when modified', ->
  build true

task 'build-cov', 'Compile CoffeeScript source files along with the coverage libs', ->
  buildCoverage()

task 'test-cov', 'Run the test suite with code coverage', ->
  buildCoverage ->
    # Set the env
    process.env.ORTOO_COV = 1
    runTests true

option '-d', '--debug', 'run the test in debug mode'
option '-g', '--grep [GREP]', 'run the tests that match the grep'
task 'test', 'Run the test suite', (options) ->
  build ->
    runTests(false, options)
    
