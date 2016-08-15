Rails.application.config.browserify_rails
  .commandline_options = "-t [ babelify --presets [ es2015 ] --plugins [ transform-object-rest-spread ] --extensions .es6 ]"
