# DATA_STORAGE_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines the persistence layer of the Gas Cylinder Weight Monitor system.

It specifies:

Data ownership

Data hierarchy

Database structure

Table definitions

Retention philosophy

Derived data strategy

Historical preservation strategy

This document does not define:

Analytics algorithms

Prediction algorithms

Sensor calibration

Those belong elsewhere.

# 2. STORAGE PHILOSOPHY

Storage exists to preserve knowledge.

## Fundamental Principle

Storage is cheap.

Lost information is expensive.

Therefore:

Prefer preserving data.

Avoid destructive transformations.

## Design Rule

Never overwrite history.

Append knowledge.

# 3. DATA HIERARCHY

The system stores information at multiple layers.

Layer 1

Raw Measurements

Layer 2

Derived Measurements

Layer 3

Events

Layer 4

Analytics

Layer 5

Predictions

Each layer depends on the previous layer.

# 4. DATA OWNERSHIP

Every piece of information has one owner.

Raw Weight

Owner:

Measurement Layer

Gas Remaining

Owner:

Domain Layer

Burn Rate

Owner:

Analytics Layer

Days Remaining

Owner:

Prediction Layer

This prevents ambiguity.

# 5. STORAGE ENGINE

Initial storage engine:

SQLite

Reasons:

Simple

Reliable

Embedded

Easy backup

Easy migration

Sufficient for V1

Future migration remains possible.

# 6. DATABASE PHILOSOPHY

The database is the source of truth.

Rules:

Store facts

Store timestamps

Store context

Avoid hidden assumptions

# 7. TIMESTAMP POLICY

Every stored record must include:

Timestamp

Reason:

Without time:

History is meaningless.

Time is a first-class entity.

# 8. MEASUREMENT TABLE

Table:

weight_readings

Purpose:

Store authoritative heartbeat measurements.

Fields

id

timestamp

gross_weight_g

quality_state

node_id

noise_sigma

health_state

Purpose:

Historical reconstruction.

# 9. WHY HEARTBEAT STORAGE EXISTS

The heartbeat table forms the backbone of the system.

Current cadence:

15 minutes

Provides:

History

Analytics

Prediction inputs

Auditability

# 10. RAW DATA RETENTION

Policy:

Retain indefinitely.

Reason:

Future algorithms may require recomputation.

Raw data is the most valuable asset.

# 11. EVENT TABLE

Table:

events

Purpose:

Store significant occurrences.

Examples

Install

Removal

Refill

Low Gas

Sensor Failure

Calibration Update

Fields

event_id

timestamp

event_type

event_payload

severity

node_id

# 12. EVENT PHILOSOPHY

Measurements answer:

What happened continuously?

Events answer:

What changed?

Events create narrative context.

# 13. INSTALL EVENTS

Purpose:

Create anchor history.

Stored Information

Install Weight

Derived Steel

Capacity Class

Confidence

Install events become extremely valuable over time.

# 14. REFILL EVENTS

Purpose:

Capture cylinder replacement cycles.

Stored Information

Old cycle

New cycle

Weight jump

Derived steel estimate

Refill history improves future estimation.

# 15. CALIBRATION TABLE

Table:

calibration_history

Purpose:

Track calibration evolution.

Fields

timestamp

cal_factor

offset

operator

notes

Reason:

Calibration is not static.

# 16. HEALTH TABLE

Table:

health_reports

Purpose:

Track node health.

Fields

timestamp

noise_level

sensor_status

transport_status

health_state

Purpose:

Long-term diagnostics.

# 17. NODE TABLE

Table:

nodes

Purpose:

Track sensor nodes.

Fields

node_id

created_at

firmware_version

last_seen

status

Supports future multi-node expansion.

# 18. CYLINDER CYCLE TABLE

Table:

cylinder_cycles

Purpose:

Represent install-to-replacement lifecycle.

Fields

cycle_id

install_time

replacement_time

install_weight

derived_steel

capacity

total_consumption

duration_days

One of the most valuable tables in the system.

# 19. DAILY SUMMARY TABLE

Table:

daily_summary

Purpose:

Compression layer.

Fields

date

gas_used_g

avg_weight_g

sessions

prediction_snapshot

Benefits

Fast reporting

Fast dashboards

Lower computation cost

# 20. WEEKLY SUMMARY TABLE

Purpose:

Medium-term aggregation.

Fields

week

gas_used_g

avg_daily_use

variability

Useful for trend analysis.

# 21. MONTHLY SUMMARY TABLE

Purpose:

Long-term behavior.

Examples

Seasonal analysis

Household changes

Consumption shifts

# 22. ANALYTICS TABLE

Table:

analytics_snapshots

Purpose:

Persist calculated insights.

Examples

Burn rate

Consumption trend

Anomaly score

Variability score

Allows historical comparison.

# 23. PREDICTION TABLE

Table:

prediction_history

Purpose:

Store every prediction made.

Fields

timestamp

days_remaining

predicted_empty_date

confidence

algorithm_version

Reason:

Predictions must be auditable.

# 24. WHY PREDICTION HISTORY MATTERS

Without history:

Cannot evaluate accuracy.

With history:

Prediction quality becomes measurable.

The system can learn from mistakes.

# 25. CONFIGURATION TABLE

Table:

system_config

Purpose:

Persist system settings.

Examples

Heartbeat interval

Thresholds

Network parameters

Rule:

Configuration should be explicit.

Never hidden.

# 26. DATA IMMUTABILITY

Facts should be immutable.

Example

Measured weight should never change.

If interpretation changes:

Create new derived records.

Preserve original facts.

# 27. AUDITABILITY

Every important decision should be traceable.

Examples

Why was gas estimated at 40%?

Why was an alert generated?

Why was a refill detected?

Answer must exist in stored history.

# 28. RETENTION POLICY

Raw Measurements

Retain indefinitely.

Events

Retain indefinitely.

Analytics

Retain indefinitely.

Predictions

Retain indefinitely.

Storage cost is small.

Historical value is large.

# 29. BACKUP PHILOSOPHY

History is an asset.

Backup strategy must exist.

Potential options

File backups

Database snapshots

Cloud synchronization

Implementation deferred.

# 30. FUTURE STORAGE EVOLUTION

V1

SQLite

Future

Timeseries database

Cloud warehouse

Fleet storage

Migration should be possible without changing higher layers.

# 31. STORAGE ACCEPTANCE CRITERIA

Storage system accepted when:

Measurements preserved

Events preserved

Predictions auditable

History recoverable

Data integrity maintained

# 32. STORAGE SUMMARY

The database is the memory of the system.

Measurements become history.

History becomes analytics.

Analytics become predictions.

Predictions become decisions.

Without storage, intelligence cannot exist.

END OF DATA_STORAGE_SPECIFICATION.md v1.0