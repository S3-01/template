#!/bin/bash

# SSH Diagnostic Script
# Diagnóstico completo para problemas de SSH

echo "=================================================="
echo "       DIAGNÓSTICO SSH - $(date)"
echo "=================================================="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo ""
echo "1. ESTADO DEL SERVICIO SSH"
echo "=========================="

# Verificar si SSH está instalado
if command -v sshd &> /dev/null; then
    print_status 0 "SSH daemon está instalado"
else
    print_status 1 "SSH daemon NO está instalado"
    echo "   Ejecuta: apt update && apt install openssh-server"
fi

# Verificar estado del servicio
echo ""
echo "Estado del servicio:"
systemctl is-active ssh >/dev/null 2>&1
ACTIVE=$?
systemctl is-enabled ssh >/dev/null 2>&1
ENABLED=$?

print_status $ACTIVE "SSH está activo"
print_status $ENABLED "SSH está habilitado para inicio automático"

if [ $ACTIVE -ne 0 ]; then
    echo "   Para iniciar: systemctl start ssh"
fi

if [ $ENABLED -ne 0 ]; then
    echo "   Para habilitar: systemctl enable ssh"
fi

echo ""
echo "2. CONFIGURACIÓN DE RED"
echo "======================"

# Verificar puertos en escucha
echo ""
echo "Puertos SSH en escucha:"
SSH_PORTS=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | cut -d':' -f2 | sort -u)

if [ -z "$SSH_PORTS" ]; then
    print_status 1 "SSH no está escuchando en ningún puerto"
else
    for port in $SSH_PORTS; do
        print_status 0 "SSH escuchando en puerto $port"
    done
fi

# Verificar interfaces de red
echo ""
echo "Interfaces de red:"
ip addr show | grep -E "inet " | grep -v "127.0.0.1" | while read line; do
    IP=$(echo $line | awk '{print $2}' | cut -d'/' -f1)
    echo "   IP disponible: $IP"
done

echo ""
echo "3. CONFIGURACIÓN SSH"
echo "==================="

CONFIG_FILE="/etc/ssh/sshd_config"
if [ -f "$CONFIG_FILE" ]; then
    print_status 0 "Archivo de configuración existe: $CONFIG_FILE"
    
    echo ""
    echo "Configuraciones importantes:"
    
    # Puerto
    PORT=$(grep "^Port " $CONFIG_FILE 2>/dev/null | awk '{print $2}')
    if [ -z "$PORT" ]; then
        PORT="22"
        echo "   Puerto: 22 (por defecto)"
    else
        echo "   Puerto: $PORT"
    fi
    
    # PermitRootLogin
    ROOT_LOGIN=$(grep "^PermitRootLogin " $CONFIG_FILE 2>/dev/null | awk '{print $2}')
    if [ -z "$ROOT_LOGIN" ]; then
        ROOT_LOGIN="prohibit-password"
    fi
    echo "   PermitRootLogin: $ROOT_LOGIN"
    
    # PasswordAuthentication
    PASS_AUTH=$(grep "^PasswordAuthentication " $CONFIG_FILE 2>/dev/null | awk '{print $2}')
    if [ -z "$PASS_AUTH" ]; then
        PASS_AUTH="yes"
    fi
    echo "   PasswordAuthentication: $PASS_AUTH"
    
    # PubkeyAuthentication
    PUBKEY_AUTH=$(grep "^PubkeyAuthentication " $CONFIG_FILE 2>/dev/null | awk '{print $2}')
    if [ -z "$PUBKEY_AUTH" ]; then
        PUBKEY_AUTH="yes"
    fi
    echo "   PubkeyAuthentication: $PUBKEY_AUTH"
    
else
    print_status 1 "Archivo de configuración NO existe"
fi

# Verificar sintaxis del archivo de configuración
echo ""
echo "Verificación de sintaxis:"
if sshd -t 2>/dev/null; then
    print_status 0 "Configuración SSH es válida"
else
    print_status 1 "ERROR en la configuración SSH"
    echo "   Errores encontrados:"
    sshd -t 2>&1 | sed 's/^/   /'
fi

echo ""
echo "4. CLAVES DEL SERVIDOR"
echo "====================="

# Verificar claves del host
for key_type in rsa ecdsa ed25519; do
    key_file="/etc/ssh/ssh_host_${key_type}_key"
    if [ -f "$key_file" ]; then
        print_status 0 "Clave $key_type existe"
    else
        print_status 1 "Clave $key_type NO existe"
        echo "   Para generar: ssh-keygen -t $key_type -f $key_file -N ''"
    fi
done

echo ""
echo "5. FIREWALL"
echo "==========="

# Verificar UFW
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    echo "Estado de UFW: $UFW_STATUS"
    
    if echo "$UFW_STATUS" | grep -q "active"; then
        print_warning "UFW está activo, verificando reglas SSH:"
        ufw status | grep -E "(22|ssh)" || print_warning "No hay reglas SSH explícitas"
    fi
else
    echo "UFW no está instalado"
fi

# Verificar iptables
if command -v iptables &> /dev/null; then
    IPTABLES_RULES=$(iptables -L INPUT -n 2>/dev/null | grep -E "(22|ssh)" | wc -l)
    if [ $IPTABLES_RULES -gt 0 ]; then
        echo "Reglas iptables para SSH encontradas: $IPTABLES_RULES"
    else
        echo "No hay reglas iptables específicas para SSH"
    fi
fi

echo ""
echo "6. LOGS RECIENTES"
echo "================="

echo "Últimos 10 eventos SSH:"
journalctl -u ssh --no-pager -n 10 2>/dev/null | tail -10 | sed 's/^/   /'

echo ""
echo "Errores de autenticación recientes:"
grep "sshd.*Failed\|sshd.*Invalid\|sshd.*Connection.*closed" /var/log/auth.log 2>/dev/null | tail -5 | sed 's/^/   /' || echo "   No se encontraron errores recientes"

echo ""
echo "7. PRUEBA DE CONECTIVIDAD LOCAL"
echo "=============================="

echo "Probando conexión SSH local..."
timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes localhost exit 2>/dev/null
if [ $? -eq 0 ]; then
    print_status 0 "Conexión SSH local exitosa"
else
    print_status 1 "Fallo en conexión SSH local"
    echo "   Posibles causas: servicio inactivo, configuración incorrecta, o claves faltantes"
fi

echo ""
echo "8. RECOMENDACIONES"
echo "=================="

echo ""
if [ $ACTIVE -ne 0 ]; then
    echo "• Iniciar servicio SSH: systemctl start ssh"
fi

if [ $ENABLED -ne 0 ]; then
    echo "• Habilitar SSH en inicio: systemctl enable ssh"
fi

if [ -z "$SSH_PORTS" ]; then
    echo "• SSH no está escuchando. Verificar configuración y reiniciar servicio"
fi

# Verificar si hay claves faltantes
missing_keys=0
for key_type in rsa ecdsa ed25519; do
    if [ ! -f "/etc/ssh/ssh_host_${key_type}_key" ]; then
        missing_keys=1
        break
    fi
done

if [ $missing_keys -eq 1 ]; then
    echo "• Generar claves del servidor: ssh-keygen -A"
fi

if ! sshd -t 2>/dev/null; then
    echo "• Corregir errores en /etc/ssh/sshd_config"
fi

echo ""
echo "=================================================="
echo "Diagnóstico completado - $(date)"

echo "=================================================="






cat > /etc/ssh/sshd_config << EOF
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF



# Eliminar claves viejas (pueden estar corruptas)
rm -f /etc/ssh/ssh_host_*

# Generar nuevas claves
ssh-keygen -A


# Verificar que la configuración es válida
sshd -t

# Si no hay errores, iniciar SSH
systemctl start ssh
systemctl enable ssh
systemctl status ssh





# Ejecuta todo esto en secuencia:
sshd -t
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

cat > /etc/ssh/sshd_config << EOF
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

sshd -t
systemctl start ssh
systemctl enable ssh
systemctl status ssh
ss -tlnp | grep :22
