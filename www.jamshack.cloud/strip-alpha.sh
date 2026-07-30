#!/bin/bash
# strip-alpha.sh — supprime le canal alpha des captures pour App Store Connect
#
# Usage :
#   ./strip-alpha.sh <dossier> [couleur-de-fond]
#
# Exemples :
#   ./strip-alpha.sh ~/Desktop/Captures
#   ./strip-alpha.sh ~/Desktop/Captures black
#
# Les fichiers d'origine sont conservés ; les versions opaques sont écrites
# dans un sous-dossier "opaque/".

set -euo pipefail

SRC="${1:-}"
BG="${2:-white}"

if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "Usage : $0 <dossier> [couleur-de-fond]" >&2
  exit 1
fi

DEST="$SRC/opaque"
mkdir -p "$DEST"

# ImageMagick permet de choisir la couleur de composition ; sinon on retombe
# sur sips (aplatissement sur noir via conversion JPEG).
if command -v magick >/dev/null 2>&1; then
  ENGINE="magick"
elif command -v convert >/dev/null 2>&1; then
  ENGINE="convert"
else
  ENGINE="sips"
  echo "ImageMagick absent → repli sur sips (aplatissement sur noir, sortie JPEG)."
  echo "Pour contrôler la couleur de fond : brew install imagemagick"
  echo
fi

has_alpha() {
  # Renvoie 0 si le fichier possède un canal alpha
  local channels
  channels=$(sips -g hasAlpha "$1" 2>/dev/null | awk '/hasAlpha/ {print $2}')
  [[ "$channels" == "yes" ]]
}

count_total=0
count_fixed=0
count_clean=0

shopt -s nullglob nocaseglob
for f in "$SRC"/*.png "$SRC"/*.jpg "$SRC"/*.jpeg; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  name="${base%.*}"
  count_total=$((count_total + 1))

  if ! has_alpha "$f"; then
    echo "○ $base — déjà opaque, copié tel quel"
    cp "$f" "$DEST/$base"
    count_clean=$((count_clean + 1))
    continue
  fi

  case "$ENGINE" in
    magick|convert)
      out="$DEST/$name.png"
      "$ENGINE" "$f" -background "$BG" -alpha remove -alpha off -strip "$out"
      echo "● $base — alpha supprimé (fond $BG) → $(basename "$out")"
      ;;
    sips)
      out="$DEST/$name.jpg"
      sips -s format jpeg -s formatOptions 100 "$f" --out "$out" >/dev/null
      echo "● $base — converti en JPEG opaque → $(basename "$out")"
      ;;
  esac
  count_fixed=$((count_fixed + 1))
done
shopt -u nullglob nocaseglob

echo
echo "─────────────────────────────────────────"
echo "$count_total fichier(s) traité(s)"
echo "  $count_fixed avec alpha supprimé"
echo "  $count_clean déjà conformes"
echo "Résultat dans : $DEST"

# Vérification finale : plus aucun alpha ne doit subsister
echo
echo "Vérification :"
remaining=0
shopt -s nullglob nocaseglob
for f in "$DEST"/*.png "$DEST"/*.jpg "$DEST"/*.jpeg; do
  [[ -f "$f" ]] || continue
  if has_alpha "$f"; then
    echo "  ✗ $(basename "$f") contient encore un canal alpha"
    remaining=$((remaining + 1))
  fi
done
shopt -u nullglob nocaseglob

if [[ $remaining -eq 0 ]]; then
  echo "  ✓ Aucun canal alpha détecté — prêt pour App Store Connect"
else
  echo "  $remaining fichier(s) à reprendre manuellement"
  exit 1
fi
