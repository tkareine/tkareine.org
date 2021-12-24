---
layout: post
title: Suppressing duplicate requests in web services
date: 2021-12-24T11:50+02
published: true
---

Suppressing duplicate request processing prevents some forms of data
corruption, such as data duplication and lost data. Achieving
suppression together with client retries establishes *exactly-once*
request processing semantics in the system.[^1] In this article, I
present an imaginary web service built on microservice style design,
inspect that and its clients together as a system, define the duplicate
request processing problem, and the general solution to it. Finally,
I'll show one possible way to implement the solution.

The microservices involved use synchronous requests to pull and push
data so that any part of the overall state is managed centrally in one
place (the conventional approach to microservices communicating with the
REST/RPC/GraphQL protocols).

## Web service as a system

The imaginary web service manages education related entities: students,
employees, facilities, and so on.[^2] Typical management operations are
creating, reading, updating, and deleting entities. Here, we focus on
employees, their employment contracts, and related information.
Collectively, we'll call those as "staff" entities and dedicate an
application named "Staff service" for processing them. There's also an
identity provider (IdP) service that is used to authenticate both
students and employees. Because the IdP is provided as an external
service, we have another application, called "Users service", that maps
our user identifiers to the IdP's user identifiers. Finally, an API
gateway node serves as the reverse HTTP proxy for all inbound traffic to
APIs.

Here's a diagram of the web service from the viewpoint of the Staff API:

<img src="{{ "/" | relative_url }}{% ministamp _assets/images/imaginary-web-service-components.svg assets/images/imaginary-web-service-components.svg %}" alt="An imaginary web service comprising of the client, three internal services, and one external service" title="An imaginary web service" width="100%" style="max-width: 500px;" />

Because we need to allow employees to login to the service, the Staff
service needs to associate a user entity for an employee. This happens
by calling the API of the Users service, which hides the complexity of
the IdP's User management API.

Looking at the diagram, we can identify the following components and
group them:

1. The servers behind the public APIs: the API gateway, the IdP service,
   microservices, and databases.

2. The clients accessing the public APIs: browsers running webapps and
   integration clients that synchronize education related entities
   between this system and another.

3. Network components: the internet where the clients connect from, the
   private network of the web service, and virtual networks within the
   hosts that run microservices inside containers.

The operations of the client-server APIs the microservers expose both
internally and externally can be grouped into:

1. Queries, which are for reading data. A query request does not inflict
   any externally visible change to state of the server. Examples are
   the HTTP GET and HEAD methods and the query operations of GraphQL.

2. Mutation, which are for writing data and triggering effects. A
   mutation request causes externally visible change to the state of the
   server. Examples are the HTTP POST/PUT/PATCH/DELETE methods and the
   mutation operations of GraphQL.

Considering some of the typical technologies we use building web
services like this, we'll likely use TCP as the connection-oriented
protocol for transferring data between hosts. When two hosts have agreed
to establish a TCP session, the protocol protects against packet
duplication with sequence numbers and acknowledgements, and data
integrity with checksums on IP packets. But a TCP session protects data
transfer only between two hosts. For instance, creating a new employee
involves adding a new user entity to the IdP service. When looking at
the communication path of that API operation, there will be four
separate TCP sessions (the numbers in red circles in the previous
diagram):

1. Between the browser and the API gateway: call the public Staff API to
   create an employee

2. Between the API gateway and the Staff service: forward the call to
   the microservice

3. Between the Staff service and the Users service: call the Users API
   to create a new user entity to associate with the employee

4. Between the Users service and the IdP service: call the User
   management API to create the user entity to the IdP in order to allow
   the employee to login, and provide user identifier mapping between
   systems

Another technology in general use is database transactions, especially
for SQL databases which usually come with the [ACID][acid] properties. A
connection from the application server to the database sits on top of
TCP usually, and the database server guarantees that if the transaction
commits successfully, the app's modifications to the data leave the
database in a consistent state. It's another safeguard against data
corruption, but again between two components only. The creation of a new
employee in our web service involves two SQL transactions (the letters
in gray circles in the diagram above):

1. Staff service: add a row for the new employee

2. Users service: add a row for the new user

Turns out that any technology protecting only parts of the whole
communications path is not sufficient in protecting the whole
path. Let's look at some possible problems.

## Examples of problems caused by not protecting the whole communications path

*Broken data integrity*: Even though a TCP session uses checksums to
ensure two hosts transfer data unchanged over the communications
channel, it does not guard the application server from reading data
received or writing data to be sent via malfunctioning hardware
memory. Data corruption can occur.

*Broken data confidentiality*: A client that serves to integrate an
external and our imaginary web service sends the login password of the
employee along with the data in the request to create the employee to
the Staff API. TLS does protect the communication channel between any
two hosts with encryption, but it does not prevent the application
server from reading the password in clear text. Any process in the
server can read the password, actually.

*Broken duplicate request processing suppression*: A client requesting
to create a new employee using the Staff API encounters either a timeout
or receives a timeout related error response. What happens if the client
attempts to send the request again? From the client's perspective, any
of the following might have happened to the original request:

1. The API gateway received the request, but the gateway crashed and
   never sent the response to the client. The gateway might or might not
   have forwarded the request to the Staff service before crashing.

2. The API gateway received the request, but the Staff service is down,
   not accepting connections. The timeout for the expectation to receive
   data in the client is lower than in the API gateway for the overall
   connection attempts to the Staff service, and so the client closes
   this request attempt.

3. The Staff service received the request and used an SQL transaction to
   encompass sending its own request to the Users API for creating the
   associated user entity. The Staff service received the success
   response from the Users service, updated the employee row, and
   committed the SQL transaction. But the Staff service crashed just
   before responding back to the API gateway. Eventually, the gateway
   times out the connection to the Staff service and sends a *504
   Gateway Timeout* error response to the client.

4. Like previously, but just after opening the encompassing SQL
   transaction, the Staff service enters stop-the-world garbage
   collection phase, which effectively pauses the whole service. This
   makes the API gateway respond with *504 Gateway Timeout* to the
   client. After the garbage collection phase is over, the service
   continues processing like nothing would have happened.

5. Like cases 2, 3, or 4, but it was the Users service that failed.

All the five situations above are different forms of timeouts. In cases
3 and 4, the request was processed completely, but the client does not
get to know about it. If the client retries the original request, there
could be 0, 1, or 2 employees in the system. Here we presume, for the
sake of general argument, that the employee data the client sends does
not contain data that has uniqueness constraints (the username attribute
might be such, for example). It's clear that TCP's data correctness
mechanisms alone cannot guarantee that a request traversed over many
hops would be processed only once.

In case 5, the system was left in an illegal state: there's a user
entity in the IdP and a corresponding identifier mapping in the Users
service, but no associated employee entity in the Staff service. This
demonstrates that database transactions alone cannot guarantee that the
overall system was left in correct state.

Both TCP and database transactions helped to ensure data correctness
between two components, but they didn't guarantee that the overall
system was left in correct state.

Even though I'm focusing on the duplicate request processing suppression
problem in this article, the general solution to all of them is the
same.

## The end-to-end argument

The *end-to-end argument* is a design principle that guides where to
locate the implementation of a *function* for the benefit of a
distributed system. The function in question can be duplicate message
suppression, data integrity, or data confidentiality, for
example. Saltzer, Reed, and Clark [articulated the
argument][end-to-end-arguments-in-system-design] in 1981, and it goes as
follows:

> The function in question can completely and correctly be implemented
> only with the knowledge and help of the application standing at the
> end points of the communication system. Therefore, providing that
> questioned function as a feature of the communication system itself is
> not possible. (Sometimes an incomplete version of the function
> provided by the communication system may be useful as a performance
> enhancement.)

Put other way, correct implementation of the function requires that the
client and the server at the ends of the communication path work
together in achieving the function.

Going back to the earlier example problems, a way to guarantee data
integrity is to make the client to compute a hash over the request's
payload data and to include the hash in the request. The application
servers, upon receiving the request, compute the hash and compare it to
the expected one in the request. If the computed hash equals the
expected hash, the server may process the request.

Data confidentiality can be achieved by using end-to-end encryption.

There's no established way to suppress duplicate request processing. In
the [Designing Data-Intensive
Applications][designing-data-intensive-applications] book, Martin
Kleppmann describes one approach. The system must be designed so that it
holds up exactly-once semantics for processing requests, and an
effective way to achieve this is to make operations *idempotent*.[^3]

Considering our earlier grouping of the operations of client-server APIs
into queries and mutations, we can ensure that queries are idempotent by
making sure they never affect state so that possible change in state is
visible to the client (for instance, request logging would be
permitted). Usually this is trivial to achieve with read database
queries if returning the data based on the current database state is
enough. This does forgo the ability for the client to request data about
the state in earlier moments, however; solving that would require
storing versioned data snapshots in the database.

For mutations, Kleppmann proposes to include an operation identifier in
the request originating from the client. Upon receiving the request, the
server can query its database to see if an operation with this
identifier has been processed already. The server processes the request
only if there's no existing row with the identifier. When the processing
is about to finish, server adds a row indicating that the request has
been completed. The operation identifier can either be generated or
derived from the payload, whichever is more convenient for the business
logic.

Applying Kleppmann's approach to suppress duplicate request processing,
in the context of the imaginary web service presented earlier, is the
last part of this article.

## Applying duplicate request suppression

Let's establish API design principles to support idempotency. I've
chosen to use GraphQL as the application-level protocol here, but the
principles are the same regardless of using another protocol, such as
REST or RPC.

1. GraphQL query operations return the data based on the current state
   of the server. It's expected that a query with certain input
   requested over time may return different data as output, reflecting
   changes in the current state of the service by mutations.

2. All GraphQL mutation operations must include operation identifier as
   input, in a parameter called `transactionId`. Two requests with the
   same `transactionId` value indicate that the requests are
   duplicates. The client must generate the identifier as a random
   [UUIDv4][uuid] value.

3. The server must apply the operation only once for a particular
   `transactionId` value, the first time the server receives a request
   with a `transactionId` it hasn't processed yet.

4. The response to a GraphQL mutation operation with a particular
   `transactionId` value must always produce the same logical output. If
   the server processed the mutation successfully, the response must
   signal success for all requests having the same `transactionId`
   value. Similarly, if the server completed processing with a failure,
   all the responses to the same `transactionId` must signal that
   failure. In particular, a success response may contain output
   reflecting the current state of the data, but that output might be
   different when client requests the same mutation again (another
   mutation may have changed the data).

5. The same `transactionId` value must be passed as-is to dependent
   services.

Except for the first design principle, which should be self-sufficient,
I'll go through them one-by-one.

The 2nd principle enables distinguishing between two requests and to
tell whether they are for the same purpose, even if the input payload
would be otherwise be the same. This allows creating different user
entities sharing their name, for instance.

As an example, here's the GraphQL mutation to create a new employee in
the Staff API:

{% highlight graphql %}
{% raw %}
mutation {
  createEmployee(
    input: {
      transactionId: "addb372c-046f-43e8-c91f-1df1a30caaa1"
      data: {
        firstName: "Albert"
        lastName: "Vesker"
        employment: {
          startsAt: "2021-08-12"
          personnelTypeCodes: [MANAGEMENT]
          # etc…
        }
        # etc…
      }
    }
  ) {
    id
  }
}
{% endraw %}
{% endhighlight %}

The 3rd principle implements idempotency in the server logic, but it
isn't enough for the client to implement retries for timed out
requests. That is covered by the 4th principle: it allows the client
retry the request until it gets to see the response.

I think supporting client retries is one of the main selling points of
idempotency. It also explains why uniqueness constraints on entity
attributes are not enough to support duplicate request suppression. A
constraint on an attribute, such as username, does prevent clients from
creating duplicate user entities, but client retries are broken. The
following sequence diagram shows why:

<img src="{{ "/" | relative_url }}{% ministamp _assets/images/client-retries-when-only-uniqueness-constraint.svg assets/images/client-retries-when-only-uniqueness-constraint.svg %}" alt="A sequence diagram showing how client can receive an error when retrying a mutation operation" title="A sequence diagram showing how client can receive an error when retrying a mutation operation" width="100%" style="max-width: 550px;" />

In the diagram, client requests creating a new employee with a certain
username. The service enforces that the username must be unique. The
request propagates via the API gateway to the application service, and
the service processes the request with success. But then the API gateway
crashes before it forwards the response to the client. Eventually, the
retry timeout of the client triggers and the client sends the same
request again. This time the client receives the response, but it's a
failure: an employee with the supplied username exists already. This is
unexpected from the client's perspective.

An implementation of the 3rd and 4th principles in the server is an SQL
table for storing the outcomes of processed mutations. The database
schema could be like the following for [PostgreSQL][postgresql]:

{% highlight sql %}
{% raw %}
create type transaction_operation as enum (
  'CREATE_EMPLOYEE',
  'UPDATE_EMPLOYEE',
  'DELETE_EMPLOYEE'
);

create table transaction (
  id uuid not null primary key,
  operation transaction_operation not null,
  target jsonb,
  error_msg text,
  created_at timestamptz not null default now(),
  check (target is not null or error_msg is not null)
);
{% endraw %}
{% endhighlight %}

Here are some example rows to support further discussion:

<div class="wide-table">
  <table class="code-table">
    <thead>
      <tr>
        <th>id</th>
        <th>operation</th>
        <th>target</th>
        <th>error_msg</th>
        <th>created_at</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>addb372c-046f-43e8-c91f-1df1a30caaa0</td>
        <td>CREATE_EMPLOYEE</td>
        <td>["549d9715-0949-4a57-b9fb-1c56eb8e5029"]</td>
        <td/>
        <td>2021-12-03 11:59:30.085 +0200</td>
      </tr>
      <tr>
        <td>abdb372c-026f-43e8-c91f-2df1b30d8aa1</td>
        <td>UPDATE_EMPLOYEE</td>
        <td>["549d9715-0949-4a57-b9fb-1c56eb8e5029"]</td>
        <td/>
        <td>2021-12-03 12:00:14.290 +0200</td>
      </tr>
      <tr>
        <td>abdb372c-026f-43e8-c91f-2df1b30d8aa2</td>
        <td>UPDATE_EMPLOYEE</td>
        <td>["549d9715-0949-4a57-b9fb-1c56eb8e5029"]</td>
        <td>invalid email</td>
        <td>2021-12-03 12:03:43.110 +0200</td>
      </tr>
      <tr>
        <td>11d36de7-0e36-475a-ae01-baa634010aa3</td>
        <td>DELETE_EMPLOYEE</td>
        <td>["549d9715-0949-4a57-b9fb-1c56eb8e5029"]</td>
        <td/>
        <td>2021-12-03 12:18:11.507 +0200</td>
      </tr>
      <tr>
        <td>addb372c-046f-43e8-c91f-1df1a30caaa4</td>
        <td>CREATE_EMPLOYEE</td>
        <td/>
        <td>duplicate employee username</td>
        <td>2021-12-03 13:52:52.067 +0200</td>
      </tr>
    </tbody>
  </table>
</div>

The `id` column stores the `transactionId` of a processed mutation
request. The `operation` and `target` columns together enable storing
different kind of completed mutations in this single table; the
`operation` signifies the type of the mutation operation performed, and
the `target` column stores the primary key of the target entity as a
JSON array. For the employee entity, the primary key is just a single
UUID value, but for another entity type, such as school position, the
primary key might be the pair of employment id and school id. We can
store any primary key tuple, regardless of their component data types,
by encoding them as JSON arrays.

A `null` value in the `error_msg` column tells that the operation was a
success. A string value present means that the operation in question
failed. For example, the third operation (the `transactionId` ending
with `a2`) completed with a failure to update a particular employee
entity, because email validation failed. The `error_msg` column makes it
possible to resend the same error back to the client if the client
retries the operation with the same `transactionId` value. An
`error_msg` value can exist without an entity target id as well: the
last operation (the `transactionId` ending with `a4`) was a failure to
create a new employee. We may publish the identifier of a new entity
only after succeeding in entity creation.

In general terms, the Staff service utilizes the `transaction` table as
follows:

1. Upon receiving a new mutation request, the service opens a database
   transaction.

2. If the `transaction` table contains a row with the same
   `transactionId` value as in the request, the service knows that the
   request has been processed already, and now it only rebuilds the
   response for the original processing outcome back to the client. The
   response is either a success or failure, depending on if the
   `error_msg` column is populated or not:

   * If `error_msg` is present, the service builds a failure response
     with a description why the mutation failed.

   * If `error_msg` is not present, the service builds a success
     response. The response might include data about the entity after
     the mutation is completed. If so, the service includes data about
     the current state of the entity. Because a later mutation might
     have changed the entity after reconstructing the response for an
     older mutation, we settle for showing the current data available
     (which might be nothing if the entity is already deleted). This is
     what I meant earlier by *including the same logical output* in the
     4th API design principle.

3. If the `transaction` table didn't contain a row with this
   `transactionId` value, the service knows that now is the first and
   only time to process the request. The service must execute any calls
   to remote services (doesn't matter who owns them) within the context
   of the open database transaction and expect errors. But rollbacking
   the whole database transaction upon remote call error is not the
   right way do it either: the service must still be able to append a
   new row to the `transaction` table in the end of the database
   transaction.

   This is where the [`ROLLBACK TO
   SAVEPOINT`][postgresql-rollback-to-savepoint] SQL command is very
   useful. Mark a savepoint within the transaction just before the point
   of doing anything that you expect to raise an error. It an error does
   happen, handle it gracefully, rollback to the savepoint, and remember
   the error for the next step.

4. Now the service has completed processing the mutation either with
   success or failure. The service appends a new row to the
   `transaction` table accordingly.

5. The service commits the database transaction and responds to the
   client.

The 5th API design principle is about the ability to track the
propagation of change across services. If the Users service, coming
after the Staff service in the communication path of processing client's
mutation request, has completed a request with a certain
`transactionId`, but the Staff service isn't, we know that the Staff
service is malfunctioning.

Continuing the earlier example of creating a new employee in the Staff
API (the `createEmployee` mutation), the Staff service might send a
GraphQL mutation like this to the Users service in order to create a
user entity to associate with the employee:

{% highlight graphql %}
{% raw %}
mutation {
  createUser(
    input: {
      transactionId: "addb372c-046f-43e8-c91f-1df1a30caaa1"
      data: {
        firstName: "Albert"
        lastName: "Vesker"
        # etc…
      }
    }
  ) {
    id
  }
}
{% endraw %}
{% endhighlight %}

This would be a call to a remote service in the 3rd step of the usage
description of the `transaction` table we just went through. The service
making remote calls should utilize retries for timed out connection
attempts.

Now I can justify my choice of naming for the `transactionId` parameter.
I think duplicate request processing suppression and database
transactions share some of their goals. Especially, both aim to protect
against data corruption by guaranteeing that processing takes effect at
most once. But duplicate request suppression is not a form of
distributed transactions either. For example, it's possible that the
Staff service might crash while processing the `createEmployee`
mutation, just after the User service has completed processing the
`createUser` mutation received from the Staff service. In that
situation, the Users service will have a row in its `transaction` table
indicating completed request processing, but the same table in the Staff
service won't contain a corresponding row for the `createEmployee`
mutation. The system will be left in an inconsistent state unless the
client retries the request until receiving a response.[^4]

Note that because the `transactionId` parameter is user input, its value
must be treated as unsafe and potentially malicious. Clients might
generate values that are not truly random, even though the values might
conform to the UUID format. This is why services must enforce
authorization for clients accessing their data.

## Communicating with external services

End-to-end wise, the IdP service is the last service in the
communication path of creating a new employee. It's part of the system,
but, being an external service, we cannot enforce our API design
principles to it. Is there anything we can do to prevent duplicate
request processing?

Uniqueness constrains on entity attributes enforced by the API of the
external service do help, even if they don't behave nicely with request
retries. For example, the IdP service in my imaginary web service might
enforce unique usernames for user entities. That effectively acts as a
duplication suppressor for request retries when attempting to create a
new entity. If you route all requests to the external service via your
own service acting as a *facade*, you can anticipate username constraint
errors on retries and check if the user was created successfully on an
earlier attempt after all. In addition, you should have a mechanism to
suppress duplicate request processing in the client-facing side of the
facade service, especially if the service stores state about some of the
data in the external service (entity identifier mapping, like in the
Users service, for instance).

## Summary

The longer your web service operates and the more requests it handles,
the more important suppressing duplicate request processing
becomes. Faults can and eventually will happen in the components of your
system. Some of those faults will trigger your services receiving
duplicated requests. Idempotent request processing constitutes that
requesting the same operation with the same input many times over
applies the effect in the service only once. The trick is in the
identification of the input data, and I've shown one way to implement it
with the `transactionId` parameter.

There are many ways to go about this. In considering any approach, I'd
inspect it from the viewpoint of the client: how can you ensure that
it's safe for the client at the start of the communications path to
retry requests, and that the response, when it finally arrives, has the
same content as the response to the first request that was actually
processed?

[^1]: In *exactly-once semantics*, a system processes a message so that
    the final effect is the same as if no faults occurred, even if the
    operation was retried due to some fault.

[^2]: An *entity* is an object that is defined primarily by its
    identifying attribute (such as UUID). Two different entities might
    have the same descriptive attributes (such as name).

[^3]: An operation is *idempotent* if, given the same input, you apply
    it many times, and the effect is the same as if you applied it only
    once.

[^4]: Request processing can be made more reliable between two services
    with a message broker: the source service publishes requests as
    messages to the broker, while the destination service consumes
    messages and acknowledges consumed messages after completing
    processing them. This is possible with [Apache
    Kafka][kafka-message-delivery-semantics], for example.

[acid]: https://en.wikipedia.org/wiki/ACID
[designing-data-intensive-applications]: https://dataintensive.net/
[end-to-end-arguments-in-system-design]: https://web.mit.edu/Saltzer/www/publications/endtoend/endtoend.pdf
[kafka-message-delivery-semantics]: https://kafka.apache.org/documentation/#semantics
[postgresql-rollback-to-savepoint]: https://www.postgresql.org/docs/14/sql-rollback-to.html
[postgresql]: https://www.postgresql.org/
[uuid]: https://en.wikipedia.org/wiki/Universally_unique_identifier
