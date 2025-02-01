#!/bin/bash

# Log file
LOGFILE="middleware.log"

# Ollama API endpoint
OLLAMA_API_URL="http://localhost:11434/api/generate"

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $message" >> "$LOGFILE"
}

# Function to display a fancy banner with Figlet
display_banner() {
    if command -v figlet &> /dev/null; then
        figlet "PVK"
    else
        echo "========================================"
        echo "          AI Server Assistant           "
        echo "========================================"
    fi
}

# Function to ask Ollama for a command
ask_ollama() {
    local prompt=$1
    local payload=$(cat <<EOF
{
    "model": "deepseek-r1:latest",
    "prompt": "Generate only a valid Linux command to: $prompt. The command should be related to system monitoring or management. Do not provide explanations or additional text. Only return the command itself.",
    "stream": false
}
EOF
    )

    response=$(curl -s -X POST "$OLLAMA_API_URL" -H "Content-Type: application/json" -d "$payload")
    generated_text=$(echo "$response" | jq -r '.response' | head -n 1 | tr -d '\n')

    if [[ -z "$generated_text" ]]; then
        log_message "WARNING" "Ollama returned an empty command."
        echo "Error: Ollama did not generate a valid command."
        return 1
    fi

    if ! is_command_safe "$generated_text"; then
        log_message "WARNING" "Blocked unsafe command from AI: $generated_text"
        echo "Error: Command is not allowed."
        return 1
    fi

    echo "$generated_text"
}

# Function to check if a command is safe
is_command_safe() {
    local command=$1
    local safe_keywords=("cpu" "memory" "disk" "ps" "df" "systemctl" "top" "free" "du" "kill" "renice" "htop" "uptime" "vmstat" "iostat" "sensors" "netstat" "ip" "ss")

    for keyword in "${safe_keywords[@]}"; do
        if [[ "$command" == *"$keyword"* ]]; then
            return 0
        fi
    done

    return 1
}

# Function to execute a command
execute_command() {
    local command=$1

    if ! is_command_safe "$command"; then
        log_message "WARNING" "Blocked unsafe command: $command"
        echo "Error: Command is not allowed."
        return 1
    fi

    read -p "Are you sure you want to run this command? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Command execution cancelled."
        return 1
    fi

    log_message "INFO" "Executing command: $command"
    output=$(eval "$command" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "$output"
    else
        log_message "ERROR" "Command failed: $output"
        echo "Error: $output"
    fi
}

# Function to monitor system resources
monitor_system() {
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    memory_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    disk_usage=$(df / | grep / | awk '{print $5}' | sed 's/%//g')
    network_usage=$(ip -s link show eth0 | awk '/RX:|TX:/ {getline; print $1, $2}')
    temperature=$(sensors | grep 'Core 0' | awk '{print $3}')

    echo "CPU Usage: $cpu_usage%"
    echo "Memory Usage: $memory_usage%"
    echo "Disk Usage: $disk_usage%"
    echo "Network Usage: $network_usage"
    echo "CPU Temperature: $temperature"

    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        echo "Alert: CPU usage is high. Consider closing some processes."
    fi
    if (( $(echo "$memory_usage > 90" | bc -l) )); then
        echo "Alert: Memory usage is high. Free up RAM."
    fi
    if (( $(echo "$disk_usage > 90" | bc -l) )); then
        echo "Alert: Disk usage is high. Clean up disk space."
    fi
}

# Main function
main() {
    display_banner
    echo "AI-Driven Server Management Assistant"
    echo "Type 'exit' to quit."

    while true; do
        read -r -p "Enter your command: " user_input
        if [[ "$user_input" == "exit" ]]; then
            echo "Exiting..."
            break
        fi

        generated_command=$(ask_ollama "$user_input")

        if [[ "$generated_command" == "Error:"* ]] || [[ -z "$generated_command" ]]; then
            echo "Error: Ollama did not generate a valid command."
            continue
        fi

        echo "Generated Command: $generated_command"
        execute_command "$generated_command"

        echo -e "\nSystem Status:"
        monitor_system
    done
}

# Run the main function
main
