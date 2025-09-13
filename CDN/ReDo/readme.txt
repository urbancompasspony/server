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

linite_backup_20250913_143000.tar.gz
├── manifest.yaml          # Metadados completos
├── configs/              
│   ├── system.yaml       # Config do host
│   └── containers.yaml   # Registry containers
├── system/               
│   ├── etc/             # Configs do OS
│   └── packages.list    # Pacotes instalados
├── containers/          
│   ├── container1.tar.gz        # Export do container
│   ├── container1_volumes.tar.gz # Volumes
│   └── macvlan-network.json     # Config de rede
└── restore.sh           # Script auto-contido
