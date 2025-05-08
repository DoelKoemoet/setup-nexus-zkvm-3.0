#!/bin/bash
set -e

echo "🚀 Menyiapkan Nexus zkVM environment..."

# 1. Instal dependensi sistem
echo "📦 Menginstal dependensi..."
sudo apt update && sudo apt install curl git build-essential pkg-config libssl-dev -y

# 2. Instal Rust jika belum ada
if ! command -v rustc &> /dev/null; then
    echo "🦀 Menginstal Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "✅ Rust sudah terinstal."
fi

# 3. Install toolchain nightly yang diperlukan
echo "🧱 Menambahkan nightly toolchain..."
rustup install nightly-2025-01-02
rustup component add rust-src --toolchain nightly-2025-01-02

# 4. Periksa dan instal cargo-nexus terbaru dari GitHub
echo "📥 Memeriksa dan menginstal cargo-nexus..."
LATEST_TAG=$(curl -s https://api.github.com/repos/nexus-xyz/nexus-zkvm/tags | jq -r '.[0].name')
echo "Versi terbaru cargo-nexus adalah: $LATEST_TAG"
rustup run nightly-2025-01-02 cargo install --git https://github.com/nexus-xyz/nexus-zkvm cargo-nexus --tag "$LATEST_TAG"

# 5. Buat project zkVM demo
PROJECT_DIR="$HOME/nexus-host"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "📁 Membuat project Nexus zkVM..."
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    rustup run nightly-2025-01-02 cargo nexus new
else
    echo "⚠️ Project sudah ada di $PROJECT_DIR. Lewati."
    cd "$PROJECT_DIR"
fi

# 6. Ganti isi program dengan contoh fib
cat > "$PROJECT_DIR/src/main.rs" <<EOF
#![no_std]
#![no_main]

fn fib(n: u32) -> u32 {
    match n {
        0 => 0,
        1 => 1,
        _ => fib(n - 1) + fib(n - 2),
    }
}

#[nexus_rt::main]
fn main() {
    let n = 7;
    let result = fib(n);
    assert_eq!(result, 13);
}
EOF

# 7. Buat wrapper script yang menjalankan run, prove, verify
WRAPPER_SCRIPT="$PROJECT_DIR/run_host.sh"
echo "🛠️  Membuat wrapper script..."
cat > "$WRAPPER_SCRIPT" <<EOT
#!/bin/bash
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "\$LOG_DIR"

RUN_LOG="\$LOG_DIR/run.log"
PROVE_LOG="\$LOG_DIR/prove.log"
VERIFY_LOG="\$LOG_DIR/verify.log"

echo "▶️  [\$(date)] Menjalankan Nexus zkVM..." >> "\$RUN_LOG"
rustup run nightly-2025-01-02 cargo nexus run --public 7 >> "\$RUN_LOG" 2>&1

echo "🔒 [\$(date)] Membuktikan program..." >> "\$PROVE_LOG"
rustup run nightly-2025-01-02 cargo nexus prove >> "\$PROVE_LOG" 2>&1

echo "✅ [\$(date)] Memverifikasi bukti..." >> "\$VERIFY_LOG"
rustup run nightly-2025-01-02 cargo nexus verify >> "\$VERIFY_LOG" 2>&1
EOT

chmod +x "$WRAPPER_SCRIPT"

# 8. Buat systemd service
SERVICE_FILE="/etc/systemd/system/nexus-zkvm.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "📄 Membuat systemd service..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Nexus zkVM Demo Service
After=network.target

[Service]
Type=simple
ExecStart=$WRAPPER_SCRIPT
WorkingDirectory=$PROJECT_DIR
Restart=on-failure
Environment="PATH=$HOME/.cargo/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF
else
    echo "⚠️ Service sudah ada."
fi

# 9. Buat logrotate config
LOGROTATE_CONF="/etc/logrotate.d/nexus-zkvm"
sudo tee "$LOGROTATE_CONF" > /dev/null <<EOF
$PROJECT_DIR/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# 10. Reload & aktifkan service
echo "🔄 Mengaktifkan service Nexus zkVM..."
sudo systemctl daemon-reload
sudo systemctl enable nexus-zkvm
sudo systemctl restart nexus-zkvm

echo "✅ Instalasi selesai!"
echo "Cek status: sudo systemctl status nexus-zkvm"
echo "Cek log: tail -f $PROJECT_DIR/logs/run.log"
