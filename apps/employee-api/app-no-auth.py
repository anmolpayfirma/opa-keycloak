#!/usr/bin/env python3

import http.server
import socketserver
import json
import os
from urllib.parse import urlparse

class EmployeeAPIHandler(http.server.BaseHTTPRequestHandler):
    
    def do_GET(self):
        self.handle_request()
    
    def do_POST(self):
        self.handle_request()
    
    def do_PUT(self):
        self.handle_request()
    
    def do_DELETE(self):
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
        
        # Handle the request (no authorization needed - Kong handles it)
        if self.path == '/employees' or self.path == '/api/v1/employees':
            self.handle_employees_list()
        elif self.path.startswith('/employees/') or self.path.startswith('/api/v1/employees/'):
            # Extract employee ID from path
            if self.path.startswith('/api/v1/employees/'):
                employee_id = self.path.split('/')[-1]
            else:
                employee_id = self.path.split('/')[-1]
            self.handle_employee_detail(employee_id)
        else:
            self.send_error_response(404, 'Not found')
    
    def handle_health_check(self):
        health_data = {
            'status': 'healthy',
            'service': 'Employee API',
            'version': os.getenv('APP_VERSION', '1.0.0'),
            'authorization': 'handled_by_kong'
        }
        self.send_json_response(200, health_data)
    
    def handle_employees_list(self):
        # Return list of all employees (Kong already authorized this)
        employees = [
            {'id': 'EMP001', 'name': 'John Doe', 'department': 'Engineering'},
            {'id': 'EMP002', 'name': 'Jane Smith', 'department': 'Marketing'},
            {'id': 'EMP003', 'name': 'Bob Employee', 'department': 'Engineering'},
            {'id': 'MGR001', 'name': 'Alice Manager', 'department': 'Management'}
        ]
        self.send_json_response(200, {'employees': employees})
    
    def handle_employee_detail(self, employee_id):
        # Return specific employee details (Kong already authorized this)
        employees = {
            'EMP001': {'id': 'EMP001', 'name': 'John Doe', 'department': 'Engineering'},
            'EMP002': {'id': 'EMP002', 'name': 'Jane Smith', 'department': 'Marketing'},
            'EMP003': {'id': 'EMP003', 'name': 'Bob Employee', 'department': 'Engineering'},
            'MGR001': {'id': 'MGR001', 'name': 'Alice Manager', 'department': 'Management'}
        }
        
        if employee_id in employees:
            self.send_json_response(200, {'employee': employees[employee_id]})
        else:
            self.send_error_response(404, 'Employee not found')

def main():
    port = int(os.getenv('PORT', 8080))
    
    print(f"Starting Employee API server on port {port}")
    print("Authorization is handled by Kong Gateway")
    
    with socketserver.TCPServer(("", port), EmployeeAPIHandler) as httpd:
        print(f"Employee API server running at http://0.0.0.0:{port}")
        httpd.serve_forever()

if __name__ == '__main__':
    main() 