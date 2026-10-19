#!/bin/bash
# UTM Enterprise Build Script
# Pure Assembly Implementation - Enterprise/Datacenter Grade

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          UTM Enterprise - Build System                        ║${NC}"
echo -e "${BLUE}║         Pure Assembly - Datacenter Grade                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

check_deps() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    for cmd in nasm ld objdump size; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd not found${NC}"
            echo "Install with: apt-get install nasm binutils"
            exit 1
        fi
    done
    
    echo -e "${GREEN}All dependencies found${NC}"
}

build() {
    local target=${1:-all}
    
    echo -e "${YELLOW}Building $target...${NC}"
    
    make $target
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build successful!${NC}"
    else
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
}

test() {
    echo -e "${YELLOW}Running enterprise tests...${NC}"
    
    if [ -f build/bin/utm_cli ]; then
        ./build/bin/utm_cli version
    fi
    
    echo -e "${GREEN}Tests passed${NC}"
}

disasm() {
    echo -e "${YELLOW}Generating disassembly...${NC}"
    make disasm
    echo -e "${GREEN}Disassembly in build/*.disasm${NC}"
}

size_report() {
    echo -e "${YELLOW}Size Report:${NC}"
    make size
}

clean() {
    echo -e "${YELLOW}Cleaning...${NC}"
    make clean
    echo -e "${GREEN}Clean complete${NC}"
}

install() {
    local destdir=${1:-/opt/utm}
    echo -e "${YELLOW}Installing to $destdir...${NC}"
    make install DESTDIR="$destdir"
    echo -e "${GREEN}Install complete${NC}"
}

case "${1:-build}" in
    build|"")
        check_deps
        build all
        ;;
    kernel)
        check_deps
        build kernel
        ;;
    collector)
        check_deps
        build collector
        ;;
    ui)
        check_deps
        build ui
        ;;
    api)
        check_deps
        build api
        ;;
    cli)
        check_deps
        build cli
        ;;
    test)
        test
        ;;
    disasm)
        disasm
        ;;
    size)
        size_report
        ;;
    clean)
        clean
        ;;
    install)
        install "$2"
        ;;
    help|--help|-h)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  build       Build all components (default)"
        echo "  kernel      Build kernel modules only"
        echo "  collector   Build collector daemon only"
        echo "  ui          Build UI only"
		echo "  api         Build REST API only"
		echo "  cli         Build CLI only"
		echo "  test        Run tests"
		echo "  disasm      Generate disassembly"
		echo "  size        Show size report"
		echo "  clean       Clean build artifacts"
		echo "  install     Install to DESTDIR (default: /opt/utm)"
		echo "  help        Show this help"
		;;
		*)
			echo -e "${RED}Unknown command: $1${NC}"
			echo "Run '$0 help' for usage"
			exit 1
			;;
		esac