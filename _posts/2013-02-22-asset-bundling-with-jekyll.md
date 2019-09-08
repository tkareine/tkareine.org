---
layout: post
title: Asset bundling with Jekyll
date: 2013-02-22T03:15+02
published: true
---

How do you ship the stylesheets and JavaScript sources of your [Jekyll](https://jekyllrb.com/)-built site? Shipping them as is, source file for source file, works, but causes the browser to request each of them separately from the backend. You want to consider concatenating all the stylesheet sources specific to your site into one file and then minifying that file. This is called _asset bundling_. And you should apply the same for JavaScript sources, too. This reduces the number of requests the browser does upon initial page load, shortening the time it takes to load the page.

Asset bundling has a related problem: caching. Generally, when the assets of your site change, you want the browser to fetch the latest version from the backend. The problem is in detecting when to use the version in the browser's cache and when to refetch the latest version of the asset from the backend. This can be solved by setting the HTTP response headers so that html files are considered to be dynamic resources, refetched when changed. The asset files are regarded as static resources, having long caching period. Whenever the contents of an asset changes, we refer to a new static resource in the html file. The latter is called _cache busting_. There's two techniques to it: using a URL query parameter or a fingerprint in file path.[^1]

It is up to you to solve both asset bundling and cache busting with Jekyll. Out of the box, Jekyll just copies each source as is to the generated site directory. This does not help asset bundling. And you handle the references to the assets in html files manually without any cache busting mechanism. Let's see what we can do about these.

## Jekyll with GitHub pages

With [GitHub pages](https://pages.github.com/), you let the service generate the site from your sources. The tradeoff is that GitHub runs Jekyll with `--safe` switch, disabling plugins. This means you have to do with what Jekyll has by default.[^2]

For bundling assets, there are two options. Either combine the assets manually, or use an external tool for it. I just put all JavaScript codes in a single file when there's not too much of it. The latter option is the one I prefer for stylesheets, because I don't want to write CSS by hand, anyway. I use [Compass](http://compass-style.org/) to author stylesheets with [Sass](https://sass-lang.com/) markup and direct Compass to compile the resulting CSS into a single compact file. The bad thing is that I have to add the compiled CSS files to git.

Update (9 March 2013): Another alternative is to concatenate assets with `include` tags, as shown [here](https://developmentseed.org/blog/2011/09/09/jekyll-github-pages/).
{: .update}

Then you have to solve cache busting. Here's one way to do it. In your content file, add a query parameter to the URL of the asset:

{% highlight html %}
{% raw %}
<link href="{{ site.baseurl }}assets/styles/screen.css?bust={{ site.time | date: '%s' }}" rel="stylesheet" media="screen, projection">
{% endraw %}
{% endhighlight %}

When you generate the site, the `bust` parameter will have a timestamp from the moment of site generation.

{% highlight html %}
<link href="/assets/styles/screen.css?bust=1419885211" rel="stylesheet" media="screen, projection">
{% endhighlight %}

Update (29 December 2014): Changed the example above to use plain Unix timestamp as the cache bust value.
{: .update}

The timestamp will change upon each site generation, likely updating too often compared to the frequency of changes you have for `screen.css`. Assets need timestamps to update only when the contents of the assets change. But at least timestamp generation is automatic, so the tradeoff might be okay. I guarantee you won't remember to do it manually every time when needed.

This was a path of compromises. But for a small number of stylesheets and JavaScript sources, I don't think it is all that bad.

## Jekyll with jekyll-minibundle

In order to address the compromises discussed above, you have to use Jekyll with plugins. If you look at the [Jekyll plugin page](https://jekyllrb.com/docs/plugins/) and search for "asset", you will find many plugins written for handling asset bundling.

But for my own preferences, I found most of the existing plugins too complex to use. Neither did like to install a lot of transitive gem dependencies. So, I decided to write my own: [jekyll-minibundle][minibundle]. The plugin has no gem dependencies and it works with any minification tool supporting standard unix input and output.

Let's go through bundling JavaScript sources.

First, you need to choose your minification tool. [UglifyJS2](https://github.com/mishoo/UglifyJS2) is a fast one. Install the tool of your choice and set the path to its executable in `$JEKYLL_MINIBUNDLE_CMD_JS` environment variable. For example:

{% highlight bash %}
$ export JEKYLL_MINIBUNDLE_CMD_JS='/usr/local/share/npm/bin/uglifyjs --'
{% endhighlight %}

Then, install jekyll-minibundle with

{% highlight bash %}
$ gem install jekyll-minibundle
{% endhighlight %}

and place the following line to `_plugins/minibundle.rb`:

{% highlight ruby %}
require 'jekyll/minibundle'
{% endhighlight %}

Place your JavaScript sources to `_assets/scripts` directory in the site project.

In your content file where you want the `<script>` tag to appear, place a `minibundle` [Liquid](https://github.com/Shopify/liquid/wiki/Liquid-for-Designers) block:

{% highlight text %}
{% raw %}
{% minibundle js %}
source_dir: _assets/scripts
destination_path: assets/site
assets:
- scrolling_menu
- program_table
- some_sharing
{% endminibundle %}
{% endraw %}
{% endhighlight %}

Here we specify that the output will be a JavaScript bundle with `scrolling_menu.js`, `program_table.js`, and `some_sharing.js` as input sources from `_assets/scripts` directory. These will be fed to the minifier in the given order. The output will be stored to `_site/assets/site-<md5digest>.js`. The plugin will insert the MD5 digest over the contents of the bundle as the fingerprint to the filename:

{% highlight html %}
<script type="text/javascript" src="assets/site-9a93bf1d8459c9a344a36af564b078a1.js"></script>
{% endhighlight %}

The plugin supports the same mechanism for stylesheets. However, I still like to use Compass for stylesheets, because it has so many other benefits. Because Compass can handle bundling, the plugin only needs to copy the file and add a fingerprint to the filename.

In order to do this, tell git to ignore `_tmp` directory, and configure Compass to place the output to `_tmp/screen.css`. Then, add this line to your content file for including the path to the bundle:

{% highlight html %}
{% raw %}
<link href="{% ministamp _tmp/screen.css assets/screen.css %}" rel="stylesheet" media="screen, projection">
{% endraw %}
{% endhighlight %}

The resulting filename fill have the MD5 digest of the file as the fingerprint:

{% highlight html %}
<link href="assets/screen-2ef6d65c7f031e021a59eb5c1916f2f2.css" rel="stylesheet" media="screen, projection">
{% endhighlight %}

This approach works with [RequireJS optimizer](https://requirejs.org/docs/optimization.html), too!

Both the fingerprinting and asset bundling mechanisms work in Jekyll's auto regeneration mode.

The plugin has one more trick in its sleeves. If you set environment variable `$JEKYLL_MINIBUNDLE_MODE` to `development`, the plugin copies asset files as such to the destination directory, and omits fingerprinting. This is useful in development workflow, where you need the filenames and line numbers of the original asset sources.

I have shown how to automate asset bundling and fingerprinting for cache busting with the plugin. In addition, we have gotten rid off all the compromises we had when using vanilla Jekyll: there is no need to store generated bundle files in git, and asset fingerprints change only when the contents of the assets change.

You can read more about the plugin at its [project page in GitHub][minibundle]. Also, you might be interested in a [site](http://agilejkl.com/) that uses the plugin just like described above.

[^1]: [Google recommends](https://developers.google.com/speed/docs/best-practices/caching#LeverageProxyCaching) cache busting with fingerprinting over using a query parameter. Some old proxy caches do not cache static files at all if the URL contains query parameters.
[^2]: However, you can work around this by generating your site locally and then pushing the generated files to GitHub. Then you're not locked to Jekyll's safe mode.
{: .footnotes}

[minibundle]: https://github.com/tkareine/jekyll-minibundle
