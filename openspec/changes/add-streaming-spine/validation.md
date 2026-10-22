# Validation record: on-device (tasks 7.1, 7.3)

Device: <device>, Android 17 / API 37, connected by wireless adb.
Endpoint: llama-swap on the LAN at `http://<llama-swap-host>:8000/v1`
(a llama.cpp front, which is the endpoint family this change exists for).
Models: `gemma4-26b-a4b` (streams `content` only), `qwen3.6-35b-a3b`
(streams `reasoning_content`, then `content`).

Harness: `integration_test/streaming_spine_test.dart`, one test per round so a
Wi-Fi dropout costs one round rather than the suite. Each round starts from
`pm clear dev.natter.app`.

## Result

| round | result | what was observed |
| --- | --- | --- |
| 7.1 plain model | pass | `Waiting.` placeholder, answer text grew over 4-8 polls, reply reached 60 in full, no placeholder ever rendered as message body, no thinking state invented |
| 7.1 thinking model | pass | `Waiting` then `Thinking` observed in that order, answer grew over 9-11 polls; wire check for the same prompt showed 2580 chars of `reasoning_content` against 923 chars of `content`, and the rendered body matched the `content` text, so reasoning stayed hidden |
| 7.1 with no API key | pass | a keyless local endpoint configures, enables Send, and streams; proves the keyless fix below |
| 7.3 cancel mid-answer | pass | partial answer committed as one turn, placeholder and the Stop affordance both gone |
| 7.3 cancel during thinking | pass | cancels with only reasoning captured commit nothing, and the conversation is still usable: the next send streamed and answered |
| 7.3 blank-answer fallback | pass | against `integration_test/support/mock_reasoning_endpoint.py` (reasoning only, no answer text): one commit of the reasoning as the answer, `growth=1` proving reasoning was never rendered as answer text while streaming |
| 7.3 error + retry | pass | unreachable endpoint surfaced `Cannot reach the endpoint: No route to host` with Retry; Retry streamed a reply and cleared the banner |

Command shape (one round at a time; `--plain-name` selects it):

```
adb -s <device> shell pm clear dev.natter.app
flutter test integration_test -d <device> --timeout 9m \
  --plain-name "7.1 plain" \
  --dart-define=NATTER_BASE_URL=http://<llama-swap-host>:8000/v1 \
  --dart-define=NATTER_BAD_URL=http://<llama-swap-host>:1/v1 \
  --dart-define=NATTER_MOCK_URL=http://<dev-box>:8010/v1 \
  --dart-define=NATTER_PLAIN_MODEL=gemma4-26b-a4b \
  --dart-define=NATTER_THINKING_MODEL=qwen3.6-35b-a3b \
  --dart-define=NATTER_API_KEY=
```

## What the device caught that the suite did not

**Keyless endpoints were unusable.** `EndpointProfile.isConfigured` demanded a
non-empty API key, so a local llama.cpp / llama-swap server, which answers `200`
to unauthenticated requests, left Send disabled with the app otherwise
configured. The proposal's own stated use case is "point the app at a live
llama.cpp server", so this is a bug against this change rather than new scope:
URL plus model now make an endpoint usable, an empty key sends no `Authorization`
header, and the settings helper says the key is optional. Covered by a spec
scenario plus unit tests, and re-validated on-device with `NATTER_API_KEY` empty.

**A thinking-phase cancel was untested behaviour.** Cancelling while only
reasoning has arrived commits nothing. That is the existing intent, and the right
one - half a chain of thought is not an answer - but nothing pinned it, so it is
now a spec scenario, a unit test, and an on-device round.

**Android's cleartext policy does not apply to this app.** The block lives in the
platform's HTTP stack; `dart:io` opens its own sockets. So the `http://` base URL
in the settings helper is accurate, and no network security config is needed.
Recording this because the opposite assumption nearly produced a config change.

## Still open

- **OpenRouter is not run.** Descoped from this change on purpose: MVP is BYO-endpoint
  with no hosted-provider requirement, and no key was available. Consequence, stated
  plainly: the `reasoning_content` vs `reasoning` superset is proven only against a
  llama.cpp-family gateway, and no provider that *requires* an API key has been driven
  from a device. The next change that touches provider differences owes that round,
  and this harness is the vehicle for it.
- **TLS on the device is unverified.** Every round above ran against a plain HTTP
  LAN endpoint. The HTTPS front (`https://<tls-front-host>:8443/v1`,
  Let's Encrypt cert) was unreachable from the phone: the tunnel carries traffic
  but the phone does not resolve that name, so no cert-validation or
  TLS-path behaviour has been observed on Android. One 7.1 round against that URL
  would close it.
- **No connect timeout.** With DNS failing, the draft sat at `Waiting.` for more
  than two minutes with no error surfaced. That is a user-visible behaviour change,
  so it is not fixed here: it is proposed as `add-endpoint-timeouts`, which also
  owes the on-device rounds for a black-holed endpoint and a stalled stream.
