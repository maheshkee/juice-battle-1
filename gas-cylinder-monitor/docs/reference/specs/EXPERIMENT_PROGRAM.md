# EXPERIMENT_PROGRAM.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines the engineering validation program for the Gas Cylinder Weight Monitor project.

The purpose of the experiment program is to transform:

Assumptions ↓ Evidence

Reasoning ↓ Validation

Design ↓ Knowledge

# 2. PHILOSOPHY

The project follows:

Measure ↓ Validate ↓ Trust

Not:

Assume ↓ Implement ↓ Hope

Every major engineering decision should eventually be backed by evidence.

# 3. EXPERIMENT LIFECYCLE

Every experiment follows:

text id="p1dnz3" Question ↓ Theory ↓ Procedure ↓ Data ↓ Analysis ↓ Decision

# 4. STANDARD EXPERIMENT TEMPLATE

Every experiment must contain:

Experiment ID

Objective

Background Theory

Equipment

Procedure

Data To Capture

Acceptance Criteria

Failure Criteria

Decision Impact

# 5. VALIDATION PYRAMID

Experiments should follow dependency order.

Level 1

Electrical Validation

Level 2

Sensor Validation

Level 3

Calibration Validation

Level 4

Transport Validation

Level 5

Analytics Validation

Level 6

Prediction Validation

Rule:

Never validate upper layers before lower layers.

# 6. E-000

ESP32-C3 + HX711 Bring-Up

Status

Critical Path

Objective

Determine whether ESP32-C3 can reliably communicate with HX711.

Questions

Does communication work?

Are logic levels safe?

Are readings stable?

Can counts be collected reliably?

Equipment

ESP32-C3

HX711

Load Cell

USB Power

Procedure

Wire HX711.

Read raw counts.

Observe stability.

Record results.

Data To Capture

Raw counts

Noise range

Communication failures

Voltage observations

Acceptance Criteria

Reliable readings

No communication failures

Stable count stream

Known noise profile

Decision Impact

Everything depends on E-000.

# 7. E-001

Calibration Derivation

Objective

Derive counts-to-grams conversion.

Questions

Can weight be accurately measured?

How repeatable is calibration?

Equipment

Known calibration weights

Scale assembly

ESP32 node

Procedure

Apply known weights.

Record counts.

Fit calibration.

Validate output.

Data To Capture

Weight

Counts

Error

Residuals

Acceptance Criteria

Repeatable calibration

Predictable conversion

Documented procedure

Decision Impact

Enables trustworthy weight.

# 8. E-002

Noise Characterisation

Objective

Quantify measurement noise.

Questions

What is the noise floor?

How much variation exists?

What averaging depth is required?

Procedure

Leave system undisturbed.

Collect samples.

Compute statistics.

Metrics

σ

Variance

Peak-to-peak

Range

Acceptance Criteria

Noise profile documented.

Threshold derivation possible.

Decision Impact

Determines averaging strategy.

# 9. E-003

Transport Validation

Objective

Validate ESP32 → UNO Q communication.

Questions

Can messages be delivered reliably?

Can failures be recovered?

Procedure

Transmit measurements.

Verify storage.

Introduce disconnects.

Verify recovery.

Acceptance Criteria

Reliable delivery

Automatic recovery

No silent failures

Decision Impact

Enables distributed architecture.

# 10. E-004

Measurement Stability Validation

Objective

Verify stable readings over time.

Questions

Do measurements wander?

Are plateaus detectable?

Procedure

Apply fixed load.

Observe for extended duration.

Metrics

Variance

Drift

Plateau quality

Acceptance Criteria

Stable plateau detection.

Known stability limits.

# 11. E-005

Linearity & Hysteresis Characterisation

Objective

Validate measurement behavior across range.

Questions

Is calibration linear?

Does loading equal unloading?

Equipment

Multiple known weights.

Procedure

Apply increasing loads.

Record measurements.

Remove loads.

Record measurements.

Compare results.

Metrics

Residual error

Linearity curve

Hysteresis error

Acceptance Criteria

Behavior documented.

Error understood.

Decision Impact

Validates measurement model.

# 12. E-006A

Anchor Validation

Objective

Validate steel derivation logic.

Questions

Can full-install anchors reliably derive steel?

Procedure

Measure full cylinder.

Calculate steel.

Compare with known tare if available.

Acceptance Criteria

Steel estimate reasonable.

Consistent across installs.

# 13. E-006B

Consumption Validation

Objective

Validate usage tracking.

Questions

Can actual gas usage be measured accurately?

Procedure

Track controlled usage.

Compare before/after weights.

Metrics

Measured consumption

Expected consumption

Error

Acceptance Criteria

Consumption matches reality within acceptable limits.

Decision Impact

Enables analytics.

# 14. E-007A

Refill Detection Validation

Objective

Validate refill event detection.

Questions

Can new cylinder installation be reliably identified?

Procedure

Simulate replacement cycles.

Observe event detection.

Acceptance Criteria

Refills detected consistently.

Minimal false positives.

# 15. E-007B

Threshold Validation

Objective

Validate event thresholds.

Questions

Are thresholds too sensitive?

Too conservative?

Procedure

Exercise event logic.

Observe outcomes.

Tune thresholds.

Acceptance Criteria

Reliable event classification.

# 16. E-008

Prediction Validation

Objective

Evaluate forecast accuracy.

Questions

Do predictions match reality?

Procedure

Store forecasts.

Compare against actual depletion.

Metrics

Forecast error

Confidence accuracy

Prediction drift

Acceptance Criteria

Forecast quality measurable.

# 17. E-009

Alert Validation

Objective

Validate user notifications.

Questions

Are alerts useful?

Are they timely?

Procedure

Simulate low-gas conditions.

Observe behavior.

Acceptance Criteria

Actionable alerts.

Minimal nuisance.

# 18. THERMAL STUDY

Objective

Characterize temperature effects.

Questions

Does scale zero drift?

Does calibration drift?

Procedure

Observe system across temperature changes.

Metrics

Offset drift

Gain drift

Noise changes

Decision Impact

Determines compensation requirements.

# 19. LONG-TERM DRIFT STUDY

Objective

Understand stability over weeks.

Questions

Does the system slowly change?

Procedure

Monitor fixed loads.

Observe over long periods.

Metrics

Baseline drift

Creep

Calibration change

# 20. DIURNAL STUDY

Objective

Understand daily environmental cycles.

Procedure

Collect measurements over multiple days.

Observe

Morning

Afternoon

Evening

Night

Metrics

Weight variation

Temperature influence

Noise variation

# 21. FAILURE INJECTION

Objective

Understand recovery behavior.

Examples

Disconnect WiFi

Restart node

Restart hub

Disconnect sensor

Acceptance Criteria

Recovery automatic.

No hidden failures.

# 22. DATA QUALITY POLICY

All experiments must preserve:

Raw Data

Processed Data

Analysis

Conclusions

Reason

Future reinterpretation may be necessary.

# 23. EXPERIMENT LOGGING

Every experiment should produce:

Experiment Report

Contents

Date

Version

Configuration

Observations

Results

Conclusions

# 24. DECISION RECORDS

Experiments should drive decisions.

Example

Experiment ↓ Evidence ↓ Decision ↓ Documentation

Never:

Opinion ↓ Decision

# 25. COMPLETION CRITERIA

An experiment is complete when:

Question answered

Evidence collected

Decision made

Documentation updated

Not merely when data exists.

# 26. MVP VALIDATION GATE

MVP considered validated when:

E-000 Complete

E-001 Complete

E-002 Complete

E-003 Complete

Basic weight displayed on UNO Q

Everything else builds on this.

# 27. V1 VALIDATION GATE

V1 considered validated when:

Anchor logic proven

Consumption validated

Prediction operational

Alerts operational

User receives useful value.

# 28. KNOWLEDGE MANAGEMENT RULE

Experimental knowledge must be preserved.

Results become:

Specifications

Design decisions

Future assumptions

Never repeat solved work.

# 29. EXPERIMENT PROGRAM SUMMARY

The experiment program exists to transform engineering uncertainty into engineering knowledge.

Every major component of the system must eventually move from:

PENDING ↓ REASONED ↓ PROVEN

The project succeeds not because it contains many features, but because every important feature is supported by evidence.

END OF EXPERIMENT_PROGRAM.md v1.0