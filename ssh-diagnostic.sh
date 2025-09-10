#ARREGLAR SSH
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


################################################################################
#########     DAR VOLUMEN A DISCO Y AÑADIR CORRECTAMENTE EN EL FSTAB    ########
################################################################################
Ejemplo:
# 1. Verificar el disco adicional
lsblk -f
blkid /dev/sda1

# 2. Si no está formateado, formatearlo:
mkfs.ext4 /dev/sda1

# 3. Obtener el UUID real:
UUID_REAL=$(blkid /dev/sda1 | grep -o 'UUID="[^"]*"' | sed 's/UUID="//g' | sed 's/"//g')
echo "UUID de sda1: $UUID_REAL"

salida :
UUID de sda1: 64e8f049-94e4-4170-a6b6-ea09ecd55f9e
14e80291-01

# 3.1. Hacer backup del fstab actual
sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# 3.2. Agregar la entrada correcta al fstab
echo 'UUID=64e8f049-94e4-4170-a6b6-ea09ecd55f9e /data ext4 defaults 0 2' | sudo tee -a /etc/fstab

# 3.3. Verificar que se agregó correctamente
tail -3 /etc/fstab

# 3.4. IMPORTANTE: Probar antes de reiniciar
sudo mount -a --dry-run

# 4. Crear punto de montaje:
mkdir -p /data

# 7. Si todo está bien:
mount /data



