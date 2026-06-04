# ANALYTICS_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines the Analytics Layer.

The Analytics Layer transforms:

Measurements ↓ Information ↓ Understanding

It answers:

How much gas was used?

How quickly is it being used?

Is usage changing?

Is behavior normal?

Is something unusual happening?

This document does not define:

Sensor calibration

Gas estimation

Prediction algorithms

Those belong elsewhere.

# 2. ANALYTICS PHILOSOPHY

The purpose of analytics is not complexity.

The purpose is understanding.

The analytics layer should answer:

“What has happened?”

Prediction answers:

“What will happen?”

# 3. ANALYTICS HIERARCHY

Level 1

Measurements

Level 2

Consumption

Level 3

Patterns

Level 4

Anomalies

Level 5

Prediction Inputs

Each level depends on the previous level.

# 4. FUNDAMENTAL ANALYTIC

The most important analytic is:

Consumption

Everything else depends on consumption.

# 5. CONSUMPTION THEORY

Recall:

text id="vjjh6r" Gross = Steel + Gas

Previous Measurement

text id="jv11s5" G₀ = S + g₀

Current Measurement

text id="3wgvsm" G₁ = S + g₁

Consumption

text id="8sl1aq" G₀ - G₁

Steel cancels.

Result:

Consumption can be measured immediately.

Even before steel is known.

# 6. DELTA ENGINE

Purpose:

Calculate change between measurements.

Formula

text id="fxslpn" Δ = Previous - Current

Positive

Consumption

Near Zero

Stable

Negative

Potential refill

Potential anomaly

Potential error

# 7. DAILY CONSUMPTION

Definition:

Gas used during a calendar day.

Units:

grams/day

Examples

120 g/day

350 g/day

900 g/day

Daily consumption is the first meaningful metric.

# 8. DAILY CONSUMPTION QUALITY

Daily consumption should include:

Value

Confidence

Data Completeness

Example

text id="qv4h5t" 412 g/day Confidence: High Coverage: 100%

# 9. WEEKLY CONSUMPTION

Purpose:

Reduce day-to-day noise.

Benefits:

More stable trends

Less sensitive to unusual events

Better prediction inputs

Weekly behavior often matters more than daily behavior.

# 10. MONTHLY CONSUMPTION

Purpose:

Understand long-term behavior.

Examples

Seasonal changes

Family changes

Lifestyle changes

Travel periods

Monthly metrics reveal structural trends.

# 11. BURN RATE

Burn Rate is the most important derived metric.

Definition

Average gas consumed per day.

Formula

text id="6is3h6" Burn Rate = Total Consumption / Elapsed Days

Units

grams/day

# 12. BURN RATE TYPES

Instantaneous

Short-Term

7-day average

Medium-Term

30-day average

Cycle Average

Entire cylinder cycle

Each has different uses.

# 13. WHY MULTIPLE BURN RATES EXIST

Different time horizons answer different questions.

Short-Term

Current behavior

Long-Term

Typical behavior

Cycle Average

Historical behavior

No single burn rate is sufficient.

# 14. MOVING AVERAGES

Purpose:

Reduce noise.

Examples

3-day

7-day

14-day

30-day

Moving averages reveal trends.

# 15. TREND ANALYSIS

Questions:

Is usage increasing?

Is usage decreasing?

Is usage stable?

Trend is more important than individual measurements.

# 16. CONSUMPTION VARIABILITY

Definition:

How much usage fluctuates.

Low Variability

Predictable household

High Variability

Unpredictable household

Variability affects prediction confidence.

# 17. STABILITY SCORE

Purpose:

Quantify consistency.

Inputs

Burn Rate Variance

Trend Stability

Measurement Quality

Output

Stable

Moderate

Variable

# 18. SESSION THEORY

Cooking typically occurs in sessions.

Examples

Breakfast

Lunch

Dinner

Sessions create recognizable consumption patterns.

# 19. SESSION DETECTION

Potential indicators:

Weight decrease

Stable plateau

Weight decrease

Stable plateau

Purpose:

Understand behavior.

Not required for V1.

# 20. DAILY PROFILE

The system may learn:

Morning usage

Afternoon usage

Evening usage

Creates a behavioral fingerprint.

Future capability.

# 21. CYLINDER CYCLE ANALYTICS

Each cylinder cycle becomes a learning unit.

Metrics

Duration

Total Consumption

Average Burn Rate

Prediction Accuracy

Cycle analytics improve future performance.

# 22. ANOMALY DETECTION

Purpose:

Identify unusual behavior.

Not necessarily faults.

Simply:

Unexpected observations.

# 23. ANOMALY TYPES

Measurement anomalies

Consumption anomalies

Prediction anomalies

System anomalies

Each category should be treated separately.

# 24. CONSUMPTION ANOMALIES

Examples

Sudden spike

Sudden drop

Extended inactivity

Unexpected pattern

These deserve investigation.

# 25. REFILL ANOMALIES

Example

Weight increases.

Possible Causes

Refill

Measurement error

Incorrect state

Analytics should classify before concluding.

# 26. LEAK DETECTION THEORY

Future capability.

Concept:

Detect gas loss inconsistent with normal use.

Potential indicators:

Continuous decline

Night-time consumption

Persistent weight loss

Leak detection is an analytics problem.

Not a sensor problem.

# 27. HEALTH ANALYTICS

The analytics layer also evaluates system behavior.

Metrics

Noise Growth

Calibration Stability

Measurement Completeness

Transport Reliability

Purpose:

Trust assessment.

# 28. CONFIDENCE MODEL

Every analytic should include confidence.

Bad

text id="sm7szt" Burn Rate = 450 g/day

Better

text id="ivgajy" Burn Rate = 450 g/day Confidence = High

# 29. CONFIDENCE INPUTS

History Depth

Measurement Quality

Variability

Completeness

More evidence

Higher confidence

# 30. ANALYTICS SNAPSHOTS

Store periodic analytics results.

Purpose

Historical comparison

Trend tracking

Auditability

Examples

Burn rate history

Variability history

Stability history

# 31. DASHBOARD METRICS

Recommended V1 Dashboard

Current Gas

Gas Percentage

Burn Rate

Days Remaining

Last Update

Everything else is secondary.

# 32. V1 ANALYTICS SCOPE

Included

Daily Usage

Weekly Usage

Burn Rate

Cycle Metrics

Excluded

Leak Detection

Behavior Fingerprints

Advanced Pattern Recognition

# 33. FUTURE ANALYTICS

Potential additions:

Seasonality

Behavior Modeling

Household Classification

Usage Forecasting

Anomaly Scoring

Leak Analytics

All depend on historical data.

# 34. ANALYTICS ACCEPTANCE CRITERIA

Analytics accepted when:

Explainable

Repeatable

Auditable

Measurement-based

No black-box metrics.

# 35. ANALYTICS SUMMARY

The Analytics Layer transforms:

Measurements ↓ Consumption ↓ Patterns ↓ Understanding

Its purpose is not to predict the future.

Its purpose is to explain the past and present.

Prediction is built on top of analytics.

END OF ANALYTICS_SPECIFICATION.md v1.0