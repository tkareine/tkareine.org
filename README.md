# Introduction

The data of my blog, served from
[GitHub Pages](http://help.github.com/pages/).

Uses [Jekyll](https://github.com/mojombo/jekyll) and
[Compass](http://compass-style.org/).

# Usage

Local usage:

    $ gem install bundler
    $ bundle install

In a terminal, launch Compass for compiling `*.scss` to `*.css`
(GitHub does not do this for you):

    $ bundle exec rake compass:watch

In another terminal, launch Jekyll for compiling and previewing the
site:

    $ bundle exec rake jekyll

When you're ready, compile stylesheets without sourcemaps, commit, and
push the changes to GitHub:

    $ bundle exec rake compass:compile
    $ git commit
    $ git push origin master

# License

Copyright &copy; 2010-2013 Tuomas Kareinen. You need my permission to
reuse content in `_posts` directory. Everything else is released under
[MIT License](http://www.opensource.org/licenses/MIT).
