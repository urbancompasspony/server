/srv/
├── system.yaml          # Configuração do host (já existe)
├── containers.yaml      # Registry de containers (já existe)
├── backup/
│   ├── manifest.yaml    # Metadados do backup
│   ├── configs/         # Configurações do sistema
│   ├── containers/      # Dados dos containers
│   └── system/          # Configs do OS
└── scripts/
    ├── backup-full.sh   # Backup completo
    └── restore-full.sh  # Restore completo
