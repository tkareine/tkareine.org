# frozen_string_literal: true

require 'rake/clean'
require 'rubocop/rake_task'

JEKYLL_CONFIG = {
  bin:         'jekyll',
  common_opts: '--trace',
  config:      '--config _config.yml'
}.freeze

SASS_CONFIG = {
  bin:               'node_modules/.bin/node-sass',
  common_options:    '--output-style compressed',
  sourcemap_options: '--source-map-embed --source-map-contents',
  output_dir:        '_tmp',
  output_file:       '_tmp/site.css',
  input_file:        '_assets/styles/site.scss'
}.freeze

DEV_ENV = {
  'JEKYLL_MINIBUNDLE_MODE' => 'development'
}.freeze

PROD_ENV = {
  'JEKYLL_ENV' => 'production'
}.freeze

AWS_ENV_NAMES = %w{AWS_PROFILE}.freeze

directory '_tmp'

CLOBBER.include '_tmp'

namespace :sass do
  desc 'Ensure node-sass is installed'
  task :verify do
    unless File.executable?(SASS_CONFIG.fetch(:bin))
      raise "node-sass executable not found: #{SASS_CONFIG.fetch(:bin)}\nTry `npm ci`."
    end
  end

  CLOBBER.include 'node_modules'

  desc 'Compile assets with Sass (prod env)'
  task compile: :_tmp do
    sh %{#{SASS_CONFIG.fetch(:bin)} #{SASS_CONFIG.fetch(:common_options)} #{SASS_CONFIG.fetch(:input_file)} > #{SASS_CONFIG.fetch(:output_file)}}
  end

  CLEAN.include SASS_CONFIG.fetch(:output_file)

  desc 'Compile and watch assets with Sass, recompiling when necessary (dev env)'
  task watch: :_tmp do
    sh %{#{SASS_CONFIG.fetch(:bin)} #{SASS_CONFIG.fetch(:common_options)} #{SASS_CONFIG.fetch(:sourcemap_options)} #{SASS_CONFIG.fetch(:input_file)} > #{SASS_CONFIG.fetch(:output_file)}}
    sh %{#{SASS_CONFIG.fetch(:bin)} --watch #{SASS_CONFIG.fetch(:common_options)} #{SASS_CONFIG.fetch(:sourcemap_options)} --output #{SASS_CONFIG.fetch(:output_dir)} #{SASS_CONFIG.fetch(:input_file)}}
  end
end

namespace :jekyll do
  desc 'Compile the site (prod env)'
  task :compile do
    sh PROD_ENV, %{#{JEKYLL_CONFIG.fetch(:bin)} build #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:config)}}
  end

  namespace :watch do
    desc 'Compile, watch, and serve the site locally (dev env)'
    task :dev do
      sh DEV_ENV, %{#{JEKYLL_CONFIG.fetch(:bin)} serve --watch #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:config)}}
    end

    desc 'Compile, watch, and serve the site locally (prod env)'
    task :prod do
      sh PROD_ENV, %{#{JEKYLL_CONFIG.fetch(:bin)} serve --watch #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:config)}}
    end
  end

  CLEAN.include '_site'
end

namespace :aws do
  desc 'Ensure AWS settings are set as environment variables'
  task :verify do
    abort 'AWS settings are unset, try `source .env.sh`' if AWS_ENV_NAMES.find do |n|
      env_var = ENV[n]
      env_var.nil? || env_var.empty?
    end
  end

  desc 'Deploy _site to AWS S3 bucket'
  task :deploy do
    sh "aws s3 sync _site/ s3://tkareine.org --delete --exclude 'assets/*.css' --exclude 'assets/*.css' --cache-control 'max-age=0'"
    sh "aws s3 sync _site/ s3://tkareine.org --include 'assets/*.css' --include 'assets/*.js' --cache-control 'max-age=31536000'"
    sh 'aws s3 website s3://tkareine.org --index-document index.html --error-document error.html'
  end
end

desc 'Compile the site (prod env)'
task site: %i{clean sass:verify sass:compile jekyll:compile}

desc 'Compile the site and deploy it (prod env)'
task deploy: %i{aws:verify site aws:deploy}

RuboCop::RakeTask.new

task default: :site
