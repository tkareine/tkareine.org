---
layout: post
title: Exclusive scheduled jobs using database locks
date: 2026-03-10T22:15+02
published: true
---

Using locks implemented as rows in an SQL database enables running scheduled background jobs in an application, providing a best-effort guarantee that only one application instance at a time runs a particular job. This is one possible solution, and it's an appealing one because an SQL database usually serves as the primary database for the application – you don't need any additional infrastructure services. The implementation achieves fault tolerance and is easy to understand and operate, but sacrifices load balancing as a trade-off. I describe how to do it and provide SQL operations as examples.

Before I go into the solution, it's worth emphasizing that the characteristics and requirements of running background jobs should drive any design. There are surprisingly many aspects to think about. Among the considerations are how jobs get created (are they triggered by events or a schedule), whether the system should attempt to run a particular job only once, need for fault tolerance, load balancing, and scalability; followed by computing resource requirements, and whether it is acceptable to share the computing resources with the application's primary workload. See the [Background jobs][Azure Well-Architected Framework Background jobs] section of Microsoft Azure Well-Architected Framework for a good overview.

## Exclusive job implementation

The concept of an _exclusive job_ models the permission to run a particular job on only one application instance. I represent the model as a record having the following fields:

- `job_id`: Identifies a particular job. For example, `DeleteOldTransactionIds` or `CheckRemoteServiceHealth`.

- `job_instance_id`: A static identifier of the application instance. An application instance can simply use a static UUID generated in memory at instance startup for all `job_id`s.

- `lock_expires_at`: A timestamp in the future indicating when an acquired lock can be treated as expired. The value is calculated by the application. I'll describe its meaning shortly.

A scheduler triggers all the application instances to compete for the permission to run a certain job. The application relies on the database to provide atomic operations so that only one instance may insert or update a row for a `job_id` value.

The `exclusive_job` table stores the rows. Here is the schema for PostgreSQL:

{% highlight sql %}
{% raw %}
create table exclusive_job (
  job_id text primary key not null check (char_length(job_id) between 1 and 255),
  job_instance_id uuid not null,
  lock_expires_at timestamptz not null
);
{% endraw %}
{% endhighlight %}

The application defines the `tryAcquireLock` operation, which performs the following query to either acquire (insert row) or conditionally update the lock (update existing row). I use named parameters (such as `$job_id`) instead of positional parameters for easier reading (this is invalid SQL syntax as PostgreSQL allows positional parameters only):

{% highlight sql %}
{% raw %}
insert into exclusive_job as ej (
  job_id,
  job_instance_id,
  lock_expires_at
)
values ($job_id, $job_instance_id, $lock_expires_at)
on conflict (job_id) do update
set
  job_instance_id = excluded.job_instance_id,
  lock_expires_at = excluded.lock_expires_at
where
  ej.lock_expires_at < now() or
  (ej.job_id = excluded.job_id and ej.job_instance_id = excluded.job_instance_id)
{% endraw %}
{% endhighlight %}

As said, a scheduler triggers the application code to run a job identified by `job_id` for each application instance at approximately the same time. The instances compete to acquire the lock for the job using the `tryAcquireLock` operation. The first instance to execute the query will win. The row count of the query's result set signals either winning the lock (count > 0) or losing the lock (count = 0). The instance that has acquired the lock gets the permission to run the job; other instances back off.

The `lock_expires_at` column gives the ability to run the same `job_id` again in the next scheduled trigger. By relying on scheduled triggers and expiring locks, the design attains fault tolerance. The clocks of the application instances must be synchronized to make this work, but a small clock skew is tolerable.

A lock expiry value should be large enough that all application instances have a window to compete for the lock simultaneously, and that the winning instance has sufficient time to complete the job before expiration. On the other hand, the value should be small enough to allow the instances to compete again in the next scheduled trigger. Getting lock expiry right is the delicate part of this design. For example, if a job takes at most a minute to complete and you schedule running the job once per hour, then a value of 5 minutes might be suitable.

The `tryAcquireLock` operation is reentrant, meaning the same application instance already holding the lock may acquire the lock again.

Use the `updateLock` operation to guard against overlapping executions of the same long-running job. Overlapping might happen when the initial expiry time is too small compared to the amount of work anticipated: usually the job might take a few minutes to complete, but sometimes there's so much work that the job is still running when it's time to trigger the next scheduled run. In that case, the application should split the job into parts and update the expiry time just before running each part. Here's the SQL query for `updateLock`:

{% highlight sql %}
{% raw %}
update exclusive_job
set lock_expires_at = $lock_expires_at
where job_id = $job_id and job_instance_id = $job_instance_id
{% endraw %}
{% endhighlight %}

The query allows only the application instance that has acquired the lock to update the expiry time. A positive row count of the result set indicates if the update was applied. Note that the query allows the instance holding the lock to update the lock even if the lock is already expired.

An application instance that fails applying the update implies a problem where the lock has been expired and another instance has acquired it. This might be a symptom of using too small a value for `lock_expires_at`. I recommend aborting the job in a fail-fast manner if that happens.

One could also define the `releaseLock` operation for the application instance holding the lock to release the lock explicitly:

{% highlight sql %}
{% raw %}
delete from exclusive_job
where job_id = $job_id and job_instance_id = $job_instance_id
{% endraw %}
{% endhighlight %}

But using it would be safe only if you can guarantee that there cannot be other application instances still competing to acquire the lock for the same `job_id` in the same scheduled moment. An example scenario to avoid would be the following: instance A acquires a job's lock, completes the job quickly, and releases the lock; this is followed by instance B acquiring the lock for the same job. Now instance B would run the same job again. Instead, it's safer to just let the lock expire.

Each of the `tryAcquireLock`, `updateLock`, and `releaseLock` operations must be wrapped in a dedicated database transaction to obtain exclusive access to the guarded job. Don't include other database queries inside those transactions.

## Intended usage scenario

The implementation is designed for relatively lightweight jobs triggered by a scheduler. Each job should move affected state toward the desired state (eventual consistency and idempotent operations). The database manages state, making it easy to replicate the application to have many instances. You might run the application as a Deployment in Kubernetes, for example.

## Design trade-offs

For design trade-offs, you lose the following:

1. Cannot guarantee that exactly one application instance runs a job per trigger. After acquiring a lock, but just before executing the job, an instance may get paused long enough for the lock to expire and another instance to acquire the lock, resulting in running the job twice. A stop-the-world pause by a garbage collector is one example. See [How to Do Distributed Locking] by Martin Kleppmann for an example and more interesting details. This is acceptable because the design described here uses locking as an efficiency optimization, not for correctness.

2. No load balancing. There's no mechanism to distribute load intelligently among application instances. But you can distribute jobs randomly by delaying the call to `tryAcquireLock` with a small random duration. This also protects against the application instance having the greatest positive clock skew from always acquiring the lock.

3. The application runs background jobs alongside its primary workload. This resource sharing might harm the availability of the application.

4. You cannot scale resources for different background job types. The reason is the same as for not having load balancing.

5. You need to synchronize the clocks for all application instances. This shouldn't be a big problem in practice by using NTP.

6. It won't work with event triggers. Fault tolerance relies on periodically repeated triggers.

You gain the following:

1. Best-effort job exclusivity as an efficiency optimization. The `tryAcquireLock` operation ensures that only one application instance at a time may acquire a lock for a job. Connection pool usage does not affect lock handling.[^1] Using a large enough lock expiry time, the instance holding the lock should have time enough to complete the job for the common case. The nature of the job should allow running it many times, possibly concurrently, in the worst case.

2. Fault tolerance: if an application instance terminates ungracefully while running a job, the lock will expire eventually and another instance will retry the job the next time the job gets triggered.

3. Easy to understand and to operate: the implementation uses one SQL table for storing state. If something goes wrong in operations, you can either delete the contents of the table or just let the locks expire.

## Conclusion

I believe the exclusive jobs described here are interesting for simple background jobs that need to be repeated. Examples include cleanups, storing the health-check results of remote services in the database, and propagating state from one application to another in an eventually consistent fashion.

You get quite a lot for one SQL table and some application code around it. The accidental complexity of this approach is low.

I'm sure what I've presented is one variation of many similar tried-and-true solutions. My motivation was to document this particular variation, as I haven't found any articles describing something like it.

Finally, I've talked about the required atomic operations in the context of SQL databases, but there's actually nothing specific to SQL here. For example, the design can be implemented on a document-oriented database, such as MongoDB. Further, the update functionality of `tryAcquireLock` can be removed if the database supports deleting entries automatically upon lock expiry (see [TTL indexes][MongoDB TTL indexes] for MongoDB). So you have even more options for applying the design!

[^1]: Specifically, there's no need for the [advisory locks](https://www.postgresql.org/docs/18/explicit-locking.html#ADVISORY-LOCKS) of PostgreSQL. Using an advisory lock on the session level can cause problems with a connection pool. For example, if the application got connection A from the pool to acquire the advisory lock, it wouldn't be able to update the lock if it got connection B from the pool.

[Azure Well-Architected Framework Background jobs]: https://learn.microsoft.com/en-us/azure/well-architected/design-guides/background-jobs
[How to Do Distributed Locking]: https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
[MongoDB TTL indexes]: https://www.mongodb.com/docs/manual/core/index-ttl/
