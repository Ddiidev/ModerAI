#!/bin/bash

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Função de ajuda
show_help() {
    echo "Uso: $0 <comando> [opções]"
    echo "Comandos:"
    echo "  build                         # Constrói todas as imagens Docker"
    echo "  deploy                        # Faz deploy da stack completa"
    echo "  redeploy                      # Reconstrói imagens e faz redeploy"
    echo "  status                        # Mostra o status dos serviços"

    echo "  <serviço> [réplicas] [opções] # Escala um serviço específico"
    echo ""
    echo "Exemplos de escalonamento:"
    echo "  $0 backend 10                 # Escala o serviço 'backend' para 10 réplicas"
    echo "  $0 frontend --cpu 0.5 --mem 512M # Atualiza os recursos do serviço 'frontend'"
    echo ""
    echo "Exemplos de deploy:"
    echo "  $0 build                      # Constrói as imagens"
    echo "  $0 deploy                     # Faz deploy da stack"
    echo "  $0 redeploy                   # Reconstrói e faz redeploy"
    echo ""
    echo "Serviços disponíveis: backend, frontend"
}

# Função para validar o nome do serviço
validate_service() {
    local service_name=$1
    if [[ "$service_name" != "backend" && "$service_name" != "frontend" ]]; then
        echo -e "${RED}Erro: Serviço '$service_name' desconhecido. Use 'backend' ou 'frontend'.${NC}"
        show_help
        exit 1
    fi
}

# Função para construir as imagens
build_images() {
    echo -e "${YELLOW}Construindo imagens Docker...${NC}"
    
    echo -e "${YELLOW}Construindo imagem do backend...${NC}"
    if docker build -t moderai-backend:latest ./ModerAIAPI; then
        echo -e "${GREEN}✓ Imagem do backend construída com sucesso${NC}"
    else
        echo -e "${RED}✗ Erro ao construir imagem do backend${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Construindo imagem do frontend...${NC}"
    if docker build -t moderai-frontend:latest ./ModerAI-Web-v2; then
        echo -e "${GREEN}✓ Imagem do frontend construída com sucesso${NC}"
    else
        echo -e "${RED}✗ Erro ao construir imagem do frontend${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Todas as imagens foram construídas com sucesso!${NC}"
}

# Função para fazer deploy da stack
deploy_stack() {
    echo -e "${YELLOW}Fazendo deploy da stack ModerAI...${NC}"
    
    ensure_swarm_active
    
    if docker stack deploy -c stack.yml moderai; then
        echo -e "${GREEN}✓ Stack implantada com sucesso!${NC}"
        echo -e "${YELLOW}Aguardando serviços ficarem prontos...${NC}"
        sleep 10
        show_status
    else
        echo -e "${RED}✗ Erro ao implantar a stack${NC}"
        return 1
    fi
}

# Função para fazer redeploy completo
redeploy_stack() {
    echo -e "${YELLOW}Fazendo redeploy completo...${NC}"
    
    # Construir imagens
    if ! build_images; then
        echo -e "${RED}Erro durante a construção das imagens. Abortando redeploy.${NC}"
        return 1
    fi
    
    # Fazer deploy
    deploy_stack
}

# Função para mostrar o status dos serviços
show_status() {
    echo -e "${GREEN}Status dos serviços Docker Swarm:${NC}"
    docker service ls --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}\t{{.Ports}}"
    echo -e "\n${GREEN}Detalhes das tarefas dos serviços:${NC}"
    docker service ps moderai_backend moderai_frontend --format "table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}" 2>/dev/null || echo "Nenhum serviço encontrado. Execute '$0 deploy' primeiro."
}

# Função para verificar e inicializar o Swarm se necessário
ensure_swarm_active() {
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo -e "${YELLOW}Docker Swarm não está ativo. Inicializando...${NC}"
        if docker swarm init; then
            echo -e "${GREEN}✓ Docker Swarm inicializado com sucesso!${NC}"
        else
            echo -e "${RED}✗ Erro ao inicializar o Docker Swarm${NC}"
            exit 1
        fi
    fi
}


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

if [[ "$1" == "build" ]]; then
    build_images
    exit $?
fi

if [[ "$1" == "deploy" ]]; then
    deploy_stack
    exit $?
fi

if [[ "$1" == "redeploy" ]]; then
    redeploy_stack
    exit $?
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
    echo -e "${RED}Erro: Ao definir CPU ou memória, ambos devem ser especificados.${NC}"
    show_help
    exit 1
fi

# Construir o comando de atualização
UPDATE_COMMAND="docker service update --with-registry-auth"

if [[ -n "$REPLICAS" ]]; then
    UPDATE_COMMAND="$UPDATE_COMMAND --replicas $REPLICAS"
    echo -e "${YELLOW}Escalando $SERVICE para $REPLICAS réplicas...${NC}"
fi

if [[ -n "$CPU" ]]; then
    UPDATE_COMMAND="$UPDATE_COMMAND --limit-cpu $CPU --reserve-cpu $CPU"
    echo -e "${YELLOW}Atualizando limites de CPU para $SERVICE: $CPU${NC}"
fi

if [[ -n "$MEMORY" ]]; then
    UPDATE_COMMAND="$UPDATE_COMMAND --limit-memory $MEMORY --reserve-memory $MEMORY"
    echo -e "${YELLOW}Atualizando limites de memória para $SERVICE: $MEMORY${NC}"
fi

UPDATE_COMMAND="$UPDATE_COMMAND moderai_$SERVICE"

# Executar o comando
eval $UPDATE_COMMAND

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Comando executado com sucesso!${NC}"
    show_status
else
    echo -e "${RED}Erro ao executar o comando Docker Swarm.${NC}"
fi