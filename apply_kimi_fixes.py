#!/usr/bin/env python3
# Фиксы по ревью Кими: пункты 1,2,3,4,5,6 из "обязательно". Идемпотентно.
import re, subprocess, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parent
if not (ROOT/'module'/'vrrd.sh').exists(): sys.exit('Запусти в корне клона.')

FIX = []  # (file, old, new, tag)
def add(f,o,n,tag): FIX.append((f,o,n,tag))

OVR_OLD = '[ -f /data/adb/oneplus15-vrr-state/vrr.conf ] && . /data/adb/oneplus15-vrr-state/vrr.conf'
OVR_NEW = '''OVRR_CONF=/data/adb/oneplus15-vrr-state/vrr.conf
if [ -f "$OVRR_CONF" ]; then
  if sh -n "$OVRR_CONF" 2>/dev/null; then
    . "$OVRR_CONF"
  else
    echo "override config $OVRR_CONF has a syntax error; ignored" >> "$LOG"
  fi
fi'''
# Кими п.5: не соурсить пользовательский конф как код без проверки синтаксиса
for f in ('module/post-fs-data.sh','module/service.sh','module/vrrd.sh'):
    add(f, OVR_OLD, OVR_NEW, 'override-syntax-check')

# Кими п.6: полнота перезаписи в FORCE_ALL (иначе однострочный XML деградирует тихо)
add('module/post-fs-data.sh',
'''run sed -E -f "$RULES" "$S" > "$D"
if [ "$WIN_OVERRIDE" = all ]; then''',
'''run sed -E -f "$RULES" "$S" > "$D"
if [ "$FORCE_ALL" = 1 ]; then
  n_items=$(grep -o '<item ' "$D" | wc -l | tr -d ' ')
  n_high=$(grep -o '<item [^>]*rateId="[0-9]-[0-9]-[0-9]-7"' "$D" | wc -l | tr -d ' ')
  [ "$n_items" -gt 0 ] && [ "$n_items" = "$n_high" ] || abort "FORCE_ALL: only $n_high/$n_items items carry a 165 Hz rateId"
fi
if [ "$WIN_OVERRIDE" = all ]; then''', 'force-all-completeness')

# Кими п.4: дефолты демона -> измеренная карта 3/0
add('module/vrrd.sh', 'ACTIVE_MODE=7\nIDLE_MODE=1', 'ACTIVE_MODE=3\nIDLE_MODE=0', 'vrrd-defaults-3-0')

# Тесты: отвязать restore-integration от дефолтов скрипта (явно 7/1)
add('tests/restore-integration.py',
r'''(self.d / 'vrr.conf').write_text("IDLE_TIMEOUT=0.1\nKEEP_ACTIVE_CAMERA=0\nKEEP_ACTIVE_PKGS=''\nDEBUG=1\n")''',
r'''(self.d / 'vrr.conf').write_text("IDLE_TIMEOUT=0.1\nACTIVE_MODE=7\nIDLE_MODE=1\nKEEP_ACTIVE_CAMERA=0\nKEEP_ACTIVE_PKGS=''\nDEBUG=1\n")''',
'test-pin-modes')

# Новый тест: однострочный XML в FORCE_ALL должен отклоняться
add('tests/patch-pipeline.py',
"\nif __name__ == '__main__': unittest.main()",
'''
    def test_force_all_single_line_rejected(self):
        single = SOURCE.replace('\\n', '')
        self.xml.write_text(single)
        self.run_patch(False)

if __name__ == '__main__': unittest.main()''', 'test-force-all-single-line')

# ---- двухпроходная проверка якорей, затем запись ----
texts={}; missing=[]; ready=0; already=0
for f,o,n,tag in FIX:
    p=ROOT/f
    if not p.exists(): missing.append((f,tag,'FILE MISSING')); continue
    t=texts.get(f,p.read_text())
    if o in t:
        if t.count(o)!=1: missing.append((f,tag,'NOT UNIQUE'))
        else: texts[f]=t.replace(o,n,1); ready+=1
    elif n in t: already+=1
    else: missing.append((f,tag,'NOT FOUND: '+o[:50].replace('\n','\\n')))
if missing:
    print('НЕ применено (пришли вывод):')
    for m in missing: print('  ',m)
    sys.exit(1)
for f,t in texts.items(): (ROOT/f).write_text(t)
print(f'код: применено {ready}, уже было {already}')

# ---- Кими п.1: устаревший module/SHA256SUMS (package.py генерирует сам) ----
sha=ROOT/'module'/'SHA256SUMS'
if sha.exists(): sha.unlink(); print('удалён устаревший module/SHA256SUMS')
gi=ROOT/'.gitignore'
gitx=gi.read_text() if gi.exists() else ''
if 'module/SHA256SUMS' not in gitx:
    with gi.open('a') as fh: fh.write('\nmodule/SHA256SUMS\n')
    print('module/SHA256SUMS добавлен в .gitignore')

# ---- Кими п.2: update.json указывает на апстрим ----
uj=ROOT/'update.json'
if uj.exists(): uj.unlink(); print('удалён update.json (апстрим-указатель)')

# ---- Кими п.3: vrr.conf — killall не работает, путь через stop-флаг ----
vc=ROOT/'module'/'vrr.conf'
if vc.exists():
    lines=vc.read_text().split('\n'); out=[]
    for i,ln in enumerate(lines):
        if ln.lstrip().startswith('#') and 'killall' in ln:
            if out and 'After editing' in out[-1]: out.pop()
            out += ['# After editing: reboot, or restart the daemon cooperatively via the stop flag:',
                    '#   su -c "touch /data/adb/modules/OnePlus15-165HZ-LTPO/stop"   # daemon exits & restores baseline',
                    '#   sleep 3',
                    '#   su -c "rm /data/adb/modules/OnePlus15-165HZ-LTPO/stop; sh /data/adb/modules/OnePlus15-165HZ-LTPO/service.sh"']
        else: out.append(ln)
    vc.write_text('\n'.join(out)); print('vrr.conf: перезапуск через stop-флаг')

# ---- синтаксис ----
bad=[s.name for s in sorted((ROOT/'module').glob('*.sh'))
     if subprocess.run(['sh','-n',str(s)],capture_output=True).returncode!=0]
if bad: sys.exit('СИНТАКСИС: '+', '.join(bad))
print('sh -n: OK')

# ---- прогон затронутых сьютов (не блокирует, но смотри) ----
for s in ('tests/settings-state.py','tests/restore-integration.py','tests/patch-pipeline.py'):
    r=subprocess.run([sys.executable,s],cwd=ROOT,capture_output=True,text=True)
    print(s,'OK' if r.returncode==0 else 'FAIL')
    if r.returncode!=0: print(r.stderr[-1500:])

subprocess.run(['git','add','-A'],cwd=ROOT,check=True)
subprocess.run(['git','commit','-m','fix: review findings — override syntax guard, FORCE_ALL completeness, daemon defaults 3/0, drop stale SHA256SUMS/update.json, stop-flag restart'],cwd=ROOT,check=True)
print('Готово. Дальше: python tools/package.py --source-revision "$(git rev-parse HEAD)"')
