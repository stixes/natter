#!/usr/bin/env python3
"""A deliberately degenerate OpenAI-compatible SSE endpoint.

It streams only `reasoning_content`, then ends with no answer text at all. That
is the exact shape that drives Natter's blank-answer fallback, and no real model
here produces it on demand, so the fallback otherwise has no on-device coverage.

Run on the dev machine (it must be reachable from the phone's Wi-Fi):

    python3 integration_test/support/mock_reasoning_endpoint.py 8010

Then point the harness at it:

    --dart-define=NATTER_MOCK_URL=http://<dev-box>:8010/v1

Task-scoped test support for add-streaming-spine; it goes away with the change.
"""

import http.server
import json
import sys
import time

MARKER = 'nothing here is answer text, by construction. '
DELAY = 0.2

repeated = MARKER * 8
reasoning_chunks = [
    repeated[index:index + 20] for index in range(0, len(repeated), 20)
]

events = (
    [{'choices': [{'delta': {'role': 'assistant'}}]}]
    + [{'choices': [{'delta': {'reasoning_content': piece}}]}
       for piece in reasoning_chunks]
    + [{'choices': [{'delta': {}, 'finish_reason': 'stop'}]}]
)


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
        for event in events:
            self.wfile.write(f'data: {json.dumps(event)}\n\n'.encode())
            self.wfile.flush()
            time.sleep(DELAY)
        self.wfile.write(b'data: [DONE]\n\n')
        self.wfile.flush()

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8010
    print(f'mock reasoning-only endpoint on :{port} '
          f'(marker: {MARKER.strip()!r})')
    http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
