---
layout: post
title: Readable tests
date: 2012-05-06 21:20
published: true
comments: true
---

When I go to explore unfamiliar code, I dig up its tests first. I hope the tests introduce me gently to the purpose of the code, covering the common use cases first, followed by edge conditions and more peculiar cases. I expect tests to reveal me the general behavior and purpose of the code. I don't expect other documentation.[^1]

Later, when I change the code by refactoring and adding new features, I don't expect to modify most of the tests. Finding the place for writing new tests for the added feature is intuitive, because the structure of the tests guides me to proper location.

That's what good tests are like. The implied characteristics are introduction, documentation, and rigidity against changes. The fact that such tests protect you against regression bugs is almost an afterthought.

I think readability is a good term for covering these features. Here's a few guidelines for writing such tests.

## Setup state, make claims about it

Say you have a class or webpage that needs to be tested in certain state. It is important to clearly separate state setup code from test assertions. The former answers to the question _"where are we?"_, while the latter answers to _"what is it like?"_ I use terms _system-under-test_ to denote the state to be tested.

The actual tests are just claims about the state of system-under-test. They cause no changes to the state (no side-effects). I use term _test claim_ for that.

Together, a system-under-test and its test claims form a _"test context"_.

An example of such a test, written in JavaScript and using [Mocha](http://visionmedia.github.com/mocha/) test framework:

<figure>
<figcaption>cart_page_spec.js</figcaption>
{% highlight js %}
{% raw %}
description('shopping cart page', function() {
  description('when page is loaded', function() {  // system-under-test
    before(function(done) {
      App.loadCart(done)
    })

    it('shows checkout button', function() {       // test claim
      expect($('.cart button.checkout')).to.be.visible
    })

    it('has no payment options', function() {
      expect($('.cart .payment .method')).to.be.empty
    })

    // more claims...
  })

  description('when choosing to pay', function() {
    before(function(done) {
      App.loadCart(function() {
        TestHelpers.clickCheckoutButton(done)
      })
    })

    it('hides checkout button', function() {
      expect($('.cart button.checkout')).to.be.hidden
    })

    it('has payment options', function() {
      expect($('.cart .payment .method')).not.to.be.empty
    })

    // more claims...
  })
})
{% endraw %}
{% endhighlight %}
</figure>

Prepare the states of system-under-tests (`describe` blocks) in their setup codes (`before` blocks in the example above). Make sure to reset everything the tests depend on. This ensures that each system-under-test gets a fresh start, avoiding state leaks from others.

For cleaning your tracks, you could have teardown code to be run after the tests of a specific test context. It is best to avoid teardowns, however, because they are easy to forget to write. It is better to write your setup code so that it ensures the world is in proper state for your tests to run.

Try to separate tests so that each assertion makes a specific claim. You can use multiple assertions for a specific claim, however. Custom matchers help you with this, especially if you test a specific thing more than once.

When you write your tests like this, you gain two benefits: you can run your tests in any order, and you get the choice to run the setup code for a system-under-test only once. For instance, Ruby's [MiniTest](https://github.com/seattlerb/minitest) runs tests in random order, helping to catch tests that have side-effects in their claims. Mocha has `before` block for running setup code for a system-under-test only once (`beforeEach` runs setup for each claim). This speeds up test execution.

In addition, prefer active clauses for describing a system-under-test and its claims. An active clause clearly identifies that the claim is about the system-under-test. Also, words _should_ and _must_ are just noise: compare _"it has payment options"_ against _"it should have payment options"_.

## Test state transitions

Note that the states of the two test contexts in `cart_page_spec.js` (above) differ only by the clicking of the checkout button. Why didn't I just take the state of the first test context and modify that for the purposes of the latter test context? I chose to reset the world between them, because it gives us orthogonality (state changes in test context A do not get reflected in test context B). After a few state transitions, it becomes hard to keep track of the state changes happened so far. Ideally, you want to see the whole state of the current system-under-test in one glimpse. You achieve that by initializing the whole state in the setup block of the system-under-test.

Now I can also reorder test contexts as I like. I can move the most common cases to the top of the test file and edge cases to the bottom.

But sometimes it is useful to have state transitions between test contexts. For example, such a case might occur for input validation before checkout confirmation:

<figure>
<figcaption>cart_page_validation_spec.js</figcaption>
{% highlight js %}
{% raw %}
description('cart page validation', function() {
  description('when entering invalid credit card number', function()
    before(function(done) {
      App.loadCart(function() {
        TestHelpers.clickCheckoutButton(function() {
          $('.cart .payment .creditcard .number').val('lolbal')
          done()
        })
      })
    })

    it('highlights credit card number as invalid', function() {
      expect($('.cart .payment .creditcard .number')).hasClass('invalid')).to.equal(true)
    })

    it('disables confirmation', function() {
      expect($('.cart button.confirm')).to.be.disabled
    })

    description('and then entering valid credit card number', function()
      before(function(done) {
        $('.cart .payment .creditcard .number').val('4012888888881881')  // not mine, mind you
        done()
      })

      it('does not highlight credit card number as invalid', function() {
        expect($('.cart .payment .creditcard .number')).hasClass('invalid')).to.equal(false)
      })

      it('enables confirmation', function() {
        expect($('.cart .payment button.confirm')).to.be.enabled
      })
    })
  })
})
{% endraw %}
{% endhighlight %}
</figure>

Essentially, here you test that validation mechanism handles the case of revalidating invalid input.

I prefer to nest test contexts that depend on earlier ones. That communicates the intent of dependence clearly. It also keeps the number of nestings in check, because three or more nesting levels makes the test context difficult to read as whole.

## Group tests by semantics

If a set of tests are similar in semantics, you should group them together so that it is easy so see the difference between them:

<figure>
<figcaption>date_format_spec.js</figcaption>
{% highlight js %}
{% raw %}
describe('date formatting', function() {
  _.each([
    { desc: 'non-date string', args: ['lolbal'] },
    { desc: 'empty object',    args: [{}] },
    { desc: 'number':          args: [1] }
  ], function(spec) {
    it('throws exception if given ' + spec.desc, function() {
      expect(function() { Format.date.apply(null, spec.args) }).to.throw(/^Invalid date: /)
    })
  })
})
{% endraw %}
{% endhighlight %}
</figure>

Those tests were about input argument validation. I would separate them from testing the happy path:

<figure>
<figcaption>date_format_spec.js (continued)</figcaption>
{% highlight js %}
{% raw %}
describe('date formatting', function() {
  _.each([
   { desc: 'Date object, with long weekday',                  args: [new Date(2010, 2, 2), {weekday: 'long'}],  expected: 'Wednesday May 2, 2010' },
   { desc: 'Date object, with short weekday',                 args: [new Date(2010, 2, 2), {weekday: 'short'}], expected: 'Wed May 2, 2010' },
   { desc: 'Date object, without weekday',                    args: [new Date(2010, 2, 2), {weekday: false}],   expected: 'May 2, 2010' },
   { desc: 'String presentation of date, with long weekday',  args: ['2010-03-02',         {weekday: 'long'}],  expected: 'Wednesday May 2, 2010' },
   { desc: 'String presentation of date, with short weekday', args: ['2010-03-02',         {weekday: 'short'}], expected: 'Wed May 2, 2010' },
   { desc: 'String presentation of date, without weekday',    args: ['2010-03-02',         {weekday: false}],   expected: 'May 2, 2010' }
  ], function(spec) {
    it('formats ' + spec.desc, function() {
      expect(Format.date.apply(null, spec.args)).to.equal(spec.expected)
    })
  })

  // input argument validation tests are here
})
{% endraw %}
{% endhighlight %}
</figure>

By putting the expected input and output of each test case to its own line, possibly with a short description how the case differs from others, you can easily compare them and spot missing tests for edge conditions.

When you adhere to writing a test claim for each test case, it becomes easy to see which particular test fails when you run the test suite.

If your test framework of choice has expression syntax for test claim definition, you can avoid repeating the boilerplate code for each test claim. First, think a group of test cases and see what is common to them. Then, put the varying parts of the cases to a collection. Lastly, iterate the collection so that the body of the iteration becomes the test claim definition. This is what I did in the examples above.

I think this improves readability a lot, because now I can put each test case to its own line, without the boilerplate code between them. This is a manifestation of [Don't Repeat Yourself](http://en.wikipedia.org/wiki/Don't_repeat_yourself) (DRY) principle.

But don't take DRY to the extreme. You should aim for making tests readable, not as short as possible. This is why I separated the group of happy path tests from the group of argument validation tests.

## On test abstraction levels

Choosing the most suitable abstraction level for testing your code is hard. There are many characteristics at play, some of which are at odds with each other: coverage, simplicity, execution speed, and maintenance. For example, if you choose the application user interface as the abstraction level for all your tests, you gain easier test code maintenance (architectural refactorings do not cause changes to tests), but lose in execution speed (all the application components will be used).

Of course, it is about balance. Choose the characteristics that you desire most for testing a particural part of your application.

I'd write tests for a date formatting component at the unit level, like in `date_format_spec.js`. It makes no sense to launch the whole application in order to test dates get formatted as expected: the user interface might change during development, and covering all the inputs makes the execution speed slow for such a low level component.

On the other hand, if I had an application with Model-View-Controller architecture, I wouldn't write tests for controllers, models, and views alone. Writing tests for a specific controller only would require using dummy implementations of associated models and views. Maintaining tests across refactorings would be laborious, because changes in the interfaces of controllers, models, or views would propagate to many tests. Instead, I would raise the abstraction level and write tests at the functional level. In `cart_page_spec.js`, the web page with the related behavior is the functional level.

You need tests to have confidence that everything works as expected. Isolate your tests from external interfaces of which output you cannot control. Otherwise, you lose that confidence. You can use fake or stub implementations for external interfaces. A fake implementation is easier to put in place if you first abstract the external interface behind your own component:

<figure>
<figcaption>rest.js</figcaption>
{% highlight js %}
{% raw %}
define(['environment'], function(environment) {
  if (environment.production) {
    return createProductionAPI()
  } else {
    return createTestAPI()
  }

  function createProductionAPI() {
    return {
      postCheckout: function(callback) { $.ajax(/*...*/).success(callback) }
    }
  }

  function createTestAPI() {
    return {
      postCheckout: function(callback) { callback(stubs.postCheckoutResponse) }
    }
  }
})
{% endraw %}
{% endhighlight %}
</figure>

Here I have a component of the frontend part of a web application, abstracting the REST API of the backend part. All the REST API calls in the frontend go through this component. In test environment, the component returns canned responses without actually sending requests. It is not a big leap to change the dummy response to fit a particular test's needs, either.

I dislike using mocks in tests and guiding code design. They end up being a maintenance burden everywhere I've worked with them.

## Summary

Like good code, writing good tests is hard and takes many iterations. I use these guidelines to steer me when I write tests, but I wouldn't hesitate to drop following a particular guideline if it makes the end result more readable.

[^1]: The emphasis is on _expectation_. For example, a hack in the middle of self-documenting code is unexpected. Thus, you should document any unexpected code. You can even isolate the hack to its own function with a descriptive name.
{: .footnotes}
