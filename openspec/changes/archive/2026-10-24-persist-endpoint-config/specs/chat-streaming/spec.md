# Spec Delta

## ADDED Requirements

### Requirement: Durable endpoint configuration
The app SHALL write the configured base URL and model name to durable on-device settings
and restore them when the app starts, so an endpoint configured once remains in use after
a restart. The API key MUST NOT be written to that settings store; it SHALL continue to
reside only in secure, keystore-backed storage.

#### Scenario: Configuration survives a restart
- **WHEN** the user saves a base URL and model name, closes the app, and opens it again
- **THEN** the endpoint counts as configured and chat requests use the saved base URL and
  model without the user entering them again

#### Scenario: The API key stays out of plain settings
- **WHEN** the user saves an endpoint that includes an API key
- **THEN** the key is present only in secure storage and absent from the durable plain
  settings that hold the base URL and model

#### Scenario: A keyless endpoint survives a restart
- **WHEN** the user saves a base URL and model name with no API key and restarts the app
- **THEN** the base URL and model are restored, the endpoint still counts as configured,
  and requests carry no `Authorization` header

#### Scenario: First launch after the upgrade
- **WHEN** the app starts with an API key already in secure storage but no saved base URL
  or model
- **THEN** the endpoint counts as unconfigured until the user saves a base URL and model,
  after which both persist across later restarts
