---
layout: post
title: Lightweight Node.js version switching
date: 2018-10-10T01:05+03
published: true
---

Recently, I've been paying attention to the time it takes my shell's
init script to complete. Bash is notoriously slow, but since it's
popular in scripting use, I keep using it. This leaves me to optimize my
`~/.bashrc`.

I program with Node.js frequently, so a Node.js version manager is an
essential tool. Upon investigating the execution time of my `.bashrc`, I
found that loading [nvm] takes a lot of time:

<figure>
{% highlight bash %}
{% raw %}
$ ls ~/.nvm/versions/node
v10.11.0	v8.12.0		v9.11.2

$ export NVM_DIR="$HOME/.nvm"

$ time source "$HOME/brew/opt/nvm/nvm.sh"

real	0m0.397s
user	0m0.270s
sys	0m0.134s

$ nvm --version
0.33.11
{% endraw %}
{% endhighlight %}
</figure>

400 ms for sourcing `nvm.sh` is a way too big share of the time budget
I'd like to allocate for starting Bash in interactive mode. It's a pity,
because `nvm` is a quite nice tool.

An alternative for `nvm` is [nodenv]:

<figure>
{% highlight bash %}
{% raw %}
$ ls ~/.nodenv/versions
10.11.0	8.12.0	9.11.2

$ time eval "$(~/brew/bin/nodenv init -)"

real	0m0.070s
user	0m0.034s
sys	0m0.034s

$ nodenv --version
nodenv 1.1.2
{% endraw %}
{% endhighlight %}
</figure>

I can manage with 70 ms. This is the tool I chose to use as my Node.js
version manager for a while. But because `nodenv` utilizes shims to wrap
the executables of the selected Node.js version, a couple of problems
arise. The first is that after installing a new executable from global
npm package, you must remember to run `nodenv rehash` to rebuild the
shims. Otherwise you can't run the executable. The second is that you
lose access to the manual pages of the wrapped executables: a shim is an
indirection for the actual executable, causing `man`'s manual page
search to miss the page. A demonstration of the problems:

<figure>
{% highlight bash %}
{% raw %}
$ npm ls -g --depth=0
/Users/tkareine/.nodenv/versions/10.11.0/lib
`-- npm@6.4.1

$ npm install -g marked
/Users/tkareine/.nodenv/versions/10.11.0/bin/marked -> /Users/tkareine/.nodenv/versions/10.11.0/lib/node_modules/marked/bin/marked
+ marked@0.5.1
added 1 package from 1 contributor in 0.586s

$ command -v marked

$ nodenv rehash

$ command -v marked
/Users/tkareine/.nodenv/shims/marked

$ man -w node
No manual entry for node

$ man -w marked
No manual entry for marked
{% endraw %}
{% endhighlight %}
</figure>

I keep forgetting to run `nodenv rehash` and I do would like to access
the manual pages of the executables of the selected Node.js version.

`nvm` and `nodenv` have a lot of features. While they are useful in some
scenarios, such as continuous integration setups, I'd be satisfied with
less in my development environment. The ability to install specific
Node.js versions and to switch between them easily, independently per
shell session, would be enough.

In the Ruby community, [ruby-install] and [chruby] tools provide just
these features, and nothing more. The former is for installing Rubies
and the latter for switching between them. What's great about this
arrangement of separate tools is that the switcher, `chruby`, is very
lightweight.

[node-build], part of `nodenv` project, is a dedicated Node.js
installer. It checks the digest of the downloaded Node.js package and
allows you to unpack it to any directory. This is good and I'll keep
using it.

For the version switcher, I didn't find anything I liked. [sh-chnode] is
written in the same spirit as `chruby`, but includes some design
decisions I didn't like personally.

I ended up writing my own version switcher, even though there's already
so many of them. But this one is fast to load, does one thing well, and
is suitable for me. :) Naming is hard, so I just call it `chnode`. Let's
see it in action:

<figure>
{% highlight bash %}
{% raw %}
$ ls ~/.nodes
node-10.11.0	node-8.12.0	node-9.11.2

$ time source ~/brew/opt/chnode/share/chnode/chnode.sh

real	0m0.007s
user	0m0.004s
sys	0m0.003s

$ chnode node-10

$ chnode
 * node-10.11.0
   node-8.12.0
   node-9.11.2

$ npm ls -g --depth=0
/Users/tkareine/.nodes/node-10.11.0/lib
└── npm@6.4.1

$ command -v marked
/Users/tkareine/.nodes/node-10.11.0/bin/marked

$ man -w node
/Users/tkareine/.nodes/node-10.11.0/share/man/man1/node.1

$ man -w marked
/Users/tkareine/.nodes/node-10.11.0/share/man/man1/marked.1

$ chnode --version
chnode: 0.2.0
{% endraw %}
{% endhighlight %}
</figure>

For me, [chnode] is the tool comparable to `chruby` for Node.js
versions. Like `chruby`, the primary mechanism of `chnode` is to modify
the `PATH` environment variable to include the path to the `bin`
subdirectory of the selected Node.js version. But unlike `chruby`,
`chnode` does not modify any Node.js specific environment variable
(there's no need).

I didn't implement auto-switching to `chnode`. The feature would switch
Node.js version to the version specified in the `.node-version` file if
the current working directory, or its parent, would have the file. You
might put such a file at a project's root directory. `chruby` has the
feature, but because I don't use it, I dropped it.

`chnode` supports [GNU Bash] and [Zsh], has good test coverage, and
allows you to display the selected Node.js version in the shell prompt
with ease. It's MIT licensed. See the [README][chnode-README] for more.

Finally, the total execution time of initializing my [Bash
setup][my-bashrc] in interactive mode, including selecting a Node.js
version with `chnode`:

<figure>
{% highlight bash %}
{% raw %}
$ time bash -i -c true

real	0m0.375s
user	0m0.228s
sys	0m0.075s
{% endraw %}
{% endhighlight %}
</figure>

[GNU Bash]: https://www.gnu.org/software/bash/
[Zsh]: https://www.zsh.org/
[chnode-README]: https://github.com/tkareine/chnode#readme
[chnode]: https://github.com/tkareine/chnode
[chruby]: https://github.com/postmodern/chruby
[my-bashrc]: https://github.com/tkareine/dotfiles/blob/master/.bashrc
[node-build]: https://github.com/nodenv/node-build
[nodenv]: https://github.com/nodenv/nodenv
[nvm]: https://github.com/creationix/nvm
[ruby-install]: https://github.com/postmodern/ruby-install
[sh-chnode]: https://github.com/moll/sh-chnode
