import http.server
import socket
import threading
import time
import unittest
import urllib.error
import urllib.request

import gdrive_auth


class AuthorizationCallbackTests(unittest.TestCase):
    def make_server(self):
        gdrive_auth._Handler.state = 'TEST_STATE'
        return http.server.HTTPServer(('127.0.0.1', 0), gdrive_auth._Handler)

    def callback(self, server, query):
        errors = []

        def request():
            try:
                with urllib.request.urlopen(
                    f'http://127.0.0.1:{server.server_port}/?{query}', timeout=2
                ) as response:
                    response.read()
            except urllib.error.HTTPError as error:
                error.close()
            except Exception as error:
                errors.append(error)

        thread = threading.Thread(target=request)
        thread.start()
        return thread, errors

    def test_callback_completes_without_second_connection(self):
        server = self.make_server()
        thread, errors = self.callback(server, 'state=TEST_STATE&code=CODE')
        result = gdrive_auth._wait_for_authorization(server, timeout=1)
        thread.join(timeout=2)
        self.assertEqual(result, {'code': 'CODE'})
        self.assertEqual(errors, [])
        self.assertFalse(thread.is_alive())
        with socket.socket() as probe:
            self.assertNotEqual(probe.connect_ex(server.server_address), 0)

    def test_denied_authorization_returns_promptly(self):
        server = self.make_server()
        thread, errors = self.callback(
            server, 'state=TEST_STATE&error=access_denied'
        )
        result = gdrive_auth._wait_for_authorization(server, timeout=1)
        thread.join(timeout=2)
        self.assertEqual(result, {'error': 'access_denied'})
        self.assertEqual(errors, [])

    def test_timeout_is_total_and_closes_listener(self):
        server = self.make_server()
        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            gdrive_auth._wait_for_authorization(server, timeout=0.05)
        self.assertLess(time.monotonic() - started, 1)
        with socket.socket() as probe:
            self.assertNotEqual(probe.connect_ex(server.server_address), 0)

    def test_wrong_state_does_not_complete_authorization(self):
        server = self.make_server()
        thread, errors = self.callback(server, 'state=WRONG&code=CODE')
        with self.assertRaises(TimeoutError):
            gdrive_auth._wait_for_authorization(server, timeout=0.15)
        thread.join(timeout=2)
        self.assertEqual(errors, [])
        self.assertIsNone(gdrive_auth._Handler.result)


if __name__ == '__main__':
    unittest.main()
