#!/usr/bin/env python3

import http.server
import socketserver
import json
import os
import urllib.request
import urllib.parse
import urllib.error
import base64
from urllib.parse import urlparse

class AuthServiceHandler(http.server.BaseHTTPRequestHandler):
    
    def do_GET(self):
        self.handle_request()
    
    def do_POST(self):
        self.handle_request()
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()
    
    def send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    
    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_cors_headers()
        self.end_headers()
        
        response = json.dumps(data)
        self.wfile.write(response.encode('utf-8'))
    
    def send_error_response(self, status_code, message):
        self.send_json_response(status_code, {'error': message})
    
    def handle_request(self):
        # Health check endpoint
        if self.path == '/health':
            self.handle_health_check()
            return
        
        # Authorization endpoint
        if self.path == '/authorize':
            self.handle_authorization()
            return
        
        # Forward request to Employee API after authorization
        if self.path.startswith('/api/v1/employees'):
            self.handle_protected_request()
            return
        
        self.send_error_response(404, 'Not found')
    
    def handle_health_check(self):
        health_data = {
            'status': 'healthy',
            'service': 'Authorization Service',
            'version': os.getenv('APP_VERSION', '1.0.0')
        }
        self.send_json_response(200, health_data)
    
    def handle_authorization(self):
        """Handle authorization check only"""
        try:
            # Get Authorization header
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_error_response(401, 'Missing or invalid authorization header')
                return
            
            # Get request details
            original_path = self.headers.get('X-Original-Path', self.path)
            original_method = self.headers.get('X-Original-Method', self.command)
            
            # Check authorization with OPA
            if self.check_authorization(auth_header, original_path, original_method):
                self.send_json_response(200, {'authorized': True})
            else:
                self.send_error_response(403, 'Access denied')
                
        except Exception as e:
            print(f"Authorization error: {e}")
            self.send_error_response(500, 'Authorization service error')
    
    def handle_protected_request(self):
        """Handle the full request with authorization and forwarding"""
        try:
            # Get Authorization header
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_error_response(401, 'Missing or invalid authorization header')
                return
            
            # Check authorization with OPA
            if not self.check_authorization(auth_header, self.path, self.command):
                self.send_error_response(403, 'Access denied')
                return
            
            # Forward to Employee API
            self.forward_to_employee_api()
            
        except Exception as e:
            print(f"Request handling error: {e}")
            self.send_error_response(500, 'Service error')
    
    def check_authorization(self, auth_header, path, method):
        """Check authorization with OPA"""
        try:
            opa_host = os.getenv('OPA_SERVICE_HOST', 'opa-service.default.svc.cluster.local')
            opa_port = os.getenv('OPA_SERVICE_PORT', '8181')
            opa_url = f"http://{opa_host}:{opa_port}/v1/data/employee/authz/allow"
            
            # Prepare OPA input
            opa_input = {
                'token': auth_header,
                'path': path,
                'method': method
            }
            
            # Call OPA
            data = json.dumps({'input': opa_input}).encode('utf-8')
            req = urllib.request.Request(opa_url, data=data)
            req.add_header('Content-Type', 'application/json')
            
            with urllib.request.urlopen(req, timeout=5) as response:
                opa_response = json.loads(response.read().decode('utf-8'))
                return opa_response.get('result', False)
                
        except Exception as e:
            print(f"OPA authorization error: {e}")
            return False
    
    def forward_to_employee_api(self):
        """Forward request to Employee API"""
        try:
            employee_api_host = os.getenv('EMPLOYEE_API_HOST', 'employee-api-service.default.svc.cluster.local')
            employee_api_port = os.getenv('EMPLOYEE_API_PORT', '80')
            employee_api_url = f"http://{employee_api_host}:{employee_api_port}{self.path}"
            
            # Prepare request
            req = urllib.request.Request(employee_api_url, method=self.command)
            
            # Copy relevant headers (excluding Authorization since Employee API doesn't need it)
            for header_name, header_value in self.headers.items():
                if header_name.lower() not in ['host', 'authorization']:
                    req.add_header(header_name, header_value)
            
            # Handle request body for POST/PUT
            if self.command in ['POST', 'PUT']:
                content_length = int(self.headers.get('Content-Length', 0))
                if content_length > 0:
                    req.data = self.rfile.read(content_length)
            
            # Make request to Employee API
            with urllib.request.urlopen(req, timeout=10) as response:
                # Forward response
                self.send_response(response.getcode())
                
                # Forward response headers
                for header_name, header_value in response.headers.items():
                    if header_name.lower() not in ['server', 'date']:
                        self.send_header(header_name, header_value)
                
                self.send_cors_headers()
                self.end_headers()
                
                # Forward response body
                self.wfile.write(response.read())
                
        except urllib.error.HTTPError as e:
            self.send_error_response(e.code, f'Employee API error: {e.reason}')
        except Exception as e:
            print(f"Forward error: {e}")
            self.send_error_response(500, 'Failed to forward request')

def main():
    port = int(os.getenv('PORT', 8080))
    
    print(f"Starting Authorization Service on port {port}")
    print(f"OPA Service: {os.getenv('OPA_SERVICE_HOST', 'opa-service.default.svc.cluster.local')}:{os.getenv('OPA_SERVICE_PORT', '8181')}")
    print(f"Employee API: {os.getenv('EMPLOYEE_API_HOST', 'employee-api-service.default.svc.cluster.local')}:{os.getenv('EMPLOYEE_API_PORT', '80')}")
    
    with socketserver.TCPServer(("", port), AuthServiceHandler) as httpd:
        print(f"Authorization Service running at http://0.0.0.0:{port}")
        httpd.serve_forever()

if __name__ == '__main__':
    main() 