#!/bin/bash

# ==========================================
# Configuration
# ==========================================
DOTFILES="$HOME/Documents/dotfile"
CONFIG_DIR="$HOME/.config"

# 检查是否安装 gum
if ! command -v gum &>/dev/null; then
  echo "❌ Gum not found. Installing via brew..."
  brew install gum
fi

# ==========================================
# Helpers & UI
# ==========================================
show_banner() {
  clear
  gum style \
    --foreground 212 --border-foreground 212 --border double \
    --align center --width 50 --margin "1 2" --padding "2 4" \
    "🔮 DOTFILES CONTROL CENTER" \
    "Manage your digital life like a Pro"
}

log_success() { gum style --foreground 82 "✅ $1"; }
log_error() { gum style --foreground 196 "❌ $1"; }
log_info() { gum style --foreground 39 "ℹ️  $1"; }

# ==========================================
# 1. 巡检 & 收编 (Adopt) - [已修复逻辑]
# ==========================================
action_adopt() {
  gum style --bold --foreground 212 "🔍 Scanning for unmanaged configs in ~/.config..."

  UNMANAGED=""

  # 修复：使用原生 for 循环代替 find，避免 .config 父目录导致的误判
  # 遍历 .config 下的所有非隐藏文件/文件夹
  for path in "$CONFIG_DIR"/*; do
    # 获取文件名
    name=$(basename "$path")

    # 排除系统垃圾
    if [[ "$name" == ".DS_Store" ]]; then continue; fi

    # 核心判断逻辑：
    # 1. 必须是目录 (-d)
    # 2. 必须不是软链接 (! -L)
    if [ -d "$path" ] && [ ! -L "$path" ]; then
      # 将发现的目录追加到列表中
      UNMANAGED+="$name"$'\n'
    fi
  done

  # 去掉最后多余的换行符
  UNMANAGED=$(echo "$UNMANAGED" | sed '/^$/d')

  if [ -z "$UNMANAGED" ]; then
    log_success "Clean! All configs are managed (symlinked)."
    return
  fi

  # 让用户多选
  APPS_TO_ADOPT=$(echo "$UNMANAGED" | gum choose --no-limit --height 15 --header "Select apps to adopt into dotfiles:")

  if [ -z "$APPS_TO_ADOPT" ]; then
    log_info "No apps selected."
    return
  fi

  # 将多行字符串转换为数组进行遍历
  echo "$APPS_TO_ADOPT" | while read -r app; do
    if [ -z "$app" ]; then continue; fi

    gum spin --spinner dot --title "Adopting $app..." -- sleep 1

    SRC="$CONFIG_DIR/$app"
    DEST_PARENT="$DOTFILES/$app/.config"

    # 1. 创建目标坑位
    mkdir -p "$DEST_PARENT"

    # 2. 移动实体文件 (这里要非常小心路径)
    # 使用 mv 将整个文件夹移动过去
    if mv "$SRC" "$DEST_PARENT/"; then
      # 3. 发射 Stow 链接
      cd "$DOTFILES" || exit
      # Stow 需要在该应用包的根目录下执行
      if stow "$app"; then
        log_success "Adopted: $app"
      else
        log_error "Stow failed for $app. Check manualy."
      fi
    else
      log_error "Failed to move $app"
    fi
  done

  gum style --foreground 212 "✨ Operation complete."
  # 等待用户按键，防止结果一闪而过
  read -n 1 -s -r -p "Press any key to continue..."
}

# ==========================================
# 2. 安全审计 & 提交 (Commit) - [智能剔除版]
# ==========================================
action_sync() {
  cd "$DOTFILES" || exit

  gum style --foreground 212 "📊 Git Status:"
  git status -s
  echo ""

  gum confirm "Proceed with Sync?" || return

  # 1. 先把所有东西加入暂存区
  git add .

  gum spin --spinner monkey --title "🕵️ Scanning for secrets (Keys/Tokens)..." -- sleep 1

  if command -v gitleaks &>/dev/null; then
    # 创建临时报告文件
    LEAK_REPORT=$(mktemp)

    # 运行 Gitleaks，并将输出重定向到临时文件
    # 注意：这里我们允许它报错 (if ! ...)，然后进入处理逻辑
    if ! gitleaks protect --staged --verbose --config "$DOTFILES/.gitleaks.toml" >"$LEAK_REPORT" 2>&1; then

      echo ""
      log_error "Secrets detected! Initiating Auto-Filter Protocol..."

      # === 核心魔法：解析并剔除脏文件 ===

      # 从日志中提取 "File: <路径>" 这一行，并去重
      # grep 匹配 "File:", awk 取第二个字段(路径)
      BAD_FILES=$(grep -E "^\s*File:\s+" "$LEAK_REPORT" | awk '{print $2}' | sort | uniq)

      # 遍历所有脏文件，将它们从暂存区移除
      for file in $BAD_FILES; do
        if [ -n "$file" ]; then
          git restore --staged "$file"
          gum style --foreground 208 "🚫 Skipped (Unstaged): $file"
        fi
      done

      # 清理临时报告
      rm "$LEAK_REPORT"

      echo ""

      # === 检查是否还有剩余文件 ===
      # 如果踢出脏文件后，暂存区空了，就终止提交
      if [ -z "$(git diff --cached --name-only)" ]; then
        log_error "No valid files left to commit (All contained secrets). Aborting."
        read -n 1 -s -r -p "Press any key to return..."
        return
      fi

      log_info "Proceeding with remaining safe files..."
      sleep 1
    else
      log_success "Security Scan Passed."
      rm "$LEAK_REPORT"
    fi
  else
    log_info "Gitleaks not found, skipping security scan."
  fi

  # 3. 剩下的流程不变
  TYPE=$(gum choose "feat" "fix" "chore" "docs" "style" "refactor")
  SCOPE=$(gum input --placeholder "scope (e.g. nvim, tmux)")
  MSG=$(gum input --placeholder "What changed?")

  if [ -z "$MSG" ]; then
    log_error "Commit message empty. Aborted."
    return
  fi

  if [ -z "$SCOPE" ]; then
    FULL_MSG="$TYPE: $MSG"
  else
    FULL_MSG="$TYPE($SCOPE): $MSG"
  fi

  # 4. 提交 & 推送
  if git commit -m "$FULL_MSG"; then
    gum spin --spinner globe --title "Pushing to remote..." -- git push
    log_success "Synced successfully! 🚀"
  else
    log_error "Commit failed."
  fi
  read -n 1 -s -r -p "Press any key to continue..."
}

# ==========================================
# 3. 状态概览 (Dashboard)
# ==========================================
action_status() {
  echo ""
  gum style --foreground 212 "📂 Dotfiles Structure (~/Documents/dotfile):"

  if command -v eza &>/dev/null; then
    eza --tree --level=2 --icons --git-ignore "$DOTFILES" | gum style --border rounded --padding "1 2" --border-foreground 240
  else
    tree -L 2 "$DOTFILES"
  fi

  read -n 1 -s -r -p "Press any key to return..."
}

# ==========================================
# Main Loop
# ==========================================
while true; do
  show_banner

  CHOICE=$(gum choose \
    "1. 📥 Adopt Unmanaged Configs (Detect & Stow)" \
    "2. 🔄 Sync to GitHub (Audit -> Commit -> Push)" \
    "3. 📂 View Dashboard (Tree View)" \
    "4. 🚪 Exit")

  case "$CHOICE" in
  "1. 📥 Adopt"*) action_adopt ;;
  "2. 🔄 Sync"*) action_sync ;;
  "3. 📂 View"*) action_status ;;
  "4. 🚪 Exit")
    clear
    exit 0
    ;;
  esac

  if [[ "$CHOICE" != *"View"* ]] && [[ "$CHOICE" != *"Adopt"* ]] && [[ "$CHOICE" != *"Sync"* ]]; then
    echo ""
    sleep 1
  fi
done
