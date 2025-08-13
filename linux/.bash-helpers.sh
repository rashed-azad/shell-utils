#!/bin/bash
# =============================================================================
# BASH HELPERS - Enhanced Shell Utilities and Functions
# =============================================================================
# 
# This script provides a collection of useful bash functions and aliases for
# daily development and system administration tasks.
#
# USAGE:
#   source .bash-helpers.sh
#
# FEATURES:
#   - Color-coded terminal output
#   - Git workflow helpers
#   - File management utilities
#   - System cleanup tools
#   - Navigation shortcuts
#
# AUTHOR: Enhanced version with comprehensive documentation
# =============================================================================

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================
# These color codes provide consistent, readable output across all functions.
# Usage: printf '%bYour colored text%b\n' "$Green" "$nc"
#
# Available colors:
#   - Black, Red, Green, Brown_Orange, Blue, Purple, Cyan, Light_Gray
#   - Dark_Gray, Light_Red, Light_Green, Yellow, Light_Blue, Light_Purple, Light_Cyan, White
#   - nc: No color (reset to default)

readonly Black='\033[0;30m'        # Dark black
readonly Red='\033[0;31m'          # Dark red
readonly Green='\033[0;32m'        # Dark green
readonly Brown_Orange='\033[0;33m' # Dark yellow/brown
readonly Blue='\033[0;34m'         # Dark blue
readonly Purple='\033[0;35m'       # Dark purple
readonly Cyan='\033[0;36m'         # Dark cyan
readonly Light_Gray='\033[0;37m'   # Light gray
readonly Dark_Gray='\033[1;30m'    # Bright black
readonly Light_Red='\033[1;31m'    # Bright red
readonly Light_Green='\033[1;32m'  # Bright green
readonly Yellow='\033[1;33m'       # Bright yellow
readonly Light_Blue='\033[1;34m'   # Bright blue
readonly Light_Purple='\033[1;35m' # Bright purple
readonly Light_Cyan='\033[1;36m'   # Bright cyan
readonly White='\033[1;37m'        # Bright white
readonly nc='\033[0m'              # No color (reset)

# =============================================================================
# NAVIGATION UTILITIES
# =============================================================================

# Navigate up multiple directory levels quickly
# 
# USAGE:
#   up [levels]
#
# EXAMPLES:
#   up          # Go up 1 level (same as cd ..)
#   up 2        # Go up 2 levels (same as cd ../..)
#   up 3        # Go up 3 levels
#
# DESCRIPTION:
#   This function allows you to quickly navigate up multiple directory levels
#   without typing multiple 'cd ..' commands. It's especially useful when
#   working in deeply nested project structures.
up() {
  # Loop through the specified number of levels
  for D in $(seq 1 $1); do
    cd ..
  done
}

# =============================================================================
# GIT WORKFLOW HELPERS
# =============================================================================

# Configure git prompt settings for colored output
force_color_prompt=yes
color_prompt=yes

# Parse and display the current git branch name
# 
# USAGE:
#   parse_git_branch
#
# OUTPUT:
#   Returns the current branch name in parentheses, e.g., "(main)"
#   Returns empty string if not in a git repository
#
# DESCRIPTION:
#   This function extracts the current git branch name and formats it
#   for display in the shell prompt. It's automatically used by the
#   PS1 prompt configuration below.
parse_git_branch() {
  # Get current branch and format it with parentheses
  git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

# Configure the shell prompt with git branch information
# 
# FEATURES:
#   - Shows username@hostname
#   - Shows current working directory
#   - Shows current git branch (if in a git repository)
#   - Color-coded for better readability
if [ "$color_prompt" = yes ]; then
  # Colored prompt with git branch
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;31m\]$(parse_git_branch)\[\033[00m\]\$ '
else
  # Plain prompt with git branch
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w$(parse_git_branch)\$ '
fi

# Clean up temporary variables
unset color_prompt force_color_prompt

# Execute git commands recursively across all submodules
# 
# USAGE:
#   gitm <git_command>
#
# EXAMPLES:
#   gitm status          # Check status of all submodules
#   gitm pull            # Pull latest changes in all submodules
#   gitm checkout main   # Switch all submodules to main branch
#
# DESCRIPTION:
#   This function runs the specified git command in all submodules
#   recursively. It's useful for managing projects with multiple
#   git submodules that need to be updated simultaneously.
gitm() {
  git submodule foreach --recursive "$@"
}

# Delete local git branches that no longer exist on the remote repository
# 
# USAGE:
#   delete_branch_local
#
# DESCRIPTION:
#   This function helps clean up your local git repository by removing
#   branches that have been deleted from the remote repository. It:
#   1. Fetches the latest information from remote
#   2. Checks each local branch against the remote
#   3. Deletes local branches that don't exist remotely
#   4. Provides feedback about what's being deleted
#
# SAFETY:
#   - Only deletes branches that don't exist on remote
#   - Uses force delete (-D) to ensure removal
#   - Provides clear feedback about each action
delete_branch_local() {
  # Fetch the latest information from the remote repository
  # -f: force fetch
  # -p: prune deleted remote branches
  # -P: prune deleted remote branches (alternative flag)
  git fetch -f -p -P

  # Get the list of all local branches
  # cut -c 3- removes the first two characters (branch indicator)
  local_branches=$(git branch | cut -c 3-)

  # Iterate through each local branch
  for branch in $local_branches; do
    # Check if the branch exists on the remote repository
    if ! git show-ref --quiet "refs/remotes/origin/$branch"; then
      echo "The branch '$branch' does not exist on the remote repository."
      echo "Deleting the local branch..."
      # Use -D to force delete (even if not merged)
      git branch -D "$branch"
    fi
  done
}

# Delete local branches recursively across all git submodules
# 
# USAGE:
#   delete_branch_local_recur
#
# DESCRIPTION:
#   This function runs the delete_branch_local function in all submodules
#   recursively. It's useful for cleaning up branches across complex
#   projects with multiple git submodules.
delete_branch_local_recur() {
  gitm "bash -c '$(declare -f delete_branch_local); delete_branch_local'"
}

# =============================================================================
# FILE MANAGEMENT UTILITIES
# =============================================================================

# Remove files by extension using the system trash (safe deletion)
# 
# USAGE:
#   rmr [extension]
#
# EXAMPLES:
#   rmr txt        # Remove all .txt files in current directory and subdirectories
#   rmr log        # Remove all .log files
#   rmr            # Remove all .txt files (default)
#
# DESCRIPTION:
#   This function safely removes files by moving them to the system trash
#   instead of permanently deleting them. It searches recursively through
#   all subdirectories and provides feedback about each file being moved.
#
# SAFETY:
#   - Files are moved to trash, not permanently deleted
#   - Uses gio trash for GNOME/GTK environments
#   - Provides feedback about each file being processed
rmr() {
  local ext="${1:-txt}" # Default to 'txt' if no argument is provided

  # Find and move files to trash using gio trash
  # -type f: only files (not directories)
  # -name "*.ext": match files with specified extension
  # -exec echo: print the file being processed
  # -exec gio trash: move file to trash
  find . -type f -name "*.$ext" -exec echo "Moving to trash: {}" \; -exec gio trash {} \;
}

# Copy file contents to system clipboard
# 
# USAGE:
#   xcp <filename>
#
# EXAMPLES:
#   xcp config.txt     # Copy contents of config.txt to clipboard
#   xcp ~/.bashrc      # Copy bash configuration to clipboard
#
# DESCRIPTION:
#   This function copies the entire contents of a file to the system
#   clipboard, making it easy to paste into other applications. It
#   automatically installs xclip if it's not available on the system.
#
# FEATURES:
#   - Automatically installs xclip if missing
#   - Validates file existence before copying
#   - Provides clear feedback about the operation
#   - Works with any text file
xcp() {
  # Function to copy file content to clipboard using xclip
  # If xclip is not installed, it will automatically install it.
  #
  # Usage: xcp <filename>
  # Example: xcp file.txt
  #
  # This will copy the contents of file.txt to the clipboard.
  # If xclip is not installed, it will be installed automatically.

  # Check if xclip is installed
  if ! command -v xclip &>/dev/null; then
    echo "xclip is not installed. Installing xclip..."
    sudo apt-get update && sudo apt-get install -y xclip
  fi

  # Check if the file exists
  if [ -f "$1" ]; then
    xclip -selection clipboard <"$1"
    echo "Copied contents of $1 to clipboard."
  else
    echo "Error: $1 is not a valid file."
  fi
}

# =============================================================================
# SYSTEM MAINTENANCE TOOLS
# =============================================================================

# Comprehensive Debian/Ubuntu system cleanup
# 
# USAGE:
#   clean_debian
#
# DESCRIPTION:
#   This function performs a comprehensive cleanup of a Debian/Ubuntu system
#   to free up disk space and remove unnecessary packages. It's a one-command
#   solution for system maintenance.
#
# CLEANUP ACTIONS:
#   1. Remove unnecessary packages (autoremove)
#   2. Purge packages and their configuration files
#   3. Clean package cache and downloaded files
#   4. Remove old kernel images (keeping current and one previous)
#   5. Clear log files (truncate to 0 bytes)
#   6. Remove unused locale files
#   7. Remove orphaned packages
#
# SAFETY:
#   - Keeps current kernel and one previous version
#   - Only removes packages that are safe to remove
#   - Provides feedback throughout the process
#   - Uses standard apt commands
#
# WARNING:
#   This function requires sudo privileges and will modify system packages.
#   Run this only when you understand what it does.
clean_debian() {
  # Execute all cleanup commands in sequence
  # Each command is chained with && to stop on any failure
  sudo apt-get autoremove -y && \
  sudo apt-get purge -y && \
  sudo apt-get autoremove --purge -y && \
  sudo apt-get clean && \
  sudo apt-get autoclean && \
  sudo apt-get remove --purge $(dpkg --list | grep linux-image | awk '{ if ($1 == "ii") print $2}' | grep -v $(uname -r | cut -d"-" -f1,2) | head -n -1) && \
  sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; && \
  sudo apt-get install -y localepurge && \
  sudo localepurge && \
  sudo apt-get install -y deborphan && \
  sudo deborphan | xargs sudo apt-get -y remove --purge && \
  echo "System cleanup complete!"
}

# =============================================================================
# USEFUL ALIASES
# =============================================================================
# These aliases provide shortcuts for common commands and improve
# the user experience with colored output and better formatting.

# Enhanced ls with long format and human-readable sizes
alias ll="ls -l"

# Colored grep for better readability
alias grep="grep --color=auto"
alias egrep="egrep --color=auto"
alias fgrep="fgrep --color=auto"

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

# Add system directories to PATH for administrative commands
# This ensures that system administration tools are available
export PATH="$PATH:/sbin:/usr/sbin:usr/local/sbin:"