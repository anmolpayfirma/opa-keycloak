#!/usr/bin/env python3
import json
import requests
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import re

class EmployeeAPIHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_request()
    
    def do_POST(self):
        self.handle_request()
    
    def do_PUT(self):
        self.handle_request()
    
    def do_DELETE(self):
        self.handle_request()
    
    def handle_request(self):
        # Health check endpoint doesn't require authorization
        if self.path == '/health':
            self.handle_health_check()
            return
            
        # Get authorization header for other endpoints
        auth_header = self.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            self.send_error_response(401, 'Missing or invalid authorization header')
            return
        
        token = auth_header[7:]  # Remove 'Bearer ' prefix
        
        # Check authorization with OPA
        if not self.check_authorization(token):
            self.send_error_response(403, 'Access denied')
            return
        
        # Handle the request
        if self.path == '/employees':
            self.handle_employees_list()
        elif self.path.startswith('/employees/'):
            employee_id = self.path.split('/')[-1]
            self.handle_employee_detail(employee_id)
        else:
            self.send_error_response(404, 'Not found')
    
    def check_authorization(self, token):
        try:
            # Get OPA service URL from environment variable or use default
            opa_host = os.getenv('OPA_SERVICE_HOST', 'opa-service.opa-keycloak-practice.svc.cluster.local')
            opa_port = os.getenv('OPA_SERVICE_PORT', '8181')
            opa_url = f'http://{opa_host}:{opa_port}/v1/data/system/authz/allow'
            
            payload = {
                'input': {
                    'method': self.command,
                    'path': self.path,
                    'token': token
                }
            }
            
            response = requests.post(opa_url, json=payload, timeout=5)
            if response.status_code == 200:
                result = response.json()
                return result.get('result', False)
            return False
        except Exception as e:
            print(f"Authorization error: {e}")
            return False
    
    def handle_health_check(self):
        self.send_json_response(200, {
            "status": "healthy", 
            "service": "Employee API",
            "version": os.getenv('APP_VERSION', '1.0.0')
        })
    
    def handle_employees_list(self):
        employees = [
            {"id": "EMP001", "name": "John Manager", "department": "Engineering"},
            {"id": "EMP002", "name": "Jane HR", "department": "HR"},
            {"id": "EMP003", "name": "Bob Employee", "department": "Engineering"}
        ]
        self.send_json_response(200, {"employees": employees})
    
    def handle_employee_detail(self, employee_id):
        employees = {
            "EMP001": {"id": "EMP001", "name": "John Manager", "department": "Engineering"},
            "EMP002": {"id": "EMP002", "name": "Jane HR", "department": "HR"},
            "EMP003": {"id": "EMP003", "name": "Bob Employee", "department": "Engineering"}
        }
        
        if employee_id in employees:
            self.send_json_response(200, {"employee": employees[employee_id]})
        else:
            self.send_error_response(404, 'Employee not found')
    
    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def send_error_response(self, status_code, message):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps({"error": message}).encode())
    
    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}")

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    server = HTTPServer(('0.0.0.0', port), EmployeeAPIHandler)
    print(f"Employee API starting on port {port}...")
    print(f"Health check available at: http://localhost:{port}/health")
    server.serve_forever() 