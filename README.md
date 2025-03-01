# tkareine.org

The data of my blog. Utilizes [Jekyll] and [Sass]. Deployed to an S3
bucket at AWS.

## Usage

To install dependencies:

``` shell
gem install bundler
bundle install
npm ci
```

To compile and watch Sass sources for changes with [Sass]:

``` shell
bundle exec rake sass:watch
```

In another terminal, launch [Jekyll] to compile, watch site sources for
changes, and serve the site with the [Webrick] http server:

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

Copyright &copy; 2018 Tuomas Kareinen. I hope you'd ask my permission to
reuse the content in the `_posts` and `_sources` directories. Everything
else is released under the [MIT
License](https://opensource.org/licenses/MIT).

[Jekyll]: https://jekyllrb.com/
[Sass]: https://sass-lang.com/
[Webrick]: https://github.com/ruby/webrick
