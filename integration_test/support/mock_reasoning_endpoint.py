#!/usr/bin/env python3
"""A deliberately degenerate OpenAI-compatible SSE endpoint.

Two modes, selected by the request path:

- default: streams only `reasoning_content`, then ends with no answer text at
  all. That is the shape that drives Natter's blank-answer fallback.
- `/stall`: streams a few answer chunks and then goes silent for longer than
  the client's silence bound. That drives the `The reply stopped arriving.`
  path and proves the already-streamed text is kept.

Run on the dev machine (it must be reachable from the phone's Wi-Fi):

    python3 integration_test/support/mock_reasoning_endpoint.py 8010

Then point the harness at it:

    --dart-define=NATTER_MOCK_URL=http://<dev-box>:8010/v1
    --dart-define=NATTER_STALL_URL=http://<dev-box>:8010/v1/stall

Substitute your own host for the placeholder; angle brackets are not shell-safe.

Task-scoped test support for add-streaming-spine and add-endpoint-timeouts; it
goes away with those changes.
"""

import http.server
import json
import sys
import time

MARKER = 'nothing here is answer text, by construction. '
DELAY = 0.2

# Longer than ChatCompletionsClient.defaultSilenceTimeout (60 s), so the client
# gives up while the server is still holding the connection open.
STALL_DELAY = 90

repeated = MARKER * 8
reasoning_chunks = [
    repeated[index:index + 20] for index in range(0, len(repeated), 20)
]

reasoning_events = (
    [{'choices': [{'delta': {'role': 'assistant'}}]}]
    + [{'choices': [{'delta': {'reasoning_content': piece}}]}
       for piece in reasoning_chunks]
    + [{'choices': [{'delta': {}, 'finish_reason': 'stop'}]}]
)

stall_events = [
    {'choices': [{'delta': {'role': 'assistant'}}]},
    {'choices': [{'delta': {'content': 'This answer starts normally. '}}]},
    {'choices': [{'delta': {'content': 'Then the stream goes silent. '}}]},
    {'choices': [{'delta': {'content': 'Keep this text after the timeout.'}}]},
]


class Handler(http.server.BaseHTTPRequestHandler):
    # HTTP/1.0: the response has no Content-Length, so closing the connection is
    # what tells the client the stream ended.
    protocol_version = 'HTTP/1.0'

    def do_POST(self):
        length = int(self.headers.get('content-length', 0))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header('content-type', 'text/event-stream')
        self.end_headers()

        if '/stall' in self.path:
            self._stream(stall_events)
            time.sleep(STALL_DELAY)
            try:
                self.wfile.write(b'data: [DONE]\n\n')
                self.wfile.flush()
            except Exception:
                pass  # the client has already given up and closed the socket
            return

        self._stream(reasoning_events)
        self.wfile.write(b'data: [DONE]\n\n')
        self.wfile.flush()

    def _stream(self, events):
        for event in events:
            self.wfile.write(f'data: {json.dumps(event)}\n\n'.encode())
            self.wfile.flush()
            time.sleep(DELAY)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8010
    print(f'mock endpoint on :{port} '
          f'(blank-answer marker: {MARKER.strip()!r}; /stall for the stalled '
          f'stream)')
    http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
