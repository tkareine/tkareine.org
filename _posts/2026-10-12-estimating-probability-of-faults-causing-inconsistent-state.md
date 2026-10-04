---
layout: post
title: Estimating the probability of faults causing inconsistent state
date: 2026-10-12T00:23+03
published: true
---

How likely are faults leading to bad states in a distributed system? Specifically, I am interested in faults causing the constituent components of the system to enter states that are inconsistent with each other. I have sometimes estimated the likelihood of such faults with a variation of the [Drake equation](https://en.wikipedia.org/wiki/Drake_equation), which was originally invented for estimating the number of active and communicative civilizations in the galaxy.

For example, let's look at a possible fault in a workflow where microservices use HTTP to communicate and where we want to create a user domain object in the User API. Each microservice manages its own state independently of the others. The user object should have an associated user account in the Identity and Management (IdM) service and a workspace object in a third service; here, the meanings of these objects don't matter as much as their relations. The diagram below shows the expected happy path for user creation at the top and one possible fault at the bottom:

<img src="{{ "/" | relative_url }}{% ministamp _assets/images/inconsistent-state-across-services.svg assets/images/inconsistent-state-across-services.svg %}" alt="Sequence diagram showing successful and failed attempts to create a user object together with its associations to a user account and a workspace object. The failed attempt is caused by a server crash and introduces inconsistent state between the services." title="Sequences of successful and failed attempts to create a user object together with its associations to a user account and a workspace object" width="100%" style="max-width: 500px;" />

The APIs offer upsert-style operations where an operation creates an object if it does not exist already, or otherwise updates it; a key given as an input parameter identifies the object. This provides the [idempotency property](https://en.wikipedia.org/wiki/Idempotence) for the operation, which makes the operation safe to retry.

The fault portrayed at the bottom of the diagram happens when the User API crashes (or shuts down ungracefully) while the API is processing the `POST /user` request. The crash happens just after sending the request to create the user account to the IdM. The request to the Workspace API was never sent. The states of the User API, IdM, and Workspace API become inconsistent with each other: the IdM service has the user account, but the Workspace API lacks the user's workspace object (it was never requested), and the User API lacks the user object (it was never committed to the database).

Should we worry about such faults? I think this calls for assessing our tolerance for risk: what are the potential impacts of the faults, and how probable are they?

To get some idea of the probability of any fault that introduces inconsistent state within the system, we can estimate the number of their occurrences during one year of operation:

<p class="math">N<sub>faults</sub> = N<sub>requestsInYear</sub> × f<sub>writeOps</sub> × f<sub>writeCoord</sub> × f<sub>writeCrash</sub> × f<sub>badState</sub></p>

Where

<dl>
  <dt class="math">f<sub>writeOps</sub></dt>
  <dd>The fraction of all operations entering the system that change the state of one or more services. These are write operations.</dd>

  <dt class="math">f<sub>writeCoord</sub></dt>
  <dd>The fraction of <span class="math">f<sub>writeOps</sub></span> that coordinate with other services to achieve any workflow. Having more different service roles would increase the fraction.</dd>

  <dt class="math">f<sub>writeCrash</sub></dt>
  <dd>The fraction of <span class="math">f<sub>writeCoord</sub></span> where any service crashes while processing the write operation, aborting it. The higher your SLA, the smaller the fraction should be.</dd>

  <dt class="math">f<sub>badState</sub></dt>
  <dd>The fraction of <span class="math">f<sub>writeCrash</sub></span> causing any service to enter a state that is inconsistent with other services in the system.</dd>
</dl>

Further, we can estimate the total number of requests in a year (<span class="math">N<sub>requestsInYear</sub></span>) by assuming a constant rate of incoming requests.

We get about 6.3 fault occurrences if we set

- 10 requests/sec
- 10% of all operations are writes (<span class="math">f<sub>writeOps</sub></span>)
- Out of the write operations, 20% are used to implement workflows by services coordinating (<span class="math">f<sub>writeCoord</sub></span>)
- Out of the coordinating write operations, there's a 0.01% probability that any service crashes while processing them (<span class="math">f<sub>writeCrash</sub></span>)
- For any such crash, there's a 1% probability that inconsistent state gets introduced into the system (<span class="math">f<sub>badState</sub></span>)

Assuming faults occur independently of each other, the number of faults in a year would follow a [Poisson distribution](https://en.wikipedia.org/wiki/Poisson_distribution) with the expectation of <span class="math">N<sub>faults</sub></span>. The probability of at least one fault during the year is then

<p class="math">P(≥ 1 fault in a year) = 1 - P(0 faults in a year) = 1 − e<sup>−N<sub>faults</sub></sup> ≈ 1 − e<sup>−6.3</sup> ≈ 99.8%</p>

Here are the parameters filled in, so you can try changing them:

<style>
.math {
  font-style: italic;
}
.small {
  font-size: 80%;
}
.estimate {
  display: flex;
  align-items: first baseline;
  justify-content: flex-start;
  flex-wrap: nowrap;
}
.estimate .formula {
  display: flex;
  align-items: last baseline;
  justify-content: flex-start;
  flex-wrap: wrap;
}
.estimate .formula > * {
  margin: 0.5em 0.1em;
}
.estimate label {
  display: block;
  text-wrap: wrap;
  overflow-wrap: break-word;
}
.estimate input {
  display: block;
  max-width: 4em;
}
.estimate + .estimate {
  margin-top: 0.5em;
}
.estimate .error {
  color: #e30000;
}
</style>

<div class="estimate math">
  <div class="result">N<sub>faults</sub></div>
  <div class="formula">
    <div>=</div>
    <label for="estimate-rps"><span class="small">Requests/<br/>sec</span><input type="text" id="estimate-rps" value="10" /></label>
    <div>× (60 × 60 × 24 × 365 <span class="small">sec/year</span>) ×</div>
    <label for="estimate-f-write-ops">f<sub>writeOps</sub><input type="text" id="estimate-f-write-ops" value="0.1" /></label>
    <div>×</div>
    <label for="estimate-f-write-coord">f<sub>writeCoord</sub><input type="text" id="estimate-f-write-coord" value="0.2" /></label>
    <div>×</div>
    <label for="estimate-f-write-crash">f<sub>writeCrash</sub><input type="text" id="estimate-f-write-crash" value="0.0001" /></label>
    <div>×</div>
    <label for="estimate-f-bad-state">f<sub>badState</sub><input type="text" id="estimate-f-bad-state" value="0.01" /></label>
    <div>= <span id="estimate-num-faults"></span></div>
  </div>
</div>

<div class="estimate math">
  <div class="result">P(≥ 1 fault in a year)</div>
  <div class="formula">
    <div>=</div>
    <div>1 − e<sup>−N<sub>faults</sub></sup></div>
    <div>= <span id="estimate-p-at-least-one-fault"></span></div>
  </div>
</div>

<script>
;(function () {
  function estimateNumFaults(rps, fWriteOps, fWriteCoord, fWriteCrash, fBadState) {
    const numRequestsInYear = rps * (60 * 60 * 24 * 365)
    return numRequestsInYear * fWriteOps * fWriteCoord * fWriteCrash * fBadState
  }

  function probabilityOfAtLeastOneEvent(numEvents) {
    // `1 - e^(-x) = -(e^(-x) - 1)`, using `Math.expm1` for precision when x is small
    return -Math.expm1(-numEvents)
  }

  const numFaultsElem = document.querySelector("#estimate-num-faults")
  const pAtLeastOneFaultElem = document.querySelector("#estimate-p-at-least-one-fault")

  const rpsElem = document.querySelector("#estimate-rps")
  const fWriteOpsElem = document.querySelector("#estimate-f-write-ops")
  const fWriteCoordElem = document.querySelector("#estimate-f-write-coord")
  const fWriteCrashElem = document.querySelector("#estimate-f-write-crash")
  const fBadStateElem = document.querySelector("#estimate-f-bad-state")

  const numberFormat = new Intl.NumberFormat(undefined, { maximumSignificantDigits: 2 })
  const percentFormat = new Intl.NumberFormat(undefined, { style: "percent", maximumSignificantDigits: 3 })

  function updateEstimate() {
    const rps = Number(rpsElem.value)
    const fWriteOps = Number(fWriteOpsElem.value)
    const fWriteCoord = Number(fWriteCoordElem.value)
    const fWriteCrash = Number(fWriteCrashElem.value)
    const fBadState = Number(fBadStateElem.value)

    if ([rps, fWriteOps, fWriteCoord, fWriteCrash, fBadState].findIndex((v) => isNaN(v)) >= 0) {
      ;[numFaultsElem, pAtLeastOneFaultElem].forEach((elem) => {
        elem.textContent = "NaN"
        elem.classList.add("error")
      })
      return
    }

    const numFaults = estimateNumFaults(rps, fWriteOps, fWriteCoord, fWriteCrash, fBadState)

    numFaultsElem.textContent = numberFormat.format(numFaults)
    pAtLeastOneFaultElem.textContent = percentFormat.format(probabilityOfAtLeastOneEvent(numFaults))
    ;[numFaultsElem, pAtLeastOneFaultElem].forEach((elem) => elem.classList.remove("error"))
  }

  updateEstimate()

  ;[rpsElem, fWriteOpsElem, fWriteCoordElem, fWriteCrashElem, fBadStateElem].forEach((elem) => {
    elem.addEventListener("input", updateEstimate)
  })
})()
</script>

Given enough time with a steady rate of incoming requests, even rare faults become likely. I find it surprising that a modest rate of 10 requests/sec is likely enough to introduce inconsistent state within the system in one year of operation. What's worse is that we might not even notice when it happens.

If the impact of the fault exceeds our tolerance for risk, we need fault-tolerance mechanisms that bring the system back to a consistent state. For example, the client can retry a failed `POST /user` request until it succeeds, which is safe because the operations are idempotent upserts. Alternatively, services can communicate through events delivered by a log-based message broker, which persists the events and redelivers them after a crash.
