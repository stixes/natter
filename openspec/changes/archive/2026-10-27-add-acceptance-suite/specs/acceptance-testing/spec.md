# Spec Delta

## Purpose

Confirms, in one command on a device, that a build still does what the shipped specs promise, so a release can be gated on evidence rather than on trust.

## ADDED Requirements

### Requirement: Acceptance suite release gate
The project SHALL provide an acceptance suite that confirms the key behaviors
of shipped capabilities end-to-end on a device, driven by a single command
whose exit status states whether the build is releasable. The command SHALL
start from a clean app state, and the full suite SHALL complete in under five
minutes on the default emulator target.

#### Scenario: Gate runs against a clean install
- **WHEN** the gate command is run with no prior app state on the device
- **THEN** the suite runs from an empty install and exits 0 when every
  scenario confirms

#### Scenario: Failing behavior blocks the gate
- **WHEN** a shipped key behavior is broken in the build under test
- **THEN** the gate command exits non-zero and names the scenario that failed

#### Scenario: Gate stays quick
- **WHEN** the full suite is run on the default emulator target
- **THEN** it completes in under five minutes

### Requirement: Suite hermeticity
The acceptance suite SHALL drive the real app against an endpoint provided by
the suite itself on the test device's loopback interface. The suite SHALL need
no external endpoint, no credential, and no build-time configuration values,
and while the suite runs the app SHALL reach no destination outside the device.

#### Scenario: Run with no configuration
- **WHEN** the gate command is run without any endpoint or key supplied from
  outside the suite
- **THEN** every scenario runs and confirms against the suite's own endpoint

#### Scenario: Nothing leaves the device
- **WHEN** the suite drives a full send, stream, and history round trip
- **THEN** the only network destination touched is the suite's loopback
  endpoint on the device

### Requirement: Shallow confirmations mapped to specs
Each acceptance scenario SHALL confirm the observable outcome of one scenario
from a shipped capability spec, and SHALL NOT assert internal state. Each test
file SHALL belong to one shipped capability, and each scenario SHALL name the
spec requirement it confirms.

#### Scenario: Requirement mapping is visible
- **WHEN** a developer opens any acceptance suite file
- **THEN** each scenario names the capability and requirement it confirms

#### Scenario: Failure stays shallow
- **WHEN** an acceptance scenario fails
- **THEN** the reported failure names the scenario and the observed outcome,
  without requiring diagnostic investigation of internals to read it

### Requirement: Future changes grow the suite
Every change with a spec delta that modifies a capability covered by the
acceptance suite SHALL include, in its task list, the additions or updates to
the suite that its spec delta implies, or SHALL record in its task list why no
suite change applies.

#### Scenario: Behavior change grows the suite
- **WHEN** a proposed change adds or modifies a user-visible behavior in a
  shipped capability
- **THEN** its tasks name the acceptance scenario to add or update

#### Scenario: Suite-less change records the exemption
- **WHEN** a proposed change has spec deltas but no acceptance scenario applies
- **THEN** its tasks record the reason no suite change is needed
