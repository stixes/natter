# continuous-integration Specification

## Purpose

Gives every commit an unattended, reproducible verdict on whether the build is
releasable, so quality gates stop depending on a developer remembering to run
them or on one always-on machine being available.

## Requirements

### Requirement: Every push gets a build verdict

The project SHALL run an unattended build for every push to any branch and on
explicit manual request, and SHALL attach the resulting verdict to the exact
commit tested, so that a commit's releasability is readable without asking a
developer.

#### Scenario: Push to a working branch is built

- **WHEN** a commit is pushed to any branch of the repository
- **THEN** the build runs for that commit and its verdict is attached to it

#### Scenario: Manual request runs the same build

- **WHEN** a build is started by explicit manual request rather than by a push
- **THEN** the same stages run and produce the same kind of verdict

#### Scenario: A commit is built once

- **WHEN** a commit is reachable both as a branch push and as the head of an
  open pull request in this repository
- **THEN** that commit is built once rather than twice

### Requirement: Superseded runs are cancelled, the newest is not

When several pushes land on the same branch, the build SHALL cancel superseded
runs and complete the newest one. A run on the default branch SHALL NOT be
cancelled. A cancelled run SHALL never be readable as a pass.

#### Scenario: Rapid pushes on a branch settle on the newest

- **WHEN** two pushes land on the same branch while the first build is still
  running
- **THEN** the superseded run is cancelled and the newest commit reaches a
  verdict

#### Scenario: Default branch always reaches a verdict

- **WHEN** two pushes land on the default branch while the first build is still
  running
- **THEN** neither run is cancelled and both reach a verdict

#### Scenario: Cancellation is not a pass

- **WHEN** a run is cancelled before its stages complete
- **THEN** that commit has no passing verdict, and the newest commit's verdict
  is the one that stands

### Requirement: The gate runs unattended on a device the build provisions

The build SHALL run, end to end and unattended, the static checks, the unit
tests, and the acceptance release gate against a throwaway device that the
build itself provisions. It SHALL need no credential, no secret, and no
endpoint configured from outside the repository, and while the release gate
runs the app SHALL reach no destination beyond the gate's own loopback
endpoint.

#### Scenario: Gate confirms without any external configuration

- **WHEN** the build runs the acceptance release gate with nothing configured
  outside the repository
- **THEN** the gate runs to completion on the provisioned device and its exit
  status forms the verdict

#### Scenario: No credential is required

- **WHEN** the build runs in a state where no secret or credential is available
  to it
- **THEN** every stage still runs and reaches a verdict

#### Scenario: Nothing leaves the device in CI

- **WHEN** the acceptance gate drives a full send, stream, and history round
  trip in CI
- **THEN** the only destination touched is the gate's own loopback endpoint on
  the device

### Requirement: CI exercises the declared toolchain

The toolchain that the build exercises SHALL be pinned to the versions the dev
environment declares, and the build SHALL verify those pins before running any
test, failing loudly when a version differs from the declared one.

#### Scenario: Pin drift is caught before tests

- **WHEN** a stage of the build starts on a toolchain version that differs from
  the version the project declares
- **THEN** the build fails before any test runs, naming the version that
  differed

#### Scenario: Declared toolchain proceeds

- **WHEN** every pinned toolchain version matches what the project declares
- **THEN** the build proceeds to the test stages

### Requirement: A failure names its stage and leaves evidence

A build failure SHALL name the stage that failed, and SHALL distinguish a build
that could not run its release gate from a gate that says the build is not
releasable. Evidence for the failing stage SHALL be retrievable from the run.

#### Scenario: Provisioning failure is not a verdict about the build

- **WHEN** the device the build provisions fails to become usable
- **THEN** the failure names device provisioning as the stage and does not
  report the build as not releasable

#### Scenario: Gate failure names the scenario

- **WHEN** the release gate exits non-zero on a scenario it ran
- **THEN** the failed stage is named and the failing scenario is readable in
  the run's output

#### Scenario: Device evidence survives the run

- **WHEN** a stage that ran on the provisioned device fails
- **THEN** that stage's log and the device-side log are retrievable after the
  run finishes

### Requirement: A full build stays inside its time budget

A full build SHALL reach a verdict within fifteen minutes of starting, and
SHALL record the duration of each stage so that an overrun names the stage
responsible.

#### Scenario: Budget is met

- **WHEN** a full build runs against a build whose gates pass
- **THEN** it reaches a verdict within fifteen minutes of starting

#### Scenario: Overrun is attributable

- **WHEN** a full build exceeds its budget
- **THEN** the recorded stage durations name which stage consumed the time

### Requirement: Pushes are watched before moving on

A push SHALL be followed by reading the verdict of the newest build for the
pushed commit before the project moves on to the next change, archives a
change, or calls a build releasable. A failed verdict SHALL be fixed, re-run,
or recorded as debt; it SHALL NOT be passed over in silence.

#### Scenario: Red verdict blocks the next step

- **WHEN** the newest build for a pushed commit fails
- **THEN** the next change is not started, and the change is either fixed or
  its failure is recorded as debt before anything else proceeds

#### Scenario: No verdict is not a green verdict

- **WHEN** the newest build for a pushed commit is cancelled or still running
- **THEN** the push is treated as having no verdict, and the build is awaited
  or re-started rather than assumed green
