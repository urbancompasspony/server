        // Configurações
        const CGI_URL = '/cgi-bin/system-diagnostic.cgi';
        const WEB_PORT = '1298'; // Adicionar esta linha

        // Elementos DOM
        let currentTest = null;
        let diagnosticResults = {};

        // Inicialização
        document.addEventListener('DOMContentLoaded', function() {
            loadSystemInfo();
        });

        // Executar diagnóstico completo
        // SOLUÇÃO OTIMIZADA: Progresso com timing inteligente

async function runFullDiagnostic() {
    showLoading('Executando diagnóstico completo do sistema...');
    
    // Progresso OTIMIZADO - mais lento no início, acelera no meio, para no final
    const progressSteps = [
        { percent: 0, message: 'Iniciando diagnóstico do sistema...', delay: 500 },
        { percent: 5, message: 'Verificando consistência do armazenamento...', delay: 2000 },
        { percent: 15, message: 'Analisando integridade dos sistemas de arquivos...', delay: 2500 },
        { percent: 25, message: 'Verificando dispositivos SMART...', delay: 2000 },
        { percent: 35, message: 'Testando servidores DNS (8 servidores)...', delay: 3000 },
        { percent: 50, message: 'Verificando interfaces de rede...', delay: 1500 },
        { percent: 60, message: 'Analisando serviços críticos do sistema...', delay: 2000 },
        { percent: 70, message: 'Verificando Docker e containers...', delay: 1500 },
        { percent: 80, message: 'Analisando carga, memória e processos...', delay: 1000 },
        { percent: 85, message: 'Coletando logs de erro do sistema...', delay: 500 }
        // NÃO incluir 90%+ aqui - será controlado pela resposta real
    ];

    let currentStep = 0;
    let progressCompleted = false;
    showProgress(progressSteps[0].percent, progressSteps[0].message);

    // Função para avançar progresso de forma inteligente
    function advanceProgress() {
        if (progressCompleted || currentStep >= progressSteps.length) return;
        
        currentStep++;
        if (currentStep < progressSteps.length) {
            const step = progressSteps[currentStep];
            showProgress(step.percent, step.message);
            
            // Agendar próximo avanço com delay variável
            setTimeout(advanceProgress, step.delay);
        }
    }

    // Iniciar progresso
    setTimeout(advanceProgress, progressSteps[0].delay);

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
                action: 'full-diagnostic'
            })
        });

        // AQUI É O SEGREDO: Quando a resposta chegar, acelerar para 100%
        progressCompleted = true;
        const endTime = Date.now();
        const duration = Math.round((endTime - startTime) / 1000);
        
        // Finalizar rapidamente quando a resposta chegar
        showProgress(90, 'Processando resultados...');
        await sleep(300);
        showProgress(95, 'Analisando dados coletados...');
        await sleep(200);
        showProgress(100, `Diagnóstico concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        // Aguardar só um pouquinho para mostrar 100%
        setTimeout(() => {
            processResults(data, 'Diagnóstico Completo');
        }, 600);

    } catch (error) {
        progressCompleted = true;
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar diagnóstico: ' + error.message, 'error');
    }
}

// Função auxiliar para sleep
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// Versão alternativa: Progresso adaptativo baseado no tempo real
async function runFullDiagnosticAdaptive() {
    showLoading('Executando diagnóstico completo do sistema...');
    
    const progressMessages = [
        'Iniciando diagnóstico do sistema...',
        'Verificando consistência do armazenamento...',
        'Analisando integridade dos sistemas de arquivos...',
        'Verificando dispositivos SMART...',
        'Testando conectividade DNS...',
        'Verificando interfaces de rede...',
        'Analisando serviços críticos...',
        'Verificando Docker e containers...',
        'Analisando sistema e processos...',
        'Coletando logs de erro...'
    ];

    let currentStep = 0;
    let isCompleted = false;
    showProgress(0, progressMessages[0]);

    // Progresso baseado no tempo estimado (15-20 segundos total)
    const progressTimer = setInterval(() => {
        if (isCompleted) return;
        
        currentStep++;
        const progressPercent = Math.min(85, (currentStep / progressMessages.length) * 85);
        const messageIndex = Math.min(currentStep - 1, progressMessages.length - 1);
        
        showProgress(progressPercent, progressMessages[messageIndex]);
        
        // Parar em 85% e aguardar resposta
        if (progressPercent >= 85) {
            clearInterval(progressTimer);
        }
    }, 1800); // A cada 1.8 segundos

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
                action: 'full-diagnostic'
            })
        });

        // Finalizar progresso quando resposta chegar
        isCompleted = true;
        clearInterval(progressTimer);
        
        const duration = Math.round((Date.now() - startTime) / 1000);
        
        // Finalização rápida
        showProgress(90, 'Processando resultados...');
        await sleep(200);
        showProgress(100, `Concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        setTimeout(() => {
            processResults(data, 'Diagnóstico Completo');
        }, 500);

    } catch (error) {
        isCompleted = true;
        clearInterval(progressTimer);
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar diagnóstico: ' + error.message, 'error');
    }
}

// Versão para testes específicos também otimizada
async function runSpecificTest(testType) {
    const testConfigs = {
        'storage': {
            name: 'Teste de Armazenamento',
            steps: [
                { percent: 0, message: 'Iniciando teste de armazenamento...', delay: 500 },
                { percent: 20, message: 'Verificando montagens do fstab...', delay: 1500 },
                { percent: 40, message: 'Analisando dispositivos SMART...', delay: 2000 },
                { percent: 60, message: 'Verificando uso de disco...', delay: 1500 },
                { percent: 80, message: 'Verificando inodes...', delay: 1000 }
            ]
        },
        'network': {
            name: 'Teste de Rede',
            steps: [
                { percent: 0, message: 'Iniciando teste de rede...', delay: 500 },
                { percent: 30, message: 'Testando 8 servidores DNS...', delay: 3000 },
                { percent: 70, message: 'Verificando interfaces...', delay: 1500 },
                { percent: 85, message: 'Verificando resolução DNS...', delay: 1000 }
            ]
        },
        'services': {
            name: 'Teste de Serviços',
            steps: [
                { percent: 0, message: 'Iniciando teste de serviços...', delay: 500 },
                { percent: 25, message: 'Verificando serviços críticos...', delay: 1500 },
                { percent: 50, message: 'Analisando Docker...', delay: 2000 },
                { percent: 75, message: 'Verificando LibVirt...', delay: 1000 }
            ]
        },
        'system': {
            name: 'Teste de Sistema',
            steps: [
                { percent: 0, message: 'Iniciando análise do sistema...', delay: 500 },
                { percent: 30, message: 'Verificando carga e memória...', delay: 1000 },
                { percent: 60, message: 'Analisando processos zumbi...', delay: 1000 },
                { percent: 85, message: 'Coletando logs de erro...', delay: 1500 }
            ]
        }
    };

    const config = testConfigs[testType] || {
        name: 'Teste Específico',
        steps: [
            { percent: 0, message: 'Iniciando teste...', delay: 500 },
            { percent: 50, message: 'Executando...', delay: 2000 },
            { percent: 80, message: 'Finalizando...', delay: 1000 }
        ]
    };

    showLoading(`Executando ${config.name.toLowerCase()}...`);
    
    let currentStep = 0;
    let isCompleted = false;
    showProgress(config.steps[0].percent, config.steps[0].message);

    function advanceStep() {
        if (isCompleted || currentStep >= config.steps.length) return;
        
        currentStep++;
        if (currentStep < config.steps.length) {
            const step = config.steps[currentStep];
            showProgress(step.percent, step.message);
            setTimeout(advanceStep, step.delay);
        }
    }

    setTimeout(advanceStep, config.steps[0].delay);

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
                action: 'specific-test',
                test: testType
            })
        });

        isCompleted = true;
        const duration = Math.round((Date.now() - startTime) / 1000);
        
        showProgress(95, 'Processando resultados...');
        await sleep(200);
        showProgress(100, `${config.name} concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        setTimeout(() => {
            processResults(data, config.name);
        }, 400);

    } catch (error) {
        isCompleted = true;
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar teste: ' + error.message, 'error');
    }
}

function simulateProgressWithSteps(steps) {
    let currentStep = 0;
    showProgress(steps[0].percent, steps[0].step);
    
    return setInterval(() => {
        currentStep++;
        if (currentStep < steps.length) {
            showProgress(steps[currentStep].percent, steps[currentStep].step);
        }
    }, 2000); // Muda a cada 2 segundos
}

        // Executar teste específico
        async function runSpecificTest(testType) {
            const testNames = {
                'storage': 'Teste de Armazenamento',
                'network': 'Teste de Rede',
                'services': 'Teste de Serviços',
                'system': 'Teste de Sistema'
            };

            const testName = testNames[testType] || 'Teste Específico';
            showLoading(`Executando ${testName.toLowerCase()}...`);
            showProgress(0, `Iniciando ${testName.toLowerCase()}...`);

            try {
                const response = await fetch(CGI_URL, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                        action: 'specific-test',
                        test: testType
                    })
                });

                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }

                const data = await response.text();
                processResults(data, testName);

            } catch (error) {
                hideLoading();
                hideProgress();
                showAlert('Erro ao executar teste: ' + error.message, 'error');
            }
        }

        // Processar resultados
        function processResults(data, testName) {
            hideLoading();
            hideProgress();

            // Tentar parsear como JSON primeiro
            let results;
            try {
                results = JSON.parse(data);
            } catch (e) {
                // Se não for JSON, tratar como texto simples
                results = { output: data };
            }

            // Analisar os resultados
            const analysis = analyzeResults(results.output || data);

            // Mostrar resultados
            showResults(results.output || data, testName, analysis);

            // Atualizar resumo
            updateSummary(analysis);
        }

        function analyzeResults(output) {
    const analysis = {
        status: 'unknown',
        errors: 0,
        warnings: 0,
        tests: 0,
        sections: []
    };

    if (!output) return analysis;

    // MÉTODO MAIS CONFIÁVEL: Extrair do resumo final
    const errorMatch = output.match(/Erros críticos encontrados: (\d+)/);
    const warningMatch = output.match(/Avisos encontrados: (\d+)/);
    
    if (errorMatch) {
        analysis.errors = parseInt(errorMatch[1]);
    }
    if (warningMatch) {
        analysis.warnings = parseInt(warningMatch[1]);
    }

    // Contar testes
    const testMatches = output.match(/🔍 Teste \d+:/g);
    analysis.tests = testMatches ? testMatches.length : 0;

    // Determinar status
    if (analysis.errors > 0) {
        analysis.status = 'error';
    } else if (analysis.warnings > 0) {
        analysis.status = 'warning';  
    } else {
        analysis.status = 'success';
    }

    return analysis;
}

        // Obter status da seção
        function getSectionStatus(content) {
            if (content.includes('❌') || content.includes('ERRO') || content.includes('CRÍTICO')) {
                return 'error';
            }
            if (content.includes('⚠️') || content.includes('AVISO')) {
                return 'warning';
            }
            return 'success';
        }

        // Mostrar resultados
        function showResults(output, testName, analysis) {
            const container = document.getElementById('result-container');
            const title = document.getElementById('result-title');
            const content = document.getElementById('result-content');

            title.textContent = `${testName} - ${new Date().toLocaleString('pt-BR')}`;
            content.innerHTML = `<pre>${output}</pre>`;

            // Aplicar classe CSS baseada no status
            container.className = `result-container active ${analysis.status}`;

            // Mostrar alerta baseado no status
            if (analysis.status === 'success') {
                showAlert('Diagnóstico concluído com sucesso! Sistema saudável.', 'success');
            } else if (analysis.status === 'warning') {
                showAlert(`Diagnóstico concluído com ${analysis.warnings} aviso(s). Verificar itens mencionados.`, 'warning');
            } else {
                showAlert(`Diagnóstico concluído com ${analysis.errors} erro(s) crítico(s). Ação imediata necessária!`, 'error');
            }
        }

        // Atualizar resumo
        function updateSummary(analysis) {
            const summaryContainer = document.getElementById('result-summary');
            const statusElement = document.getElementById('summary-status');
            const errorsElement = document.getElementById('summary-errors');
            const warningsElement = document.getElementById('summary-warnings');
            const testsElement = document.getElementById('summary-tests');

            // Mostrar resumo
            summaryContainer.style.display = 'block';

            // Atualizar valores
            statusElement.textContent = getStatusText(analysis.status);
            statusElement.className = `summary-value ${analysis.status}`;

            errorsElement.textContent = analysis.errors;
            errorsElement.className = `summary-value ${analysis.errors > 0 ? 'error' : 'success'}`;

            warningsElement.textContent = analysis.warnings;
            warningsElement.className = `summary-value ${analysis.warnings > 0 ? 'warning' : 'success'}`;

            testsElement.textContent = analysis.tests || 'Completo';
            testsElement.className = 'summary-value success';
        }

        // Obter texto do status
        function getStatusText(status) {
            switch (status) {
                case 'success': return '✅ Saudável';
                case 'warning': return '⚠️ Com Avisos';
                case 'error': return '❌ Crítico';
                default: return '❓ Desconhecido';
            }
        }

// Mostrar/ocultar informações do sistema (com timeout e fallback)
        async function showSystemInfo() {
            const infoContainer = document.getElementById('system-info');
            const detailsElement = document.getElementById('system-details');

            // Verificar se está visível
            const computedDisplay = window.getComputedStyle(infoContainer).display;
            const isVisible = computedDisplay === 'block';
            
            if (isVisible) {
                infoContainer.style.display = 'none';
                return;
            }

            // Mostrar container
            infoContainer.style.display = 'block';
            
            // Verificar se já tem conteúdo válido (não é "Carregando..." nem erro)
            const currentContent = detailsElement.innerHTML;
            const hasValidContent = currentContent.includes('<pre style=') || 
                                  currentContent.includes('Sistema Operacional') ||
                                  (currentContent.length > 100 && !currentContent.includes('🔄 Carregando'));
            
            if (hasValidContent) {
                return; // Já tem conteúdo válido
            }

            // Carregar informações com timeout
            detailsElement.innerHTML = '<p>🔄 Carregando informações do sistema...</p>';

            try {
                // Criar uma Promise com timeout
                const fetchWithTimeout = new Promise(async (resolve, reject) => {
                    const timeoutId = setTimeout(() => {
                        reject(new Error('Timeout: CGI não respondeu em 3 segundos'));
                    }, 3000);

                    try {
                        const response = await fetch(CGI_URL, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/x-www-form-urlencoded',
                            },
                            body: new URLSearchParams({
                                action: 'system-info'
                            })
                        });

                        clearTimeout(timeoutId);

                        if (!response.ok) {
                            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                        }

                        const data = await response.text();
                        resolve(data);
                    } catch (error) {
                        clearTimeout(timeoutId);
                        reject(error);
                    }
                });

                const data = await fetchWithTimeout;
                detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${data}</pre>`;

            } catch (error) {
                console.log('Erro ao carregar do CGI:', error.message);
                
                // Mostrar informações de fallback (do navegador)
                const fallbackInfo = `
📊 Informações do Sistema (Navegador)
=====================================

🖥️ Sistema Operacional: ${navigator.platform}
🌐 Navegador: ${navigator.userAgent.split(' ')[0]} ${navigator.appVersion.split(' ')[0]}
📱 Resolução da Tela: ${screen.width}x${screen.height}
🎨 Profundidade de Cor: ${screen.colorDepth} bits
🕐 Data/Hora Local: ${new Date().toLocaleString('pt-BR')}
🌍 Idioma: ${navigator.language}
⚡ Cookies Habilitados: ${navigator.cookieEnabled ? 'Sim' : 'Não'}
🔌 Online: ${navigator.onLine ? 'Sim' : 'Não'}
💾 Memória (estimada): ${navigator.deviceMemory ? navigator.deviceMemory + ' GB' : 'Não disponível'}
🔄 Cores do Processador: ${navigator.hardwareConcurrency || 'Não disponível'}

⚠️ Nota: Servidor CGI não disponível. Exibindo informações do navegador.
                `;

                detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${fallbackInfo}</pre>`;
            }
        }

        // Carregar informações do sistema na inicialização
        async function loadSystemInfo() {
            try {
                const response = await fetch(CGI_URL, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                        action: 'quick-info'
                    })
                });

                if (response.ok) {
                    const data = await response.text();
                    // Processar informações básicas se necessário
                }
            } catch (error) {
                console.log('Informações do sistema não disponíveis');
            }
        }

        // Funções de UI
        function showLoading(text = 'Processando...') {
            const loading = document.getElementById('loading');
            const loadingText = document.getElementById('loading-text');

            loadingText.textContent = text;
            loading.classList.add('active');
        }

        function hideLoading() {
            const loading = document.getElementById('loading');
            loading.classList.remove('active');
        }

        function showProgress(percent, text = '') {
            const container = document.getElementById('progress-container');
            const fill = document.getElementById('progress-fill');
            const textElement = document.getElementById('progress-text');

            container.style.display = 'block';
            fill.style.width = `${percent}%`;
            if (text) textElement.textContent = text;
        }

        function hideProgress() {
            const container = document.getElementById('progress-container');
            container.style.display = 'none';
        }

        function showAlert(message, type = 'success') {
            const alert = document.getElementById('alert-container');
            alert.textContent = message;
            alert.className = `alert alert-${type} active`;

            setTimeout(() => {
                alert.classList.remove('active');
            }, 5000);
        }

        // Funções de ação
        function downloadResults() {
            const content = document.getElementById('result-content');
            if (!content.textContent.trim()) {
                showAlert('Nenhum resultado para baixar', 'warning');
                return;
            }

            const blob = new Blob([content.textContent], { type: 'text/plain' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `diagnostico-sistema-${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.txt`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);

            showAlert('Resultado baixado com sucesso!', 'success');
        }

        function printResults() {
            const content = document.getElementById('result-content');
            if (!content.textContent.trim()) {
                showAlert('Nenhum resultado para imprimir', 'warning');
                return;
            }

            const printWindow = window.open('', '_blank');
            printWindow.document.write(`
            <html>
            <head>
            <title>Diagnóstico do Sistema</title>
            <style>
            body { font-family: monospace; margin: 20px; }
            pre { white-space: pre-wrap; font-size: 12px; }
            .header { border-bottom: 2px solid #333; padding-bottom: 10px; margin-bottom: 20px; }
            </style>
            </head>
            <body>
            <div class="header">
            <h1>🔍 Diagnóstico do Sistema</h1>
            <p>Data: ${new Date().toLocaleString('pt-BR')}</p>
            </div>
            <pre>${content.textContent}</pre>
            </body>
            </html>
            `);
            printWindow.document.close();
            printWindow.print();
        }

        function clearResults() {
            const container = document.getElementById('result-container');
            const summary = document.getElementById('result-summary');
            const content = document.getElementById('result-content');

            container.classList.remove('active');
            summary.style.display = 'none';
            content.innerHTML = '';

            showAlert('Resultados limpos', 'success');
        }

        // Atalhos de teclado
        document.addEventListener('keydown', function(e) {
            if (e.ctrlKey && e.key === 'd') {
                e.preventDefault();
                runFullDiagnostic();
            }
            if (e.ctrlKey && e.key === 's') {
                e.preventDefault();
                downloadResults();
            }
            if (e.key === 'Escape') {
                clearResults();
            }
        });

        // Função para simular progresso durante diagnóstico
        function simulateProgress(duration = 10000) {
            let progress = 0;
            const interval = 100;
            const increment = 100 / (duration / interval);

            const progressInterval = setInterval(() => {
                progress += increment;
                if (progress >= 100) {
                    progress = 100;
                    clearInterval(progressInterval);
                }
                showProgress(progress, `Executando diagnóstico... ${Math.round(progress)}%`);
            }, interval);

            return progressInterval;
        }

        // Adicionar efeitos visuais
        function addVisualEffects() {
            // Efeito de hover nos cards
            const cards = document.querySelectorAll('.menu-card');
            cards.forEach(card => {
                card.addEventListener('mouseenter', function() {
                    this.style.transform = 'translateY(-5px) scale(1.02)';
                });

                card.addEventListener('mouseleave', function() {
                    this.style.transform = 'translateY(0) scale(1)';
                });
            });
        }

        // Função para verificar status do servidor CGI
        async function checkCGIStatus() {
            try {
                const response = await fetch(CGI_URL, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                        action: 'ping'
                    })
                });

                if (response.ok) {
                    return true;
                }
            } catch (error) {
                console.error('CGI não disponível:', error);
            }
            return false;
        }

        // Inicialização completa
        window.addEventListener('load', function() {
            addVisualEffects();

            // Verificar status do CGI
            checkCGIStatus().then(status => {
                if (!status) {
                    showAlert('⚠️ Aviso: Servidor CGI pode não estar disponível. Verifique a configuração.', 'warning');

                    // Mostrar dados de exemplo para demonstração
                    setTimeout(() => {
                        showDemoData();
                    }, 2000);
                }
            });

            console.log('Sistema de Diagnóstico WebUI carregado com sucesso!');
        });

        // Função para mostrar dados de demonstração (quando CGI não estiver disponível)
        function showDemoData() {
            const demoOutput = `============================================
            Diagnóstico do Sistema v3.7 - 04.06.2025
            ============================================

            ✅ Autenticação realizada com sucesso!

            🔍 Teste 01: Verificando armazenamento...
            2025-01-07 10:30:15 - Verificando consistência do /etc/fstab...
            ✅ OK: Todos os sistemas de arquivos do fstab estão montados
            2025-01-07 10:30:18 - Verificando integridade dos sistemas de arquivos...
            ✅ OK: Nenhum erro de sistema de arquivos detectado
            2025-01-07 10:30:21 - Verificando armazenamento com possíveis BAD BLOCKS...
            ✅ OK: Dispositivo /dev/sda sem problemas SMART para relatar.
            ✅ OK: Dispositivo /dev/sdb sem problemas SMART para relatar.

            🔍 Teste 02: Verificando utilização de armazenamento...
            ✅ OK: Nenhum disco com 100% de uso
            2025-01-07 10:30:24 - Verificando uso acima de 90%...
            ✅ OK: Nenhum disco com +90% de uso
            2025-01-07 10:30:27 - Verificando utilização de inodes...
            ✅ OK: Nenhum disco com inodes esgotados

            🔍 Teste 03: Verificando conectividade de rede...
            ✅ DNS 1.1.1.1 respondendo!
            64 bytes from 1.1.1.1: icmp_seq=1 ttl=58 time=12.4 ms
            ✅ DNS 8.8.8.8 respondendo!
            64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=15.2 ms
            2025-01-07 10:30:35 - Verificando interfaces de rede...
            ✅ Todas as interfaces de rede existentes estão ativas!
            2025-01-07 10:30:38 - Verificando resolução DNS...
            ✅ Resolução DNS OK, os seguintes dados foram coletados:
            IP WAN   : 203.0.113.45
            IP LAN   : 192.168.1.100
            Gateway  : 192.168.1.1
            Subnet   : 192.168.1.0
            Interface: eth0

            🔍 Teste 04: Verificando serviços essenciais...
            ✅ OK: Serviço ssh.socket está ativo
            ✅ OK: Serviço systemd-resolved está ativo
            ✅ OK: Serviço NetworkManager está ativo
            ✅ OK: Serviço cron está ativo
            2025-01-07 10:30:45 - Verificando Docker...
            ✅ OK: Docker está ativo
            ✅ OK: Docker está respondendo aos comandos normalmente.
            ✅ OK: Containers ativos e operando normalmente de acordo com o sistema.
            ✅ OK: Não há containers reiniciando em estado de erro.
            ✅ OK: Não há containers com alto consumo de CPU.
            2025-01-07 10:30:52 - Verificando LibVirt...
            ✅ OK: LibVirt não está instalado neste servidor. Sem capacidades de virtualização.

            🔍 Teste 05: Verificações adicionais do sistema...
            ✅ OK: Carga do sistema normal (1.2)
            ✅ OK: Uso de memória normal (45%)
            ✅ OK: Nenhum processo zumbi detectado.
            2025-01-07 10:30:58 - Verificando logs de sistema...

            ============================================
            📊 RESUMO DO DIAGNÓSTICO
            ============================================
            2025-01-07 10:31:00 - Diagnóstico concluído
            Erros críticos encontrados: 0
            Avisos encontrados: 0

            🎉 SISTEMA SAUDÁVEL: Nenhum problema detectado!`;

            processResults(demoOutput, 'Diagnóstico de Demonstração');
        }

        // Auto-refresh para alguns dados (opcional)
        function startAutoRefresh() {
            // Atualizar informações do sistema a cada 30 segundos
            setInterval(() => {
                const infoContainer = document.getElementById('system-info');
                if (infoContainer.style.display === 'block') {
                    loadSystemInfo();
                }
            }, 30000);
        }

        // Função para exportar relatório em formato HTML
        function exportHTMLReport() {
            const content = document.getElementById('result-content');
            const summary = document.getElementById('result-summary');

            if (!content.textContent.trim()) {
                showAlert('Nenhum resultado para exportar', 'warning');
                return;
            }

            const htmlContent = `<!DOCTYPE html>
            <html lang="pt-BR">
            <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Relatório de Diagnóstico do Sistema</title>
            <style>
            body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
            .container { max-width: 1000px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .header { text-align: center; border-bottom: 2px solid #3498db; padding-bottom: 20px; margin-bottom: 30px; }
            .header h1 { color: #2c3e50; margin-bottom: 10px; }
            .summary { background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
            .content { font-family: monospace; background: #2c3e50; color: #ecf0f1; padding: 20px; border-radius: 8px; white-space: pre-wrap; }
            .footer { text-align: center; margin-top: 30px; color: #7f8c8d; }
            </style>
            </head>
            <body>
            <div class="container">
            <div class="header">
            <h1>🔍 Relatório de Diagnóstico do Sistema</h1>
            <p>Gerado em: ${new Date().toLocaleString('pt-BR')}</p>
            </div>

            ${summary.style.display !== 'none' ? `<div class="summary">${summary.innerHTML}</div>` : ''}

            <div class="content">${content.textContent}</div>

            <div class="footer">
            <p>Relatório gerado pelo Sistema de Diagnóstico WebUI v3.7</p>
            </div>
            </div>
            </body>
            </html>`;

            const blob = new Blob([htmlContent], { type: 'text/html' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `relatorio-diagnostico-${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.html`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);

            showAlert('Relatório HTML exportado com sucesso!', 'success');
        }

        // Adicionar botão de exportar HTML
        function addHTMLExportButton() {
            const resultActions = document.querySelector('.result-actions');
            if (resultActions && !document.getElementById('html-export-btn')) {
                const htmlBtn = document.createElement('button');
                htmlBtn.id = 'html-export-btn';
                htmlBtn.className = 'btn';
                htmlBtn.innerHTML = '📄 HTML';
                htmlBtn.onclick = exportHTMLReport;
                resultActions.insertBefore(htmlBtn, resultActions.lastElementChild);
            }
        }
