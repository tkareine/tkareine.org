# frozen_string_literal: true

require 'rake/clean'
require 'rubocop/rake_task'

JEKYLL_CONFIG = {
  bin:         'jekyll',
  common_opts: '--trace',
  prod_config: '--config _config.yml',
  dev_config:  '--config _config.yml,_config-dev.yml'
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

directory '_tmp'

CLOBBER.include '_tmp'

namespace :sass do
  desc 'Ensure node-sass is installed'
  task :verify do
    unless File.executable?(SASS_CONFIG.fetch(:bin))
      raise "node-sass executable not found: #{SASS_CONFIG.fetch(:bin)}\nTry `npm install`."
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
    sh %{#{JEKYLL_CONFIG.fetch(:bin)} build #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:prod_config)}}
  end

  namespace :watch do
    desc 'Compile, watch, and serve the site locally (dev env)'
    task :dev do
      sh DEV_ENV, %{#{JEKYLL_CONFIG.fetch(:bin)} serve --watch #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:dev_config)}}
    end

    desc 'Compile, watch, and serve the site locally (prod env)'
    task :prod do
      sh %{#{JEKYLL_CONFIG.fetch(:bin)} serve --watch #{JEKYLL_CONFIG.fetch(:common_opts)} #{JEKYLL_CONFIG.fetch(:prod_config)}}
    end
  end

  CLEAN.include '_site'
end

desc 'Compile the site (prod env)'
task site: %i{clean sass:verify sass:compile jekyll:compile}

desc 'Compile the site and deploy it (prod env)'
task :deploy do
  sh %{git checkout master}
  sh %{git checkout -B tmp-gh-pages}
  Rake::Task['site'].invoke
  sh %{git add -f _site}
  sh %{git commit -m 'Generated site'}
  sh %{git subtree split --prefix _site -b gh-pages}
  sh %{git push -f origin gh-pages}
  sh %{git branch -D gh-pages}
  sh %{git checkout master}
end

RuboCop::RakeTask.new

task default: :site
