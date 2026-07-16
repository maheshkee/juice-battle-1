# PREDICTION_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines the Prediction Layer.

The Prediction Layer transforms:

Measurements ↓ Analytics ↓ Forecasts

It answers:

When will gas run out?

How many days remain?

How confident are we?

How accurate have previous predictions been?

This document does not define:

Sensor calibration

Gas estimation

Storage

Analytics generation

Those belong elsewhere.

# 2. PREDICTION PHILOSOPHY

Predictions are estimates.

Not facts.

Not guarantees.

Not promises.

The system should communicate:

Expected Outcome

and

Uncertainty

Both are equally important.

# 3. PRIMARY OBJECTIVE

The prediction system exists to answer one question:

text id="frd8mp" When should the user order a replacement cylinder?

Everything else is secondary.

# 4. PREDICTION HIERARCHY

Level 1

Current State

Level 2

Consumption Rate

Level 3

Future Projection

Level 4

Confidence

Level 5

Decision Support

Each level depends on the previous level.

# 5. INPUTS

The prediction engine consumes:

Remaining Gas

Burn Rate

Usage Variability

Measurement Quality

History Depth

Cylinder Cycle Data

Predictions never operate directly on raw HX711 data.

# 6. PREDICTION V0.1

Simplest possible forecast.

Formula

text id="1wyh3f" Days Remaining = Remaining Gas / Burn Rate

Example

Remaining Gas

6 kg

Burn Rate

500 g/day

Days Remaining

text id="2aw7ui" 6000 / 500 = 12 Days

This becomes the first working forecast.

# 7. WHY V0.1 EXISTS

Purpose:

Simplicity

Transparency

Explainability

A simple prediction that users understand is better than a complex prediction nobody trusts.

# 8. PREDICTION V0.2

Adds:

Moving Average Burn Rates

Instead of:

Today’s usage

Use:

7-day average

14-day average

30-day average

Benefits:

Reduced noise

Improved stability

Better forecasts

# 9. PREDICTION V1.0

Adds:

Consumption Variability

Trend Awareness

Confidence Scoring

Prediction History

Still explainable.

Still auditable.

# 10. REMAINING GAS

Prediction starts with:

Gas Remaining

Source:

Domain Layer

Formula

text id="a7f5xl" Gas Remaining = Gross - Steel

Prediction assumes this value is available.

# 11. BURN RATE

Prediction quality depends heavily on burn rate quality.

Burn Rate Types

Instantaneous

7-Day

30-Day

Cycle Average

Selection depends on confidence.

# 12. WHICH BURN RATE TO USE

Short History

Use:

Recent burn rate

Long History

Use:

Weighted averages

Multiple completed cycles

Use:

Hybrid model

The system evolves naturally.

# 13. FORECAST WINDOW

Predictions become less reliable farther into the future.

Short Horizon

1–7 days

High confidence

Medium Horizon

7–30 days

Moderate confidence

Long Horizon

30+ days

Lower confidence

# 14. CONFIDENCE PHILOSOPHY

Every prediction must include confidence.

Bad

text id="lbpmij" 12 days remaining

Better

text id="t5a56m" 12 days remaining Confidence: Medium

Best

text id="6pofhp" 12 days remaining Range: 10–14 days Confidence: Medium

# 15. CONFIDENCE FACTORS

Confidence depends on:

History Depth

Measurement Quality

Usage Stability

Prediction Accuracy History

More evidence

Higher confidence

# 16. HISTORY DEPTH SCORE

Example

1 Day

Low confidence

1 Week

Medium confidence

1 Month

High confidence

Multiple Cycles

Very high confidence

# 17. VARIABILITY PENALTY

Stable households are easier to predict.

Example

450 g/day

460 g/day

440 g/day

455 g/day

Very predictable.

Example

100 g/day

900 g/day

50 g/day

1200 g/day

Much harder.

Prediction confidence decreases.

# 18. PREDICTION RANGE

Single-number forecasts create false certainty.

Preferred Format

```text id=“4s5av9” Expected: 12 days

Range: 10–14 days ```

This better represents uncertainty.

# 19. CONSERVATIVE BIAS

The system intentionally favors safety.

Reason

Running out of gas is worse than ordering early.

Therefore:

When uncertain,

lean toward shorter forecasts.

# 20. EARLY WARNING PHILOSOPHY

Prediction only becomes useful when linked to action.

Example

10 Days Remaining

Possible Action

Monitor

5 Days Remaining

Possible Action

Consider ordering

2 Days Remaining

Possible Action

Order immediately

# 21. ALERT THRESHOLDS

Thresholds should be configurable.

Examples

10 days

5 days

2 days

Different households have different needs.

# 22. PREDICTION HISTORY

Every prediction should be stored.

Purpose

Auditability

Accuracy Measurement

Model Improvement

Prediction history is critical.

# 23. WHY STORE PREDICTIONS

Without storage:

No evaluation possible.

With storage:

Forecast quality becomes measurable.

The system can improve itself.

# 24. FORECAST ACCURACY

Question

Was the prediction correct?

Measure

Predicted Empty Date

Actual Empty Date

Difference

This becomes a key metric.

# 25. FORECAST ERROR

Definition

Prediction

minus

Reality

Example

Predicted:

12 June

Actual:

14 June

Error:

2 Days

This should be tracked continuously.

# 26. CYLINDER-CYCLE LEARNING

Each completed cycle becomes training data.

Stored Information

Burn Rate

Forecast Accuracy

Usage Pattern

Cycle Duration

Knowledge compounds.

# 27. MODEL EVOLUTION

Prediction quality should improve naturally.

Cycle 1

Basic understanding

Cycle 2

Better understanding

Cycle 5

Strong understanding

The system becomes smarter through observation.

# 28. REFILL-AWARE PREDICTION

Refills provide strong feedback.

Known:

Cycle ended

Useful for:

Forecast validation

Burn-rate refinement

Confidence adjustment

# 29. FAILURE CONDITIONS

Predictions should refuse certainty when evidence is weak.

Examples

Insufficient history

Missing measurements

Poor calibration

Unstable usage

Response

Reduce confidence

Increase range

Never pretend certainty.

# 30. V1 PREDICTION SCOPE

Included

Days Remaining

Expected Empty Date

Basic Confidence

Prediction History

Excluded

Machine Learning

Behavior Forecasting

Seasonality Models

Cloud Intelligence

# 31. FUTURE PREDICTION CAPABILITIES

Potential additions:

Seasonal Modeling

Holiday Effects

Behavior Forecasting

Adaptive Forecasts

Fleet Intelligence

Multi-Cycle Optimization

All depend on accumulated history.

# 32. PREDICTION ACCEPTANCE CRITERIA

Prediction system accepted when:

Forecasts are explainable

Forecasts are auditable

Confidence is reported

Historical accuracy is measurable

Users can understand outputs

No black-box forecasting.

# 33. PREDICTION SUMMARY

The Prediction Layer transforms:

Remaining Gas

Consumption Behavior ↓ Future Expectations

Its purpose is not to predict perfectly.

Its purpose is to provide useful, honest, and actionable forecasts with clearly communicated uncertainty.

The system should always prefer an honest estimate over a confident but incorrect prediction.

END OF PREDICTION_SPECIFICATION.md v1.0