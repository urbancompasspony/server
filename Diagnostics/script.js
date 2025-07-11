// Configurações
const CGI_URL = '/cgi-bin/system-diagnostic.cgi';
const WEB_PORT = '1298';

// Variáveis globais de controle
let diagnosticRunning = false;
let currentRequestId = null;
let currentTest = null;
let diagnosticResults = {};

// === FUNÇÃO PRINCIPAL: DIAGNÓSTICO COMPLETO ===
async function runFullDiagnostic() {
    if (diagnosticRunning) {
        showAlert('⏳ Diagnóstico em andamento! Aguarde...', 'warning');
        return;
    }
    
    diagnosticRunning = true;
    currentRequestId = Date.now();
    
    // Desabilitar botão visualmente
    const button = document.querySelector('[onclick="runFullDiagnostic()"]');
    if (button) {
        button.disabled = true;
        button.style.opacity = '0.5';
        button.innerHTML = '⏳ Executando...';
        button.style.cursor = 'not-allowed';
    }
        
    showLoading('Executando diagnóstico completo do sistema... por favor, não feche ou saia desta página!');
    
    // Progresso OTIMIZADO
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
    ];

    let currentStep = 0;
    let progressCompleted = false;
    showProgress(progressSteps[0].percent, progressSteps[0].message);

    function advanceProgress() {
        if (progressCompleted || currentStep >= progressSteps.length) return;
        
        currentStep++;
        if (currentStep < progressSteps.length) {
            const step = progressSteps[currentStep];
            showProgress(step.percent, step.message);
            setTimeout(advanceProgress, step.delay);
        }
    }

    setTimeout(advanceProgress, progressSteps[0].delay);

    try {
        const startTime = Date.now();
        
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'full-diagnostic' })
        });

        progressCompleted = true;
        const duration = Math.round((Date.now() - startTime) / 1000);
        
        showProgress(90, 'Processando resultados...');
        await sleep(300);
        showProgress(95, 'Analisando dados coletados...');
        await sleep(200);
        showProgress(100, `Diagnóstico concluído em ${duration}s!`);

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        
        setTimeout(() => {
            processResults(data, 'Diagnóstico Completo');
        }, 600);

    } catch (error) {
        progressCompleted = true;
        hideLoading();
        hideProgress();
        showAlert('Erro ao executar diagnóstico: ' + error.message, 'error');
    } finally {
        // SEMPRE libera a trava
        diagnosticRunning = false;
        currentRequestId = null;
        if (button) {
            button.disabled = false;
            button.style.opacity = '1';
            button.innerHTML = '🚀 Diagnóstico Completo';
            button.style.cursor = 'pointer';
        }
    }
}

// === FUNÇÃO: TESTES ESPECÍFICOS COM PROTEÇÃO ===
async function runSpecificTest(testType) {
    if (diagnosticRunning) {
        showAlert('⏳ Diagnóstico em andamento! Aguarde...', 'warning');
        return;
    }
    
    diagnosticRunning = true;
    
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
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
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
    } finally {
        // SEMPRE libera a trava
        diagnosticRunning = false;
    }
}

// === FUNÇÕES DE PROCESSAMENTO ===
function processResults(data, testName) {
    hideLoading();
    hideProgress();

    let results;
    try {
        results = JSON.parse(data);
    } catch (e) {
        results = { output: data };
    }

    const analysis = analyzeResults(results.output || data);
    showResults(results.output || data, testName, analysis);
    updateSummary(analysis);
}

function analyzeResults(output) {
    const analysis = { status: 'unknown', errors: 0, warnings: 0, tests: 0, sections: [] };
    if (!output) return analysis;

    // Extrair do resumo final (mais confiável)
    const errorMatch = output.match(/Erros críticos encontrados: (\d+)/);
    const warningMatch = output.match(/Avisos encontrados: (\d+)/);
    
    if (errorMatch) analysis.errors = parseInt(errorMatch[1]);
    if (warningMatch) analysis.warnings = parseInt(warningMatch[1]);

    const testMatches = output.match(/🔍 Teste \d+:/g);
    analysis.tests = testMatches ? testMatches.length : 0;

    if (analysis.errors > 0) analysis.status = 'error';
    else if (analysis.warnings > 0) analysis.status = 'warning';  
    else analysis.status = 'success';

    return analysis;
}

// === FUNÇÕES DE UI ===
function showResults(output, testName, analysis) {
    const container = document.getElementById('result-container');
    const title = document.getElementById('result-title');
    const content = document.getElementById('result-content');

    title.textContent = `${testName} - ${new Date().toLocaleString('pt-BR')}`;
    content.innerHTML = `<pre>${output}</pre>`;
    container.className = `result-container active ${analysis.status}`;

    if (analysis.status === 'success') {
        showAlert('Diagnóstico concluído com sucesso! Sistema saudável.', 'success');
    } else if (analysis.status === 'warning') {
        showAlert(`Diagnóstico concluído com ${analysis.warnings} aviso(s). Verificar itens mencionados.`, 'warning');
    } else {
        showAlert(`Diagnóstico concluído com ${analysis.errors} erro(s) crítico(s). Ação imediata necessária!`, 'error');
    }
}

function updateSummary(analysis) {
    const summaryContainer = document.getElementById('result-summary');
    const statusElement = document.getElementById('summary-status');
    const errorsElement = document.getElementById('summary-errors');
    const warningsElement = document.getElementById('summary-warnings');
    const testsElement = document.getElementById('summary-tests');

    summaryContainer.style.display = 'block';

    statusElement.textContent = getStatusText(analysis.status);
    statusElement.className = `summary-value ${analysis.status}`;
    errorsElement.textContent = analysis.errors;
    errorsElement.className = `summary-value ${analysis.errors > 0 ? 'error' : 'success'}`;
    warningsElement.textContent = analysis.warnings;
    warningsElement.className = `summary-value ${analysis.warnings > 0 ? 'warning' : 'success'}`;
    testsElement.textContent = analysis.tests || 'Completo';
    testsElement.className = 'summary-value success';
}

function getStatusText(status) {
    switch (status) {
        case 'success': return '✅ Saudável';
        case 'warning': return '⚠️ Com Avisos';
        case 'error': return '❌ Crítico';
        default: return '❓ Desconhecido';
    }
}

// === INFORMAÇÕES DO SISTEMA ===
async function showSystemInfo() {
    const infoContainer = document.getElementById('system-info');
    const detailsElement = document.getElementById('system-details');

    const isVisible = window.getComputedStyle(infoContainer).display === 'block';
    if (isVisible) {
        infoContainer.style.display = 'none';
        return;
    }

    infoContainer.style.display = 'block';
    
    const currentContent = detailsElement.innerHTML;
    const hasValidContent = currentContent.includes('<pre style=') || 
                          currentContent.includes('Sistema Operacional') ||
                          (currentContent.length > 100 && !currentContent.includes('🔄 Carregando'));
    
    if (hasValidContent) return;

    detailsElement.innerHTML = '<p>🔄 Carregando informações do sistema...</p>';

    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'system-info' })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.text();
        detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${data}</pre>`;

    } catch (error) {
        console.log('Erro ao carregar do CGI:', error.message);
        
        const fallbackInfo = `📊 Informações do Sistema (Navegador)
=====================================
🖥️ Sistema Operacional: ${navigator.platform}
🌐 Navegador: ${navigator.userAgent.split(' ')[0]}
📱 Resolução: ${screen.width}x${screen.height}
🕐 Data/Hora: ${new Date().toLocaleString('pt-BR')}
🌍 Idioma: ${navigator.language}
⚡ Cookies: ${navigator.cookieEnabled ? 'Sim' : 'Não'}
🔌 Online: ${navigator.onLine ? 'Sim' : 'Não'}
💾 Memória: ${navigator.deviceMemory ? navigator.deviceMemory + ' GB' : 'N/A'}
🔄 CPU Cores: ${navigator.hardwareConcurrency || 'N/A'}

⚠️ Nota: Servidor CGI não disponível.`;

        detailsElement.innerHTML = `<pre style="background: white; padding: 15px; border-radius: 8px; color: #2c3e50; font-family: monospace;">${fallbackInfo}</pre>`;
    }
}

async function loadSystemInfo() {
    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'quick-info' })
        });
        // Processar se necessário
    } catch (error) {
        console.log('Informações do sistema não disponíveis');
    }
}

// === FUNÇÕES DE CONTROLE ===
function showLoading(text = 'Processando...') {
    const loading = document.getElementById('loading');
    const loadingText = document.getElementById('loading-text');
    loadingText.textContent = text;
    loading.classList.add('active');
}

function hideLoading() {
    document.getElementById('loading').classList.remove('active');
}

function showProgress(percent, text = '') {
    const container = document.getElementById('progress-container');
    const fill = document.getElementById('progress-fill');
    const textElement = document.getElementById('progress-text');

    if (container) container.style.display = 'block';
    if (fill) fill.style.width = `${percent}%`;
    if (textElement && text) textElement.textContent = text;
}

function hideProgress() {
    const container = document.getElementById('progress-container');
    if (container) container.style.display = 'none';
}

function showAlert(message, type = 'success') {
    const alert = document.getElementById('alert-container');
    alert.textContent = message;
    alert.className = `alert alert-${type} active`;
    setTimeout(() => alert.classList.remove('active'), 5000);
}

// === FUNÇÕES DE AÇÃO ===
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

// === FUNÇÕES AUXILIARES ===
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function addVisualEffects() {
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

async function checkCGIStatus() {
    try {
        const response = await fetch(CGI_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ action: 'ping' })
        });
        return response.ok;
    } catch (error) {
        console.error('CGI não disponível:', error);
        return false;
    }
}

// === EVENTOS E INICIALIZAÇÃO ===
window.addEventListener('beforeunload', function(e) {
    if (diagnosticRunning) {
        e.preventDefault();
        e.returnValue = '⚠️ Diagnóstico em andamento! Sair agora pode deixar processos órfãos no servidor. Tem certeza?';
        return e.returnValue;
    }
});

window.addEventListener('load', function() {
    // Reset de estado
    diagnosticRunning = false;
    currentRequestId = null;
    
    // Carregar info do sistema
    loadSystemInfo();
    
    // Adicionar efeitos visuais
    addVisualEffects();
    
    // Verificar status do CGI
    checkCGIStatus().then(status => {
        if (!status) {
            showAlert('⚠️ Aviso: Servidor CGI pode não estar disponível. Verifique a configuração.', 'warning');
        }
    });
    
    console.log('Sistema de Diagnóstico WebUI carregado com proteções ativas!');
});

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
