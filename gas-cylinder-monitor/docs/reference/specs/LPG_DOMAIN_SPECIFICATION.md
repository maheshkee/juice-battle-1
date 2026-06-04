# LPG_DOMAIN_AND_ESTIMATION_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines:

LPG domain knowledge

Gas estimation theory

Anchor theory

Cylinder modeling

Cold-start handling

Percentage calculation

Steel learning

Refill detection

Confidence estimation

This document answers:

“How do we convert weight into gas information?”

This document does not define:

Sensor calibration

Storage

Prediction

Those belong elsewhere.

# 2. FUNDAMENTAL DOMAIN PRINCIPLE

The scale measures:

Gross Weight

The user wants:

Gas Remaining

These are not the same thing.

# 3. CYLINDER MODEL

Every LPG cylinder is modeled as:

Gross Weight=Steel Weight+Gas Weight

Variables:

G = Gross Weight

S = Steel Weight

g = Gas Weight

Equation:

G = S + g

This is the fundamental equation of the entire product.

# 4. WHAT THE USER CARES ABOUT

The user does not care about:

Steel Weight

Gross Weight

HX711 Counts

Calibration Factors

The user cares about:

Remaining Gas

Gas Percentage

Days Remaining

Everything in this document exists to bridge that gap.

# 5. THE STEEL PROBLEM

Steel weight remains on the scale forever.

Only gas changes.

Example

Full Cylinder

Steel = 15.3 kg

Gas = 14.2 kg

Gross = 29.5 kg

Partially Used

Steel = 15.3 kg

Gas = 6.0 kg

Gross = 21.3 kg

Empty

Steel = 15.3 kg

Gas = 0

Gross = 15.3 kg

The scale always sees:

Steel + Gas

Never gas alone.

# 6. THE 52% TRAP

Incorrect Formula:

percentage =current_weight/full_weight

Example

Empty Cylinder

15.3 / 29.5

≈ 52%

Result:

An empty cylinder appears half full.

This is unacceptable.

Rule:

Any gas estimation algorithm that does not explicitly remove steel weight is invalid.

# 7. CORRECT GAS ESTIMATION

Gas Remaining:

g = G - S

Gas Percentage:

percentage =gas_remaining/capacity

For a domestic cylinder:

percentage =(G - S)/14.2

This produces physically meaningful percentages.

# 8. INDIAN LPG DOMAIN FACTS

Initial target:

Indian domestic LPG cylinders.

Nominal LPG quantity:

14.2 kg

Commercial examples:

19 kg

47.5 kg

425 kg

Observation:

Capacity is standardized.

Steel is not.

# 9. CAPACITY VS STEEL

Capacity:

Discrete

Predictable

Classifiable

Steel:

Continuous

Variable

Must be measured

Engineering Rule:

Classify Capacity.

Learn Steel.

# 10. WHY BRAND IS IRRELEVANT

Early approaches considered:

Indane

HP

Bharat Gas

Others

This was rejected.

Reason:

Brand mostly influences:

Steel Weight

Brand does not directly solve:

Gas Remaining

The system learns steel directly.

Therefore:

Brand becomes unnecessary.

# 11. THE UNDERDETERMINED SYSTEM

This is the most important concept in the product.

Suppose:

Gross = 22 kg

Question:

How much gas remains?

Possibility A

Steel = 15.0

Gas = 7.0

Possibility B

Steel = 15.5

Gas = 6.5

Possibility C

Steel = 15.8

Gas = 6.2

All are valid.

Therefore:

One measurement cannot uniquely determine gas.

# 12. INFORMATION THEORY VIEW

The problem is not:

Bad software

Bad hardware

Bad mathematics

The problem is:

Missing information.

No algorithm can recover information that was never observed.

# 13. ANCHOR THEORY

The solution is to acquire additional information.

Definition:

Anchor Event

A moment when gas quantity becomes known.

Once gas is known:

Steel becomes solvable.

# 14. PRIMARY ANCHOR

Full Install Anchor

Observation:

A newly delivered cylinder is full.

Known:

Gas = Capacity

Therefore:

Steel=Install Gross-Capacity

Example

Install Weight = 29.7 kg

Capacity = 14.2 kg

Steel = 15.5 kg

This becomes the preferred anchor.

# 15. SECONDARY ANCHOR

Empty Floor Anchor

Observation:

Gas ≈ 0

Therefore:

Steel≈Gross

Advantages

Direct

Simple

Accurate

Disadvantages

Not guaranteed

Many users replace early

Use as validation.

Not dependence.

# 16. STEEL LEARNING

Every anchor creates knowledge.

Example

Cycle 1

Steel = 15.3

Cycle 2

Steel = 15.6

Cycle 3

Steel = 15.4

The system accumulates steel observations.

This history becomes valuable.

# 17. CYLINDER IDENTITY

The system primarily tracks:

Cylinder Cycles

not

Cylinder Objects

Reason:

Users exchange cylinders.

Ownership changes.

History may not follow the same physical shell.

The useful unit is:

Install → Usage → Replacement

# 18. COLD START

Cold Start:

System starts with no history.

Known:

Gross

Unknown:

Steel

Gas

Exact estimation impossible.

# 19. INTERVAL ESTIMATION

Cold-start systems should estimate bounds.

Example

Gross = 22 kg

Assume:

Steel Range

14.5–15.8 kg

Gas Minimum

22 − 15.8

= 6.2 kg

Gas Maximum

22 − 14.5

= 7.5 kg

Result:

Gas ∈ [6.2, 7.5]

# 20. CONFIDENCE INTERVALS

The system should communicate uncertainty honestly.

Bad:

48%

Better:

44–53%

Best:

At least 44%

Confidence: Medium

# 21. CONSERVATIVE REPORTING

When uncertain:

Bias toward safety.

Reason:

False pessimism causes earlier ordering.

False optimism causes outages.

Outages are worse.

# 22. SELF-HEALING PROPERTY

Cold start is temporary.

Eventually:

Refill occurs

or

Empty anchor occurs

Both solve steel.

After that:

Estimation becomes exact.

The system becomes smarter naturally.

# 23. REFILL DETECTION

Definition:

Detect transition from used cylinder to full cylinder.

Characteristics

Large positive weight jump

State transition

Persistence

Refill detection creates anchor opportunities.

# 24. REMOVAL DETECTION

Definition:

Cylinder removed from platform.

Characteristics

Weight approaches scale zero.

This creates:

Maintenance opportunity

Potential recalibration opportunity

State transition

# 25. DELTA TRACKING

One of the strongest concepts in the project.

Recall:

G = S + g

Usage:

Previous Weight

Current Weight

Steel cancels.

Result:

Usage can be measured immediately.

Even when steel is unknown.

# 26. WHY DELTA TRACKING MATTERS

Analytics can begin on Day 1.

No anchor required.

No brand required.

No tare required.

Only two measurements are needed.

# 27. CONSUMPTION MODEL

Consumption is observed.

Never assumed.

The system measures:

Actual household behavior.

Not:

Internet averages

Supplier averages

Population averages

# 28. V1 ESTIMATION MODEL

Assumption:

Fresh install.

Known:

Gas = Capacity

Result:

Exact steel.

Exact percentage.

Exact gas remaining.

Simplest and strongest version.

# 29. V2 ESTIMATION MODEL

Partial cylinder.

User-assisted.

Possible inputs:

Stamped tare

Known refill date

Cylinder type

System converges faster.

# 30. V3 ESTIMATION MODEL

Unknown cylinder.

Unknown history.

No assistance.

Uses:

Interval estimation

Anchor detection

Refill learning

Self-healing

Most sophisticated version.

# 31. DOMAIN ACCEPTANCE CRITERIA

The domain model is accepted when:

Every percentage calculation removes steel.

Every estimate reports confidence.

Cold-start behavior is honest.

Anchor transitions are handled correctly.

Refill cycles improve knowledge.

# 32. DOMAIN SUMMARY

The LPG estimation problem is fundamentally an information problem.

Known:

Gross Weight

Unknown:

Steel Weight

Gas Weight

Need:

Second Equation

Acquire Through:

Anchor Events

Then:

Steel becomes known.

Gas becomes known.

Percentage becomes honest.

Prediction becomes possible.

Everything in the product depends on this chain.

END OF LPG_DOMAIN_AND_ESTIMATION_SPECIFICATION.md v1.0