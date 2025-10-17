#!/bin/bash

# ABOUTME: Convenient script to run Flutter Embedded Nostr Relay performance benchmarks
# ABOUTME: Supports various configurations and report generation options

set -e

# Default values
EVENTS=100000
CATEGORY="all"
REPORT="summary"
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    echo -e "${1}${2}${NC}"
}

# Function to show usage
show_usage() {
    echo "Flutter Embedded Nostr Relay Benchmark Runner"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -e, --events N       Number of events for testing (default: 100000)"
    echo "  -c, --category CAT   Benchmark category to run (default: all)"
    echo "                       Options: database, insertion, query, memory,"
    echo "                               concurrent, subscription, gc, all"
    echo "  -r, --report LEVEL   Report detail level (default: summary)"
    echo "                       Options: summary, detailed, full"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run all benchmarks with defaults"
    echo "  $0 -e 50000 -c database             # Test database with 50K events"
    echo "  $0 -r detailed -v                   # Detailed report with verbose output"
    echo "  $0 -e 200000 -c all -r full         # Full test with 200K events"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--events)
            EVENTS="$2"
            shift 2
            ;;
        -c|--category)
            CATEGORY="$2"
            shift 2
            ;;
        -r|--report)
            REPORT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate inputs
if ! [[ "$EVENTS" =~ ^[0-9]+$ ]] || [ "$EVENTS" -lt 1000 ]; then
    print_color $RED "Error: Events must be a number >= 1000"
    exit 1
fi

if [[ ! "$CATEGORY" =~ ^(database|insertion|query|memory|concurrent|subscription|gc|all)$ ]]; then
    print_color $RED "Error: Invalid category '$CATEGORY'"
    show_usage
    exit 1
fi

if [[ ! "$REPORT" =~ ^(summary|detailed|full)$ ]]; then
    print_color $RED "Error: Invalid report level '$REPORT'"
    show_usage
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "test/benchmarks/benchmark_runner.dart" ]; then
    print_color $RED "Error: Must be run from the flutter_embedded_nostr_relay root directory"
    exit 1
fi

# Print configuration
print_color $BLUE "🚀 Flutter Embedded Nostr Relay Benchmarks"
echo "════════════════════════════════════════════"
print_color $YELLOW "Configuration:"
echo "  Events:    $EVENTS"
echo "  Category:  $CATEGORY"
echo "  Report:    $REPORT"
echo "  Verbose:   $VERBOSE"
echo ""

# Check for required dependencies
print_color $BLUE "🔍 Checking dependencies..."

if ! command -v dart &> /dev/null; then
    print_color $RED "Error: Dart SDK not found. Please install Dart SDK."
    exit 1
fi

# Ensure dependencies are installed
print_color $BLUE "📦 Installing dependencies..."
dart pub get

# Create reports directory if it doesn't exist
mkdir -p test/benchmarks/reports

# Build arguments
ARGS="--events=$EVENTS --category=$CATEGORY --report=$REPORT"
if [ "$VERBOSE" = true ]; then
    ARGS="$ARGS --verbose"
fi

print_color $BLUE "🏃 Running benchmarks..."
echo "Command: dart test/benchmarks/benchmark_runner.dart $ARGS"
echo ""

# Run the benchmarks
if dart test/benchmarks/benchmark_runner.dart $ARGS; then
    print_color $GREEN "✅ Benchmarks completed successfully!"
    
    # Show report locations
    echo ""
    print_color $BLUE "📊 Reports generated:"
    echo "  Latest Results: test/benchmarks/reports/latest_results.json"
    echo "  Latest Summary: test/benchmarks/reports/latest_summary.md"
    
    if [[ "$REPORT" == "detailed" || "$REPORT" == "full" ]]; then
        echo "  Latest Report:  test/benchmarks/reports/latest_report.html"
    fi
    
    # Show quick summary
    if [ -f "test/benchmarks/reports/latest_summary.md" ]; then
        echo ""
        print_color $BLUE "📈 Quick Summary:"
        grep -E "^\*\*Status\*\*|^\*\*Total Benchmarks\*\*|^\*\*Successful\*\*|Failed\*\*" test/benchmarks/reports/latest_summary.md | head -4 || true
    fi
    
else
    print_color $RED "❌ Benchmarks failed. Check the output above for details."
    exit 1
fi

# Performance targets check
print_color $BLUE "🎯 Performance Target Check:"
if grep -q "✅ PASSED" test/benchmarks/reports/latest_summary.md 2>/dev/null; then
    print_color $GREEN "  Overall Status: PASSED"
else
    print_color $YELLOW "  Overall Status: Some targets not met"
fi

# Memory efficiency check
if grep -q "Memory Efficiency.*Excellent\|Good" test/benchmarks/reports/latest_summary.md 2>/dev/null; then
    print_color $GREEN "  Memory Usage: Efficient"
else
    print_color $YELLOW "  Memory Usage: Review recommended"
fi

echo ""
print_color $BLUE "🔗 Next Steps:"
echo "  1. Review the generated reports"
echo "  2. Address any failed benchmarks"
echo "  3. Monitor performance in production"
echo "  4. Run benchmarks regularly to detect regressions"
echo ""

print_color $GREEN "Benchmark run completed! 🎉"