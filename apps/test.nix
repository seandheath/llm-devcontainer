# Test runner for llm-devcontainer
#
# Verifies:
# 1. Container starts successfully
# 2. Nix store is accessible
# 3. Claude Code is installed and runnable
# 4. Basic container security is in place

{ pkgs
, self
}:

pkgs.writeShellScript "llm-devcontainer-test" ''
  set -euo pipefail

  # Colors
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'

  PASS=0
  FAIL=0

  log_test() {
    echo -e "''${YELLOW}[TEST]''${NC} $*"
  }

  log_pass() {
    echo -e "''${GREEN}[PASS]''${NC} $*"
    ((PASS++))
  }

  log_fail() {
    echo -e "''${RED}[FAIL]''${NC} $*"
    ((FAIL++))
  }

  # Ensure image exists
  if ! ${pkgs.podman}/bin/podman image exists llm-devcontainer:latest; then
    echo "[llm-devcontainer-test] Image not found, building..."
    nix run ${self}#build
  fi

  echo ""
  echo "═══════════════════════════════════════"
  echo " llm-devcontainer Test Suite"
  echo "═══════════════════════════════════════"
  echo ""

  # Create temporary test directory
  TEST_DIR=$(mktemp -d)
  trap "rm -rf $TEST_DIR" EXIT

  # Test 1: Container starts
  log_test "Container startup..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      echo "Container started successfully" >/dev/null 2>&1; then
    log_pass "Container starts"
  else
    log_fail "Container failed to start"
  fi

  # Test 2: Nix store is accessible
  log_test "Nix store accessibility..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      sh -c 'test -d /nix/store && ls /nix/store | head -1 >/dev/null'; then
    log_pass "Nix store is accessible"
  else
    log_fail "Nix store not accessible"
  fi

  # Test 3: Nix command works
  log_test "Nix command functionality..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/var:rw \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.local:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      nix --version >/dev/null 2>&1; then
    log_pass "Nix command works"
  else
    log_fail "Nix command failed"
  fi

  # Test 4: Claude Code is installed
  log_test "Claude Code installation..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      claude --version >/dev/null 2>&1; then
    log_pass "Claude Code is installed"
  else
    log_fail "Claude Code not found or not working"
  fi

  # Test 5: Entrypoint script runs
  log_test "Entrypoint initialization..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/var:rw \
      --tmpfs=/run:rw \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.local:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      /usr/local/bin/entrypoint.sh echo "Entrypoint works" 2>&1 | grep -q "Entrypoint works"; then
    log_pass "Entrypoint initializes correctly"
  else
    log_fail "Entrypoint failed"
  fi

  # Test 6: Read-only filesystem
  log_test "Read-only filesystem enforcement..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      llm-devcontainer:latest \
      sh -c 'touch /etc/test 2>&1 && exit 1 || exit 0'; then
    log_pass "Root filesystem is read-only"
  else
    log_fail "Root filesystem is writable (security issue)"
  fi

  # Test 7: Workspace mount works
  log_test "Workspace volume mounting..."
  echo "test content" > "$TEST_DIR/test.txt"
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      -v "$TEST_DIR:/workspace:rw" \
      llm-devcontainer:latest \
      cat /workspace/test.txt 2>/dev/null | grep -q "test content"; then
    log_pass "Workspace mount works"
  else
    log_fail "Workspace mount failed"
  fi

  # Test 8: Can write to workspace
  log_test "Workspace writability..."
  if ${pkgs.podman}/bin/podman run --rm \
      --userns=keep-id \
      --read-only \
      --cap-drop=ALL \
      --security-opt=no-new-privileges \
      --tmpfs=/tmp:rw,exec \
      --tmpfs=/home/developer/.cache:rw \
      --tmpfs=/home/developer/.claude:rw \
      -v /nix/store:/nix/store:ro \
      -v "$TEST_DIR:/workspace:rw" \
      llm-devcontainer:latest \
      sh -c 'echo "written from container" > /workspace/output.txt' && \
    grep -q "written from container" "$TEST_DIR/output.txt"; then
    log_pass "Workspace is writable"
  else
    log_fail "Cannot write to workspace"
  fi

  # Summary
  echo ""
  echo "═══════════════════════════════════════"
  echo " Results: $PASS passed, $FAIL failed"
  echo "═══════════════════════════════════════"
  echo ""

  if [[ $FAIL -gt 0 ]]; then
    exit 1
  fi
''
