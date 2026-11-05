#!/usr/bin/env bash
# ノード上で実行する読み取り専用の検査スクリプト(scripts/node-health.sh から呼ばれる)。
# 設定や状態は変更しない。出力は「[状態] 項目: 詳細」の 1 行ずつ。
#   OK   問題なし
#   WARN 要確認
#   NG   問題あり
#   SKIP 検査できない(ツール未導入など)

# 引数: --crash-checks  panic 系 sysctl の期待値も検査する(プロジェクトの方針に合わせて使う)
CRASH_CHECKS=0
for arg in "$@"; do
  [ "${arg}" = "--crash-checks" ] && CRASH_CHECKS=1
done

# 1 つの検査が失敗しても、残りを続ける
set +e

report() { printf '[%s] %s: %s\n' "$1" "$2" "$3"; }

# 1. 稼働状況
report OK "uptime" "$(uptime -p 2>/dev/null)  load=$(cut -d' ' -f1-3 /proc/loadavg)"

# 2. 起動履歴(直近 12 回)。60 秒未満で終わった起動は再起動ループの疑いがある
short=0
total=0
recent_list=$(journalctl --list-boots --no-pager 2>/dev/null | tail -12)
while read -r idx _ wd1 d1 t1 _ wd2 d2 t2 _; do
  [ -z "${idx}" ] && continue
  total=$((total + 1))
  s=$(date -d "${d1} ${t1}" +%s 2>/dev/null)
  e=$(date -d "${d2} ${t2}" +%s 2>/dev/null)
  if [ -n "${s}" ] && [ -n "${e}" ] && [ $((e - s)) -lt 60 ]; then
    short=$((short + 1))
  fi
done <<< "${recent_list}"
if [ "${total}" -eq 0 ]; then
  report SKIP "boot-history" "journal から起動履歴を取得できません"
elif [ "${short}" -ge 2 ]; then
  report NG "boot-history" "直近 ${total} 回のうち 60 秒未満の起動が ${short} 回(再起動ループの疑い)"
elif [ "${short}" -eq 1 ]; then
  report WARN "boot-history" "直近 ${total} 回のうち 60 秒未満の起動が 1 回"
else
  report OK "boot-history" "直近 ${total} 回に短時間の起動なし"
fi

# 2b. 前回の終了が正常か(shutdown/reboot の記録があるか)
if [ "${total:-0}" -ge 2 ]; then
  # 正常な終了の記録: reboot/poweroff の target 到達、systemd-shutdown の動作
  # (journald の "Journal stopped" は起動時にも出るため、判定には使わない)
  if journalctl -b -1 --no-pager 2>/dev/null | grep -qE "Reached target .*(Shutdown|Reboot|Power-Off)|systemd-shutdown\["; then
    report OK "prev-shutdown" "前回は正常な shutdown/reboot の記録あり"
  else
    report NG "prev-shutdown" "前回は正常な終了の記録なし(ログが途切れて停止した可能性)"
  fi
else
  report SKIP "prev-shutdown" "起動履歴が 2 回分未満のため判定できない"
fi

# 2c. EDAC のメモリエラーカウンタ(起動後の件数。再起動でリセットされる)
edac_found=0
for mc in /sys/devices/system/edac/mc/mc*; do
  [ -d "${mc}" ] || continue
  edac_found=1
  mc_name=$(basename "${mc}")
  ce=$(cat "${mc}/ce_count" 2>/dev/null)
  ue=$(cat "${mc}/ue_count" 2>/dev/null)
  if [ "${ue:-0}" -gt 0 ]; then
    report NG "edac-${mc_name}" "UE(訂正不能)${ue} 件"
  elif [ "${ce:-0}" -gt 0 ]; then
    report WARN "edac-${mc_name}" "CE(訂正可能)${ce} 件"
  else
    report OK "edac-${mc_name}" "CE/UE ともに 0 件"
  fi
  for dimm in "${mc}"/dimm*; do
    [ -d "${dimm}" ] || continue
    dce=$(cat "${dimm}/dimm_ce_count" 2>/dev/null)
    due=$(cat "${dimm}/dimm_ue_count" 2>/dev/null)
    label=$(cat "${dimm}/dimm_label" 2>/dev/null)
    if [ "${dce:-0}" -gt 0 ] || [ "${due:-0}" -gt 0 ]; then
      report WARN "edac-dimm" "${label:-$(basename "${dimm}")}: CE ${dce:-0} 件 / UE ${due:-0} 件"
    fi
  done
done
if [ "${edac_found}" -eq 0 ]; then
  report SKIP "edac" "/sys/devices/system/edac/mc がない(EDAC ドライバ未読み込み)"
fi

# 3. MCE(機械チェック例外)。現在の起動と、前の 3 回の起動を見る
mce_list=""
for b in 0 -1 -2 -3; do
  n=$(journalctl -k -b "${b}" --no-pager 2>/dev/null | grep -c 'Machine Check')
  mce_list="${mce_list} boot${b}=${n}"
done
if echo "${mce_list}" | grep -qE 'boot-?[0-9]*=[1-9]'; then
  if journalctl -k -b -1 --no-pager 2>/dev/null | grep -q 'Machine Check'; then
    report NG "mce" "起動ごとの件数:${mce_list}(前回の起動にも発生)"
  else
    report WARN "mce" "起動ごとの件数:${mce_list}"
  fi
else
  report OK "mce" "記録なし(${mce_list# })"
fi

# 4. メモリ・PCIe などのエラー(rasdaemon)
if command -v ras-mc-ctl >/dev/null 2>&1; then
  # SIGNAL events(systemd の通知)は障害ではないので除く
  ras_out=$(ras-mc-ctl --summary 2>/dev/null \
    | awk '/SIGNAL events/{skip=1; next} skip && /^\t/{next} {skip=0; print}' \
    | grep -v '^No ' | grep -v '^[[:space:]]*$' | tr -s ' \t' ' ')
  if [ -z "${ras_out}" ]; then
    report OK "ras" "メモリ・PCIe のエラー記録なし"
  else
    report WARN "ras" "$(echo "${ras_out}" | tr '\n' ' ' | cut -c1-200)"
  fi
else
  report SKIP "ras" "ras-mc-ctl 未導入"
fi

# 5. kdump とクラッシュダンプ(kdump-tools が入っているホストだけ検査する)
if systemctl cat kdump-tools.service >/dev/null 2>&1; then
  if systemctl is-active --quiet kdump-tools 2>/dev/null; then
    kdump_state="active"
  else
    kdump_state="inactive"
  fi
  dumps=$(find /var/crash -maxdepth 2 -name 'vmcore*' 2>/dev/null | wc -l)
  if [ "${dumps}" -gt 0 ]; then
    report WARN "kdump" "kdump=${kdump_state}, クラッシュダンプ ${dumps} 件あり(/var/crash)"
  else
    report OK "kdump" "kdump=${kdump_state}, クラッシュダンプなし"
  fi

  # 5b. クラッシュカーネルの読み込みと予約メモリ(panic 時にダンプを取れるか)
  if [ "$(cat /sys/kernel/kexec_crash_loaded 2>/dev/null)" = "1" ]; then
    report OK "kexec-loaded" "1(クラッシュカーネル読み込み済み)"
  else
    report NG "kexec-loaded" "1 ではない。panic 時にダンプを取得できない"
  fi
  crash_size=$(cat /sys/kernel/kexec_crash_size 2>/dev/null)
  if [ "${crash_size:-0}" -gt 0 ]; then
    report OK "kexec-size" "${crash_size} bytes 予約済み"
  else
    report NG "kexec-size" "0(crashkernel が予約されていない)"
  fi
else
  report SKIP "kdump" "kdump-tools 未導入"
fi

# 5c. panic 系 sysctl。期待値はプロジェクトの方針なので、--crash-checks を付けたときだけ検査する
if [ "${CRASH_CHECKS}" -eq 1 ]; then
  for kv in kernel.hardlockup_panic=1 kernel.softlockup_panic=1 kernel.unknown_nmi_panic=1 kernel.panic=30; do
    key=${kv%%=*}
    want=${kv#*=}
    got=$(sysctl -n "${key}" 2>/dev/null)
    if [ "${got}" = "${want}" ]; then
      report OK "sysctl" "${key}=${got}"
    else
      report NG "sysctl" "${key} 期待値 ${want} / 現在値 ${got:-取得できず}"
    fi
  done
fi

# 6. ディスクの健康状態(SMART)と SSD の寿命
if command -v smartctl >/dev/null 2>&1; then
  for dev in $(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do
    info=$(smartctl -i -H -A "/dev/${dev}" 2>/dev/null)
    if [ -z "${info}" ]; then
      report SKIP "smart-${dev}" "smartctl で取得できず"
      continue
    fi
    st=$(echo "${info}" | grep -E 'overall-health|SMART Health Status|result:' | head -1)
    model=$(echo "${info}" | sed -n -e 's/^Device Model: *//p' -e 's/^Model Number: *//p' | head -1)

    # 寿命の残り(%)。NVMe は Percentage Used、SATA は寿命系の属性の VALUE を使う
    life_remain=""
    life_src=""
    used=$(echo "${info}" | sed -n 's/^Percentage Used: *\([0-9]*\)%.*/\1/p' | head -1)
    if [ -n "${used}" ]; then
      life_remain=$((100 - used))
      life_src="NVMe"
    else
      for id in 233 177 232 231; do
        v=$(echo "${info}" | awk -v id="${id}" '$1==id{print $4; exit}')
        if [ -n "${v}" ]; then
          life_remain=$((10#${v}))
          life_src="ID${id}"
          break
        fi
      done
    fi

    realloc=$(echo "${info}" | awk '$1==5{print $10; exit}')
    poh=$(echo "${info}" | awk '$1==9{print $10; exit}')
    lba=$(echo "${info}" | awk '$1==241{print $10; exit}')
    written=""
    if [[ "${lba}" =~ ^[0-9]+$ ]]; then
      written=$(awk -v l="${lba}" 'BEGIN{printf "%.1f TB", l*512/1e12}')
    fi

    detail="${model:-機種不明} 寿命残り=${life_remain:-取得できず}%(${life_src:-不明})"
    detail="${detail} 再割り当て=${realloc:-不明} 使用時間=${poh:-不明}h"
    [ -n "${written}" ] && detail="${detail} 書き込み総量=${written}"

    status=OK
    reason=""
    if [ -n "${st}" ] && ! echo "${st}" | grep -qE 'PASSED|OK'; then
      status=NG
      reason="SMART 判定 NG"
    fi
    if [[ "${life_remain}" =~ ^[0-9]+$ ]]; then
      if [ "${life_remain}" -le 5 ]; then
        status=NG
        reason="${reason} 寿命残りわずか"
      elif [ "${life_remain}" -le 20 ] && [ "${status}" = OK ]; then
        status=WARN
        reason="${reason} 寿命残り少なめ"
      fi
    fi
    if [[ "${realloc}" =~ ^[0-9]+$ ]] && [ "${realloc}" -gt 0 ] && [ "${status}" = OK ]; then
      status=WARN
      reason="${reason} 再割り当てセクタあり"
    fi
    report "${status}" "smart-${dev}" "${detail}${reason:+ (${reason# })}"
  done
else
  report SKIP "smart" "smartctl 未導入"
fi

# 7. ディスク使用率(ルート)
use=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
if [ -n "${use}" ] && [ "${use}" -ge 90 ]; then
  report WARN "disk-root" "使用率 ${use}%"
elif [ -n "${use}" ]; then
  report OK "disk-root" "使用率 ${use}%"
else
  report SKIP "disk-root" "df で取得できません"
fi

# 8. 失敗中のサービス
failed_units=$(systemctl --failed --no-legend 2>/dev/null | awk 'NF{print $2}' | tr '\n' ' ')
failed=$(echo "${failed_units}" | wc -w)
if [ "${failed}" -gt 0 ]; then
  report WARN "failed-units" "${failed} 件: ${failed_units}"
else
  report OK "failed-units" "なし"
fi

# 9. 時刻同期
ntp=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
if [ "${ntp}" = "yes" ]; then
  report OK "time-sync" "同期済み"
else
  report WARN "time-sync" "NTPSynchronized=${ntp:-不明}"
fi

# ---- 以下は情報(INFO)。判定には使わない。トラブルシュート用 ----

# 10. BIOS・マザーボード・システム(dmidecode)
if command -v dmidecode >/dev/null 2>&1; then
  report INFO "bios" "$(dmidecode -s bios-vendor 2>/dev/null) $(dmidecode -s bios-version 2>/dev/null) (日付 $(dmidecode -s bios-release-date 2>/dev/null))"
  report INFO "board" "$(dmidecode -s baseboard-manufacturer 2>/dev/null) $(dmidecode -s baseboard-product-name 2>/dev/null) rev $(dmidecode -s baseboard-version 2>/dev/null)"
  report INFO "system" "$(dmidecode -s system-manufacturer 2>/dev/null) $(dmidecode -s system-product-name 2>/dev/null)"

  # 装着中の DIMM(場所・容量・部品番号)。シリアル番号は出さない
  dimms=$(dmidecode -t memory 2>/dev/null | awk '
    /^Memory Device/ { if (size != "" && size !~ /No Module/) print loc " " size " " pn; loc=""; size=""; pn="" }
    /^\tSize:/ { sub(/^\tSize: /, ""); size=$0 }
    /^\tLocator:/ { sub(/^\tLocator: /, ""); loc=$0 }
    /^\tPart Number:/ { sub(/^\tPart Number: /, ""); pn=$0; gsub(/ +$/, "", pn) }
    END { if (size != "" && size !~ /No Module/) print loc " " size " " pn }' | tr '\n' '/' | sed 's|/$||')
  report INFO "dimm" "${dimms:-不明}"
else
  report SKIP "bios" "dmidecode 未導入(導入すると BIOS・基板・メモリ構成を表示できる)"
fi

# 11. CPU・microcode・カーネル
cpu_model=$(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1)
microcode=$(grep -m1 '^microcode' /proc/cpuinfo 2>/dev/null | awk '{print $3}')
report INFO "cpu" "${cpu_model:-不明} microcode=${microcode:-不明}"
report INFO "kernel" "$(uname -r) cmdline: $(cut -c1-200 /proc/cmdline 2>/dev/null)"

# 12. 前回の起動が終わった直前のカーネルログ(どこで止まったかの手がかり)
if journalctl -k -b -1 --no-pager >/dev/null 2>&1; then
  last_lines=$(journalctl -k -b -1 --no-pager -n 3 -o short-iso 2>/dev/null | cut -c1-180 | tr '\n' ' ')
  report INFO "prev-boot-end" "${last_lines:-なし}"
else
  report INFO "prev-boot-end" "前回の起動のログなし"
fi

# 13. クラッシュ時の記録(pstore)
pstore_n=$(ls /sys/fs/pstore 2>/dev/null | wc -l)
report INFO "pstore" "${pstore_n} 件"

# 14. IPMI の SEL(BMC のイベントログ)。BMC が無いホストでは何もしない
if [ -e /dev/ipmi0 ] || [ -e /dev/ipmi/0 ] || [ -e /dev/ipmidev/0 ]; then
  if command -v ipmitool >/dev/null 2>&1; then
    sel_n=$(ipmitool sel list 2>/dev/null | wc -l)
    report INFO "ipmi-sel" "${sel_n} 件(ipmitool sel list で確認)"
    ipmitool sel list 2>/dev/null | tail -5 | cut -c1-200 | while IFS= read -r l; do report INFO "  sel" "$l"; done
  else
    report SKIP "ipmi-sel" "ipmitool 未導入"
  fi
else
  report SKIP "ipmi-sel" "IPMI デバイスなし"
fi
