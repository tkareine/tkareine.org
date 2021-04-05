---
layout: post
title: Standalone Git branch from subdirectory
date: 2021-04-05T15:00+03
published: true
---

Imagine you have a subdirectory of generated files and you want to store
them into Git as a standalone (orphan) branch. For example, you have
generated html files and associated CSS and JavaScript assets, with the
intention of publishing them as a [GitHub Pages
site](https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages#publishing-sources-for-github-pages-sites)
from the `gh-pages` Git branch of the project. Git's plumbing commands
allow automating storing the generated files into the `gh-pages` branch,
recreating the branch each time you publish. Here's a Bash oneliner to
do that:

{% highlight bash %}
{% raw %}
git add --force build \
  && git update-ref refs/heads/gh-pages "$(git commit-tree -m 'Generated build' "$(git write-tree --prefix=build/)")" \
  && git reset
{% endraw %}
{% endhighlight %}

For that Bash command list, I presume that

* the generated files are already in the `build` subdirectory,
* you include `build` in the `.gitignore` file of the project, and
* the Git index (staging area) is clear currently.

Let's go over the parts of the command list.

## 1. Stage the generated files into Git index

{% highlight bash %}
{% raw %}
git add --force build
{% endraw %}
{% endhighlight %}

I'll use the `--force` switch to allow Git to add ignored files.

## 2. Create a Git tree object from the current index

{% highlight bash %}
{% raw %}
git write-tree --prefix=build/
{% endraw %}
{% endhighlight %}

A Git tree object groups Git objects and stores the paths of the
objects. The tree object will be used to create a commit object in the
next step.

The `--prefix=build/` option makes Git to treat the `build` directory as
the root directory for the files within the directory. For example, a
file with the `build/dir/index.html` path gets recorded with the
`dir/index.html` path inside the tree object.

The command prints the name of the tree object to stdout (I'll use the
`$tree` shell variable for that in the next step).

## 3. Create a Git commit object from the tree object

{% highlight bash %}
{% raw %}
git commit-tree -m 'Generated build' $tree
{% endraw %}
{% endhighlight %}

The command prints the commit object id to stdout (let's put it into the
`$commit` variable).

## 4. Set a branch to refer to the commit object

{% highlight bash %}
{% raw %}
git update-ref refs/heads/gh-pages $commit
{% endraw %}
{% endhighlight %}

This overwrites the `gh-pages` branch, if it exists already.

## 5. Reset index to the current HEAD

{% highlight bash %}
{% raw %}
git reset
{% endraw %}
{% endhighlight %}

This needs to be done for clearing the index.

Now the target branch, `gh-pages`, contains a single orphaned commit,
using the `build` subdirectory as the root directory of the files.

If you want to, you can store the previous commit of the `gh-pages`
branch as the parent of the next commit, but then there are edge cases
to consider: you'll need to detect if the target branch exists already
and whether the new contents of the `build` directory differ between the
next and the previous commit (it doesn't make sense to create a new
commit with an empty diff compared to the parent commit). Covering them
would require elaborate scripting compared to the Bash oneliner I went
through.

As a real example, the [Hacker's Tiny Slide
Deck](https://github.com/tkareine/hackers-tiny-slide-deck) project uses
this trick in storing the generated slides (an html file) and the
JavaScript bundle of the project into the `gh-pages` branch of the
project, from where GitHub Pages publishes them. The relevant Git
commands are in
[package.json](https://github.com/tkareine/hackers-tiny-slide-deck/blob/044da2e4d28eaca5db554a0d6f3c41c6d4e905ea/package.json#L33).

Here's a screenshot of [GitUp](https://gitup.co/) app's map view of the
Git repository of Hacker's Tiny Slide Deck, showing what the standalone
`gh-pages` branch looks like:

<img src="{{ "/" | relative_url }}{% ministamp _assets/images/gh-pages-gitup-map-view.png assets/images/gh-pages-gitup-map-view.png %}" alt="A map view from the GitUp app showing the master and gh-pages branches" title="A map view from the GitUp app" width="195" height="258" />

The chapter titled [Git
Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) from
the Pro Git book is a great resource for learning more about Git
internals.
