# TRANSPORT_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines communication between:

ESP32-C3 Sensor Node

and

UNO Q Hub

It specifies:

Message contracts

Transport behavior

Heartbeats

Event delivery

Retry mechanisms

Offline behavior

Node identity

Future scalability

This document intentionally does not define:

Sensor calibration

Gas estimation

Analytics

Prediction

Those belong elsewhere.

# 2. TRANSPORT PHILOSOPHY

The transport layer exists to move information.

It does not:

Interpret information

Modify information

Create information

Transport should be transparent.

# 3. PRIMARY GOAL

Transport must reliably answer:

text id="tv4gfq" Can the hub trust that a measurement produced by a node was delivered correctly?

# 4. DESIGN PRINCIPLES

Reliability over speed.

Correctness over optimization.

Recoverability over perfection.

Simplicity over cleverness.

# 5. ARCHITECTURE

text id="e6gl2v" ESP32 Node       ↓ Transport Layer       ↓ UNO Q Hub

Transport is a bridge.

Nothing more.

Nothing less.

# 6. COMMUNICATION MODEL

The project adopts a hybrid model.

Push

Node initiates communication.

Pull

Hub initiates communication.

Both are required.

# 7. PUSH MODEL

Node detects something important.

Node sends immediately.

Examples

Install detected

Removal detected

Low gas event

Sensor fault

Purpose

Reduce latency.

# 8. PULL MODEL

Hub requests information.

Examples

Current weight

Node diagnostics

Configuration status

Purpose

Support on-demand access.

# 9. MESSAGE CATEGORIES

All transport traffic should belong to one category.

Measurement

Heartbeat

Event

Command

Response

Diagnostic

This simplifies routing.

# 10. NODE IDENTITY

Every node must possess a unique identifier.

Example

text id="pdmqj7" cylinder_node_001

Purpose

Routing

History

Diagnostics

Future multi-node support

Node identity is mandatory.

# 11. TIMESTAMP POLICY

Every message must contain:

Timestamp

Reason

Without time:

Data becomes meaningless.

Time is first-class metadata.

# 12. MEASUREMENT MESSAGE

Purpose

Transmit weight observations.

Required Fields

Node ID

Timestamp

Weight

Quality

Health State

Example Structure

{  "type":"measurement",  "node_id":"cylinder_node_001",  "timestamp":"...",  "weight_g":24520,  "quality":"GOOD",  "health":"GOOD"}

# 13. HEARTBEAT MESSAGE

Purpose

Prove liveness.

Create history.

Maintain synchronization.

Current Interval

15 minutes

Heartbeat is mandatory.

# 14. HEARTBEAT CONTENT

Minimum Fields

Node ID

Timestamp

Weight

Health

Firmware Version

The heartbeat becomes the authoritative timeline.

# 15. EVENT MESSAGE

Purpose

Transmit important state transitions.

Examples

Install

Removal

Refill

Low Gas

Calibration Update

Sensor Fault

Events are sparse.

Events are meaningful.

# 16. EVENT STRUCTURE

Example

{  "type":"event",  "event":"install",  "timestamp":"...",  "node_id":"cylinder_node_001"}

Payloads may vary by event type.

# 17. COMMAND MESSAGE

Purpose

Allow hub control.

Examples

Request Reading

Request Diagnostics

Request Health

Request Configuration

Commands originate from the hub.

# 18. RESPONSE MESSAGE

Purpose

Answer commands.

Every command should generate:

Success

or

Failure

No silent outcomes.

# 19. DIAGNOSTIC MESSAGE

Purpose

Expose internal node state.

Examples

Noise Metrics

Calibration Information

Sensor Status

Transport Statistics

Useful for troubleshooting.

# 20. MESSAGE VERSIONING

All messages should include:

Protocol Version

Reason

Future compatibility.

Example

{  "protocol":"1.0"}

# 21. DELIVERY GUARANTEE

Target

At-Least-Once Delivery

Reason

Missing measurements are worse than duplicates.

Duplicates can be handled.

Lost information cannot.

# 22. DUPLICATE HANDLING

Messages should possess unique identifiers.

Purpose

Deduplication.

The hub decides:

Already Processed?

or

New Message?

# 23. ACKNOWLEDGEMENT MODEL

Node Sends ↓ Hub Receives ↓ Hub Acknowledges ↓ Node Clears Buffer

Acknowledgement confirms delivery.

# 24. RETRY STRATEGY

If acknowledgement absent:

Retry.

Never assume success.

Retries should be bounded.

Avoid infinite loops.

# 25. OFFLINE NODE BEHAVIOR

If transport unavailable:

Continue measuring.

Continue buffering.

Measurement should never stop because networking failed.

# 26. OFFLINE HUB BEHAVIOR

If hub unavailable:

Node stores pending messages.

When connection returns:

Replay buffered data.

No measurement loss.

# 27. BUFFERING STRATEGY

Purpose

Protect against temporary outages.

Buffer Contents

Heartbeats

Events

Diagnostics

Measurements remain valuable even after delayed delivery.

# 28. BUFFER OVERFLOW POLICY

If storage fills:

Preserve newest data.

Log overflow event.

Data loss should be explicit.

Never silent.

# 29. RECONNECT STRATEGY

When connection restored:

Authenticate

Synchronize

Replay backlog

Resume normal operation

Recovery must be automatic.

# 30. LIVENESS DETECTION

Question

Is the node alive?

Answer

Heartbeat received within expected interval.

No heartbeat:

Node may be offline.

# 31. HEALTH REPORTING

Node reports:

Sensor Health

Transport Health

Measurement Health

Calibration Health

Purpose

Trust assessment.

# 32. CONFIGURATION TRANSPORT

Future capability.

Examples

Threshold updates

Heartbeat interval

Feature flags

Configuration should be transportable.

# 33. SECURITY PHILOSOPHY

V1

Trusted household network.

Focus

Reliability first.

Security enhancements deferred.

# 34. TIME SYNCHRONIZATION

Accurate timestamps matter.

Potential Sources

Hub time

Network time

RTC

Decision deferred.

# 35. FUTURE MULTI-NODE SUPPORT

Current

1 Node

1 Cylinder

Future

N Nodes

N Cylinders

Node identity enables expansion.

# 36. TRANSPORT FAILURE STATES

Possible Failures

Disconnected

Slow

Intermittent

Unreachable

Corrupted

Each requires classification.

# 37. TRANSPORT HEALTH STATES

GOOD

WARNING

DEGRADED

FAILED

Visible to analytics.

# 38. ACCEPTANCE CRITERIA

Transport accepted when:

Measurements delivered

Events delivered

Heartbeats reliable

Retries functional

Buffering functional

Recovery automatic

# 39. E-003 ACCEPTANCE CRITERIA

One successful path:

ESP32 ↓ Transport ↓ UNO Q ↓ Storage

Must be reliable.

Not merely functional.

# 40. TRANSPORT SUMMARY

The transport layer exists to move trusted information from the measurement layer to the intelligence layer.

Its responsibilities are:

Delivery

Recovery

Synchronization

Liveness

Identity

It should remain simple, observable, and reliable.

Transport should never become the source of business logic.

END OF TRANSPORT_SPECIFICATION.md v1.0