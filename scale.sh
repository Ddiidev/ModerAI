#!/bin/bash

# Script para escalonamento de serviços Docker Swarm
# Uso: ./scale.sh <service> [replicas|--cpu <value> --mem <value>]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para mostrar ajuda
show_help() {
    echo -e "${BLUE}ModerAI Docker Swarm Scaling Script${NC}"
    echo ""
    echo "Uso:"
    echo "  $0 <service> <replicas>                    # Escalonamento horizontal"
    echo "  $0 <service> --cpu <value> --mem <value>   # Escalonamento vertical"
    echo "  $0 <service> <replicas> --cpu <value> --mem <value>  # Ambos"
    echo ""
    echo "Serviços disponíveis:"
    echo "  - backend"
    echo "  - frontend"
    echo ""
    echo "Exemplos:"
    echo "  $0 backend 10                              # Escala backend para 10 réplicas"
    echo "  $0 frontend --cpu 0.5 --mem 512M          # Atualiza recursos do frontend"
    echo "  $0 backend 8 --cpu 1 --mem 1G             # Escala para 8 réplicas e atualiza recursos"
    echo ""
}

# Função para validar se o serviço existe
validate_service() {
    local service=$1
    if [[ "$service" != "backend" && "$service" != "frontend" ]]; then
        echo -e "${RED}Erro: Serviço '$service' não é válido. Use 'backend' ou 'frontend'.${NC}"
        exit 1
    fi
}

# Função para escalonamento horizontal
scale_horizontal() {
    local service=$1
    local replicas=$2
    
    echo -e "${YELLOW}Escalonando $service para $replicas réplicas...${NC}"
    
    if docker service scale "moderai_${service}=${replicas}"; then
        echo -e "${GREEN}✓ Escalonamento horizontal concluído com sucesso!${NC}"
        echo -e "${BLUE}Status atual:${NC}"
        docker service ls --filter name="moderai_${service}"
    else
        echo -e "${RED}✗ Erro no escalonamento horizontal${NC}"
        exit 1
    fi
}

# Função para escalonamento vertical
scale_vertical() {
    local service=$1
    local cpu=$2
    local memory=$3
    
    echo -e "${YELLOW}Atualizando recursos do $service (CPU: $cpu, Memória: $memory)...${NC}"
    
    if docker service update \
        --limit-cpu="$cpu" \
        --limit-memory="$memory" \
        --update-parallelism=1 \
        --update-delay=10s \
        "moderai_${service}"; then
        echo -e "${GREEN}✓ Escalonamento vertical concluído com sucesso!${NC}"
        echo -e "${BLUE}Status atual:${NC}"
        docker service inspect "moderai_${service}" --format='{{.Spec.TaskTemplate.Resources.Limits}}'
    else
        echo -e "${RED}✗ Erro no escalonamento vertical${NC}"
        exit 1
    fi
}

# Função para mostrar status atual
show_status() {
    echo -e "${BLUE}Status atual dos serviços:${NC}"
    docker service ls --filter name="moderai_"
    echo ""
    echo -e "${BLUE}Detalhes das réplicas:${NC}"
    docker service ps moderai_backend moderai_frontend --format "table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}"
}

# Verificar se Docker Swarm está ativo
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo -e "${RED}Erro: Docker Swarm não está ativo. Execute 'docker swarm init' primeiro.${NC}"
    exit 1
fi

# Verificar argumentos
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ "$1" == "status" ]]; then
    show_status
    exit 0
fi

if [[ $# -lt 2 ]]; then
    echo -e "${RED}Erro: Argumentos insuficientes${NC}"
    show_help
    exit 1
fi

# Variáveis
SERVICE=$1
validate_service "$SERVICE"

# Parse dos argumentos
REPLICAS=""
CPU=""
MEMORY=""

shift # Remove o nome do serviço dos argumentos

while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu)
            CPU="$2"
            shift 2
            ;;
        --mem|--memory)
            MEMORY="$2"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                REPLICAS="$1"
                shift
            else
                echo -e "${RED}Erro: Argumento desconhecido '$1'${NC}"
                show_help
                exit 1
            fi
            ;;
    esac
done

# Validações
if [[ -n "$CPU" && -z "$MEMORY" ]] || [[ -z "$CPU" && -n "$MEMORY" ]]; then
    echo -e "${RED}Erro: Para escalonamento vertical, você deve especificar tanto --cpu quanto --mem${NC}"
    exit 1
fi

if [[ -z "$REPLICAS" && -z "$CPU" ]]; then
    echo -e "${RED}Erro: Você deve especificar pelo menos o número de réplicas ou recursos (--cpu e --mem)${NC}"
    show_help
    exit 1
fi

# Executar escalonamento
echo -e "${BLUE}Iniciando escalonamento do serviço: $SERVICE${NC}"
echo ""

if [[ -n "$REPLICAS" ]]; then
    scale_horizontal "$SERVICE" "$REPLICAS"
fi

if [[ -n "$CPU" && -n "$MEMORY" ]]; then
    scale_vertical "$SERVICE" "$CPU" "$MEMORY"
fi

echo ""
echo -e "${GREEN}✓ Operação concluída com sucesso!${NC}"
echo ""
show_status