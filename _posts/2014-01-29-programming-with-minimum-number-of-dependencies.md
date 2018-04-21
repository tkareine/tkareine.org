---
layout: post
title: Programming with minimum number of dependencies
date: 2014-01-29T21:40+02
published: true
---

When you're concentrating on the essentials of your current programming task, you'll want to avoid sidetracks as much as possible. Encounter a tricky subtask and you'll start searching the web for a 3rd party code solving it for you. When you're introducing additional dependencies without much further thought, you're not considering their burden on maintenance.

How often do you check for outdated dependencies (and actually do upgrade, doing all the required client side changes)? Do you have local modifications to any of the dependencies (I hope not, but if you do, how do you track the modifications in order to reapply them)? Once you've updated the dependencies, how do you make sure your code still works as intended (how comprehensive are your tests)? And then there's the hell of library incompatibilities.

You can think that dependencies are like loans you'll have to take care of for the whole lifespan of the project. The interest rate varies for each dependency, so it pays off to justify having each of them.

Sometimes, you can go a surprisingly long way without additional dependencies. I take occasional delight in programming with as few library dependencies as possible.[^1] It's fun for the challenge, and it makes you think about your design.

Recently, I needed a program to fix outdated identifiers in my customer's MongoDB documents. These identifiers referred to documents in external service A. Each identifier was paired with another identifier for external service B, and luckily the latter ones were still correct. By querying the REST API of service A with service B identifier, I could find out the correct service A identifier and update the document in MongoDB.

Because this was for an occasional maintenance need, I decided not to include the program as part of the application's code. A command line tool felt better. Observing that both MongoDB and service A's REST API speak JSON, all I essentially needed was the ability to communicate and handle JSON. For the REST API, the communication happens over socket connection. For MongoDB, you could use a driver for your programming language to talk with the database. But there was an alternative: because the query and insert operations the tool needed were simple, I could attach the tool to Mongo's shell with a Unix pipe, evaluating database commands in JavaScript and reading the results as JSON via the pipe.

I went to write the tool in Ruby. It turned out that I didn't need external libraries at all. Ruby's standard library has a decent (though verbose to use) HTTP library, a JSON parser and generator, and a great set of tools to work with processes and IO (just take a look at how versatile [Kernel.spawn](https://ruby-doc.org/core-2.1.0/Kernel.html#method-i-spawn) is!) I embedded the small amount of JavaScript needed for database operations straight into the program. User input escaping within the JavaScript commands was easy: just encode the input into JSON.

Because there are no 3rd party libraries, there's no need for dependency management. The tool is ready to use as long as you've Ruby installed.[^2]

To demonstrate the implementation, I wrote a similar [toy program](https://gist.github.com/tkareine/8693458). This one is for searching term definitions: if there are definitions matching the search term in MongoDB, the program shows them. Otherwise, the program searches the definition from [DuckDuckGo's Instant Answer API](https://duckduckgo.com/api), stores the new definition to MongoDB, and shows it.

Healthy dependency management balances the risks and benefits. This article is not about doing it all by yourself, avoiding dependencies for the sake of it. Instead, you should consider each dependency, think what you benefit from it, and how it fits to the whole project.

[^1]: [jekyll-minibundle](https://github.com/tkareine/jekyll-minibundle) is an example of this.
[^2]: Ruby belongs to the customer's development environment already, so it's not a new dependency by itself.
{: .footnotes}
