# frozen_string_literal: true

require 'rake/clean'
require 'shellwords'
require 'rubocop/rake_task'
require_relative '_rake/support'

JEKYLL_CONFIG = {
  bin:         'jekyll',
  common_opts: '--trace',
  config:      '--config _config.yml'
}.freeze

SASS_CONFIG = {
  bin:          'node_modules/.bin/sass',
  dev_options:  '--style=compressed --embed-sources --embed-source-map',
  prod_options: '--style=compressed --no-source-map',
  output_file:  '_tmp/site.css',
  input_file:   '_assets/styles/site.scss'
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
  desc 'Check if Sass is installed'
  task :verify do
    unless File.executable?(SASS_CONFIG.fetch(:bin))
      raise "Sass executable not found: #{SASS_CONFIG.fetch(:bin)}\nTry `npm ci`."
    end
  end

  CLOBBER.include 'node_modules'

  # See https://sass-lang.com/documentation/cli/dart-sass/
  desc 'Compile assets with Sass (prod env)'
  task compile: :_tmp do
    sh %{#{SASS_CONFIG.fetch(:bin)} #{SASS_CONFIG.fetch(:prod_options)} #{SASS_CONFIG.fetch(:input_file)}:#{SASS_CONFIG.fetch(:output_file)}}
  end

  CLEAN.include SASS_CONFIG.fetch(:output_file)

  desc 'Compile and watch assets with Sass, recompiling when necessary (dev env)'
  task watch: :_tmp do
    sh %{#{SASS_CONFIG.fetch(:bin)} #{SASS_CONFIG.fetch(:dev_options)} #{SASS_CONFIG.fetch(:input_file)}:#{SASS_CONFIG.fetch(:output_file)}}
    sh %{#{SASS_CONFIG.fetch(:bin)} --watch #{SASS_CONFIG.fetch(:dev_options)} #{SASS_CONFIG.fetch(:input_file)}:#{SASS_CONFIG.fetch(:output_file)}}
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
  desc 'Check if AWS environment variables are set'
  task :verify do
    unless Support.command_exist?('aws')
      raise 'AWS CLI executable not found: aws'
    end

    abort "AWS environment variables are unset.\nTry `source .env.sh`." if AWS_ENV_NAMES.find do |n|
      env_var = ENV.fetch(n, nil)
      env_var.nil? || env_var.empty?
    end
  end

  desc 'Deploy _site to AWS S3 bucket'
  task :deploy do
    site_dir = Pathname.new('_site')
    stamped_assets =
      Dir['_site/assets/**/*.*']
      .grep(/-[a-z0-9]{32}\./)
      .map { |f| Pathname.new(f).relative_path_from(site_dir).to_s.shellescape }
    excludes = stamped_assets.map { |f| "--exclude #{f}" }.join(' ')
    includes = stamped_assets.map { |f| "--include #{f}" }.join(' ')
    sh "aws s3 sync _site/ s3://tkareine.org --delete #{excludes} --cache-control no-cache"
    sh "aws s3 sync _site/ s3://tkareine.org #{includes} --cache-control max-age=31536000"
  end
end

desc 'Compile the site (prod env)'
task site: %i{clean sass:verify sass:compile jekyll:compile}

desc 'Compile the site and deploy it (prod env)'
task deploy: %i{aws:verify site aws:deploy}

RuboCop::RakeTask.new

task default: :site
