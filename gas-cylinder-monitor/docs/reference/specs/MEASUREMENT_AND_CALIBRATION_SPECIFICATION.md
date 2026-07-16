# MEASUREMENT_AND_CALIBRATION_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines how the system transforms raw sensor observations into trustworthy weight measurements.

It specifies:

Measurement architecture

Calibration architecture

Noise characterization

Stability detection

Drift analysis

Validation methodology

Acceptance criteria

Experiment framework

This document intentionally stops at:

Gross Weight

Gas estimation belongs elsewhere.

Prediction belongs elsewhere.

# 2. FUNDAMENTAL PRINCIPLE

The entire product depends on one question:

“What is the true weight right now?”

If this answer is wrong:

Gas remaining is wrong

Percentage is wrong

Burn rate is wrong

Prediction is wrong

Therefore:

Measurement integrity is the foundation of the entire system.

# 3. MEASUREMENT PHILOSOPHY

The system never trusts a single reading.

Instead:

Observation ↓ Validation ↓ Confidence ↓ Measurement

Rule:

A sample is not a measurement.

A measurement is not truth.

A trusted measurement is truth.

# 4. MEASUREMENT STACK

The complete measurement pipeline is:

text id="efn7bx" Raw HX711 Counts ↓ Corrupt Value Filter ↓ Clean Samples ↓ Noise Characterisation ↓ Averaging ↓ Stability Detection ↓ Scale Zero Removal ↓ Calibration ↓ Gross Weight ↓ Quality Classification ↓ Publication

Each stage exists for a specific reason.

No stage should be skipped.

# 5. SENSOR MODEL

Physical Force ↓ Load Cell ↓ Differential Voltage ↓ HX711 ↓ ADC Counts ↓ ESP32 Processing ↓ Weight

The ESP32 never measures force directly.

It measures a processed representation of force.

# 6. RAW COUNT DOMAIN

The native unit of the HX711 is:

ADC Counts

Not grams.

Not kilograms.

Not percentages.

Not gas.

Example

text id="1r5ylv" 842311 842298 842320 842304

These values are observations only.

They have no meaning to users.

# 7. RAW SAMPLE PROPERTIES

Raw samples exhibit:

Noise

Offset

Drift

Occasional corruption

Environmental sensitivity

All subsequent processing exists to manage these properties.

# 8. CORRUPT SAMPLE DETECTION

Not every reading should be trusted.

Potential corruption sources:

Timing errors

Communication faults

Power disturbances

Sensor faults

Memory corruption

Corrupt samples must be rejected before entering the pipeline.

Rule:

Bad samples die immediately.

# 9. CORRUPTION POLICY

Invalid samples:

Not averaged

Not stored

Not published

Not used for calibration

Reason:

Corruption compounds.

Early rejection prevents propagation.

# 10. NOISE MODEL

Noise is unavoidable.

The objective is not elimination.

The objective is quantification.

Noise Sources

Electrical

Mechanical

Thermal

Environmental

Power Supply

The system should understand its noise.

Not guess it.

# 11. NOISE CHARACTERISATION

Noise becomes a measured quantity.

Metrics:

Standard Deviation (σ)

Peak-to-Peak

Range

Variance

Noise measurements influence:

Averaging depth

Threshold selection

Health classification

Confidence scoring

# 12. BOOT CHARACTERISATION

At startup:

The system characterizes itself.

Measure:

Noise

Offset

Stability

Sensor response

Purpose:

Establish baseline conditions.

# 13. NOISE FLOOR

Definition:

Minimum measurable variation under stable conditions.

Importance:

All thresholds must exceed the noise floor.

Otherwise:

False events occur.

# 14. AVERAGING

Purpose:

Reduce random error.

Mechanism:

Multiple observations combine into one estimate.

Benefit:

Noise decreases.

Signal becomes clearer.

Limitation:

Averaging cannot remove:

Bias

Drift

Bad calibration

Mechanical problems

# 15. DERIVING N

Many projects choose:

N = 10

N = 20

N = 50

arbitrarily.

This project rejects arbitrary N.

Correct Process

Measure Noise ↓ Determine Desired Confidence ↓ Derive N

N is an engineering result.

Not a guess.

# 16. STABILITY THEORY

The system should measure stable reality.

Not motion.

Example

User places cylinder.

Scale flexes.

Platform settles.

Readings oscillate.

Capturing during motion produces error.

# 17. STABILITY DETECTION

The system seeks:

Stable plateaus.

Indicators

Low variance

Low trend

Sufficient duration

Only stable plateaus become trusted measurements.

# 18. MEASUREMENT STATES

text id="s2vhg0" UNSTABLE ↓ SETTLING ↓ STABLE ↓ CAPTURED

UNSTABLE

Movement detected.

SETTLING

Verifying stability.

STABLE

Eligible for publication.

CAPTURED

Stored and transmitted.

# 19. THE TWO-TARE MODEL

Critical Concept.

Tare #1

Scale Zero

Tare #2

Cylinder Steel

These solve different problems.

They must never be confused.

# 20. SCALE ZERO

Definition:

Weight reading with an empty platform.

Purpose:

Remove sensor offset.

Layer:

Measurement Layer

Unit:

Counts or grams

# 21. CYLINDER STEEL

Definition:

Weight of empty cylinder shell.

Purpose:

Separate steel from gas.

Layer:

Domain Layer

Unit:

Grams

# 22. CALIBRATION OVERVIEW

Calibration creates a mapping:

Counts ↔ Weight

Without calibration:

The system knows only counts.

With calibration:

The system knows physical reality.

# 23. CAL_FACTOR

Primary calibration parameter.

Purpose:

Convert counts into weight.

Example

text id="1t2i2w" grams = (raw - offset) / cal_factor

Formula may vary.

Principle remains identical.

# 24. CALIBRATION REQUIREMENTS

Calibration must be:

Repeatable

Verifiable

Documented

Reproducible

Calibration is evidence.

Not magic.

# 25. SINGLE-POINT CALIBRATION

Advantages:

Simple

Fast

Disadvantages:

Cannot verify linearity

Cannot reveal hysteresis

Cannot reveal range errors

Useful for bring-up.

Insufficient for characterization.

# 26. MULTI-POINT CALIBRATION

Preferred method.

Known weights applied across range.

Examples:

500 g

1 kg

2 kg

5 kg

10 kg

20 kg

Purpose:

Validate entire operating range.

# 27. LINEARITY

Question:

Does one conversion relationship work everywhere?

Test:

Multiple weights

Compare expected vs measured

Outcome:

Linearity curve

Residual analysis

# 28. HYSTERESIS

Question:

Does history matter?

Procedure

Load

Measure

Unload

Measure

Same weight.

Different path.

Difference = hysteresis.

# 29. EXPERIMENT 005

Primary characterization experiment.

Goals

Validate calibration

Measure linearity

Measure hysteresis

Determine residual error

Experiment 005 validates the measurement model.

# 30. DRIFT

Drift is slow error.

Unlike noise:

Drift does not average away.

Sources

Temperature

Mechanical creep

Mounting stress

Aging

# 31. THERMAL DRIFT

Questions

Does offset move?

Does cal_factor move?

Does noise change?

Required because kitchens are not laboratories.

# 32. LONG-TERM DRIFT

Questions

What changes after:

Hours

Days

Weeks

Months

Purpose:

Understand stability.

# 33. DIURNAL DRIFT

Observe:

Morning

Afternoon

Evening

Night

Real environments create cycles.

The system must understand them.

# 34. QUALITY CLASSIFICATION

Every measurement receives a quality state.

GOOD

Expected uncertainty.

WARNING

Elevated uncertainty.

DEGRADED

Significant concern.

FAILED

Measurement not trusted.

# 35. HEALTH INDICATORS

Noise growth

Calibration instability

Missing samples

Sensor faults

Transport anomalies

Health is continuously evaluated.

# 36. SELF-VALIDATION

Calibration is never trusted forever.

Validation Sources

Anchor events

Known weights

Historical consistency

Residual analysis

Trust must be earned continuously.

# 37. ERROR BUDGET

Errors should be categorized.

Random Error

Noise

Systematic Error

Calibration

Offset

Bias

Environmental Error

Temperature

Mechanical stress

Understanding error is more important than minimizing every error.

# 38. ACCEPTANCE CRITERIA

Measurement system accepted when:

Stable

Repeatable

Characterized

Predictable

Auditable

Not merely operational.

# 39. E-000 ACCEPTANCE

ESP32 + HX711 accepted when:

Reliable communication

Stable counts

Safe electrical interface

Repeatable measurements

Known noise profile

# 40. MEASUREMENT SPECIFICATION SUMMARY

The measurement subsystem exists to answer one question:

“What is the true weight right now?”

It achieves this through:

Filtering

Characterisation

Calibration

Validation

Health Monitoring

Only after trustworthy weight exists can the remainder of the product function correctly.

# 41. DRIFT CORRECTION ARCHITECTURE — PLANNED

Two-stage design, gated by evidence, not assumed in advance.

Stage 1 — additive correction (default path):

gas_g_corrected = gas_g_raw − creep(Δt since disturbance) − thermal(T_measured)

Parameters (τ, plateau magnitude, α) come from 3E-008. Validate by checking the
residual after correction is small and structureless (consistent with existing
noise floor).

Stage 2 — recursive estimator (escalation path only):

Triggered only if Stage 1's residual retains structure after correction — evidence
creep and thermal interact rather than simply summing.

State vector: [W_true, creep_bias, burn_rate]. Temperature is measured directly,
not a hidden state — subtracted before the filter runs.

Process model: W(t+1) = W(t) − r(t)·Δt, b(t+1) = b(t)·e^(−Δt/τ), r(t+1) ≈ r(t).

Observation: raw(t) − α·(T(t) − T_ref) = W(t) + b(t) + noise(t).

Measurement noise variance = existing measured σ² (3E-001/002) — no new
characterisation needed.

Decision criterion: Stage 2 is only justified if Stage 1 fails validation. Do not
build Stage 2 speculatively.

Note: sections 39–40 are existing closing sections of this document. This section
was added in Session 63 as section 41.

END OF MEASUREMENT_AND_CALIBRATION_SPECIFICATION.md v1.0