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
    """Install a proxy service with parameters"""
    data = request.json or {}
    service_type = data.get('type')
    
    if not service_type:
        return jsonify({'error': 'type is required'}), 400
    
    if service_type not in ['snell', 'singbox', 'reality', 'hysteria2']:
        return jsonify({'error': f'unknown service: {service_type}'}), 400
    
    # Check if already installed
    if service_type in SERVICES and os.path.exists(SERVICES[service_type]['config']):
        return jsonify({'error': f'{service_type} is already installed'}), 400
    
    # Build environment for installation
    env = os.environ.copy()
    env['AUTO_INSTALL'] = '1'
    env['DEBIAN_FRONTEND'] = 'noninteractive'
    
    # Pass parameters
    port = data.get('port')
    if port:
        env['INSTALL_PORT'] = str(port)
    
    domain = data.get('domain')
    if domain:
        env['INSTALL_DOMAIN'] = domain
    
    sni = data.get('sni', 'www.microsoft.com')
    
    # Run installation script
    if service_type == 'snell':
        result = install_snell(env, port, sni)
    elif service_type == 'singbox':
        result = install_singbox(env, port, sni)
    elif service_type == 'reality':
        result = install_reality(env, port, sni)
    elif service_type == 'hysteria2':
        result = install_hysteria2(env, port, domain)
    else:
        return jsonify({'error': 'not implemented'}), 501
    
    return result

def install_snell(env, port=None, sni='www.microsoft.com'):
    """Install Snell + Shadow-TLS"""
    port = port or 8443
    sni = sni or 'www.microsoft.com'
    snell_port = 12580
    
    # Download and install Snell
    arch = run_command('uname -m')['stdout']
    if 'x86_64' in arch:
        arch_suffix = 'amd64'
    elif 'aarch64' in arch or 'arm64' in arch:
        arch_suffix = 'aarch64'
    else:
        arch_suffix = 'armv7l'
    
    # Get latest snell version
    snell_version = run_command("curl -s https://manual.nssurge.com/others/snell.html | grep -oP 'snell-server-v\\K[0-9.]+' | head -1")['stdout'] or '4.1.1'
    
    cmds = [
        'mkdir -p /etc/snell',
        f'cd /tmp && curl -sLO https://dl.nssurge.com/snell/snell-server-v{snell_version}-linux-{arch_suffix}.zip',
        f'cd /tmp && unzip -o snell-server-v{snell_version}-linux-{arch_suffix}.zip',
        'mv /tmp/snell-server /usr/local/bin/',
        'chmod +x /usr/local/bin/snell-server',
    ]
    
    for cmd in cmds:
        r = run_command(cmd, timeout=120)
        if r['returncode'] != 0 and 'already exists' not in r['stderr']:
            pass  # Continue anyway
    
    # Generate PSK
    psk = run_command("openssl rand -base64 16")['stdout']
    
    # Create Snell config
    snell_config = f"""[snell-server]
listen = 127.0.0.1:{snell_port}
psk = {psk}
ipv6 = false
"""
    with open('/etc/snell/snell.conf', 'w') as f:
        f.write(snell_config)
    
    # Create systemd service
    service = f"""[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    with open('/lib/systemd/system/snell.service', 'w') as f:
        f.write(service)
    
    # Download and install Shadow-TLS
    stls_version = run_command("curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest | grep -oP '\"tag_name\": \"v\\K[0-9.]+' | head -1")['stdout'] or '0.2.25'
    stls_arch = 'x86_64' if 'amd64' in arch_suffix else arch_suffix
    
    run_command(f'cd /tmp && curl -sLO https://github.com/ihciah/shadow-tls/releases/download/v{stls_version}/shadow-tls-{stls_arch}-unknown-linux-musl')
    run_command(f'mv /tmp/shadow-tls-{stls_arch}-unknown-linux-musl /usr/local/bin/shadow-tls')
    run_command('chmod +x /usr/local/bin/shadow-tls')
    
    # Generate Shadow-TLS password
    stls_password = run_command("openssl rand -base64 16")['stdout']
    
    # Create Shadow-TLS service
    stls_service = f"""[Unit]
Description=Shadow-TLS for Snell
After=network.target snell.service

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen 0.0.0.0:{port} --server 127.0.0.1:{snell_port} --tls {sni}:443 --password {stls_password}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    with open('/etc/systemd/system/shadow-tls-snell.service', 'w') as f:
        f.write(stls_service)
    
    # Save config
    server_ip = get_server_ip()
    config_content = f"""SERVER_IP={server_ip}
TYPE=Snell
SNELL_PORT={snell_port}
SHADOW_TLS_PORT={port}
SNELL_PSK={psk}
SHADOW_TLS_PASSWORD={stls_password}
SNELL_VERSION={snell_version}
"""
    with open('/etc/snell-proxy-config.txt', 'w') as f:
        f.write(config_content)
    
    # Start services
    run_command('systemctl daemon-reload')
    run_command('systemctl enable snell shadow-tls-snell')
    run_command('systemctl start snell shadow-tls-snell')
    
    return jsonify({
        'status': 'ok',
        'message': 'Snell + Shadow-TLS installed',
        'config': {
            'ip': server_ip,
            'port': port,
            'psk': psk,
            'shadow_tls_password': stls_password
        }
    })

def install_singbox(env, port=None, sni='www.microsoft.com'):
    """Install Sing-box SS-2022"""
    port = port or 8443
    sni = sni or 'www.microsoft.com'
    ss_port = 12581
    
    # Download sing-box
    arch = run_command('uname -m')['stdout']
    if 'x86_64' in arch:
        arch_suffix = 'amd64'
    elif 'aarch64' in arch or 'arm64' in arch:
        arch_suffix = 'arm64'
    else:
        arch_suffix = 'armv7'
    
    version = run_command("curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '\"tag_name\": \"v\\K[0-9.]+' | head -1")['stdout'] or '1.10.0'
    
    cmds = [
        'mkdir -p /etc/sing-box',
        f'cd /tmp && curl -sLO https://github.com/SagerNet/sing-box/releases/download/v{version}/sing-box-{version}-linux-{arch_suffix}.tar.gz',
        f'cd /tmp && tar -xzf sing-box-{version}-linux-{arch_suffix}.tar.gz',
        f'mv /tmp/sing-box-{version}-linux-{arch_suffix}/sing-box /usr/local/bin/',
        'chmod +x /usr/local/bin/sing-box',
    ]
    
    for cmd in cmds:
        run_command(cmd, timeout=120)
    
    # Generate SS password
    ss_password = run_command("openssl rand -base64 16")['stdout']
    stls_password = run_command("openssl rand -base64 16")['stdout']
    
    # Create sing-box config
    config = {
        "inbounds": [{
            "type": "shadowsocks",
            "listen": "127.0.0.1",
            "listen_port": ss_port,
            "method": "2022-blake3-aes-128-gcm",
            "password": ss_password,
            "network": ["tcp", "udp"]
        }],
        "outbounds": [{"type": "direct"}]
    }
    
    with open('/etc/sing-box/config.json', 'w') as f:
        json.dump(config, f, indent=2)
    
    # Create systemd service
    service = """[Unit]
Description=Sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    with open('/lib/systemd/system/sing-box.service', 'w') as f:
        f.write(service)
    
    # Shadow-TLS
    stls_version = run_command("curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest | grep -oP '\"tag_name\": \"v\\K[0-9.]+' | head -1")['stdout'] or '0.2.25'
    stls_arch = 'x86_64' if 'amd64' in arch_suffix else arch_suffix.replace('arm64', 'aarch64')
    
    if not os.path.exists('/usr/local/bin/shadow-tls'):
        run_command(f'cd /tmp && curl -sLO https://github.com/ihciah/shadow-tls/releases/download/v{stls_version}/shadow-tls-{stls_arch}-unknown-linux-musl')
        run_command(f'mv /tmp/shadow-tls-{stls_arch}-unknown-linux-musl /usr/local/bin/shadow-tls')
        run_command('chmod +x /usr/local/bin/shadow-tls')
    
    # Save config and start
    server_ip = get_server_ip()
    config_content = f"""SERVER_IP={server_ip}
TYPE=Singbox
SS_PORT={ss_port}
SHADOW_TLS_PORT={port}
SS_PASSWORD={ss_password}
SHADOW_TLS_PASSWORD={stls_password}
SINGBOX_VERSION={version}
"""
    with open('/etc/singbox-proxy-config.txt', 'w') as f:
        f.write(config_content)
    
    run_command('systemctl daemon-reload')
    run_command('systemctl enable sing-box')
    run_command('systemctl start sing-box')
    
    return jsonify({
        'status': 'ok',
        'message': 'Sing-box SS-2022 installed',
        'config': {
            'ip': server_ip,
            'port': port,
            'ss_password': ss_password,
            'shadow_tls_password': stls_password
        }
    })

def install_reality(env, port=None, sni='www.microsoft.com'):
    """Install VLESS Reality with auto-generated keys"""
    port = port or 443
    sni = sni or 'www.microsoft.com'
    
    # Download sing-box if not exists
    arch = run_command('uname -m')['stdout']
    if 'x86_64' in arch:
        arch_suffix = 'amd64'
    elif 'aarch64' in arch or 'arm64' in arch:
        arch_suffix = 'arm64'
    else:
        arch_suffix = 'armv7'
    
    version = run_command("curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -oP '\"tag_name\": \"v\\K[0-9.]+' | head -1")['stdout'] or '1.10.0'
    
    if not os.path.exists('/usr/local/bin/sing-box'):
        cmds = [
            'mkdir -p /etc/sing-box-reality',
            f'cd /tmp && curl -sLO https://github.com/SagerNet/sing-box/releases/download/v{version}/sing-box-{version}-linux-{arch_suffix}.tar.gz',
            f'cd /tmp && tar -xzf sing-box-{version}-linux-{arch_suffix}.tar.gz',
            f'mv /tmp/sing-box-{version}-linux-{arch_suffix}/sing-box /usr/local/bin/',
            'chmod +x /usr/local/bin/sing-box',
        ]
        for cmd in cmds:
            run_command(cmd, timeout=120)
    else:
        run_command('mkdir -p /etc/sing-box-reality')
    
    # Generate x25519 key pair using sing-box
    key_result = run_command('/usr/local/bin/sing-box generate reality-keypair')
    if key_result['returncode'] != 0:
        # Fallback: use openssl
        priv_key = run_command("openssl genpkey -algorithm x25519 | openssl pkey -text -noout | grep -A3 'priv:' | tail -3 | tr -d ' :\\n' | xxd -r -p | base64 | tr '/+' '_-' | tr -d '='")['stdout']
        pub_key = run_command("openssl genpkey -algorithm x25519 | openssl pkey -pubout -outform DER | tail -c 32 | base64 | tr '/+' '_-' | tr -d '='")['stdout']
    else:
        # Parse sing-box output
        lines = key_result['stdout'].strip().split('\n')
        priv_key = pub_key = ''
        for line in lines:
            if 'PrivateKey:' in line:
                priv_key = line.split(':')[1].strip()
            elif 'PublicKey:' in line:
                pub_key = line.split(':')[1].strip()
    
    # Generate UUID
    uuid = run_command("cat /proc/sys/kernel/random/uuid")['stdout']
    
    # Generate short_id
    short_id = run_command("openssl rand -hex 8")['stdout']
    
    # Reality config
    config = {
        "inbounds": [{
            "type": "vless",
            "listen": "::",
            "listen_port": port,
            "users": [{"uuid": uuid, "flow": "xtls-rprx-vision"}],
            "tls": {
                "enabled": True,
                "server_name": sni,
                "reality": {
                    "enabled": True,
                    "handshake": {
                        "server": sni,
                        "server_port": 443
                    },
                    "private_key": priv_key,
                    "short_id": [short_id]
                }
            }
        }],
        "outbounds": [{"type": "direct"}]
    }
    
    with open('/etc/sing-box-reality/config.json', 'w') as f:
        json.dump(config, f, indent=2)
    
    # Create systemd service
    service = """[Unit]
Description=Sing-box Reality Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box-reality/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    with open('/lib/systemd/system/sing-box-reality.service', 'w') as f:
        f.write(service)
    
    # Save config
    server_ip = get_server_ip()
    config_content = f"""SERVER_IP={server_ip}
TYPE=Reality
REALITY_PORT={port}
REALITY_UUID={uuid}
REALITY_PUBLIC_KEY={pub_key}
REALITY_SHORT_ID={short_id}
REALITY_DEST={sni}:443
SINGBOX_VERSION={version}
"""
    with open('/etc/reality-proxy-config.txt', 'w') as f:
        f.write(config_content)
    
    run_command('systemctl daemon-reload')
    run_command('systemctl enable sing-box-reality')
    run_command('systemctl start sing-box-reality')
    
    return jsonify({
        'status': 'ok',
        'message': 'VLESS Reality installed',
        'config': {
            'ip': server_ip,
            'port': port,
            'uuid': uuid,
            'public_key': pub_key,
            'short_id': short_id,
            'sni': sni
        }
    })

def install_hysteria2(env, port=None, domain=None):
    """Install Hysteria2 with self-signed cert or domain"""
    port = port or 443
    
    # Download hysteria
    arch = run_command('uname -m')['stdout']
    if 'x86_64' in arch:
        arch_suffix = 'amd64'
    elif 'aarch64' in arch or 'arm64' in arch:
        arch_suffix = 'arm64'
    else:
        arch_suffix = 'armv7'
    
    version = run_command("curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep -oP '\"tag_name\": \"app/v\\K[0-9.]+' | head -1")['stdout'] or '2.4.5'
    
    cmds = [
        'mkdir -p /etc/hysteria2',
        f'cd /tmp && curl -sLO https://github.com/apernet/hysteria/releases/download/app/v{version}/hysteria-linux-{arch_suffix}',
        'mv /tmp/hysteria-linux-* /usr/local/bin/hysteria2',
        'chmod +x /usr/local/bin/hysteria2',
    ]
    for cmd in cmds:
        run_command(cmd, timeout=120)
    
    # Generate password
    password = run_command("openssl rand -base64 16")['stdout']
    
    # Certificate handling
    if domain:
        # Try to use acme.sh for Let's Encrypt
        acme_result = run_command(f'''
            if [ ! -f ~/.acme.sh/acme.sh ]; then
                curl -s https://get.acme.sh | sh -s email=admin@{domain}
            fi
            ~/.acme.sh/acme.sh --issue -d {domain} --standalone --httpport 80 --force 2>/dev/null
            ~/.acme.sh/acme.sh --install-cert -d {domain} \
                --key-file /etc/hysteria2/private.key \
                --fullchain-file /etc/hysteria2/cert.pem
        ''', timeout=180)
        
        if acme_result['returncode'] != 0:
            # Fallback to self-signed
            domain = None
    
    if not domain:
        # Generate self-signed certificate
        server_ip = get_server_ip()
        run_command(f'''
            openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
                -keyout /etc/hysteria2/private.key \
                -out /etc/hysteria2/cert.pem \
                -subj "/CN={server_ip}" -days 3650
        ''')
        cert_domain = server_ip
    else:
        cert_domain = domain
    
    # Hysteria2 config
    config = f"""listen: :{port}

tls:
  cert: /etc/hysteria2/cert.pem
  key: /etc/hysteria2/private.key

auth:
  type: password
  password: {password}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
"""
    with open('/etc/hysteria2/config.yaml', 'w') as f:
        f.write(config)
    
    # Create systemd service
    service = """[Unit]
Description=Hysteria2 Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria2 server -c /etc/hysteria2/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
"""
    with open('/lib/systemd/system/hysteria2.service', 'w') as f:
        f.write(service)
    
    # Save config
    server_ip = get_server_ip()
    config_content = f"""SERVER_IP={server_ip}
TYPE=Hysteria2
HYSTERIA2_PORT={port}
HYSTERIA2_PASSWORD={password}
HYSTERIA2_DOMAIN={cert_domain}
HYSTERIA2_VERSION={version}
"""
    with open('/etc/hysteria2-proxy-config.txt', 'w') as f:
        f.write(config_content)
    
    run_command('systemctl daemon-reload')
    run_command('systemctl enable hysteria2')
    run_command('systemctl start hysteria2')
    
    return jsonify({
        'status': 'ok',
        'message': 'Hysteria2 installed' + (' (self-signed cert)' if not domain else ''),
        'config': {
            'ip': server_ip,
            'port': port,
            'password': password,
            'sni': cert_domain,
            'insecure': not domain  # True if self-signed
        }
    })

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
