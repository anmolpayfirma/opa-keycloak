#!/usr/bin/env python3

import http.server
import socketserver
import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from urllib.parse import urlparse, parse_qs

class DatabaseEmployeeAPIHandler(http.server.BaseHTTPRequestHandler):
    
    def __init__(self, *args, **kwargs):
        self.db_config = {
            'host': os.getenv('DB_HOST', 'postgresql-service.default.svc.cluster.local'),
            'port': int(os.getenv('DB_PORT', '5432')),
            'database': os.getenv('DB_NAME', 'employee_api'),
            'user': os.getenv('DB_USER', 'employee_api'),
            'password': os.getenv('DB_PASSWORD', 'employee123')
        }
        super().__init__(*args, **kwargs)
    
    def get_db_connection(self):
        """Get database connection"""
        try:
            conn = psycopg2.connect(**self.db_config)
            return conn
        except Exception as e:
            print(f"Database connection error: {e}")
            return None
    
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
        
        response = json.dumps(data, default=str)  # Handle datetime serialization
        self.wfile.write(response.encode('utf-8'))
    
    def send_error_response(self, status_code, message):
        self.send_json_response(status_code, {'error': message})
    
    def handle_request(self):
        # Health check endpoint
        if self.path == '/health':
            self.handle_health_check()
            return
        
        # Parse URL
        parsed_url = urlparse(self.path)
        path_parts = [part for part in parsed_url.path.split('/') if part]
        
        # Handle different endpoints
        if len(path_parts) >= 3 and path_parts[0] == 'api' and path_parts[1] == 'v1':
            if path_parts[2] == 'employees':
                if len(path_parts) == 3:
                    # /api/v1/employees
                    if self.command == 'GET':
                        self.handle_employees_list()
                    elif self.command == 'POST':
                        self.handle_employee_create()
                    else:
                        self.send_error_response(405, 'Method not allowed')
                elif len(path_parts) == 4:
                    # /api/v1/employees/{id}
                    employee_id = path_parts[3]
                    if self.command == 'GET':
                        self.handle_employee_detail(employee_id)
                    elif self.command == 'PUT':
                        self.handle_employee_update(employee_id)
                    elif self.command == 'DELETE':
                        self.handle_employee_delete(employee_id)
                    else:
                        self.send_error_response(405, 'Method not allowed')
                else:
                    self.send_error_response(404, 'Not found')
            elif path_parts[2] == 'departments':
                if len(path_parts) == 3:
                    # /api/v1/departments
                    self.handle_departments_list()
                else:
                    self.send_error_response(404, 'Not found')
            else:
                self.send_error_response(404, 'Not found')
        else:
            self.send_error_response(404, 'Not found')
    
    def handle_health_check(self):
        # Check database connectivity
        conn = self.get_db_connection()
        if conn:
            try:
                cursor = conn.cursor()
                cursor.execute('SELECT 1')
                cursor.close()
                conn.close()
                db_status = 'connected'
            except Exception as e:
                db_status = f'error: {str(e)}'
        else:
            db_status = 'disconnected'
        
        health_data = {
            'status': 'healthy' if db_status == 'connected' else 'unhealthy',
            'service': 'Employee API',
            'version': os.getenv('APP_VERSION', '3.0.0'),
            'database': db_status,
            'authorization': 'handled_by_kong'
        }
        status_code = 200 if db_status == 'connected' else 503
        self.send_json_response(status_code, health_data)
    
    def handle_employees_list(self):
        """Get all employees from database"""
        conn = self.get_db_connection()
        if not conn:
            self.send_error_response(503, 'Database unavailable')
            return
        
        try:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            
            # Parse query parameters for filtering
            parsed_url = urlparse(self.path)
            query_params = parse_qs(parsed_url.query)
            
            # Build SQL query with optional filtering
            sql = "SELECT id, name, department, email, created_at, updated_at FROM employees"
            params = []
            
            if 'department' in query_params:
                sql += " WHERE department = %s"
                params.append(query_params['department'][0])
            
            sql += " ORDER BY name"
            
            cursor.execute(sql, params)
            employees = cursor.fetchall()
            
            cursor.close()
            conn.close()
            
            self.send_json_response(200, {
                'employees': [dict(emp) for emp in employees],
                'count': len(employees)
            })
            
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()
    
    def handle_employee_detail(self, employee_id):
        """Get specific employee from database"""
        conn = self.get_db_connection()
        if not conn:
            self.send_error_response(503, 'Database unavailable')
            return
        
        try:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute(
                "SELECT id, name, department, email, created_at, updated_at FROM employees WHERE id = %s",
                (employee_id,)
            )
            employee = cursor.fetchone()
            
            cursor.close()
            conn.close()
            
            if employee:
                self.send_json_response(200, {'employee': dict(employee)})
            else:
                self.send_error_response(404, 'Employee not found')
                
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()
    
    def handle_employee_create(self):
        """Create new employee"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                post_data = self.rfile.read(content_length)
                employee_data = json.loads(post_data.decode('utf-8'))
            else:
                self.send_error_response(400, 'No data provided')
                return
            
            # Validate required fields
            required_fields = ['id', 'name', 'department']
            for field in required_fields:
                if field not in employee_data:
                    self.send_error_response(400, f'Missing required field: {field}')
                    return
            
            conn = self.get_db_connection()
            if not conn:
                self.send_error_response(503, 'Database unavailable')
                return
            
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute(
                """INSERT INTO employees (id, name, department, email) 
                   VALUES (%s, %s, %s, %s) 
                   RETURNING id, name, department, email, created_at, updated_at""",
                (employee_data['id'], employee_data['name'], 
                 employee_data['department'], employee_data.get('email'))
            )
            new_employee = cursor.fetchone()
            
            conn.commit()
            cursor.close()
            conn.close()
            
            self.send_json_response(201, {'employee': dict(new_employee)})
            
        except json.JSONDecodeError:
            self.send_error_response(400, 'Invalid JSON')
        except psycopg2.IntegrityError as e:
            self.send_error_response(409, 'Employee ID already exists')
            if conn:
                conn.rollback()
                conn.close()
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()
    
    def handle_employee_update(self, employee_id):
        """Update existing employee"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                post_data = self.rfile.read(content_length)
                employee_data = json.loads(post_data.decode('utf-8'))
            else:
                self.send_error_response(400, 'No data provided')
                return
            
            conn = self.get_db_connection()
            if not conn:
                self.send_error_response(503, 'Database unavailable')
                return
            
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            
            # Build dynamic update query
            update_fields = []
            params = []
            
            for field in ['name', 'department', 'email']:
                if field in employee_data:
                    update_fields.append(f"{field} = %s")
                    params.append(employee_data[field])
            
            if not update_fields:
                self.send_error_response(400, 'No fields to update')
                return
            
            update_fields.append("updated_at = CURRENT_TIMESTAMP")
            params.append(employee_id)
            
            sql = f"""UPDATE employees SET {', '.join(update_fields)} 
                     WHERE id = %s 
                     RETURNING id, name, department, email, created_at, updated_at"""
            
            cursor.execute(sql, params)
            updated_employee = cursor.fetchone()
            
            if updated_employee:
                conn.commit()
                self.send_json_response(200, {'employee': dict(updated_employee)})
            else:
                self.send_error_response(404, 'Employee not found')
            
            cursor.close()
            conn.close()
            
        except json.JSONDecodeError:
            self.send_error_response(400, 'Invalid JSON')
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()
    
    def handle_employee_delete(self, employee_id):
        """Delete employee"""
        conn = self.get_db_connection()
        if not conn:
            self.send_error_response(503, 'Database unavailable')
            return
        
        try:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM employees WHERE id = %s", (employee_id,))
            
            if cursor.rowcount > 0:
                conn.commit()
                self.send_json_response(200, {'message': 'Employee deleted successfully'})
            else:
                self.send_error_response(404, 'Employee not found')
            
            cursor.close()
            conn.close()
            
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()
    
    def handle_departments_list(self):
        """Get all departments from database"""
        conn = self.get_db_connection()
        if not conn:
            self.send_error_response(503, 'Database unavailable')
            return
        
        try:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT id, name, description, created_at FROM departments ORDER BY name")
            departments = cursor.fetchall()
            
            cursor.close()
            conn.close()
            
            self.send_json_response(200, {
                'departments': [dict(dept) for dept in departments],
                'count': len(departments)
            })
            
        except Exception as e:
            print(f"Database error: {e}")
            self.send_error_response(500, 'Database error')
            if conn:
                conn.close()

def main():
    port = int(os.getenv('PORT', 8080))
    
    print(f"Starting PostgreSQL-enabled Employee API server on port {port}")
    print(f"Database: {os.getenv('DB_HOST', 'postgresql-service')}:{os.getenv('DB_PORT', '5432')}")
    print("Authorization is handled by Kong Gateway")
    
    with socketserver.TCPServer(("", port), DatabaseEmployeeAPIHandler) as httpd:
        print(f"Employee API server running at http://0.0.0.0:{port}")
        httpd.serve_forever()

if __name__ == '__main__':
    main() 