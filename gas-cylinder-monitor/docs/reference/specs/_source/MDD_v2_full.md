<!-- Source: Gas Cylinder Weight Monitor MDD 2.0 Part1.docx -->

# GAS CYLINDER WEIGHT MONITOR

# MASTER DESIGN DOCUMENT (MDD)

## Version 2.0

## Status: Active Design

## Date: 2026-06-03

# DOCUMENT PURPOSE

This document is the authoritative design reference for the Gas Cylinder Weight Monitor project.

It consolidates:

Product vision

Domain knowledge

Architecture decisions

Mathematical models

Calibration philosophy

Measurement theory

Analytics strategy

Prediction strategy

Engineering principles

Roadmap planning

This document is intended to survive hardware changes, software rewrites, transport changes, and implementation pivots.

The purpose is to preserve understanding.

# 1. EXECUTIVE SUMMARY

## Project Goal

Create a smart LPG monitoring system that continuously measures the weight of a gas cylinder, determines remaining LPG, learns household consumption behavior, predicts future depletion, and proactively warns users before gas runs out.

The long-term objective is not weight measurement.

The long-term objective is decision support.

The scale is merely the sensing mechanism.

The product value comes from:

Weight → Gas Remaining → Consumption Understanding → Prediction → Action

## Core Problem

Households typically discover an empty cylinder only after attempting to cook.

Existing methods are unreliable:

Lifting the cylinder by hand

Shaking the cylinder

Guessing based on time elapsed

Waiting until gas stops flowing

None provide:

Remaining gas

Daily consumption

Predicted depletion date

Usage patterns

The proposed system solves these problems through continuous weight measurement and intelligent interpretation.

## Product Philosophy

The project is built around several principles:

### Measurement before prediction

Predictions are worthless if measurements are wrong.

### Understanding before implementation

Every major design decision must be explainable from first principles.

### Small → Verify → Compound

Complex systems emerge from validated building blocks.

### No magic constants

Values should be measured, derived, or configurable.

### Continuous validation

Nothing is trusted forever.

Everything can drift.

Everything must be revalidated.

# 2. PRODUCT VISION

## Vision Statement

A household should always know:

How much gas remains.

How quickly it is being consumed.

When it will likely run out.

Whether current usage is normal.

without manually checking the cylinder.

## Immediate Benefits

### Remaining Gas

Users can view:

Remaining gas in grams

Remaining gas percentage

### Consumption Awareness

Users can understand:

Daily consumption

Weekly consumption

Monthly trends

### Run-Out Prediction

Users receive:

Days remaining

Expected depletion date

Early warning alerts

### Historical Understanding

The system becomes a long-term record of LPG usage.

Patterns emerge naturally:

Cooking frequency

Seasonal changes

Household behavior shifts

# 3. PRODUCT EVOLUTION ROADMAP

The project intentionally separates the complete vision from the first shipping version.

## V1 — Known Full Cylinder

### Assumption

The user installs the system when a fresh cylinder is delivered.

This assumption removes the hardest cold-start problem.

### Capabilities

Exact steel derivation

Exact gas remaining

Exact percentage

Burn-rate tracking

Consumption analytics

Days-remaining prediction

### Goal

Deliver useful value as quickly as possible.

## V2 — Assisted Partial Cylinder

### Scenario

A cylinder is already in use.

The system did not witness installation.

### Additional Inputs

The user may provide:

Stamped tare weight

Cylinder type

Other known information

### Result

The system can bootstrap gas estimates immediately.

## V3 — Fully Autonomous

### Scenario

Unknown cylinder.

Unknown state.

No user assistance.

### Strategy

Use:

Interval estimation

Refill detection

Empty-floor detection

Self-healing anchor logic

### Goal

Recover automatically over time.

# 4. SYSTEM OVERVIEW

## High-Level Architecture

Load Cell(s) ↓ HX711 ↓ ESP32-C3 Sensor Node ↓ WiFi ↓ UNO Q Hub ↓ Storage Analytics Prediction Presentation

## Why The Architecture Changed

Earlier designs used the UNO Q STM32 MCU as the sensor processor.

The architecture evolved into:

ESP32-C3 = Sensor Node

UNO Q = Hub

This separation creates clearer responsibilities.

## ESP32-C3 Mission

The ESP32 exists to answer one question:

“What is the weight right now?”

Responsibilities:

Read HX711

Filter noise

Detect invalid readings

Convert raw values

Detect events

Report measurements

The ESP32 does not own business logic.

## UNO Q Mission

The UNO Q exists to answer:

“What does the weight mean?”

Responsibilities:

Store measurements

Learn behavior

Predict future consumption

Present information

Serve applications

The UNO Q owns intelligence.

# 5. FUNDAMENTAL DOMAIN MODEL

This section contains the most important idea in the entire project.

## What The Scale Measures

The scale measures:

Gross Weight

Nothing else.

The scale does not measure:

Gas

Percentage

Burn rate

Days remaining

Those are derived quantities.

## The Fundamental Equation

Gross Weight = Steel Weight + Gas Weight

G = S + g

Where:

G = gross weight S = steel weight g = gas weight

## Why This Matters

The scale provides:

G

The user wants:

g

But:

G = S + g

contains two unknowns.

Therefore:

A single measurement cannot uniquely determine remaining gas.

This is a mathematical limitation.

Not a software limitation.

Not a sensor limitation.

Not an AI limitation.

The missing information must come from somewhere else.

# 6. THE CENTRAL INSIGHT

The entire project revolves around acquiring the missing equation.

Without it:

Remaining gas cannot be known.

With it:

The problem becomes trivial.

The rest of this document explains how the system acquires that missing information through anchor events, classification, and observation.

END OF PART 1

---

<!-- Source: Gas Cylinder Weight Monitor MDD 2.0 Part2.docx -->

# GAS CYLINDER WEIGHT MONITOR

# MASTER DESIGN DOCUMENT (MDD)

## Version 2.0

## PART 2 — LPG DOMAIN MODEL & GAS ESTIMATION THEORY

# 7. LPG DOMAIN KNOWLEDGE

Before building software, the physical reality of LPG cylinders must be understood.

The system exists in the physical world.

Therefore:

The physics and regulations governing LPG cylinders are more important than any algorithm.

## Domestic LPG In India

The project initially targets Indian domestic LPG cylinders.

The most common domestic cylinder contains:

Net LPG = 14.2 kg

This quantity is tightly regulated.

The exact fill may vary slightly due to permitted tolerance, but the nominal capacity remains fixed.

## Commercial LPG

Commercial cylinders exist in other capacities.

Examples include:

19 kg

47.5 kg

425 kg

These capacities are discrete and well separated.

This separation becomes important later for classification.

## Important Observation

Gas quantity is standardized.

Steel quantity is not.

This asymmetry drives the entire architecture.

# 8. THE STEEL PROBLEM

Every LPG cylinder consists of:

Steel Shell

LPG Contents

The steel shell remains on the scale throughout the life of the cylinder.

Only LPG leaves.

## Example

Full Cylinder

Steel = 15.3 kg

Gas = 14.2 kg

Gross = 29.5 kg

After Usage

Steel = 15.3 kg

Gas = 6.0 kg

Gross = 21.3 kg

Empty Cylinder

Steel = 15.3 kg

Gas = 0 kg

Gross = 15.3 kg

## Consequence

The scale never directly sees gas.

It always sees:

Steel + Gas

This is the fundamental challenge.

# 9. THE 52% TRAP

Many gas-monitor products make a conceptual mistake.

They assume:

percentage = current_weight / full_weight

## Example

Full:

29.5 kg

Empty:

15.3 kg

Incorrect Calculation:

15.3 / 29.5

≈ 52%

Result:

An empty cylinder appears half full.

This is catastrophic.

A user relying on such a gauge will run out unexpectedly.

## Design Rule

Any percentage calculation that does not explicitly remove steel weight is invalid.

This rule is non-negotiable.

# 10. HONEST GAS PERCENTAGE

The correct approach is:

Gas Remaining = Gross − Steel

Percentage = Gas Remaining / Capacity

## Domestic Example

Capacity = 14.2 kg

Steel = 15.3 kg

Gross = 21.3 kg

Gas Remaining:

21.3 − 15.3

= 6.0 kg

Percentage:

6.0 / 14.2

≈ 42%

## Interpretation

The gauge now correctly represents fuel.

Not total mass.

# 11. WHY BRAND DOES NOT MATTER

Early designs considered identifying:

Indane

HP

Bharat Gas

Others

This approach was ultimately rejected.

## Reason

Brand differences primarily affect:

Steel Weight

They do not significantly affect:

Gas Capacity

## What Users Care About

Users care about:

Gas Remaining

Not:

Cylinder Manufacturer

## Better Strategy

Measure steel directly.

Ignore brand.

Brand becomes unnecessary.

# 12. CAPACITY CLASSIFICATION

While steel varies continuously,

Capacity varies discretely.

This distinction is important.

## Example

Approximate Full Weights

Domestic 14.2 kg:

≈ 29–31 kg

Commercial 19 kg:

≈ 34–36 kg

47.5 kg:

Much larger

## Consequence

Capacity can often be classified from gross weight bands.

Steel cannot.

## Engineering Rule

Capacity should be classified.

Steel should be measured.

Never assume steel.

# 13. THE UNDERDETERMINED SYSTEM

This is the deepest concept in the project.

Suppose:

Gross = 22 kg

Question:

How much gas remains?

Possible Answer 1

Steel = 15.0 kg

Gas = 7.0 kg

Possible Answer 2

Steel = 15.5 kg

Gas = 6.5 kg

Possible Answer 3

Steel = 15.8 kg

Gas = 6.2 kg

All satisfy:

Gross = Steel + Gas

## Consequence

The problem has multiple valid solutions.

The system lacks sufficient information.

## Important Principle

No algorithm can recover information that does not exist.

The limitation is informational.

Not computational.

# 14. ANCHOR THEORY

The system needs a second equation.

That second equation arrives through anchor events.

## Definition

An Anchor Event is any moment where gas quantity becomes known.

Once gas is known,

Steel can be solved.

# 15. FULL INSTALL ANCHOR

Primary Anchor

Preferred Method

## Observation

A freshly delivered cylinder is full.

Therefore:

Gas = Capacity

## Equation

Gross Install = Steel + Capacity

Rearranging:

Steel = Gross Install − Capacity

## Example

Install Gross = 29.7 kg

Capacity = 14.2 kg

Steel =

29.7 − 14.2

= 15.5 kg

## Advantages

Automatic

No user input

No brand database

No waiting

Works every refill cycle

## Design Decision

Full Install Anchor is the primary calibration mechanism.

# 16. EMPTY FLOOR ANCHOR

Secondary Anchor

Cross-check Method

## Observation

An empty cylinder contains:

Gas ≈ 0

Therefore:

Gross ≈ Steel

## Advantages

Direct measurement

Very accurate

## Limitations

Not guaranteed.

Many users replace cylinders before reaching true empty.

## Design Decision

Use as verification.

Never depend on it.

# 17. CYLINDER LIFE CYCLE

Every cylinder naturally moves through states.

UNKNOWN ↓ FULL ↓ ACTIVE ↓ LOW ↓ EMPTY ↓ REMOVED ↓ REPLACED

## Importance

Every transition creates information.

The system should exploit these transitions.

# 18. PARTIAL CYLINDER COLD START

This is the hardest case.

Scenario:

System powers on.

Cylinder already exists.

No installation observed.

No removal observed.

No history exists.

Available Information:

Gross Weight

Only.

Unknown:

Steel

Gas

Result:

Exact gas quantity cannot be determined.

# 19. INTERVAL ESTIMATION

Although exact gas is impossible,

Bounds are possible.

Example

Gross = 22 kg

Steel Range:

14.5 – 15.8 kg

Gas Minimum:

22 − 15.8

= 6.2 kg

Gas Maximum:

22 − 14.5

= 7.5 kg

Result

Gas ∈ [6.2, 7.5]

Percentage

44% – 53%

## Interpretation

The system cannot know the exact value.

But it can provide an honest confidence interval.

# 20. CONSERVATIVE REPORTING

When uncertainty exists,

the system should bias toward safety.

Example

Interval:

44% – 53%

Report:

44%

or

“At least 44% remains”

Reason

False pessimism causes early ordering.

False optimism causes outages.

Outages are worse.

# 21. SELF-HEALING PROPERTY

The cold-start problem is temporary.

Eventually one of two events occurs:

Refill

Empty floor

Both are anchors.

Both solve steel.

Once steel is known,

all future estimates become exact.

## Important Insight

The system becomes smarter simply by existing longer.

Time creates information.

# 22. THE ROLE OF USER INPUT

User input should never be mandatory.

However,

user input can accelerate convergence.

Examples

Stamped tare weight

Cylinder type

Known refill date

These inputs are optional.

The system must remain functional without them.

# 23. V1 / V2 / V3 ESTIMATION STRATEGY

V1

Known full install

Exact estimation

V2

Partial cylinder

User-assisted estimation

V3

Autonomous estimation

Anchor-driven convergence

# 24. DOMAIN MODEL SUMMARY

The entire gas estimation problem can be summarized as:

Known:

Gross

Unknown:

Steel

Gas

Need:

Second equation

Acquire through:

Anchor Events

Solve:

Steel

Then:

Gas = Gross − Steel

Everything else in the project depends on this understanding.

END OF PART 2