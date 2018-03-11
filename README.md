# tkareine.org

The data of my blog, served from [GitHub
Pages](https://pages.github.com/).

Utilizes [Jekyll](https://jekyllrb.com/) and
[node-sass](https://github.com/sass/node-sass).

## Usage

To install dependencies:

``` shell
gem install bundler
bundle install
npm install
```

To compile and watch Sass sources for changes:

``` shell
bundle exec rake compass:watch
```

In another terminal, launch Jekyll to compile, watch site sources for
changes, and serving the site with http server:

``` shell
bundle exec rake jekyll:watch:prod  # or :dev
```

When you're ready to publish:

``` shell
bundle exec rake deploy
```

For other tasks, see:

``` shell
bundle exec rake -D
```

## License

Copyright &copy; 2018 Tuomas Kareinen. You need my permission to reuse
content in `_posts` directory. Everything else is released under [MIT
License](https://opensource.org/licenses/MIT).
