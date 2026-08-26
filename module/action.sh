#!/system/bin/sh
# Кнопка «Действие» в менеджере KernelSU.
# Пересобирает патч из текущего файла прошивки — нужно после OTA,
# после правки vrr.conf или после установки новых приложений с камерой.
MODDIR=${0%/*}

echo "OnePlus15-165HZ-LTPO — пересборка патча"
echo

# 1. свежий список камерных приложений
if [ -f "$MODDIR/scan_camera_pkgs.sh" ]; then
  echo "· $(sh "$MODDIR/scan_camera_pkgs.sh" 2>&1 | tail -1)"
fi

# 2. снимаем подмену, чтобы под ней открылся исходный файл прошивки
SRC=$(cat "$MODDIR/.mounted" 2>/dev/null)
[ -z "$SRC" ] && SRC=/my_product/etc/refresh_rate_config.xml
i=0
while grep -q 'version="20991231"' "$SRC" 2>/dev/null && [ $i -lt 5 ]; do
  umount "$SRC" 2>/dev/null || break
  i=$((i + 1))
done
if grep -q 'version="20991231"' "$SRC" 2>/dev/null; then
  echo "· не удалось снять подмену с $SRC — нужна перезагрузка"
  exit 1
fi
echo "· подмена снята, под ней исходник прошивки"

# 3. пересобираем и монтируем заново
sh "$MODDIR/post-fs-data.sh"

echo
if [ -f "$MODDIR/.mounted" ]; then
  echo "Готово. Что получилось:"
  D="$MODDIR/patched/refresh_rate_config.xml"
  echo "  записей 165 Гц:      $(grep -c ' rateId="[0-9]-[0-9]-[0-9]-7"' "$D" 2>/dev/null)"
  echo "  cameraOverride:      $(grep -o '<cameraOverride' "$D" 2>/dev/null | wc -l)"
  echo "  enableWinOverride:   $(grep -o 'enableWinOverride="false"' "$D" 2>/dev/null | wc -l)"
  echo
  echo "Файл подменён, но система читает его только при старте —"
  echo "чтобы изменения вступили в силу, перезагрузитесь."
else
  echo "Патч НЕ применён. Причина в логе:"
  tail -4 "$MODDIR/vrrd.log" 2>/dev/null
fi
