#!/bin/bash
# Kullanım:
#   ./build.sh            → build/bkjournal oluşturur
#   ./build.sh --install  → ayrıca ~/.local/bin/bkjournal olarak kurar
# Zamanlayıcıyı KURMAZ; onun için kurulumdan sonra `bkjournal kur` çalıştırın.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product bkjournal
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p build
cp "$BIN_DIR/bkjournal" build/bkjournal
echo "Oluşturuldu: build/bkjournal"

if [[ "${1:-}" == "--install" ]]; then
    DEST_DIR="$HOME/.local/bin"
    mkdir -p "$DEST_DIR"
    # Önce geçici ada kopyalanır, sonra taşınır; çalışan eski kopya yarım dosya görmez.
    cp build/bkjournal "$DEST_DIR/.bkjournal.yeni"
    mv -f "$DEST_DIR/.bkjournal.yeni" "$DEST_DIR/bkjournal"
    echo "Kuruldu: $DEST_DIR/bkjournal"
    echo "Denemek için:        bkjournal yaz --kuru"
    echo "Her gün çalışması için: bkjournal kur"
fi
