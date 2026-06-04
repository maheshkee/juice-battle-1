# ARCHITECTURE_SPECIFICATION.md

## Version 1.0

## Status: Active Design

# 1. PURPOSE

This document defines the architecture of the Gas Cylinder Weight Monitor system.

It specifies:

System decomposition

Component responsibilities

Data ownership

Communication paths

State boundaries

Failure boundaries

Expansion paths

This document does not define:

Calibration mathematics

Gas estimation algorithms

Prediction algorithms

Those belong in their own specifications.

# 2. ARCHITECTURAL PRINCIPLES

The architecture is built around one central principle:

## Separation of Concerns

The system is divided into layers.

Each layer answers exactly one question.

### Sensor Layer

Question:

“What is the weight?”

### Domain Layer

Question:

“How much gas remains?”

### Analytics Layer

Question:

“What patterns exist?”

### Prediction Layer

Question:

“What will happen next?”

### Presentation Layer

Question:

“What should the user see?”

# 3. SYSTEM CONTEXT

The system exists inside a household environment.

Inputs:

Cylinder weight

User requests

Time

Outputs:

Gas remaining

Alerts

Predictions

Historical reports

# 4. HIGH-LEVEL ARCHITECTURE

Load Cell(s)      ↓HX711      ↓ESP32-C3      ↓WiFi Transport      ↓UNO Q Hub      ↓SQLite      ↓Analytics Engine      ↓Prediction Engine      ↓Dashboard / API

# 5. DESIGN PHILOSOPHY

The architecture deliberately creates:

## Dumb Sensor

and

## Smart Hub

The sensor node should remain simple.

The hub should own complexity.

Reason:

Sensors are difficult to update.

Software is easy to update.

Keep intelligence where updates are easiest.

# 6. COMPONENT INVENTORY

The system contains:

### Physical Components

Load Cell

HX711

ESP32-C3

UNO Q

Power Supply

Network

### Logical Components

Sensor Service

Transport Service

Storage Service

Analytics Service

Prediction Service

Presentation Service

# 7. SENSOR SUBSYSTEM

Purpose:

Convert physical force into trustworthy weight.

Components:

Load Cell

HX711

ESP32 Firmware

Outputs:

Validated Weight

Events

Health Reports

# 8. LOAD CELL ROLE

The load cell is the primary transducer.

Input:

Force

Output:

Tiny differential voltage

Responsibilities:

Measure force only.

Nothing else.

# 9. HX711 ROLE

The HX711 is the measurement front-end.

Responsibilities:

Amplification

ADC Conversion

Digital Interface

Output:

24-bit signed counts

The HX711 does not know:

Weight

Gas

Percentage

Calibration

# 10. ESP32 ROLE

The ESP32 is the Sensor Controller.

Responsibilities:

Read HX711

Filter corruption

Average samples

Apply calibration

Detect events

Transmit data

Monitor health

Non-Responsibilities:

Prediction

Historical storage

Business logic

# 11. WHY ESP32 OWNS CALIBRATION

Calibration belongs closest to measurement.

Reason:

The hub should never need raw HX711 counts.

The hub should receive physical units.

Therefore:

ESP32 converts:

Counts → Grams

UNO Q converts:

Grams → Knowledge

# 12. NODE OUTPUT CONTRACT

Every node produces:

Weight

Timestamp

Quality

Health

Node Identity

Nothing else is required.

This keeps nodes generic.

# 13. HUB SUBSYSTEM

Purpose:

Transform measurements into understanding.

Components:

Storage

Analytics

Prediction

Presentation

Input:

Measurements

Output:

Insights

# 14. STORAGE SUBSYSTEM

Purpose:

Preserve history.

Responsibilities:

Persist measurements

Persist events

Persist predictions

Maintain integrity

Rule:

Storage never invents information.

Storage preserves information.

# 15. ANALYTICS SUBSYSTEM

Purpose:

Generate understanding.

Inputs:

Historical measurements

Events

Derived quantities

Outputs:

Consumption metrics

Usage patterns

Anomaly indicators

# 16. PREDICTION SUBSYSTEM

Purpose:

Estimate future behavior.

Inputs:

Remaining gas

Burn rate

Historical trends

Outputs:

Days remaining

Expected depletion date

Confidence

# 17. PRESENTATION SUBSYSTEM

Purpose:

Communicate information.

Responsibilities:

Dashboard

Reports

Notifications

APIs

The presentation layer never performs calculations.

# 18. DATA OWNERSHIP

Every piece of information has one owner.

Raw Weight

Owner:

ESP32

Gas Remaining

Owner:

Domain Logic

Burn Rate

Owner:

Analytics

Days Remaining

Owner:

Prediction

Display State

Owner:

Presentation

# 19. TRANSPORT PHILOSOPHY

Transport moves information.

Transport never creates information.

Transport never modifies information.

Transport should be transparent.

# 20. COMMUNICATION MODEL

Hybrid Model:

Push

and

Pull

Push:

Node initiates communication.

Example:

Install event.

Pull:

Hub requests information.

Example:

Current weight request.

Both are required.

# 21. MESSAGE TYPES

Measurement

Event

Heartbeat

Command

Response

Diagnostic

All communication should fit one of these categories.

# 22. HEARTBEAT MODEL

Heartbeat is a system-level concept.

Purpose:

Prove liveness.

Create history.

Maintain synchronization.

Current cadence:

15 minutes.

# 23. EVENT MODEL

Events are state transitions.

Examples:

Install

Removal

Low Gas

Sensor Fault

Events should be sparse.

Events should be meaningful.

# 24. NODE STATE MACHINE

BOOT↓INITIALISE↓READY↓MEASURE↓DEGRADED↓FAILED

Each state has explicit entry and exit conditions.

# 25. HUB STATE MACHINE

STARTUP↓ONLINE↓SYNCING↓ANALYSING↓SERVING

The hub may occupy multiple logical states simultaneously.

# 26. CYLINDER STATE MACHINE

UNKNOWN↓FULL↓ACTIVE↓LOW↓EMPTY↓REMOVED↓REPLACED

This state machine drives business logic.

# 27. FAILURE BOUNDARIES

A failure in one subsystem should not destroy another.

Example:

WiFi failure must not stop measurement.

Example:

Prediction failure must not stop storage.

Isolation is mandatory.

# 28. RECOVERY STRATEGY

Every subsystem must support:

Detection

Classification

Recovery

Verification

Recovery without verification is incomplete.

# 29. SCALABILITY STRATEGY

Current:

1 Node 1 Cylinder 1 Hub

Future:

N Nodes N Cylinders 1 Hub

Future:

N Hubs Cloud

The architecture should scale without redesign.

# 30. ARCHITECTURAL DECISIONS

Locked:

ESP32-C3 sensor node

HX711 front-end

UNO Q hub

Weight-based sensing

WiFi-first transport

USB power

Open:

Cloud strategy

Multi-node synchronization

Companion app architecture

# 31. ARCHITECTURE SUMMARY

The architecture intentionally separates:

Measurement from Understanding

The ESP32 owns reality.

The UNO Q owns meaning.

The system remains simple because each component answers only one question.

END OF ARCHITECTURE_SPECIFICATION.md v1.0