#!/usr/bin/env python3
# =========================================
# Proxy Manager Agent
# 轻量级 API 探针，运行在每个 VPS 上
# =========================================

import os
import sys
import json
import subprocess
import socket
from functools import wraps

try:
    from flask import Flask, request, jsonify
except ImportError:
    print("Flask not installed. Run: pip3 install flask")
    sys.exit(1)

app = Flask(__name__)

# =========================================
# Configuration
# =========================================
AGENT_PORT = int(os.environ.get('AGENT_PORT', 9900))
AGENT_TOKEN = os.environ.get('AGENT_TOKEN', '')
PROXY_MANAGER_PATH = '/opt/proxy-manager'

# Service definitions
SERVICES = {
    'snell': {'systemd': 'snell', 'config': '/etc/snell-proxy-config.txt'},
    'singbox': {'systemd': 'sing-box', 'config': '/etc/singbox-proxy-config.txt'},
    'reality': {'systemd': 'sing-box-reality', 'config': '/etc/reality-proxy-config.txt'},
    'hysteria2': {'systemd': 'hysteria2', 'config': '/etc/hysteria2-proxy-config.txt'},
}

# =========================================
# Authentication Decorator
# =========================================
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer ') or auth_header[7:] != AGENT_TOKEN:
            return jsonify({'error': 'unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

# =========================================
# Helper Functions
# =========================================
def run_command(cmd, timeout=30):
    """Execute shell command and return output"""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, 
            text=True, timeout=timeout
        )
        return {
            'returncode': result.returncode,
            'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip()
        }
    except subprocess.TimeoutExpired:
        return {'returncode': -1, 'stdout': '', 'stderr': 'timeout'}
    except Exception as e:
        return {'returncode': -1, 'stdout': '', 'stderr': str(e)}

def get_service_status(service_name):
    """Get systemd service status"""
    result = run_command(f'systemctl is-active {service_name}')
    return result['stdout'] if result['returncode'] == 0 else 'inactive'

def get_server_ip():
    """Get server public IP"""
    try:
        result = run_command('curl -s --connect-timeout 2 ifconfig.me')
        if result['returncode'] == 0:
            return result['stdout']
    except:
        pass
    return socket.gethostbyname(socket.gethostname())

def read_config_file(path):
    """Read key-value config file"""
    config = {}
    if os.path.exists(path):
        with open(path, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    return config

# =========================================
# API Endpoints
# =========================================

@app.route('/api/ping')
def ping():
    """Health check endpoint (no auth required)"""
    return jsonify({'status': 'ok', 'version': '1.0'})

@app.route('/api/status')
@require_auth
def status():
    """Get all service statuses"""
    services = {}
    for name, info in SERVICES.items():
        status = get_service_status(info['systemd'])
        services[name] = {
            'status': status,
            'installed': os.path.exists(info['config'])
        }
    
    return jsonify({
        'ip': get_server_ip(),
        'hostname': socket.gethostname(),
        'services': services
    })

@app.route('/api/config/<service_type>')
@require_auth
def get_config(service_type):
    """Get service configuration"""
    if service_type not in SERVICES:
        return jsonify({'error': 'unknown service'}), 400
    
    config_path = SERVICES[service_type]['config']
    if not os.path.exists(config_path):
        return jsonify({'error': 'service not installed'}), 404
    
    config = read_config_file(config_path)
    # Remove sensitive fields from response
    safe_fields = ['SERVER_IP', 'TYPE', 'SNELL_VERSION', 'SINGBOX_VERSION', 
                   'SHADOW_TLS_PORT', 'SS_PORT', 'REALITY_PORT', 'HYSTERIA2_PORT',
                   'TLS_DOMAIN', 'HYSTERIA2_DOMAIN', 'REALITY_DEST']
    safe_config = {k: v for k, v in config.items() if k in safe_fields}
    
    return jsonify({'config': safe_config})

@app.route('/api/install', methods=['POST'])
@require_auth
def install_service():
    """Install a proxy service"""
    data = request.json or {}
    service_type = data.get('type')
    
    if not service_type:
        return jsonify({'error': 'type is required'}), 400
    
    # Map service type to install command
    install_map = {
        'snell': '1',
        'singbox': '2',
        'reality': '3',
        'hysteria2': '4'
    }
    
    if service_type not in install_map:
        return jsonify({'error': f'unknown service: {service_type}'}), 400
    
    # Build environment for non-interactive install
    env = os.environ.copy()
    env['AUTO_INSTALL'] = '1'
    
    # Pass parameters
    if 'port' in data:
        env['INSTALL_PORT'] = str(data['port'])
    if 'domain' in data:
        env['INSTALL_DOMAIN'] = data['domain']
    
    # TODO: Implement non-interactive install support in proxy-manager.sh
    # For now, return not implemented
    return jsonify({
        'error': 'Remote install requires interactive mode. Please SSH to install.',
        'hint': f'Run: proxy-manager, then select option {install_map[service_type]}'
    }), 501

@app.route('/api/uninstall', methods=['POST'])
@require_auth
def uninstall_service():
    """Uninstall a proxy service"""
    data = request.json or {}
    service_type = data.get('type')
    
    if not service_type or service_type not in SERVICES:
        return jsonify({'error': 'valid type is required'}), 400
    
    service_info = SERVICES[service_type]
    systemd_name = service_info['systemd']
    
    # Stop and disable service
    run_command(f'systemctl stop {systemd_name}')
    run_command(f'systemctl disable {systemd_name}')
    
    # Remove files based on service type
    if service_type == 'snell':
        run_command('rm -f /lib/systemd/system/snell.service')
        run_command('rm -f /etc/systemd/system/shadow-tls-snell.service')
        run_command('rm -rf /etc/snell')
        run_command('rm -f /etc/snell-proxy-config.txt')
    elif service_type == 'singbox':
        run_command('rm -f /lib/systemd/system/sing-box.service')
        run_command('rm -rf /etc/sing-box')
        run_command('rm -f /etc/singbox-proxy-config.txt')
    elif service_type == 'reality':
        run_command('rm -f /lib/systemd/system/sing-box-reality.service')
        run_command('rm -rf /etc/sing-box-reality')
        run_command('rm -f /etc/reality-proxy-config.txt')
    elif service_type == 'hysteria2':
        run_command('rm -f /lib/systemd/system/hysteria2.service')
        run_command('rm -rf /etc/hysteria2')
        run_command('rm -f /etc/hysteria2-proxy-config.txt')
    
    run_command('systemctl daemon-reload')
    
    return jsonify({'status': 'ok', 'message': f'{service_type} uninstalled'})

@app.route('/api/restart', methods=['POST'])
@require_auth
def restart_service():
    """Restart a service"""
    data = request.json or {}
    service_type = data.get('type')
    
    if service_type == 'all':
        results = {}
        for name, info in SERVICES.items():
            result = run_command(f'systemctl restart {info["systemd"]}')
            results[name] = 'ok' if result['returncode'] == 0 else 'failed'
        return jsonify({'status': 'ok', 'results': results})
    
    if not service_type or service_type not in SERVICES:
        return jsonify({'error': 'valid type is required'}), 400
    
    systemd_name = SERVICES[service_type]['systemd']
    result = run_command(f'systemctl restart {systemd_name}')
    
    return jsonify({
        'status': 'ok' if result['returncode'] == 0 else 'error',
        'message': result['stderr'] if result['returncode'] != 0 else 'restarted'
    })

@app.route('/api/logs/<service_type>')
@require_auth
def get_logs(service_type):
    """Get recent logs for a service"""
    if service_type not in SERVICES:
        return jsonify({'error': 'unknown service'}), 400
    
    systemd_name = SERVICES[service_type]['systemd']
    result = run_command(f'journalctl -u {systemd_name} -n 50 --no-pager')
    
    return jsonify({'logs': result['stdout'].split('\n')})

# =========================================
# Main
# =========================================
if __name__ == '__main__':
    if not AGENT_TOKEN:
        print("ERROR: AGENT_TOKEN environment variable is required")
        print("Usage: AGENT_TOKEN=your_token python3 agent.py")
        sys.exit(1)
    
    print(f"Starting Proxy Manager Agent on port {AGENT_PORT}")
    print(f"Token: {AGENT_TOKEN[:4]}...{AGENT_TOKEN[-4:]}")
    
    # Run with minimal dependencies
    app.run(host='0.0.0.0', port=AGENT_PORT, threaded=True)
