#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE_TEXT'
用法:
  create-shell-submodule.sh --parent-url URL --parent-branch BRANCH --child-url URL --child-branch BRANCH --target-dir DIR --child-path PATH (--yes|--dry-run)

创建一个父壳仓库骨架，并把一个上游项目作为 Git 子模块挂载进去。

选项:
  --parent-url URL        要克隆的父壳仓库地址，例如 git@github.com:amuqiao/comfy-shell.git。
  --parent-branch NAME   要克隆的父壳仓库分支，例如 main。
  --child-url URL         要作为子模块添加的子项目仓库地址。
  --child-branch NAME    子项目要跟踪的分支，会写入 .gitmodules。
  --target-dir DIR       新壳仓库的本地目录。该目录不能已经存在。
  --child-path PATH      子项目在壳仓库中的相对路径，例如 ComfyUI。
  --yes                  确认执行克隆、文件写入和子模块添加。
  --dry-run              只校验参数并打印顶层计划动作，不写文件。
  -h, --help             显示帮助。

作用域:
  本脚本会创建一个父壳仓库工作副本，添加一个子项目子模块，创建 scripts/ 和 configs/，
  并且只在 README.md 不存在时写入 README.md。

不负责:
  不自动提交或推送，不迁移已有本地工作副本，不安装依赖，也不修改子项目内部文件。

输出:
  进度、诊断和错误输出到 stderr。最终摘要、git status 和下一步命令输出到 stdout。

副作用与保护边界:
  真实执行必须传 --yes。脚本拒绝复用已有目标目录或已有子项目路径。
  远端访问由 git clone 和 git submodule add 完成。--dry-run 不会检查克隆后才存在的仓库内容。

示例:
  scripts/create-shell-submodule.sh \
    --parent-url git@github.com:amuqiao/comfy-shell.git \
    --parent-branch main \
    --child-url git@github.com:Comfy-Org/ComfyUI.git \
    --child-branch master \
    --target-dir /Users/admin/Downloads/Code/comfy-shell \
    --child-path ComfyUI \
    --yes

  scripts/create-shell-submodule.sh \
    --parent-url git@github.com:amuqiao/comfy-shell.git \
    --parent-branch main \
    --child-url git@github.com:Comfy-Org/ComfyUI.git \
    --child-branch master \
    --target-dir /tmp/comfy-shell-check \
    --child-path ComfyUI \
    --dry-run

退出码:
  0  成功。
  2  用法、参数、配置或保护边界错误。
  其他非 0 退出码由 git 或文件系统命令返回。
USAGE_TEXT
}

error() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

info() {
  printf '%s\n' "$1" >&2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    error "$option requires a value"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "required command not found: $1"
  fi
}

is_gitlink_path() {
  local entry
  entry="$(git ls-files --stage -- "$1")"
  [[ "$entry" =~ ^160000[[:space:]] ]]
}

validate_ref_name() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    error "$label is required"
  fi
  if [[ "$value" == -* || "$value" == *..* || "$value" == */ || "$value" == *//* ]]; then
    error "$label is not a safe branch name: $value"
  fi
  if [[ ! "$value" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    error "$label contains unsupported characters: $value"
  fi
}

validate_child_path() {
  local value="$1"
  if [[ -z "$value" ]]; then
    error "--child-path is required"
  fi
  if [[ "$value" = /* || "$value" == -* || "$value" == "." || "$value" == ".." || "$value" == *"/../"* || "$value" == ../* || "$value" == */.. || "$value" == */ ]]; then
    error "--child-path must be a safe relative path"
  fi
  if [[ ! "$value" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    error "--child-path contains unsupported characters: $value"
  fi
  if [[ "$value" == *//* || "$value" == ".git" || "$value" == .git/* || "$value" == */.git || "$value" == */.git/* ]]; then
    error "--child-path must not target .git or contain empty path segments"
  fi

  local top_segment="${value%%/*}"
  case "$top_segment" in
    scripts|configs|README.md|.gitmodules)
      error "--child-path conflicts with shell-managed path: $top_segment"
      ;;
  esac
}

validate_target_dir() {
  local value="$1"
  if [[ -z "$value" ]]; then
    error "--target-dir is required"
  fi
  if [[ "$value" == -* ]]; then
    error "--target-dir must not start with '-'"
  fi
  local parent_dir
  parent_dir="$(dirname "$value")"
  if [[ ! -d "$parent_dir" ]]; then
    error "target parent directory does not exist: $parent_dir"
  fi
  if [[ -e "$value" ]]; then
    error "target directory already exists: $value"
  fi
}

write_readme() {
  local child_path="$1"
  local child_url="$2"
  local child_branch="$3"
  local repo_name
  repo_name="$(basename "$(pwd)")"

  {
    printf '# %s\n\n' "$repo_name"
    printf '%s\n\n' 'Thin shell repository for managing local setup around an upstream project source tree.'
    printf '## Layout\n\n'
    printf '    %s/\n' "$repo_name"
    printf '      %s/   # submodule: %s, branch %s\n' "$child_path" "$child_url" "$child_branch"
    printf '      configs/       # shell-managed local configs\n'
    printf '      scripts/       # shell-managed local scripts\n\n'
    printf '## Clone\n\n'
    printf '    git clone --recurse-submodules <this-repository-url>\n'
    printf '    cd %s\n\n' "$repo_name"
    printf 'If the repository was cloned without submodules:\n\n'
    printf '    git submodule update --init --recursive\n\n'
    printf '## Update Submodule\n\n'
    printf '    git submodule update --remote --merge %s\n' "$child_path"
    printf '    git add %s\n' "$child_path"
    printf '    git commit -m "Update %s submodule"\n\n' "$child_path"
    printf 'Keep shell scripts and configs in this repository, and keep upstream project changes inside the %s submodule.\n' "$child_path"
  } > README.md
}

run() {
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY-RUN:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

parent_url=""
parent_branch=""
child_url=""
child_branch=""
target_dir=""
child_path=""
yes="0"
dry_run="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent-url)
      require_value "$1" "${2:-}"
      parent_url="$2"
      shift 2
      ;;
    --parent-branch)
      require_value "$1" "${2:-}"
      parent_branch="$2"
      shift 2
      ;;
    --child-url)
      require_value "$1" "${2:-}"
      child_url="$2"
      shift 2
      ;;
    --child-branch)
      require_value "$1" "${2:-}"
      child_branch="$2"
      shift 2
      ;;
    --target-dir)
      require_value "$1" "${2:-}"
      target_dir="$2"
      shift 2
      ;;
    --child-path)
      require_value "$1" "${2:-}"
      child_path="$2"
      shift 2
      ;;
    --yes)
      yes="1"
      shift
      ;;
    --dry-run)
      dry_run="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "unknown argument: $1"
      ;;
  esac
done

[[ -n "$parent_url" ]] || error "--parent-url is required"
[[ -n "$child_url" ]] || error "--child-url is required"
validate_ref_name "--parent-branch" "$parent_branch"
validate_ref_name "--child-branch" "$child_branch"
validate_target_dir "$target_dir"
validate_child_path "$child_path"
require_command git
require_command dirname
require_command basename

if [[ "$dry_run" != "1" && "$yes" != "1" ]]; then
  error "real execution requires --yes"
fi

info "Creating shell repository skeleton"
info "parent: $parent_url ($parent_branch)"
info "child:  $child_url ($child_branch) -> $child_path"
info "target: $target_dir"

if [[ "$dry_run" == "1" ]]; then
  run git clone --branch "$parent_branch" --single-branch "$parent_url" "$target_dir"
  run git -C "$target_dir" submodule add -b "$child_branch" "$child_url" "$child_path"
  run mkdir -p "$target_dir/scripts" "$target_dir/configs"
  run touch "$target_dir/scripts/.gitkeep" "$target_dir/configs/.gitkeep"
  run git -C "$target_dir" add .gitmodules "$child_path" README.md scripts/.gitkeep configs/.gitkeep
  exit 0
fi

run git clone --branch "$parent_branch" --single-branch "$parent_url" "$target_dir"
cd "$target_dir"
repo_root="$(pwd -P)"

if [[ -e "$child_path" ]]; then
  error "child path already exists after cloning parent: $child_path"
fi

run git submodule add -b "$child_branch" "$child_url" "$child_path"

for dir in scripts configs; do
  if is_gitlink_path "$dir"; then
    error "refusing to write into submodule path: $dir"
  fi
  if [[ -L "$dir" ]]; then
    error "refusing to write through symlink: $dir"
  fi
  if [[ -e "$dir" && ! -d "$dir" ]]; then
    error "expected directory path but found non-directory: $dir"
  fi
  run mkdir -p "$dir"
  real_dir="$(cd "$dir" && pwd -P)"
  case "$real_dir" in
    "$repo_root"/*) ;;
    *) error "refusing to write outside repository root: $dir" ;;
  esac

  gitkeep="$dir/.gitkeep"
  if [[ -L "$gitkeep" ]]; then
    error "refusing to write through symlink: $gitkeep"
  fi
  if [[ -e "$gitkeep" && ! -f "$gitkeep" ]]; then
    error "expected file path but found non-file: $gitkeep"
  fi
  real_gitkeep="$real_dir/.gitkeep"
  case "$real_gitkeep" in
    "$repo_root"/*) ;;
    *) error "refusing to write outside repository root: $gitkeep" ;;
  esac
  run touch "$gitkeep"
done

if [[ -L README.md ]]; then
  error "refusing to write through symlink: README.md"
fi
if [[ -e README.md && ! -f README.md ]]; then
  error "expected file path but found non-file: README.md"
fi
if [[ -e README.md ]]; then
  info "README.md already exists; leaving it unchanged"
else
  write_readme "$child_path" "$child_url" "$child_branch"
fi

run git add .gitmodules "$child_path" README.md scripts/.gitkeep configs/.gitkeep

printf 'Skeleton created at %s\n' "$target_dir"
printf '\nStaged changes:\n'
git status --short
printf '\nNext steps:\n'
printf '  cd %s\n' "$target_dir"
printf '  git diff --cached --stat\n'
printf '  git commit -m "Add %s submodule shell"\n' "$child_path"
