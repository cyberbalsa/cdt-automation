#!/usr/bin/env python3
"""
Token Server - Serves the Red Team's secret flag token over HTTP.

==============================================================================
WHAT IS THIS?
==============================================================================
In attack/defend CTF competitions, Red Team needs a secret "token" to plant
flags on compromised systems. This simple web server provides that token.

Red Team retrieves their token like this:
    curl http://<scoring-server>:8081/token

Then plants it on a compromised box:
    echo "<token>" > /var/www/html/flag.txt

WHY A WEB SERVER?
- Automation: Red Team tools can fetch the token programmatically
- Simplicity: No authentication needed (network position = authorization)
- Rotation: Token can be changed without updating Red Team scripts

==============================================================================
PYTHON CONCEPTS USED
==============================================================================
This script demonstrates several important Python concepts:

1. HTTP SERVER (http.server module)
   Python includes a built-in web server! We customize it by creating a
   "handler" class that defines what happens when requests arrive.

2. CLASSES AND INHERITANCE
   TokenHandler inherits from BaseHTTPRequestHandler, which does most of
   the heavy HTTP lifting. We just override the methods we care about.

3. FILE I/O
   Reading files with open() and the 'with' statement (context manager),
   which automatically closes the file when done.

4. COMMAND LINE ARGUMENTS
   sys.argv contains command line arguments. sys.argv[0] is the script name,
   sys.argv[1] is the first argument (port number in our case).

==============================================================================
SECURITY NOTES
==============================================================================
- No authentication! Anyone who can reach this port can get the token.
- This is intentional - access is controlled by network segmentation.
- In a real competition, only the scoring network should reach this port.
- Never expose this to the public internet!

Usage:
    python3 token_server.py [port]

Example:
    python3 token_server.py 8081

Red team retrieves token with:
    curl http://<scoring-server>:8081/token
"""

# ==============================================================================
# IMPORTS
# ==============================================================================
# Python's standard library includes many useful modules. Here we import:
# - http.server: Built-in HTTP server functionality
# - sys: System-specific parameters (like command line arguments)

from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Where is the token file stored? This should match where the Ansible
# playbook creates it during deployment.

TOKEN_FILE = '/opt/scoring-engine/red-token.txt'


# ==============================================================================
# HTTP REQUEST HANDLER
# ==============================================================================
# In Python, a "class" is a blueprint for creating objects. Classes can
# "inherit" from other classes to reuse their functionality.
#
# BaseHTTPRequestHandler already knows how to:
# - Parse HTTP requests
# - Send HTTP responses
# - Handle network connections
#
# We just need to define what to DO when a request arrives.

class TokenHandler(BaseHTTPRequestHandler):
    """
    Custom HTTP handler that serves the Red team token.

    HTTP BASICS:
    - GET request = "give me data" (like loading a webpage)
    - POST request = "here's data for you" (like submitting a form)
    - We only handle GET requests since Red Team just needs to read the token

    HTTP RESPONSE CODES:
    - 200 = OK (success!)
    - 404 = Not Found (wrong URL path)
    - 500 = Internal Server Error (something broke on our end)
    """

    def do_GET(self):
        """
        Handle GET requests.

        This method is called automatically when someone makes a GET request.
        self.path contains the URL path (e.g., "/token" or "/wrong-path")
        """
        # Check if they're requesting the token endpoint
        if self.path == '/token':
            # Try to read and serve the token file
            try:
                # 'with' statement = "context manager"
                # It automatically closes the file when we're done,
                # even if an error occurs. Always use 'with' for files!
                with open(TOKEN_FILE, 'r') as f:
                    # .read() gets the whole file contents
                    # .strip() removes whitespace/newlines from edges
                    token = f.read().strip()

                # Send HTTP 200 OK response
                self.send_response(200)

                # HTTP headers describe the response
                # Content-Type tells the client what kind of data this is
                self.send_header('Content-Type', 'text/plain')

                # Content-Length tells the client how many bytes to expect
                self.send_header('Content-Length', len(token))

                # end_headers() sends a blank line, signaling headers are done
                self.end_headers()

                # wfile = "write file" - the connection to send data back
                # .encode() converts string to bytes (required for network)
                self.wfile.write(token.encode())

            except FileNotFoundError:
                # Token file doesn't exist - server misconfigured
                self.send_response(500)  # Internal Server Error
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Token not configured')
                # Note: b'...' is a "bytes literal" - already encoded
        else:
            # They requested something other than /token
            self.send_response(404)  # Not Found
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not found. Use GET /token')

    def log_message(self, format, *args):
        """
        Override the default logging behavior.

        By default, BaseHTTPRequestHandler prints every request to the console.
        We override this method to do nothing (suppress logging).
        This keeps the output clean during competition.

        The *args syntax means "accept any number of arguments" - we just
        ignore them all by not doing anything in this method.
        """
        pass  # 'pass' = do nothing (required because methods can't be empty)


# ==============================================================================
# MAIN FUNCTION
# ==============================================================================
# The main() function is the entry point of our program.
# It's called when the script is run directly (not imported as a module).

def main():
    """Start the token server."""

    # Parse command line arguments
    # sys.argv is a list: ['script_name.py', 'arg1', 'arg2', ...]
    # len(sys.argv) > 1 means at least one argument was provided
    # int() converts the string argument to an integer
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081

    # Create the HTTP server
    # ('0.0.0.0', port) means "listen on all network interfaces on this port"
    # '0.0.0.0' = all interfaces (vs '127.0.0.1' = localhost only)
    # TokenHandler = our custom class that handles requests
    server = HTTPServer(('0.0.0.0', port), TokenHandler)

    # Print helpful startup message
    print(f'Token server running on port {port}')
    print(f'Red team can retrieve token at: http://<server>:{port}/token')

    # Start serving requests forever (until Ctrl+C)
    try:
        # serve_forever() blocks (waits) and handles requests continuously
        server.serve_forever()
    except KeyboardInterrupt:
        # Ctrl+C raises KeyboardInterrupt - handle it gracefully
        print('\nShutting down...')
        server.shutdown()


# ==============================================================================
# SCRIPT ENTRY POINT
# ==============================================================================
# This is a Python idiom that means:
# "Only run main() if this script is executed directly"
# If someone imports this file as a module, main() won't run automatically.

if __name__ == '__main__':
    main()
