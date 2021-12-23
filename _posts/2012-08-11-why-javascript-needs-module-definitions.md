---
layout: post
title: Why JavaScript needs module definitions
date: 2012-08-11 21:44
published: true
---

Me and my colleague [Eero Anttila](https://twitter.com/eeroan) are working in a project where we are using Eero's [Continuous Calendar plugin for jQuery](https://github.com/reaktor/jquery-continuous-calendar) in the frontend. The plugin utilizes a set of date handling functions for formatting, parsing, and so on. The functions are grouped into objects (`DateTime`, `DateFormat`, `DateRange`, and `Locale`) which are injected into the global window object. A very useful aspect of the functions is that they are immutable. For example, `dateTimeObj.firstDateOfMonth()` returns a new instance of `DateTime`.

We found out that we could benefit from these functions in the application generally, needing date handling also elsewhere than in the calendar component.

Our frontend loads with [RequireJS](https://requirejs.org/), and we've been happy composing our application from small modules. Now, in order to get access to the date handling functions in our modules, we need either to ensure that Continuous Calendar gets loaded before our application's modules, or we need to introduce optional AMD support for the date functions. Because it doesn't make sense to load the whole Continuous Calendar just to get access to the functions, we decided add AMD support to them.

The AMD community has devised common patterns for making a JavaScript module[^1] to work simultaneously with AMD loaders, CommonJS, and traditional browser script loading. They are called as [Universal Module Definition](https://github.com/umdjs/umd) (UMD) patterns. Essentially, we are talking about inserting bootstrap code in the beginning of a module's source file.

Here's an example how `DateTime` global object supports AMD loaders and traditional browser script loading:

<figure>
<figcaption>DateTime.js</figcaption>
{% highlight js %}
{% raw %}
(function(root, factory) {
  if (typeof define === 'function' && define.amd) {
    // AMD loading: define module named "DateTime" with no dependencies
    // and build it
    define('DateTime', [], factory)
  } else {
    // traditional browser loading: build DateTime object without
    // dependencies and inject it into window object
    root.DateTime = factory()
  }
}(this, function() {
  // above, `this` refers to window, the second argument is the factory
  // function

  // build DateTime and return it
  var DateTime = {}
  return DateTime
})
{% endraw %}
{% endhighlight %}
</figure>

`DateTime` factory executes without external dependencies. This is communicated in the code by `define` call having empty array as its second argument for the AMD case, and the factory function call having no arguments in the traditional browser loading case.

However, for building `DateRange`, we need jQuery, `DateFormat`, and `DateTime`:

<figure>
<figcaption>DateRange.js</figcaption>
{% highlight js %}
{% raw %}
(function(root, factory) {
  if (typeof define === 'function' && define.amd) {
    // AMD loading: define module named "DateRange" with dependencies
    // and build it
    define('DateRange', ['jquery', 'DateFormat', 'DateTime'], factory)
  } else {
    // traditional browser loading: build DateRange object with
    // dependencies and inject it into window object
    root.DateTime = factory(root.jQuery, root.DateFormat, root.DateTime)
  }
}(this, function($, DateFormat, DateTime) {
  // above, `this` refers to window, the second argument is the factory
  // function with dependencies

  // build DateFormat with the help of $, DateFormat, and DateTime, and
  // return it
  var DateRange = {}
  return DateRange
})
{% endraw %}
{% endhighlight %}
</figure>

What happens here? With AMD loader, such as RequireJS, the `if` block of the bootstrap code executes. There we call `define`, specifying a module named `DateRange` (the first argument), needing jQuery, `DateFormat`, and `DateTime` as its dependencies (the array as the second argument). Eventually, after loading all the specified dependencies, the AMD loader calls the factory function (the third argument) with the dependencies as the arguments to the function.

If were are not using an AMD loader, but loading the script in the browser traditionally with `<script>` tag, the `else` block of the bootstrap applies. Before that, however, we have to ensure that we load modules in such an order that the dependencies of each module exist at the evaluation time of the module. That can be satisfied by careful organization of `<script>` tags or bundling the modules in a single source file. In this case, jQuery, `DateFormat.js`, and `DateTime.js` must be loaded before loading `DateRange.js`. When the browser evaluates `DateRange.js`, it calls the factory function with dependencies fetched from the global window object.

I really like the factory function spelling out the dependencies as parameters to the function.[^2] We get to know the dependencies just by looking at the function signature. In addition, we have located the change made to the global window object (if any) in one predefined place (the `else` block). If we're using an AMD loader, we avoid polluting the global window object altogether!

The UMD pattern drives the module author to make at most one addition to the global window object. That's a great guideline for organizing modules.

Of course, it is up to the module author to play by these rules. There's nothing preventing the factory function from referring to the window object for other dependencies or polluting the global window object. But why would the author want to surprise the users of the module?

[^1]: _Module_ meaning a JavaScript source file defining functionality that can be used elsewhere.

[^2]: The factory function is an application of [Module Pattern with import mixins](https://addyosmani.com/resources/essentialjsdesignpatterns/book/#modulepatternjavascript).
